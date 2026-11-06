/// SQLite-backed implementation of [LibraryRepository].
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/migrations.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/text_normalizer.dart';

/// SQLite storage implementation for the music library.
class SqliteLibraryRepository implements LibraryRepository {
  final Database _db;

  SqliteLibraryRepository._(this._db);

  static void _initDb(Database db) {
    SchemaMigrator.apply(db);
    db.createFunction(
      functionName: 'normalize_text',
      argumentCount: const AllowedArgumentCount(1),
      deterministic: true,
      directOnly: false,
      function: (args) {
        final val = args[0];
        if (val == null) return '';
        return TextNormalizer.normalize(val.toString());
      },
    );
  }

  /// Opens an in-memory SQLite database, applying schema migrations.
  ///
  /// Primarily intended for isolated unit testing.
  factory SqliteLibraryRepository.inMemory() {
    final db = sqlite3.openInMemory();
    _initDb(db);
    return SqliteLibraryRepository._(db);
  }

  /// Opens or creates an SQLite database at [filePath], applying schema migrations.
  factory SqliteLibraryRepository.openFile(String filePath) {
    final file = File(filePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final db = sqlite3.open(filePath);
    _initDb(db);
    return SqliteLibraryRepository._(db);
  }

  /// Wraps an existing [Database] instance, applying schema migrations.
  factory SqliteLibraryRepository.fromDatabase(Database db) {
    _initDb(db);
    return SqliteLibraryRepository._(db);
  }

  /// Opens the default database file in the application support directory.
  static Future<SqliteLibraryRepository> openDefault() async {
    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(supportDir.path, 'Aestheticy'));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }
    final dbPath = p.join(dbDir.path, 'library.db');
    return SqliteLibraryRepository.openFile(dbPath);
  }

  @override
  Future<LibraryFolder> addFolder(String path) async {
    final existing = _db.select(
      'SELECT id, path, last_scan_at FROM folders WHERE path = ? LIMIT 1;',
      [path],
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      final scanAtMs = row['last_scan_at'] as int?;
      return LibraryFolder(
        id: row['id'] as int,
        path: row['path'] as String,
        lastScanAt: scanAtMs != null
            ? DateTime.fromMillisecondsSinceEpoch(scanAtMs, isUtc: true)
            : null,
      );
    }

    _db.execute('INSERT INTO folders (path) VALUES (?);', [path]);
    final id = _db.lastInsertRowId;
    return LibraryFolder(id: id, path: path);
  }

  @override
  Future<void> removeFolder(int folderId) async {
    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      _db.execute('DELETE FROM tracks WHERE folder_id = ?;', [folderId]);
      _db.execute('DELETE FROM folders WHERE id = ?;', [folderId]);
      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
    await rebuildArtistLinks();
  }

  @override
  Future<List<LibraryFolder>> listFolders() async {
    final rows = _db.select(
      'SELECT id, path, last_scan_at FROM folders ORDER BY path COLLATE NOCASE ASC;',
    );

    return rows.map((row) {
      final scanAtMs = row['last_scan_at'] as int?;
      return LibraryFolder(
        id: row['id'] as int,
        path: row['path'] as String,
        lastScanAt: scanAtMs != null
            ? DateTime.fromMillisecondsSinceEpoch(scanAtMs, isUtc: true)
            : null,
      );
    }).toList();
  }

  @override
  Future<void> markFolderScanned(int folderId, DateTime timestamp) async {
    _db.execute(
      'UPDATE folders SET last_scan_at = ? WHERE id = ?;',
      [timestamp.toUtc().millisecondsSinceEpoch, folderId],
    );
  }

  @override
  Future<void> upsertTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final stmt = _db.prepare('''
        INSERT INTO tracks (
          path, folder_id, title, artist, album_artist, album,
          track_no, disc_no, year, duration_ms, mtime_ms, size_bytes,
          cover_key, added_at, search_text
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
          folder_id = excluded.folder_id,
          title = excluded.title,
          artist = excluded.artist,
          album_artist = excluded.album_artist,
          album = excluded.album,
          track_no = excluded.track_no,
          disc_no = excluded.disc_no,
          year = excluded.year,
          duration_ms = excluded.duration_ms,
          mtime_ms = excluded.mtime_ms,
          size_bytes = excluded.size_bytes,
          cover_key = excluded.cover_key,
          search_text = excluded.search_text;
      ''');

      for (final track in tracks) {
        final searchText = TextNormalizer.normalize(
          '${track.title ?? ''} ${track.artist ?? ''} ${track.album ?? ''} ${track.albumArtist ?? ''}',
        );

        stmt.execute([
          track.path,
          track.folderId,
          track.title,
          track.artist,
          track.albumArtist,
          track.album,
          track.trackNo,
          track.discNo,
          track.year,
          track.durationMs,
          track.mtimeMs,
          track.sizeBytes,
          track.coverKey,
          track.addedAt.millisecondsSinceEpoch,
          searchText,
        ]);
      }

      stmt.close();
      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<Map<String, ({int mtimeMs, int sizeBytes})>> existingFiles(
    int folderId,
  ) async {
    final rows = _db.select(
      'SELECT path, mtime_ms, size_bytes FROM tracks WHERE folder_id = ?;',
      [folderId],
    );

    final result = <String, ({int mtimeMs, int sizeBytes})>{};
    for (final row in rows) {
      result[row['path'] as String] = (
        mtimeMs: row['mtime_ms'] as int,
        sizeBytes: row['size_bytes'] as int,
      );
    }
    return result;
  }

  @override
  Future<void> removeTracksByPath(List<String> paths) async {
    if (paths.isEmpty) return;

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final stmt = _db.prepare('DELETE FROM tracks WHERE path = ?;');
      for (final path in paths) {
        stmt.execute([path]);
      }
      stmt.close();
      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<List<AlbumSummary>> listAlbums({int? limit, int? offset}) async {
    final sql = StringBuffer('''
      SELECT
        COALESCE(NULLIF(album, ''), 'Unknown Album') AS album_name,
        album_artist,
        MAX(year) AS release_year,
        COUNT(*) AS track_count,
        MAX(cover_key) AS cover_key,
        COUNT(DISTINCT NULLIF(artist, '')) AS distinct_artist_count,
        MIN(NULLIF(artist, '')) AS single_artist
      FROM tracks
      GROUP BY album_name, album_artist
      ORDER BY album_name COLLATE NOCASE ASC
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
      final rawAlbumArtist = row['album_artist'] as String?;
      final distinctArtistCount = row['distinct_artist_count'] as int;
      final singleArtist = row['single_artist'] as String?;

      final String? displayArtist;
      if (rawAlbumArtist != null && rawAlbumArtist.isNotEmpty) {
        displayArtist = rawAlbumArtist;
      } else if (distinctArtistCount == 1 &&
          singleArtist != null &&
          singleArtist.isNotEmpty) {
        displayArtist = singleArtist;
      } else if (distinctArtistCount > 1) {
        displayArtist = 'various';
      } else {
        displayArtist = null;
      }

      return AlbumSummary(
        album: row['album_name'] as String,
        albumArtist: rawAlbumArtist,
        year: row['release_year'] as int?,
        trackCount: row['track_count'] as int,
        coverKey: row['cover_key'] as String?,
        displayArtist: displayArtist,
      );
    }).toList();
  }

  @override
  Future<List<ArtistSummary>> listArtists({int? limit, int? offset}) async {
    final sql = StringBuffer('''
      SELECT
        ta.artist_key,
        COALESCE(
          (
            SELECT aa.canonical_name
            FROM artist_aliases aa
            WHERE aa.canonical_key = ta.artist_key
            LIMIT 1
          ),
          (
            SELECT ta2.artist_name
            FROM track_artists ta2
            WHERE ta2.artist_key = ta.artist_key
            GROUP BY ta2.artist_name
            ORDER BY COUNT(*) DESC, ta2.artist_name ASC
            LIMIT 1
          ),
          'Unknown Artist'
        ) AS artist_name,
        COUNT(DISTINCT COALESCE(NULLIF(t.album, ''), 'Unknown Album')) AS album_count,
        COUNT(DISTINCT t.id) AS track_count
      FROM track_artists ta
      JOIN tracks t ON t.id = ta.track_id
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
      return ArtistSummary(
        key: row['artist_key'] as String,
        name: (row['artist_name'] as String?) ?? 'Unknown Artist',
        albumCount: row['album_count'] as int,
        trackCount: row['track_count'] as int,
      );
    }).toList();
  }

  @override
  Future<List<Track>> tracksOfAlbum(String album, {String? albumArtist}) async {
    final rows = _db.select(
      '''
      SELECT * FROM tracks
      WHERE (
        (? = 'Unknown Album' AND (album IS NULL OR album = ''))
        OR album = ?
      )
      AND (
        ? IS NULL
        OR album_artist = ?
        OR (album_artist IS NULL AND artist = ?)
      )
      ORDER BY COALESCE(disc_no, 1) ASC, COALESCE(track_no, 0) ASC, title COLLATE NOCASE ASC;
      ''',
      [album, album, albumArtist, albumArtist, albumArtist],
    );

    return rows.map(_mapTrackRow).toList();
  }

  @override
  Future<List<Track>> tracksOfArtist(String artist, {String? artistKey}) async {
    final rows = _db.select(
      '''
      SELECT DISTINCT t.*
      FROM tracks t
      JOIN track_artists ta ON ta.track_id = t.id
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

    return rows.map(_mapTrackRow).toList();
  }

  @override
  Future<List<Track>> listTracks({
    TrackSort sort = TrackSort.titleAsc,
    int? limit,
    int? offset,
  }) async {
    final orderBy = switch (sort) {
      TrackSort.titleAsc => 'COALESCE(title, path) COLLATE NOCASE ASC',
      TrackSort.titleDesc => 'COALESCE(title, path) COLLATE NOCASE DESC',
      TrackSort.artistAsc =>
        'COALESCE(artist, \'\') COLLATE NOCASE ASC, COALESCE(title, path) COLLATE NOCASE ASC',
      TrackSort.artistDesc =>
        'COALESCE(artist, \'\') COLLATE NOCASE DESC, COALESCE(title, path) COLLATE NOCASE ASC',
      TrackSort.albumAsc =>
        'COALESCE(album, \'\') COLLATE NOCASE ASC, COALESCE(disc_no, 1) ASC, COALESCE(track_no, 0) ASC',
      TrackSort.albumDesc =>
        'COALESCE(album, \'\') COLLATE NOCASE DESC, COALESCE(disc_no, 1) ASC, COALESCE(track_no, 0) ASC',
      TrackSort.addedAtAsc => 'added_at ASC, id ASC',
      TrackSort.addedAtDesc => 'added_at DESC, id DESC',
    };

    final sql = StringBuffer('SELECT * FROM tracks ORDER BY $orderBy');
    final params = <Object?>[];

    if (limit != null) {
      sql.write(' LIMIT ?');
      params.add(limit);
      if (offset != null) {
        sql.write(' OFFSET ?');
        params.add(offset);
      }
    }

    final rows = _db.select(sql.toString(), params);
    return rows.map(_mapTrackRow).toList();
  }

  static String _escapeLike(String term) {
    return term
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  @override
  Future<List<Track>> search(String query) async {
    final normalized = TextNormalizer.normalize(query);
    if (normalized.isEmpty) return [];

    final terms = normalized
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return [];

    final whereClauses =
        List.filled(terms.length, "search_text LIKE ? ESCAPE '\\'");
    final sql = '''
      SELECT * FROM tracks
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY COALESCE(title, path) COLLATE NOCASE ASC
      LIMIT 100;
    ''';

    final params = terms.map((t) => '%${_escapeLike(t)}%').toList();
    final rows = _db.select(sql, params);
    return rows.map(_mapTrackRow).toList();
  }

  @override
  Future<List<AlbumSummary>> searchAlbums(String query, {int? limit}) async {
    final normalized = TextNormalizer.normalize(query);
    if (normalized.isEmpty) return [];

    final terms = normalized
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return [];

    final whereClauses = terms.map((_) =>
        "(normalize_text(COALESCE(NULLIF(album, ''), 'Unknown Album') || ' ' || COALESCE(album_artist, '')) LIKE ? ESCAPE '\\')"
    ).join(' AND ');

    final effectiveLimit = limit ?? 50;
    final sql = '''
      SELECT
        COALESCE(NULLIF(album, ''), 'Unknown Album') AS album_name,
        album_artist,
        MAX(year) AS release_year,
        COUNT(*) AS track_count,
        MAX(cover_key) AS cover_key,
        COUNT(DISTINCT NULLIF(artist, '')) AS distinct_artist_count,
        MIN(NULLIF(artist, '')) AS single_artist
      FROM tracks
      WHERE $whereClauses
      GROUP BY album_name, album_artist
      ORDER BY album_name COLLATE NOCASE ASC
      LIMIT ?;
    ''';

    final params = <Object?>[];
    for (final t in terms) {
      params.add('%${_escapeLike(t)}%');
    }
    params.add(effectiveLimit);

    final rows = _db.select(sql, params);
    return rows.map((row) {
      final rawAlbumArtist = row['album_artist'] as String?;
      final distinctArtistCount = row['distinct_artist_count'] as int;
      final singleArtist = row['single_artist'] as String?;

      final String? displayArtist;
      if (rawAlbumArtist != null && rawAlbumArtist.isNotEmpty) {
        displayArtist = rawAlbumArtist;
      } else if (distinctArtistCount == 1 &&
          singleArtist != null &&
          singleArtist.isNotEmpty) {
        displayArtist = singleArtist;
      } else if (distinctArtistCount > 1) {
        displayArtist = 'various';
      } else {
        displayArtist = null;
      }

      return AlbumSummary(
        album: row['album_name'] as String,
        albumArtist: rawAlbumArtist,
        year: row['release_year'] as int?,
        trackCount: row['track_count'] as int,
        coverKey: row['cover_key'] as String?,
        displayArtist: displayArtist,
      );
    }).toList();
  }

  @override
  Future<List<ArtistSummary>> searchArtists(String query, {int? limit}) async {
    final normalized = TextNormalizer.normalize(query);
    if (normalized.isEmpty) return [];

    final terms = normalized
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return [];

    final whereClauses = terms.map((_) =>
        "(normalize_text(ta.artist_name) LIKE ? ESCAPE '\\' OR ta.artist_key LIKE ? ESCAPE '\\')"
    ).join(' AND ');

    final effectiveLimit = limit ?? 50;
    final sql = '''
      SELECT
        ta.artist_key,
        COALESCE(
          (
            SELECT aa.canonical_name
            FROM artist_aliases aa
            WHERE aa.canonical_key = ta.artist_key
            LIMIT 1
          ),
          (
            SELECT ta2.artist_name
            FROM track_artists ta2
            WHERE ta2.artist_key = ta.artist_key
            GROUP BY ta2.artist_name
            ORDER BY COUNT(*) DESC, ta2.artist_name ASC
            LIMIT 1
          ),
          'Unknown Artist'
        ) AS artist_name,
        COUNT(DISTINCT COALESCE(NULLIF(t.album, ''), 'Unknown Album')) AS album_count,
        COUNT(DISTINCT t.id) AS track_count
      FROM track_artists ta
      JOIN tracks t ON t.id = ta.track_id
      WHERE $whereClauses
      GROUP BY ta.artist_key
      ORDER BY artist_name COLLATE NOCASE ASC
      LIMIT ?;
    ''';

    final params = <Object?>[];
    for (final t in terms) {
      final escaped = '%${_escapeLike(t)}%';
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

  @override
  Future<int> albumCount() async {
    final row = _db.select('''
      SELECT COUNT(*) AS total FROM (
        SELECT 1 FROM tracks
        GROUP BY COALESCE(NULLIF(album, ''), 'Unknown Album'), album_artist
      );
    ''').first;
    return row['total'] as int;
  }

  @override
  Future<int> artistCount() async {
    final row = _db.select('''
      SELECT COUNT(DISTINCT artist_key) AS total FROM track_artists;
    ''').first;
    return row['total'] as int;
  }

  @override
  Future<int> trackCount() async {
    final row = _db.select('SELECT COUNT(*) AS total FROM tracks;').first;
    return row['total'] as int;
  }

  @override
  Future<void> mergeArtists(
    String sourceKey,
    String targetKey, {
    String? targetName,
  }) async {
    final sKey = TextNormalizer.normalize(sourceKey);
    final tKey = TextNormalizer.normalize(targetKey);

    if (sKey.isEmpty || tKey.isEmpty) {
      throw ArgumentError('Artist keys cannot be empty.');
    }
    if (sKey == tKey) {
      throw ArgumentError('Cannot merge an artist into itself.');
    }

    // 1. Fetch current aliases to check for cycles and flatten chains
    final rows = _db.select(
      'SELECT alias_key, canonical_key, canonical_name FROM artist_aliases;',
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
        FROM track_artists
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
          FROM tracks
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

    // 4. Update and flatten all aliases in a transaction
    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      _db.execute('''
        UPDATE artist_aliases
        SET canonical_key = ?, canonical_name = ?
        WHERE canonical_key = ?;
      ''', [rootTargetKey, canonicalName, sKey]);

      _db.execute('''
        INSERT OR REPLACE INTO artist_aliases (alias_key, canonical_key, canonical_name)
        VALUES (?, ?, ?);
      ''', [sKey, rootTargetKey, canonicalName]);

      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }

    await rebuildArtistLinks();
  }

  @override
  Future<void> unmergeArtist(String aliasKey) async {
    final key = TextNormalizer.normalize(aliasKey);
    _db.execute('DELETE FROM artist_aliases WHERE alias_key = ?;', [key]);
    await rebuildArtistLinks();
  }

  @override
  Future<List<ArtistAlias>> listAliases() async {
    final rows = _db.select('''
      SELECT alias_key, canonical_key, canonical_name
      FROM artist_aliases
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

  @override
  Future<void> addNoSplit(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final key = TextNormalizer.normalize(trimmed);
    _db.execute('''
      INSERT OR REPLACE INTO artist_no_split (artist_key, artist_name)
      VALUES (?, ?);
    ''', [key, trimmed]);
    await rebuildArtistLinks();
  }

  @override
  Future<void> removeNoSplit(String key) async {
    final norm = TextNormalizer.normalize(key);
    _db.execute('DELETE FROM artist_no_split WHERE artist_key = ?;', [norm]);
    await rebuildArtistLinks();
  }

  @override
  Future<List<ArtistNoSplit>> listNoSplit() async {
    final rows = _db.select('''
      SELECT artist_key, artist_name
      FROM artist_no_split
      ORDER BY artist_name COLLATE NOCASE ASC;
    ''');
    return rows.map((r) {
      return ArtistNoSplit(
        artistKey: r['artist_key'] as String,
        artistName: r['artist_name'] as String,
      );
    }).toList();
  }

  @override
  Future<void> rebuildArtistLinks() async {
    SchemaMigrator.rebuildArtistLinksSync(_db);
  }

  @override
  Future<int> insertPlayEvent(PlayEvent e) async {
    _db.execute(
      '''
      INSERT INTO play_events (
        uri, title, artist, album, album_artist,
        duration_ms, started_at_ms, listened_ms, counted, completed
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      [
        e.uri,
        e.title,
        e.artist,
        e.album,
        e.albumArtist,
        e.durationMs,
        e.startedAt.toUtc().millisecondsSinceEpoch,
        e.listenedMs,
        e.counted ? 1 : 0,
        e.completed ? 1 : 0,
      ],
    );
    return _db.lastInsertRowId;
  }

  @override
  Future<void> updatePlayEvent(
    int id, {
    required int listenedMs,
    required bool counted,
    required bool completed,
  }) async {
    _db.execute(
      '''
      UPDATE play_events
      SET listened_ms = ?, counted = ?, completed = ?
      WHERE id = ?;
      ''',
      [
        listenedMs,
        counted ? 1 : 0,
        completed ? 1 : 0,
        id,
      ],
    );
  }

  @override
  Future<List<PlayEvent>> recentPlayEvents({int limit = 50}) async {
    final rows = _db.select(
      '''
      SELECT id, uri, title, artist, album, album_artist,
             duration_ms, started_at_ms, listened_ms, counted, completed
      FROM play_events
      ORDER BY started_at_ms DESC, id DESC
      LIMIT ?;
      ''',
      [limit],
    );
    return rows.map(_mapPlayEventRow).toList();
  }

  @override
  Future<int> playEventCount({bool countedOnly = false}) async {
    final sql = countedOnly
        ? 'SELECT COUNT(*) AS total FROM play_events WHERE counted = 1;'
        : 'SELECT COUNT(*) AS total FROM play_events;';
    final row = _db.select(sql).first;
    return row['total'] as int;
  }

  @override
  Future<void> clearPlayEvents() async {
    _db.execute('DELETE FROM play_events;');
  }

  // ── Favorites ────────────────────────────────────────────────────────

  @override
  Future<Set<String>> favoritePaths() async {
    final rows = _db.select('SELECT path FROM favorites;');
    return rows.map((r) => r['path'] as String).toSet();
  }

  @override
  Future<void> setFavorite(String path, bool value) async {
    if (value) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _db.execute(
        'INSERT OR REPLACE INTO favorites (path, added_at_ms) VALUES (?, ?);',
        [path, now],
      );
    } else {
      _db.execute(
        'DELETE FROM favorites WHERE path = ?;',
        [path],
      );
    }
  }

  @override
  Future<List<Track>> favoriteTracks() async {
    final rows = _db.select('''
      SELECT t.* FROM tracks t
      INNER JOIN favorites f ON t.path = f.path
      ORDER BY f.added_at_ms DESC;
    ''');
    return rows.map(_mapTrackRow).toList();
  }

  // ── Ratings ──────────────────────────────────────────────────────────

  @override
  Future<Map<String, int>> allRatings() async {
    final rows = _db.select('SELECT path, stars FROM ratings;');
    return {
      for (final r in rows) r['path'] as String: r['stars'] as int,
    };
  }

  @override
  Future<void> setRating(String path, int stars) async {
    if (stars < 0 || stars > 5) {
      throw ArgumentError.value(stars, 'stars', 'Rating stars must be between 0 and 5');
    }
    if (stars == 0) {
      _db.execute('DELETE FROM ratings WHERE path = ?;', [path]);
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      _db.execute(
        'INSERT OR REPLACE INTO ratings (path, stars, rated_at_ms) VALUES (?, ?, ?);',
        [path, stars, now],
      );
    }
  }

  // ── Playlists ────────────────────────────────────────────────────────

  static String _validatePlaylistName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const PlaylistNameException(PlaylistNameError.empty);
    }
    if (trimmed.length > 60) {
      throw PlaylistNameException(PlaylistNameError.tooLong, name: trimmed);
    }
    return trimmed;
  }

  @override
  Future<PlaylistSummary> createPlaylist(String name) async {
    final trimmed = _validatePlaylistName(name);

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final countRow = _db.select('SELECT COUNT(*) AS c FROM playlists;').first;
      if ((countRow['c'] as int) >= 500) {
        throw const PlaylistLimitException('Maximum 500 playlists limit reached');
      }

      final clash = _db.select(
        'SELECT id FROM playlists WHERE LOWER(name) = LOWER(?);',
        [trimmed],
      );
      if (clash.isNotEmpty) {
        throw PlaylistNameException(PlaylistNameError.duplicate, name: trimmed);
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      _db.execute(
        'INSERT INTO playlists (name, created_at_ms, updated_at_ms) VALUES (?, ?, ?);',
        [trimmed, now, now],
      );
      final id = _db.lastInsertRowId;
      _db.execute('COMMIT;');

      final nowDt = DateTime.fromMillisecondsSinceEpoch(now, isUtc: true);
      return PlaylistSummary(
        id: id,
        name: trimmed,
        trackCount: 0,
        totalDurationMs: 0,
        createdAt: nowDt,
        updatedAt: nowDt,
        coverKey: null,
      );
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<void> renamePlaylist(int id, String name) async {
    final trimmed = _validatePlaylistName(name);

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final clash = _db.select(
        'SELECT id FROM playlists WHERE LOWER(name) = LOWER(?) AND id != ?;',
        [trimmed, id],
      );
      if (clash.isNotEmpty) {
        throw PlaylistNameException(PlaylistNameError.duplicate, name: trimmed);
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      _db.execute(
        'UPDATE playlists SET name = ?, updated_at_ms = ? WHERE id = ?;',
        [trimmed, now, id],
      );
      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<void> deletePlaylist(int id) async {
    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      _db.execute('DELETE FROM playlist_items WHERE playlist_id = ?;', [id]);
      _db.execute('DELETE FROM playlists WHERE id = ?;', [id]);
      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<List<PlaylistSummary>> listPlaylists() async {
    const sql = '''
      SELECT p.id, p.name, p.created_at_ms, p.updated_at_ms,
             COUNT(pi.id) AS track_count,
             COALESCE(SUM(t.duration_ms), 0) AS total_duration_ms,
             (
               SELECT t2.cover_key FROM playlist_items pi2
               INNER JOIN tracks t2 ON pi2.path = t2.path
               WHERE pi2.playlist_id = p.id AND t2.cover_key IS NOT NULL AND t2.cover_key != ''
               ORDER BY pi2.position ASC
               LIMIT 1
             ) AS cover_key
      FROM playlists p
      LEFT JOIN playlist_items pi ON p.id = pi.playlist_id
      LEFT JOIN tracks t ON pi.path = t.path
      GROUP BY p.id
      ORDER BY p.name COLLATE NOCASE ASC;
    ''';
    final rows = _db.select(sql);
    return rows.map((r) => PlaylistSummary(
      id: r['id'] as int,
      name: r['name'] as String,
      trackCount: r['track_count'] as int,
      totalDurationMs: r['total_duration_ms'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at_ms'] as int, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at_ms'] as int, isUtc: true),
      coverKey: r['cover_key'] as String?,
    )).toList();
  }

  @override
  Future<List<PlaylistEntry>> playlistEntries(int id) async {
    const sql = '''
      SELECT pi.id AS entry_id, pi.position, pi.path,
             t.id AS t_id, t.path AS t_path, t.folder_id, t.title, t.artist, t.album_artist,
             t.album, t.track_no, t.disc_no, t.year, t.duration_ms, t.mtime_ms, t.size_bytes,
             t.cover_key, t.added_at
      FROM playlist_items pi
      LEFT JOIN tracks t ON pi.path = t.path
      WHERE pi.playlist_id = ?
      ORDER BY pi.position ASC;
    ''';
    final rows = _db.select(sql, [id]);
    return rows.map((r) {
      final tId = r['t_id'] as int?;
      final Track? track;
      if (tId != null) {
        track = Track(
          id: tId,
          path: r['t_path'] as String,
          folderId: r['folder_id'] as int,
          title: r['title'] as String?,
          artist: r['artist'] as String?,
          albumArtist: r['album_artist'] as String?,
          album: r['album'] as String?,
          trackNo: r['track_no'] as int?,
          discNo: r['disc_no'] as int?,
          year: r['year'] as int?,
          durationMs: r['duration_ms'] as int,
          mtimeMs: r['mtime_ms'] as int,
          sizeBytes: r['size_bytes'] as int,
          coverKey: r['cover_key'] as String?,
          addedAt: DateTime.fromMillisecondsSinceEpoch(
            r['added_at'] as int,
            isUtc: true,
          ),
        );
      } else {
        track = null;
      }
      return PlaylistEntry(
        entryId: r['entry_id'] as int,
        position: r['position'] as int,
        path: r['path'] as String,
        track: track,
      );
    }).toList();
  }

  @override
  Future<int> addToPlaylist(int id, List<String> paths) async {
    if (paths.isEmpty) return 0;

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final countRow = _db.select(
        'SELECT COUNT(*) AS c FROM playlist_items WHERE playlist_id = ?;',
        [id],
      ).first;
      final currentCount = countRow['c'] as int;
      if (currentCount + paths.length > 20000) {
        throw const PlaylistLimitException('Playlist entry limit of 20000 exceeded');
      }

      final maxPosRow = _db.select(
        'SELECT COALESCE(MAX(position), -1) AS max_pos FROM playlist_items WHERE playlist_id = ?;',
        [id],
      ).first;
      var nextPos = (maxPosRow['max_pos'] as int) + 1;

      final now = DateTime.now().millisecondsSinceEpoch;
      final stmt = _db.prepare(
        'INSERT INTO playlist_items (playlist_id, position, path, added_at_ms) VALUES (?, ?, ?, ?);',
      );
      try {
        for (final p in paths) {
          stmt.execute([id, nextPos++, p, now]);
        }
      } finally {
        stmt.close();
      }

      _db.execute(
        'UPDATE playlists SET updated_at_ms = ? WHERE id = ?;',
        [now, id],
      );
      _db.execute('COMMIT;');
      return paths.length;
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<void> removePlaylistEntries(int id, List<int> entryIds) async {
    if (entryIds.isEmpty) return;

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final placeholders = List.filled(entryIds.length, '?').join(',');
      _db.execute(
        'DELETE FROM playlist_items WHERE playlist_id = ? AND id IN ($placeholders);',
        [id, ...entryIds],
      );

      // Renumber positions without gaps
      final remaining = _db.select(
        'SELECT id FROM playlist_items WHERE playlist_id = ? ORDER BY position ASC, id ASC;',
        [id],
      );
      final updateStmt = _db.prepare(
        'UPDATE playlist_items SET position = ? WHERE id = ?;',
      );
      try {
        for (var i = 0; i < remaining.length; i++) {
          updateStmt.execute([i, remaining[i]['id'] as int]);
        }
      } finally {
        updateStmt.close();
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      _db.execute(
        'UPDATE playlists SET updated_at_ms = ? WHERE id = ?;',
        [now, id],
      );
      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<void> movePlaylistEntry(int id, int entryId, int newPosition) async {
    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final rows = _db.select(
        'SELECT id FROM playlist_items WHERE playlist_id = ? ORDER BY position ASC, id ASC;',
        [id],
      );
      final entryIds = rows.map((r) => r['id'] as int).toList();
      final oldIndex = entryIds.indexOf(entryId);
      if (oldIndex == -1) {
        _db.execute('ROLLBACK;');
        return;
      }
      final targetIndex = newPosition.clamp(0, entryIds.length - 1);
      if (oldIndex == targetIndex) {
        _db.execute('ROLLBACK;');
        return;
      }

      entryIds.removeAt(oldIndex);
      entryIds.insert(targetIndex, entryId);

      final updateStmt = _db.prepare(
        'UPDATE playlist_items SET position = ? WHERE id = ?;',
      );
      try {
        for (var i = 0; i < entryIds.length; i++) {
          updateStmt.execute([i, entryIds[i]]);
        }
      } finally {
        updateStmt.close();
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      _db.execute(
        'UPDATE playlists SET updated_at_ms = ? WHERE id = ?;',
        [now, id],
      );
      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  // ── Recently Played ──────────────────────────────────────────────────

  @override
  Future<List<Track>> recentlyPlayedTracks({int limit = 200}) async {
    const sql = '''
      SELECT t.* FROM tracks t
      INNER JOIN (
        SELECT (CASE WHEN uri LIKE 'file://%' THEN SUBSTR(uri, 8) ELSE uri END) AS clean_uri,
               MAX(started_at_ms) AS last_played
        FROM play_events
        WHERE counted = 1
        GROUP BY clean_uri
      ) p ON t.path = p.clean_uri
      ORDER BY p.last_played DESC
      LIMIT ?;
    ''';
    final rows = _db.select(sql, [limit]);
    return rows.map(_mapTrackRow).toList();
  }

  @override
  Future<void> close() async {
    _db.close();
  }

  static PlayEvent _mapPlayEventRow(Row row) {
    return PlayEvent(
      id: row['id'] as int,
      uri: row['uri'] as String,
      title: row['title'] as String?,
      artist: row['artist'] as String?,
      album: row['album'] as String?,
      albumArtist: row['album_artist'] as String?,
      durationMs: row['duration_ms'] as int?,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        row['started_at_ms'] as int,
        isUtc: true,
      ),
      listenedMs: row['listened_ms'] as int,
      counted: (row['counted'] as int) == 1,
      completed: (row['completed'] as int) == 1,
    );
  }

  static Track _mapTrackRow(Row row) {
    return Track(
      id: row['id'] as int,
      path: row['path'] as String,
      folderId: row['folder_id'] as int,
      title: row['title'] as String?,
      artist: row['artist'] as String?,
      albumArtist: row['album_artist'] as String?,
      album: row['album'] as String?,
      trackNo: row['track_no'] as int?,
      discNo: row['disc_no'] as int?,
      year: row['year'] as int?,
      durationMs: row['duration_ms'] as int,
      mtimeMs: row['mtime_ms'] as int,
      sizeBytes: row['size_bytes'] as int,
      coverKey: row['cover_key'] as String?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        row['added_at'] as int,
        isUtc: true,
      ),
    );
  }
}
