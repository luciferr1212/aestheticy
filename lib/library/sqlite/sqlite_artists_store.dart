import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/migrations.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/sqlite_row_mappers.dart';
import 'package:aestheticy/library/text_normalizer.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

/// Internal SQLite store for artists, artist search, merges, and no-split rules.
class SqliteArtistsStore {
  final Database _db;
  final String Function() _userSchema;
  final UserDataAccessMode Function() _accessMode;

  /// Creates a [SqliteArtistsStore] backed by [_db].
  SqliteArtistsStore(
    this._db, {
    String Function()? userSchema,
    UserDataAccessMode Function()? accessMode,
  })  : _userSchema = userSchema ?? (() => 'userdata'),
        _accessMode = accessMode ?? (() => UserDataAccessMode.normal);

  void _requireWritable(String operation) {
    if (_accessMode() == UserDataAccessMode.safeReadOnly) {
      throw UserDataReadOnlyException(operation);
    }
  }

  Future<List<ArtistSummary>> listArtists({int? limit, int? offset}) async {
    final u = _userSchema();
    final sql = StringBuffer('''
      SELECT
        ta.artist_key,
        COALESCE(
          (
            SELECT aa.canonical_name
            FROM $u.artist_aliases aa
            WHERE aa.canonical_key = ta.artist_key
            LIMIT 1
          ),
          (
            SELECT ta2.artist_name
            FROM main.track_artists ta2
            WHERE ta2.artist_key = ta.artist_key
            GROUP BY ta2.artist_name
            ORDER BY COUNT(*) DESC, ta2.artist_name ASC
            LIMIT 1
          ),
          'Unknown Artist'
        ) AS artist_name,
        COUNT(DISTINCT NULLIF(TRIM(t.album), '')) AS album_count,
        COUNT(DISTINCT t.id) AS track_count,
        MAX(t.added_at) AS latest_added_at
      FROM main.track_artists ta
      JOIN main.tracks t ON t.id = ta.track_id
      GROUP BY ta.artist_key
      ORDER BY artist_name COLLATE NOCASE ASC
    ''');
    final params = <Object?>[];
    if (limit != null) {
      sql.write(' LIMIT ?');
      params.add(limit);
      if (offset != null) {
        sql.write(' OFFSET ?');
        params.add(offset);
      }
    }
    sql.write(';');

    final rows = _db.select(sql.toString(), params);

    return rows.map((row) {
      final addedAtVal = row['latest_added_at'] as int?;
      return ArtistSummary(
        key: row['artist_key'] as String,
        name: (row['artist_name'] as String?) ?? 'Unknown Artist',
        albumCount: row['album_count'] as int,
        trackCount: row['track_count'] as int,
        addedAt: addedAtVal != null
            ? DateTime.fromMillisecondsSinceEpoch(addedAtVal)
            : null,
      );
    }).toList();
  }

  Future<List<Track>> tracksOfArtist(String artist, {String? artistKey}) async {
    final rows = _db.select(
      '''
      SELECT DISTINCT t.*
      FROM main.tracks t
      JOIN main.track_artists ta ON ta.track_id = t.id
      WHERE (
        (? IS NOT NULL AND ta.artist_key = ?)
        OR ta.artist_key = ?
        OR ta.artist_key = normalize_text(?)
        OR ta.artist_name = ?
      )
      ORDER BY COALESCE(t.year, 0) DESC, COALESCE(t.album, '') COLLATE NOCASE ASC, COALESCE(t.disc_no, 1) ASC, COALESCE(t.track_no, 0) ASC;
      ''',
      [artistKey, artistKey, artist, artist, artist],
    );

    return rows.map(SqliteRowMappers.mapTrack).toList();
  }

