import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/migrations.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/sqlite_row_mappers.dart';
import 'package:aestheticy/library/text_normalizer.dart';

/// Internal SQLite store for folder, track, and track-search operations.
class SqliteTracksStore {
  final Database _db;
  final String Function() _userSchema;

  /// Creates a [SqliteTracksStore] backed by [_db].
  SqliteTracksStore(
    this._db, {
    String Function()? userSchema,
  }) : _userSchema = userSchema ?? (() => 'userdata');

  Future<LibraryFolder> addFolder(String path) async {
    final existing = _db.select(
      'SELECT id, path, last_scan_at FROM main.folders WHERE path = ? LIMIT 1;',
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

    _db.execute('INSERT INTO main.folders (path) VALUES (?);', [path]);
    final id = _db.lastInsertRowId;
    return LibraryFolder(id: id, path: path);
  }

  Future<void> removeFolder(int folderId) async {
    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      _db.execute('DELETE FROM main.tracks WHERE folder_id = ?;', [folderId]);
      _db.execute('DELETE FROM main.folders WHERE id = ?;', [folderId]);
      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
    SchemaMigrator.rebuildArtistLinksSync(_db, userDataSchema: _userSchema());
  }

  /// Clears all rebuildable library tables (`main.track_artists`, `main.tracks`,
  /// `main.folders`) inside a single `main`-only transaction without touching
  /// `userdata`.
  Future<void> resetLibrary() async {
    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      _db.execute('DELETE FROM main.track_artists;');
      _db.execute('DELETE FROM main.tracks;');
      _db.execute('DELETE FROM main.folders;');
      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<List<LibraryFolder>> listFolders() async {
    final rows = _db.select(
      'SELECT id, path, last_scan_at FROM main.folders ORDER BY path COLLATE NOCASE ASC;',
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

  Future<void> markFolderScanned(int folderId, DateTime timestamp) async {
    _db.execute(
      'UPDATE main.folders SET last_scan_at = ? WHERE id = ?;',
      [timestamp.toUtc().millisecondsSinceEpoch, folderId],
    );
  }

  Future<void> upsertTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final stmt = _db.prepare('''
        INSERT INTO main.tracks (
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

  Future<Map<String, ({int mtimeMs, int sizeBytes})>> existingFiles(
    int folderId,
  ) async {
    final rows = _db.select(
      'SELECT path, mtime_ms, size_bytes FROM main.tracks WHERE folder_id = ?;',
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

  Future<void> removeTracksByPath(List<String> paths) async {
    if (paths.isEmpty) return;

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final stmt = _db.prepare('DELETE FROM main.tracks WHERE path = ?;');
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

    final sql = StringBuffer('SELECT * FROM main.tracks ORDER BY $orderBy');
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
    return rows.map(SqliteRowMappers.mapTrack).toList();
  }

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
      SELECT * FROM main.tracks
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY COALESCE(title, path) COLLATE NOCASE ASC
      LIMIT 100;
    ''';

    final params =
        terms.map((t) => '%${SqliteRowMappers.escapeLike(t)}%').toList();
    final rows = _db.select(sql, params);
    return rows.map(SqliteRowMappers.mapTrack).toList();
  }

  Future<int> trackCount() async {
    final row = _db.select('SELECT COUNT(*) AS total FROM main.tracks;').first;
    return row['total'] as int;
  }
}
