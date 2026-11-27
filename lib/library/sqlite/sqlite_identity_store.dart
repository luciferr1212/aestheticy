/// SQLite store for stable `userdata.track_identity` records, reconciliation,
/// backfill, and indexed move/rename relinking.
library;

import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/library/file_path_utils.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/text_normalizer.dart';
import 'package:aestheticy/library/track_identity_models.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

class _TrackCandidate {
  final String path;
  final String canonicalPath;
  final int sizeBytes;
  final int durationMs;
  final String? titleKey;
  final String? artistKey;
  final String? albumKey;

  const _TrackCandidate({
    required this.path,
    required this.canonicalPath,
    required this.sizeBytes,
    required this.durationMs,
    this.titleKey,
    this.artistKey,
    this.albumKey,
  });
}

class _RelinkStatements {
  final PreparedStatement updateIdentity;
  final PreparedStatement selectFav;
  final PreparedStatement deleteFav;
  final PreparedStatement insertFav;
  final PreparedStatement selectRating;
  final PreparedStatement deleteRating;
  final PreparedStatement insertRating;
  final PreparedStatement updatePlaylist;
  final PreparedStatement updatePlayEventsByKey;
  final PreparedStatement updatePlayEventsByUid;

  _RelinkStatements(Database db)
      : updateIdentity = db.prepare('''
          UPDATE userdata.track_identity
          SET path = ?, path_key = ?, size_bytes = ?, duration_ms = ?,
              title_key = ?, artist_key = ?, album_key = ?,
              last_seen_ms = ?, missing_since_ms = NULL
          WHERE uid = ?;
        '''),
        selectFav = db.prepare(
          'SELECT path, added_at_ms FROM userdata.favorites WHERE path_key IN (?, ?);',
        ),
        deleteFav = db.prepare(
          'DELETE FROM userdata.favorites WHERE path_key IN (?, ?);',
        ),
        insertFav = db.prepare(
          'INSERT OR REPLACE INTO userdata.favorites (path, added_at_ms, path_key) VALUES (?, ?, ?);',
        ),
        selectRating = db.prepare(
          'SELECT path, stars, rated_at_ms FROM userdata.ratings WHERE path_key IN (?, ?);',
        ),
        deleteRating = db.prepare(
          'DELETE FROM userdata.ratings WHERE path_key IN (?, ?);',
        ),
        insertRating = db.prepare(
          'INSERT OR REPLACE INTO userdata.ratings (path, stars, rated_at_ms, path_key) VALUES (?, ?, ?, ?);',
        ),
        updatePlaylist = db.prepare(
          'UPDATE userdata.playlist_items SET path = ?, path_key = ? WHERE path_key = ?;',
        ),
        updatePlayEventsByKey = db.prepare('''
          UPDATE userdata.play_events
          SET uri = ?, uri_key = ?, track_uid = COALESCE(track_uid, ?)
          WHERE uri_key = ?;
        '''),
        updatePlayEventsByUid = db.prepare('''
          UPDATE userdata.play_events
          SET uri = ?, uri_key = ?
          WHERE track_uid = ? AND (uri_key IS NULL OR uri_key != ?);
        ''');

  void dispose() {
    updateIdentity.close();
    selectFav.close();
    deleteFav.close();
    insertFav.close();
    selectRating.close();
    deleteRating.close();
    insertRating.close();
    updatePlaylist.close();
    updatePlayEventsByKey.close();
    updatePlayEventsByUid.close();
  }
}

/// Internal SQLite store managing `userdata.track_identity` and indexed relinking.
class SqliteIdentityStore {
  static final Random _secureRandom = Random.secure();

  final Database _db;
  final String Function() _userSchema;
  final UserDataAccessMode Function() _accessMode;
  final AppLogger? logger;

  /// Creates a [SqliteIdentityStore] backed by [_db].
  SqliteIdentityStore(
    this._db, {
    String Function()? userSchema,
    UserDataAccessMode Function()? accessMode,
    this.logger,
  })  : _userSchema = userSchema ?? (() => 'userdata'),
        _accessMode = accessMode ?? (() => UserDataAccessMode.normal);