  Future<List<ArtistSummary>> searchArtists(String query, {int? limit}) async {
    final normalized = TextNormalizer.normalize(query);
    if (normalized.isEmpty) return [];

    final terms = normalized
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return [];

    final whereClauses = terms
        .map(
          (_) =>
              "(normalize_text(ta.artist_name) LIKE ? ESCAPE '\\' OR ta.artist_key LIKE ? ESCAPE '\\')",
        )
        .join(' AND ');

    final u = _userSchema();
    final effectiveLimit = limit ?? 50;
    final sql = '''
      SELECT
        ta.artist_key,
        COALESCE(
          (
            SELECT aa.canonical_name
            FROM $u.artist_aliases aa
            WHERE aa.canonical_key = ta.artist_key
            LIMIT 1
          ),
          (
            SELECT ta2.artist_name
            FROM main.track_artists ta2
            WHERE ta2.artist_key = ta.artist_key
            GROUP BY ta2.artist_name
            ORDER BY COUNT(*) DESC, ta2.artist_name ASC
            LIMIT 1
          ),
          'Unknown Artist'
        ) AS artist_name,
        COUNT(DISTINCT NULLIF(TRIM(t.album), '')) AS album_count,
        COUNT(DISTINCT t.id) AS track_count
      FROM main.track_artists ta
      JOIN main.tracks t ON t.id = ta.track_id
      WHERE $whereClauses
      GROUP BY ta.artist_key
      ORDER BY artist_name COLLATE NOCASE ASC
      LIMIT ?;
    ''';

    final params = <Object?>[];
    for (final t in terms) {
      final escaped = '%${SqliteRowMappers.escapeLike(t)}%';
      params.add(escaped);
      params.add(escaped);
    }
    params.add(effectiveLimit);

    final rows = _db.select(sql, params);
    return rows.map((row) {
      return ArtistSummary(
        key: row['artist_key'] as String,
        name: (row['artist_name'] as String?) ?? 'Unknown Artist',
        albumCount: row['album_count'] as int,
        trackCount: row['track_count'] as int,
      );
    }).toList();
  }

  Future<int> artistCount() async {
    final row = _db.select('''
      SELECT COUNT(DISTINCT artist_key) AS total FROM main.track_artists;
    ''').first;
    return row['total'] as int;
  }

  Future<void> mergeArtists(
    String sourceKey,
    String targetKey, {
    String? targetName,
  }) async {
    _requireWritable('mergeArtists');
    final sKey = TextNormalizer.normalize(sourceKey);
    final tKey = TextNormalizer.normalize(targetKey);

    if (sKey.isEmpty || tKey.isEmpty) {
      throw ArgumentError('Artist keys cannot be empty.');
    }
    if (sKey == tKey) {
      throw ArgumentError('Cannot merge an artist into itself.');
    }

    final u = _userSchema();

    // 1. Fetch current aliases to check for cycles and flatten chains
    final rows = _db.select(
      'SELECT alias_key, canonical_key, canonical_name FROM $u.artist_aliases;',
    );
    final aliasMap = <String, String>{};
    final canonicalNameMap = <String, String>{};
    for (final r in rows) {
      aliasMap[r['alias_key'] as String] = r['canonical_key'] as String;
      canonicalNameMap[r['alias_key'] as String] =
          r['canonical_name'] as String;
    }

    // 2. Trace targetKey to its root canonical
    var rootTargetKey = tKey;
    final visited = <String>{rootTargetKey};
    while (aliasMap.containsKey(rootTargetKey)) {
      final next = aliasMap[rootTargetKey]!;
      if (next == sKey) {
        throw ArgumentError('Cannot merge: creates a cycle ($sKey -> $tKey).');
      }
      if (!visited.add(next)) break;
      rootTargetKey = next;
    }

    if (rootTargetKey == sKey) {
      throw ArgumentError('Cannot merge: creates a cycle.');
    }

    // 3. Find display name for rootTargetKey
    String canonicalName = targetName?.trim().isNotEmpty == true
        ? targetName!.trim()
        : tKey;

    if (targetName == null || targetName.trim().isEmpty) {
      final targetArtistRows = _db.select('''
        SELECT artist_name
        FROM main.track_artists
        WHERE artist_key = ?
        GROUP BY artist_name
        ORDER BY COUNT(*) DESC, artist_name ASC
        LIMIT 1;
      ''', [rootTargetKey]);

      if (targetArtistRows.isNotEmpty) {
        canonicalName = targetArtistRows.first['artist_name'] as String;
      } else if (canonicalNameMap.containsKey(rootTargetKey)) {
        canonicalName = canonicalNameMap[rootTargetKey]!;
      } else {
        final directRows = _db.select('''
          SELECT artist
          FROM main.tracks
          WHERE normalize_text(artist) = ?
          LIMIT 1;
        ''', [rootTargetKey]);
        if (directRows.isNotEmpty && directRows.first['artist'] != null) {
          canonicalName = directRows.first['artist'] as String;
        } else if (targetKey.trim().isNotEmpty && targetKey.trim() != tKey) {
          canonicalName = targetKey.trim();
        }
      }
    }

    // 4. Update and flatten all aliases in a userdata-only transaction
    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      _db.execute('''
        UPDATE $u.artist_aliases
        SET canonical_key = ?, canonical_name = ?
        WHERE canonical_key = ?;
      ''', [rootTargetKey, canonicalName, sKey]);

      _db.execute('''
        INSERT OR REPLACE INTO $u.artist_aliases (alias_key, canonical_key, canonical_name)
        VALUES (?, ?, ?);
      ''', [sKey, rootTargetKey, canonicalName]);

      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }

