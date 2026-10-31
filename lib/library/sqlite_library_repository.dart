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

  /// Opens an in-memory SQLite database, applying schema migrations.
  ///
  /// Primarily intended for isolated unit testing.
  factory SqliteLibraryRepository.inMemory() {
    final db = sqlite3.openInMemory();
    SchemaMigrator.apply(db);
    return SqliteLibraryRepository._(db);
  }

  /// Opens or creates an SQLite database at [filePath], applying schema migrations.
  factory SqliteLibraryRepository.openFile(String filePath) {
    final file = File(filePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final db = sqlite3.open(filePath);
    SchemaMigrator.apply(db);
    return SqliteLibraryRepository._(db);
  }

  /// Wraps an existing [Database] instance, applying schema migrations.
  factory SqliteLibraryRepository.fromDatabase(Database db) {
    SchemaMigrator.apply(db);
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
  Future<List<AlbumSummary>> listAlbums() async {
    final rows = _db.select('''
      SELECT
        COALESCE(NULLIF(album, ''), 'Unknown Album') AS album_name,
        album_artist,
        MAX(year) AS release_year,
        COUNT(*) AS track_count,
        MAX(cover_key) AS cover_key
      FROM tracks
      GROUP BY album_name, album_artist
      ORDER BY album_name COLLATE NOCASE ASC;
    ''');

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
  Future<List<ArtistSummary>> listArtists() async {
    final rows = _db.select('''
      SELECT
        COALESCE(NULLIF(artist, ''), 'Unknown Artist') AS artist_name,
        COUNT(DISTINCT COALESCE(NULLIF(album, ''), 'Unknown Album')) AS album_count,
        COUNT(*) AS track_count
      FROM tracks
      GROUP BY artist_name
      ORDER BY artist_name COLLATE NOCASE ASC;
    ''');

    return rows.map((row) {
      return ArtistSummary(
        name: row['artist_name'] as String,
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
  Future<List<Track>> tracksOfArtist(String artist) async {
    final rows = _db.select(
      '''
      SELECT * FROM tracks
      WHERE (
        (? = 'Unknown Artist' AND (artist IS NULL OR artist = ''))
        OR artist = ?
      )
      ORDER BY COALESCE(year, 0) DESC, COALESCE(album, '') COLLATE NOCASE ASC, COALESCE(disc_no, 1) ASC, COALESCE(track_no, 0) ASC;
      ''',
      [artist, artist],
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

  @override
  Future<List<Track>> search(String query) async {
    final normalized = TextNormalizer.normalize(query);
    if (normalized.isEmpty) return [];

    final terms = normalized
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return [];

    final whereClauses = List.filled(terms.length, 'search_text LIKE ?');
    final sql = '''
      SELECT * FROM tracks
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY COALESCE(title, path) COLLATE NOCASE ASC
      LIMIT 100;
    ''';

    final params = terms.map((t) => '%$t%').toList();
    final rows = _db.select(sql, params);
    return rows.map(_mapTrackRow).toList();
  }

  @override
  Future<int> trackCount() async {
    final row = _db.select('SELECT COUNT(*) AS total FROM tracks;').first;
    return row['total'] as int;
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