  /// Generates a random 128-bit lowercase hexadecimal UID (32 hex characters).
  static String generateUid([Random? random]) {
    final rng = random ?? _secureRandom;
    final sb = StringBuffer();
    for (var i = 0; i < 16; i++) {
      sb.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static String? _normOrNull(String? value) {
    if (value == null) return null;
    final norm = TextNormalizer.normalize(value);
    return norm.isEmpty ? null : norm;
  }

  bool get _canWrite =>
      _accessMode() == UserDataAccessMode.normal && _userSchema() == 'userdata';

  /// Looks up the stable UID for [path] (normalized via [FilePathUtils]), or
  /// returns `null` if unknown.
  Future<String?> resolveTrackUid(String path) async {
    final u = _userSchema();
    if (!_hasTable(u, 'track_identity')) return null;
    final canonical = FilePathUtils.canonicalKey(path);
    if (canonical.isEmpty) return null;
    final rows = _hasColumn(u, 'track_identity', 'path_key')
        ? _db.select(
            'SELECT uid FROM $u.track_identity WHERE path_key = ? LIMIT 1;',
            [canonical],
          )
        : _db.select(
            'SELECT uid FROM $u.track_identity WHERE normalize_file_path(path) = ? LIMIT 1;',
            [canonical],
          );
    if (rows.isEmpty) return null;
    return rows.first['uid'] as String;
  }

  /// Lists all `track_identity` rows ordered by `first_seen_ms ASC`.
  Future<List<TrackIdentity>> listIdentities() async {
    final u = _userSchema();
    if (!_hasTable(u, 'track_identity')) return const [];
    final rows = _db.select(
      '''
      SELECT uid, path, size_bytes, duration_ms, title_key, artist_key,
             album_key, first_seen_ms, last_seen_ms, missing_since_ms
      FROM $u.track_identity
      ORDER BY first_seen_ms ASC, uid ASC;
      ''',
    );
    return rows.map(_mapIdentity).toList(growable: false);
  }

  /// Ensures every track in [tracks] has a `track_identity` row and refreshes
  /// `last_seen_ms` / metadata keys inside a single `userdata`-only transaction.
  Future<void> ensureIdentitiesForTracks(
    List<Track> tracks, {
    DateTime? now,
  }) async {
    if (!_canWrite || tracks.isEmpty) return;
    final nowMs = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final existingByCanonical = _loadIdentityByCanonical();
      final insertStmt = _db.prepare('''
        INSERT INTO userdata.track_identity (
          uid, path, path_key, size_bytes, duration_ms, title_key, artist_key,
          album_key, first_seen_ms, last_seen_ms, missing_since_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL);
      ''');
      final updateStmt = _db.prepare('''
        UPDATE userdata.track_identity
        SET path = ?, path_key = ?, size_bytes = ?, duration_ms = ?,
            title_key = ?, artist_key = ?, album_key = ?, last_seen_ms = ?,
            missing_since_ms = NULL
        WHERE uid = ?;
      ''');

      try {
        for (final track in tracks) {
          final canonical = FilePathUtils.canonicalKey(track.path);
          if (canonical.isEmpty) continue;
          final titleKey = _normOrNull(track.title);
          final artistKey = _normOrNull(track.artist);
          final albumKey = _normOrNull(track.album);
          final existing = existingByCanonical[canonical];

          if (existing != null) {
            updateStmt.execute([
              track.path,
              canonical,
              track.sizeBytes,
              track.durationMs,
              titleKey,
              artistKey,
              albumKey,
              nowMs,
              existing.uid,
            ]);
          } else {
            final uid = generateUid();
            insertStmt.execute([
              uid,
              track.path,
              canonical,
              track.sizeBytes,
              track.durationMs,
              titleKey,
              artistKey,
              albumKey,
              nowMs,
              nowMs,
            ]);
            existingByCanonical[canonical] = TrackIdentity(
              uid: uid,
              path: track.path,
              sizeBytes: track.sizeBytes,
              durationMs: track.durationMs,
              titleKey: titleKey,
              artistKey: artistKey,
              albumKey: albumKey,
              firstSeenMs: nowMs,
              lastSeenMs: nowMs,
              missingSinceMs: null,
            );
          }
        }
      } finally {
        insertStmt.close();
        updateStmt.close();
      }
      _db.execute('COMMIT;');
    } catch (e, st) {
      AppLogger.instance.error(
        'IdentityStore',
        'Backfill track identities transaction failed',
        e,
        st,
      );
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Reconciles `userdata.track_identity` against `main.tracks` and user-data
  /// tables (`favorites`, `ratings`, `playlist_items`, `play_events`) using
  /// indexed key columns in a single `userdata` transaction with prepared
  /// statements.
  Future<RelinkReport> reconcileIdentities({
    DateTime? now,
    bool markUnmatchedMissing = true,
  }) async {
    return reconcileIdentitiesSync(
      now: now,
      markUnmatchedMissing: markUnmatchedMissing,
    );
  }

  /// Synchronous variant of [reconcileIdentities].
  RelinkReport reconcileIdentitiesSync({
    DateTime? now,
    bool markUnmatchedMissing = true,
  }) {
    if (!_canWrite || !_hasTable('userdata', 'track_identity')) {
      return RelinkReport.empty;
    }

    final nowMs = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final log = logger ?? AppLogger.instance;

    final trackRows = _db.select('''
      SELECT path, title, artist, album, duration_ms, size_bytes
      FROM main.tracks;
    ''');
    final tracksByCanonical = <String, _TrackCandidate>{};
    for (final r in trackRows) {
      final path = r['path'] as String;
      final canonical = FilePathUtils.canonicalKey(path);
      if (canonical.isEmpty) continue;
      tracksByCanonical[canonical] = _TrackCandidate(
        path: path,
        canonicalPath: canonical,
        sizeBytes: r['size_bytes'] as int,
        durationMs: r['duration_ms'] as int,
        titleKey: _normOrNull(r['title'] as String?),
        artistKey: _normOrNull(r['artist'] as String?),
        albumKey: _normOrNull(r['album'] as String?),
      );
    }

    final identityRows = _db.select('''
      SELECT uid, path, path_key, size_bytes, duration_ms, title_key,
             artist_key, album_key, first_seen_ms, last_seen_ms, missing_since_ms
      FROM userdata.track_identity;
    ''');

    final matchedTracks = <(TrackIdentity, _TrackCandidate)>[];
    final missingIdentities = <TrackIdentity>[];
    final matchedCanonicals = <String>{};

    for (final row in identityRows) {
      final identity = _mapIdentity(row);
      final storedKey = row['path_key'] as String?;
      final canonical = (storedKey != null && storedKey.isNotEmpty)
          ? storedKey
          : FilePathUtils.canonicalKey(identity.path);
      final matched = tracksByCanonical[canonical];
      if (matched != null) {
        matchedTracks.add((identity, matched));
        matchedCanonicals.add(canonical);
      } else {
        missingIdentities.add(identity);
      }
    }

    final unmatchedNewTracks = tracksByCanonical.values
        .where((t) => !matchedCanonicals.contains(t.canonicalPath))
        .toList();

    // Index unmatched new candidates in memory for O(1) rule lookups.
    final bySizeAndDuration = <(int, int), List<_TrackCandidate>>{};
    final byTagTriple = <(String, String?, String?), List<_TrackCandidate>>{};
    for (final candidate in unmatchedNewTracks) {
      if (candidate.sizeBytes > 0 && candidate.durationMs > 0) {
        bySizeAndDuration
            .putIfAbsent(
              (candidate.sizeBytes, candidate.durationMs),
              () => [],
            )
            .add(candidate);
      }
      final title = candidate.titleKey;
      if (title != null && title.isNotEmpty) {
        byTagTriple
            .putIfAbsent(
              (title, candidate.artistKey, candidate.albumKey),
              () => [],
            )
            .add(candidate);
      }
    }

    final proposedTargetByUid = <String, _TrackCandidate>{};
    final proposersByTargetCanonical = <String, List<TrackIdentity>>{};
    var ambiguousCount = 0;

    for (final missing in missingIdentities) {
      _TrackCandidate? chosen;

      // Rule 1: Exact size_bytes AND exact duration_ms match.
      if (missing.sizeBytes != null &&
          missing.sizeBytes! > 0 &&
          missing.durationMs != null &&
          missing.durationMs! > 0) {
        final sizeDurMatches =
            bySizeAndDuration[(missing.sizeBytes!, missing.durationMs!)] ??
                const <_TrackCandidate>[];
        if (sizeDurMatches.length == 1) {
          chosen = sizeDurMatches.single;
        } else if (sizeDurMatches.length > 1) {
          ambiguousCount++;
          log.warning(
            'Identity',
            'Ambiguous size+duration relink (${sizeDurMatches.length} candidates) for uid=${missing.uid}',
          );
          continue;
        }
      }

      // Rule 2: title_key + artist_key + album_key match AND |duration delta| <= 1500ms.
      if (chosen == null &&
          missing.titleKey != null &&
          missing.titleKey!.isNotEmpty &&
          missing.durationMs != null) {
        final tripleCandidates =
            byTagTriple[(missing.titleKey!, missing.artistKey, missing.albumKey)] ??
                const <_TrackCandidate>[];
        final tagMatches = tripleCandidates
            .where((t) => (t.durationMs - missing.durationMs!).abs() <= 1500)
            .toList();
        if (tagMatches.length == 1) {
          chosen = tagMatches.single;
        } else if (tagMatches.length > 1) {
          ambiguousCount++;
          log.warning(
            'Identity',
            'Ambiguous tag+duration relink (${tagMatches.length} candidates) for uid=${missing.uid}',
          );
          continue;
        }
      }

      if (chosen != null) {
        proposedTargetByUid[missing.uid] = chosen;
        proposersByTargetCanonical
            .putIfAbsent(chosen.canonicalPath, () => [])
            .add(missing);
      }
    }

    // Reverse ambiguity guard: never relink >1 identities to the same target file.
    final relinks = <({TrackIdentity identity, _TrackCandidate target})>[];
    final relinkedUids = <String>{};
    final relinkedTargetCanonicals = <String>{};
    for (final entry in proposersByTargetCanonical.entries) {
      if (entry.value.length == 1) {
        final identity = entry.value.single;
        final target = proposedTargetByUid[identity.uid]!;
        relinks.add((identity: identity, target: target));
        relinkedUids.add(identity.uid);
        relinkedTargetCanonicals.add(target.canonicalPath);
      } else {
        ambiguousCount++;
        log.warning(
          'Identity',
          'Ambiguous reverse relink (${entry.value.length} identities matched one track)',
        );
      }
    }

    final remainingMissing = missingIdentities
        .where((id) => !relinkedUids.contains(id.uid))
        .toList();
    final remainingNewTracks = unmatchedNewTracks
        .where((t) => !relinkedTargetCanonicals.contains(t.canonicalPath))
        .toList();

    var createdCount = 0;
    var refreshedCount = 0;
    var relinkedCount = 0;
    var markedMissingCount = 0;
    var backfilledCount = 0;

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      // 1. Refresh matched tracks (and clear missing_since_ms).
      if (matchedTracks.isNotEmpty) {
        final refreshStmt = _db.prepare('''
          UPDATE userdata.track_identity
          SET path = ?, path_key = ?, size_bytes = ?, duration_ms = ?,
              title_key = ?, artist_key = ?, album_key = ?, last_seen_ms = ?,
              missing_since_ms = NULL
          WHERE uid = ?;
        ''');
        try {
          for (final (identity, track) in matchedTracks) {
            refreshStmt.execute([
              track.path,
              track.canonicalPath,
              track.sizeBytes,
              track.durationMs,
              track.titleKey,
              track.artistKey,
              track.albumKey,
              nowMs,
              identity.uid,
            ]);
            refreshedCount++;
          }
        } finally {
          refreshStmt.close();
        }
      }

      // 2. Apply all unique relinks using indexed equality and prepared statements.
      if (relinks.isNotEmpty) {
        final stmts = _RelinkStatements(_db);
        try {
          for (final item in relinks) {
            _applyRelinkInTx(
              stmts: stmts,
              identity: item.identity,
              target: item.target,
              nowMs: nowMs,
            );
            relinkedCount++;
          }
        } finally {
          stmts.dispose();
        }
      }

      // 3. Mark un-relinked missing identities without deleting any user data.
      if (markUnmatchedMissing && remainingMissing.isNotEmpty) {
        final markStmt = _db.prepare('''
          UPDATE userdata.track_identity
          SET missing_since_ms = COALESCE(missing_since_ms, ?)
          WHERE uid = ?;
        ''');
        try {
          for (final missing in remainingMissing) {
            if (missing.missingSinceMs == null) {
              markedMissingCount++;
            }
            markStmt.execute([nowMs, missing.uid]);
          }
        } finally {
          markStmt.close();
        }
      }

      // 4. Insert newly seen tracks.
      if (remainingNewTracks.isNotEmpty) {
        final insertStmt = _db.prepare('''
          INSERT INTO userdata.track_identity (
            uid, path, path_key, size_bytes, duration_ms, title_key, artist_key,
            album_key, first_seen_ms, last_seen_ms, missing_since_ms
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL);
        ''');
        try {
          for (final track in remainingNewTracks) {
            insertStmt.execute([
              generateUid(),
              track.path,
              track.canonicalPath,
              track.sizeBytes,
              track.durationMs,
              track.titleKey,
              track.artistKey,
              track.albumKey,
              nowMs,
              nowMs,
            ]);
            createdCount++;
          }
        } finally {
          insertStmt.close();
        }
      }

      // 5. Backfill unlinked user paths & play_events.track_uid via indexed keys.
      backfilledCount = _backfillUserPathsInTx(nowMs: nowMs);

      _db.execute('COMMIT;');
    } catch (e, st) {
      AppLogger.instance.error(
        'IdentityStore',
        'Backfill track identities transaction failed',
        e,
        st,
      );
      _db.execute('ROLLBACK;');
      rethrow;
    }

    return RelinkReport(
      created: createdCount,
      refreshed: refreshedCount,
      relinked: relinkedCount,
      markedMissing: markedMissingCount,
      ambiguousCount: ambiguousCount,
      backfilledUserPaths: backfilledCount,
    );
  }

  void _applyRelinkInTx({
    required _RelinkStatements stmts,
    required TrackIdentity identity,
    required _TrackCandidate target,
    required int nowMs,
  }) {
    final oldCanonical = FilePathUtils.canonicalKey(identity.path);
    final newCanonical = target.canonicalPath;
    final newPath = target.path;

    stmts.updateIdentity.execute([
      newPath,
      newCanonical,
      target.sizeBytes,
      target.durationMs,
      target.titleKey,
      target.artistKey,
      target.albumKey,
      nowMs,
      identity.uid,
    ]);

    _relinkFavoritesInTx(stmts, oldCanonical, newCanonical, newPath);
    _relinkRatingsInTx(stmts, oldCanonical, newCanonical, newPath);

    stmts.updatePlaylist.execute([newPath, newCanonical, oldCanonical]);
    stmts.updatePlayEventsByKey.execute([
      newPath,
      newCanonical,
      identity.uid,
      oldCanonical,
    ]);
    stmts.updatePlayEventsByUid.execute([
      newPath,
      newCanonical,
      identity.uid,
      newCanonical,
    ]);
  }

  void _relinkFavoritesInTx(
    _RelinkStatements stmts,
    String oldCanonical,
    String newCanonical,
    String newPath,
  ) {
    final rows = stmts.selectFav.select([oldCanonical, newCanonical]);
    if (rows.isEmpty) return;

    var newestAddedAt = rows.first['added_at_ms'] as int;
    for (final row in rows) {
      final ts = row['added_at_ms'] as int;
      if (ts > newestAddedAt) newestAddedAt = ts;
    }

    stmts.deleteFav.execute([oldCanonical, newCanonical]);
    stmts.insertFav.execute([newPath, newestAddedAt, newCanonical]);
  }

  void _relinkRatingsInTx(
    _RelinkStatements stmts,
    String oldCanonical,
    String newCanonical,
    String newPath,
  ) {
    final rows = stmts.selectRating.select([oldCanonical, newCanonical]);
    if (rows.isEmpty) return;

    var bestStars = rows.first['stars'] as int;
    var newestRatedAt = rows.first['rated_at_ms'] as int;
    for (final row in rows) {
      final ts = row['rated_at_ms'] as int;
      if (ts > newestRatedAt) {
        newestRatedAt = ts;
        bestStars = row['stars'] as int;
      }
    }

    stmts.deleteRating.execute([oldCanonical, newCanonical]);
    stmts.insertRating.execute([newPath, bestStars, newestRatedAt, newCanonical]);
  }

  int _backfillUserPathsInTx({required int nowMs}) {
    final existingByCanonical = _loadIdentityByCanonical();
    final referencedByKey = <String, String>{};

    void collect(String rawPath, String? storedKey) {
      final key = (storedKey != null && storedKey.isNotEmpty)
          ? storedKey
          : FilePathUtils.canonicalKey(rawPath);
      if (key.isNotEmpty) {
        referencedByKey.putIfAbsent(key, () => rawPath);
      }
    }

    for (final r
        in _db.select('SELECT path, path_key FROM userdata.favorites;')) {
      collect(r['path'] as String, r['path_key'] as String?);
    }
    for (final r
        in _db.select('SELECT path, path_key FROM userdata.ratings;')) {
      collect(r['path'] as String, r['path_key'] as String?);
    }
    for (final r in _db.select(
      'SELECT MIN(path) AS path, path_key FROM userdata.playlist_items GROUP BY path_key;',
    )) {
      collect(r['path'] as String, r['path_key'] as String?);
    }

    final unlinkedEventGroups = _db.select('''
      SELECT MIN(uri) AS uri, uri_key
      FROM userdata.play_events
      WHERE track_uid IS NULL
      GROUP BY uri_key;
    ''');
    for (final r in unlinkedEventGroups) {
      collect(r['uri'] as String, r['uri_key'] as String?);
    }

    var created = 0;
    final missingKeys = referencedByKey.entries
        .where((e) => !existingByCanonical.containsKey(e.key))
        .toList();
    if (missingKeys.isNotEmpty) {
      final insertStmt = _db.prepare('''
        INSERT INTO userdata.track_identity (
          uid, path, path_key, size_bytes, duration_ms, title_key, artist_key,
          album_key, first_seen_ms, last_seen_ms, missing_since_ms
        ) VALUES (?, ?, ?, NULL, NULL, NULL, NULL, NULL, ?, ?, NULL);
      ''');
      try {
        for (final entry in missingKeys) {
          final uid = generateUid();
          insertStmt.execute([uid, entry.value, entry.key, nowMs, nowMs]);
          existingByCanonical[entry.key] = TrackIdentity(
            uid: uid,
            path: entry.value,
            firstSeenMs: nowMs,
            lastSeenMs: nowMs,
          );
          created++;
        }
      } finally {
        insertStmt.close();
      }
    }

    if (unlinkedEventGroups.isNotEmpty) {
      final updateEventStmt = _db.prepare(
        'UPDATE userdata.play_events SET track_uid = ? WHERE uri_key = ? AND track_uid IS NULL;',
      );
      try {
        for (final row in unlinkedEventGroups) {
          final rawKey = row['uri_key'] as String?;
          final key = (rawKey != null && rawKey.isNotEmpty)
              ? rawKey
              : FilePathUtils.canonicalKey(row['uri'] as String);
          final identity = existingByCanonical[key];
          if (identity != null && rawKey != null) {
            updateEventStmt.execute([identity.uid, rawKey]);
          }
        }
      } finally {
        updateEventStmt.close();
      }
    }

    return created;
  }

  Map<String, TrackIdentity> _loadIdentityByCanonical() {
    final rows = _db.select('''
      SELECT uid, path, path_key, size_bytes, duration_ms, title_key,
             artist_key, album_key, first_seen_ms, last_seen_ms, missing_since_ms
      FROM userdata.track_identity;
    ''');
    final map = <String, TrackIdentity>{};
    for (final row in rows) {
      final identity = _mapIdentity(row);
      final storedKey = row['path_key'] as String?;
      final canonical = (storedKey != null && storedKey.isNotEmpty)
          ? storedKey
          : FilePathUtils.canonicalKey(identity.path);
      if (canonical.isNotEmpty) {
        map.putIfAbsent(canonical, () => identity);
      }
    }
    return map;
  }

  bool _hasTable(String schema, String tableName) {
    final rows = _db.select(
      "SELECT 1 FROM $schema.sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  bool _hasColumn(String schema, String tableName, String colName) {
    final rows = _db.select('PRAGMA $schema.table_info($tableName);');
    return rows.any((r) => r['name'] == colName);
  }

  static TrackIdentity _mapIdentity(Row r) {
    return TrackIdentity(
      uid: r['uid'] as String,
      path: r['path'] as String,
      sizeBytes: r['size_bytes'] as int?,
      durationMs: r['duration_ms'] as int?,
      titleKey: r['title_key'] as String?,
      artistKey: r['artist_key'] as String?,
      albumKey: r['album_key'] as String?,
      firstSeenMs: r['first_seen_ms'] as int,
      lastSeenMs: r['last_seen_ms'] as int,
      missingSinceMs: r['missing_since_ms'] as int?,
    );
  }
}