    await rebuildArtistLinks();
  }

  Future<void> unmergeArtist(String aliasKey) async {
    _requireWritable('unmergeArtist');
    final u = _userSchema();
    final key = TextNormalizer.normalize(aliasKey);
    _db.execute('DELETE FROM $u.artist_aliases WHERE alias_key = ?;', [key]);
    await rebuildArtistLinks();
  }

  Future<List<ArtistAlias>> listAliases() async {
    final u = _userSchema();
    final rows = _db.select('''
      SELECT alias_key, canonical_key, canonical_name
      FROM $u.artist_aliases
      ORDER BY canonical_name COLLATE NOCASE ASC, alias_key ASC;
    ''');
    return rows.map((r) {
      return ArtistAlias(
        aliasKey: r['alias_key'] as String,
        canonicalKey: r['canonical_key'] as String,
        canonicalName: r['canonical_name'] as String,
      );
    }).toList();
  }

  Future<void> addNoSplit(String name) async {
    _requireWritable('addNoSplit');
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final u = _userSchema();
    final key = TextNormalizer.normalize(trimmed);
    _db.execute('''
      INSERT OR REPLACE INTO $u.artist_no_split (artist_key, artist_name)
      VALUES (?, ?);
    ''', [key, trimmed]);
    await rebuildArtistLinks();
  }

  Future<void> removeNoSplit(String key) async {
    _requireWritable('removeNoSplit');
    final u = _userSchema();
    final norm = TextNormalizer.normalize(key);
    _db.execute('DELETE FROM $u.artist_no_split WHERE artist_key = ?;', [norm]);
    await rebuildArtistLinks();
  }

  Future<List<ArtistNoSplit>> listNoSplit() async {
    final u = _userSchema();
    final rows = _db.select('''
      SELECT artist_key, artist_name
      FROM $u.artist_no_split
      ORDER BY artist_name COLLATE NOCASE ASC;
    ''');
    return rows.map((r) {
      return ArtistNoSplit(
        artistKey: r['artist_key'] as String,
        artistName: r['artist_name'] as String,
      );
    }).toList();
  }

  Future<void> rebuildArtistLinks() async {
    SchemaMigrator.rebuildArtistLinksSync(_db, userDataSchema: _userSchema());
  }
}
