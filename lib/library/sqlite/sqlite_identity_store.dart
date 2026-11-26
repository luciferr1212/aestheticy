/// SQLite store for stable `userdata.track_identity` records, reconciliation,
/// backfill, and move/rename relinking.
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

/// Internal SQLite store managing `userdata.track_identity` and relinking.
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
    final rows = _db.select(
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
          uid, path, size_bytes, duration_ms, title_key, artist_key,
          album_key, first_seen_ms, last_seen_ms, missing_since_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL);
      ''');
      final updateStmt = _db.prepare('''
        UPDATE userdata.track_identity
        SET path = ?, size_bytes = ?, duration_ms = ?, title_key = ?,
            artist_key = ?, album_key = ?, last_seen_ms = ?,
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
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Reconciles `userdata.track_identity` against `main.tracks` and user-data
  /// tables (`favorites`, `ratings`, `playlist_items`, `play_events`):
  /// - Refreshes matched paths and clears `missing_since_ms`.
  /// - Relinks moved/renamed tracks when a unique size+duration or tag+duration
  ///   (<= 1500 ms) candidate exists, updating all user tables atomically in
  ///   one `userdata` transaction.
  /// - Marks remaining missing identities with `missing_since_ms` when
  ///   [markUnmatchedMissing] is `true` without deleting any user data.
  /// - Creates identities for new tracks and backfills paths + `play_events.track_uid`.
  Future<RelinkReport> reconcileIdentities({
    DateTime? now,
    bool markUnmatchedMissing = true,
  }) async {
    return reconcileIdentitiesSync(
      now: now,
      markUnmatchedMissing: markUnmatchedMissing,
    );
  }

  /// Synchronous variant of [reconcileIdentities] for startup initialization.
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
      SELECT uid, path, size_bytes, duration_ms, title_key, artist_key,
             album_key, first_seen_ms, last_seen_ms, missing_since_ms
      FROM userdata.track_identity;
    ''').map(_mapIdentity).toList();

    final matchedTracks = <(TrackIdentity, _TrackCandidate)>[];
    final missingIdentities = <TrackIdentity>[];
    final matchedCanonicals = <String>{};

    for (final identity in identityRows) {
      final canonical = FilePathUtils.canonicalKey(identity.path);
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

    // Compute unique relink proposals from missingIdentities -> unmatchedNewTracks.
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
        final sizeDurMatches = unmatchedNewTracks
            .where(
              (t) =>
                  t.sizeBytes == missing.sizeBytes &&
                  t.durationMs == missing.durationMs,
            )
            .toList();
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
        final tagMatches = unmatchedNewTracks.where((t) {
          if (t.titleKey != missing.titleKey) return false;
          if (t.artistKey != missing.artistKey) return false;
          if (t.albumKey != missing.albumKey) return false;
          return (t.durationMs - missing.durationMs!).abs() <= 1500;
        }).toList();
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
      final refreshStmt = _db.prepare('''
        UPDATE userdata.track_identity
        SET path = ?, size_bytes = ?, duration_ms = ?, title_key = ?,
            artist_key = ?, album_key = ?, last_seen_ms = ?,
            missing_since_ms = NULL
        WHERE uid = ?;
      ''');
      try {
        for (final (identity, track) in matchedTracks) {
          refreshStmt.execute([
            track.path,
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

      // 2. Apply unique relinks atomically across track_identity & all user tables.
      for (final item in relinks) {
        _applyRelinkInTx(
          identity: item.identity,
          target: item.target,
          nowMs: nowMs,
        );
        relinkedCount++;
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
            uid, path, size_bytes, duration_ms, title_key, artist_key,
            album_key, first_seen_ms, last_seen_ms, missing_since_ms
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL);
        ''');
        try {
          for (final track in remainingNewTracks) {
            insertStmt.execute([
              generateUid(),
              track.path,
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

      // 5. Backfill any existing paths in favorites, ratings, playlist_items, play_events.
      backfilledCount = _backfillUserPathsInTx(nowMs: nowMs);

      _db.execute('COMMIT;');
    } catch (e) {
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
    required TrackIdentity identity,
    required _TrackCandidate target,
    required int nowMs,
  }) {
    final oldCanonical = FilePathUtils.canonicalKey(identity.path);
    final newCanonical = target.canonicalPath;
    final newPath = target.path;

    _db.execute(
      '''
      UPDATE userdata.track_identity
      SET path = ?, size_bytes = ?, duration_ms = ?, title_key = ?,
          artist_key = ?, album_key = ?, last_seen_ms = ?,
          missing_since_ms = NULL
      WHERE uid = ?;
      ''',
      [
        newPath,
        target.sizeBytes,
        target.durationMs,
        target.titleKey,
        target.artistKey,
        target.albumKey,
        nowMs,
        identity.uid,
      ],
    );

    _relinkFavoritesInTx(oldCanonical, newCanonical, newPath);
    _relinkRatingsInTx(oldCanonical, newCanonical, newPath);

    _db.execute(
      '''
      UPDATE userdata.playlist_items
      SET path = ?
      WHERE normalize_file_path(path) = ?;
      ''',
      [newPath, oldCanonical],
    );

    _db.execute(
      '''
      UPDATE userdata.play_events
      SET uri = ?, track_uid = COALESCE(track_uid, ?)
      WHERE normalize_file_path(uri) = ? OR track_uid = ?;
      ''',
      [newPath, identity.uid, oldCanonical, identity.uid],
    );
  }

  void _relinkFavoritesInTx(
    String oldCanonical,
    String newCanonical,
    String newPath,
  ) {
    final rows = _db.select(
      '''
      SELECT path, added_at_ms
      FROM userdata.favorites
      WHERE normalize_file_path(path) IN (?, ?);
      ''',
      [oldCanonical, newCanonical],
    );
    if (rows.isEmpty) return;

    var newestAddedAt = rows.first['added_at_ms'] as int;
    for (final row in rows) {
      final ts = row['added_at_ms'] as int;
      if (ts > newestAddedAt) newestAddedAt = ts;
    }

    _db.execute(
      'DELETE FROM userdata.favorites WHERE normalize_file_path(path) IN (?, ?);',
      [oldCanonical, newCanonical],
    );
    _db.execute(
      'INSERT OR REPLACE INTO userdata.favorites (path, added_at_ms) VALUES (?, ?);',
      [newPath, newestAddedAt],
    );
  }

  void _relinkRatingsInTx(
    String oldCanonical,
    String newCanonical,
    String newPath,
  ) {
    final rows = _db.select(
      '''
      SELECT path, stars, rated_at_ms
      FROM userdata.ratings
      WHERE normalize_file_path(path) IN (?, ?);
      ''',
      [oldCanonical, newCanonical],
    );
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

    _db.execute(
      'DELETE FROM userdata.ratings WHERE normalize_file_path(path) IN (?, ?);',
      [oldCanonical, newCanonical],
    );
    _db.execute(
      'INSERT OR REPLACE INTO userdata.ratings (path, stars, rated_at_ms) VALUES (?, ?, ?);',
      [newPath, bestStars, newestRatedAt],
    );
  }

  int _backfillUserPathsInTx({required int nowMs}) {
    final existingByCanonical = _loadIdentityByCanonical();
    final referencedPaths = <String>{};

    for (final r in _db.select('SELECT path FROM userdata.favorites;')) {
      referencedPaths.add(r['path'] as String);
    }
    for (final r in _db.select('SELECT path FROM userdata.ratings;')) {
      referencedPaths.add(r['path'] as String);
    }
    for (final r in _db.select('SELECT DISTINCT path FROM userdata.playlist_items;')) {
      referencedPaths.add(r['path'] as String);
    }
    for (final r in _db.select('SELECT DISTINCT uri FROM userdata.play_events;')) {
      referencedPaths.add(r['uri'] as String);
    }

    var created = 0;
    final insertStmt = _db.prepare('''
      INSERT INTO userdata.track_identity (
        uid, path, size_bytes, duration_ms, title_key, artist_key,
        album_key, first_seen_ms, last_seen_ms, missing_since_ms
      ) VALUES (?, ?, NULL, NULL, NULL, NULL, NULL, ?, ?, NULL);
    ''');
    try {
      for (final rawPath in referencedPaths) {
        final canonical = FilePathUtils.canonicalKey(rawPath);
        if (canonical.isEmpty || existingByCanonical.containsKey(canonical)) {
          continue;
        }
        final uid = generateUid();
        insertStmt.execute([uid, rawPath, nowMs, nowMs]);
        existingByCanonical[canonical] = TrackIdentity(
          uid: uid,
          path: rawPath,
          firstSeenMs: nowMs,
          lastSeenMs: nowMs,
        );
        created++;
      }
    } finally {
      insertStmt.close();
    }

    // Backfill userdata.play_events.track_uid where NULL.
    final nullUidEvents = _db.select(
      'SELECT id, uri FROM userdata.play_events WHERE track_uid IS NULL;',
    );
    if (nullUidEvents.isNotEmpty) {
      final updateEventStmt = _db.prepare(
        'UPDATE userdata.play_events SET track_uid = ? WHERE id = ?;',
      );
      try {
        for (final row in nullUidEvents) {
          final canonical = FilePathUtils.canonicalKey(row['uri'] as String);
          final identity = existingByCanonical[canonical];
          if (identity != null) {
            updateEventStmt.execute([identity.uid, row['id'] as int]);
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
      SELECT uid, path, size_bytes, duration_ms, title_key, artist_key,
             album_key, first_seen_ms, last_seen_ms, missing_since_ms
      FROM userdata.track_identity;
    ''');
    final map = <String, TrackIdentity>{};
    for (final row in rows) {
      final identity = _mapIdentity(row);
      final canonical = FilePathUtils.canonicalKey(identity.path);
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
