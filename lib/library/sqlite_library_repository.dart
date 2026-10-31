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

    await rebuildArtistLinks();
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

    await rebuildArtistLinks();
  }

  @override
  Future<List<AlbumSummary>> listAlbums({int? limit, int? offset}) async {
    final sql = StringBuffer('''
      SELECT
        COALESCE(NULLIF(album, ''), 'Unknown Album') AS album_name,
        album_artist,
        MAX(year) AS release_year,
        COUNT(*) AS track_count,
        MAX(cover_key) AS cover_key
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
      return AlbumSummary(
        album: row['album_name'] as String,
        albumArtist: row['album_artist'] as String?,
        year: row['release_year'] as int?,
        trackCount: row['track_count'] as int,
        coverKey: row['cover_key'] as String?,
      );
    }).toList();
  }

  @override
  Future<List<ArtistSummary>> listArtists({int? limit, int? offset}) async {
    final sql = StringBuffer('''
      SELECT
        ta.artist_key,
        (
          SELECT ta2.artist_name
          FROM track_artists ta2
          WHERE ta2.artist_key = ta.artist_key
          GROUP BY ta2.artist_name
          ORDER BY COUNT(*) DESC, ta2.artist_name ASC
          LIMIT 1
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
        MAX(cover_key) AS cover_key
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
      return AlbumSummary(
        album: row['album_name'] as String,
        albumArtist: row['album_artist'] as String?,
        year: row['release_year'] as int?,
        trackCount: row['track_count'] as int,
        coverKey: row['cover_key'] as String?,
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
        (
          SELECT ta2.artist_name
          FROM track_artists ta2
          WHERE ta2.artist_key = ta.artist_key
          GROUP BY ta2.artist_name
          ORDER BY COUNT(*) DESC, ta2.artist_name ASC
          LIMIT 1
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
  Future<void> mergeArtists(String sourceKey, String targetKey) async {
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
    String canonicalName = tKey;
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
  Future<void> close() async {
    _db.close();
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
