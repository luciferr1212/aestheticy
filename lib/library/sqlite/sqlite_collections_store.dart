import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/library/file_path_utils.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/sqlite_row_mappers.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

/// Internal SQLite store for favorites, star ratings, and playlists.
class SqliteCollectionsStore {
  final Database _db;
  final String Function() _userSchema;
  final UserDataAccessMode Function() _accessMode;

  /// Creates a [SqliteCollectionsStore] backed by [_db].
  SqliteCollectionsStore(
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

  // ── Favorites ────────────────────────────────────────────────────────

  Future<Set<String>> favoritePaths() async {
    final u = _userSchema();
    final rows = _db.select('SELECT path FROM $u.favorites;');
    return rows.map((r) => r['path'] as String).toSet();
  }

  Future<void> setFavorite(String path, bool value) async {
    _requireWritable('setFavorite');
    final u = _userSchema();
    if (value) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final key = FilePathUtils.canonicalKey(path);
      _db.execute(
        'INSERT OR REPLACE INTO $u.favorites (path, added_at_ms, path_key) VALUES (?, ?, ?);',
        [path, now, key],
      );
    } else {
      _db.execute(
        'DELETE FROM $u.favorites WHERE path = ?;',
        [path],
      );
    }
  }

  Future<List<Track>> favoriteTracks() async {
    final u = _userSchema();
    final rows = _db.select('''
      SELECT t.* FROM main.tracks t
      INNER JOIN $u.favorites f ON t.path = f.path
      ORDER BY f.added_at_ms DESC;
    ''');
    return rows.map(SqliteRowMappers.mapTrack).toList();
  }

  // ── Ratings ──────────────────────────────────────────────────────────

  Future<Map<String, int>> allRatings() async {
    final u = _userSchema();
    final rows = _db.select('SELECT path, stars FROM $u.ratings;');
    return {
      for (final r in rows) r['path'] as String: r['stars'] as int,
    };
  }

  Future<void> setRating(String path, int stars) async {
    _requireWritable('setRating');
    if (stars < 0 || stars > 5) {
      throw ArgumentError.value(
        stars,
        'stars',
        'Rating stars must be between 0 and 5',
      );
    }
    final u = _userSchema();
    if (stars == 0) {
      _db.execute('DELETE FROM $u.ratings WHERE path = ?;', [path]);
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      final key = FilePathUtils.canonicalKey(path);
      _db.execute(
        'INSERT OR REPLACE INTO $u.ratings (path, stars, rated_at_ms, path_key) VALUES (?, ?, ?, ?);',
        [path, stars, now, key],
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

  Future<PlaylistSummary> createPlaylist(String name) async {
    _requireWritable('createPlaylist');
    final u = _userSchema();
    final trimmed = _validatePlaylistName(name);

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final countRow =
          _db.select('SELECT COUNT(*) AS c FROM $u.playlists;').first;
      if ((countRow['c'] as int) >= 500) {
        throw const PlaylistLimitException('Maximum 500 playlists limit reached');
      }

      final clash = _db.select(
        'SELECT id FROM $u.playlists WHERE LOWER(name) = LOWER(?);',
        [trimmed],
      );
      if (clash.isNotEmpty) {
        throw PlaylistNameException(PlaylistNameError.duplicate, name: trimmed);
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      _db.execute(
        'INSERT INTO $u.playlists (name, created_at_ms, updated_at_ms) VALUES (?, ?, ?);',
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
    } catch (e, st) {
      AppLogger.instance.error(
        'CollectionsStore',
        'Playlist transaction failed',
        e,
        st,
      );
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> renamePlaylist(int id, String name) async {
    _requireWritable('renamePlaylist');
    final u = _userSchema();
    final trimmed = _validatePlaylistName(name);

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final clash = _db.select(
        'SELECT id FROM $u.playlists WHERE LOWER(name) = LOWER(?) AND id != ?;',
        [trimmed, id],
      );
      if (clash.isNotEmpty) {
        throw PlaylistNameException(PlaylistNameError.duplicate, name: trimmed);
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      _db.execute(
        'UPDATE $u.playlists SET name = ?, updated_at_ms = ? WHERE id = ?;',
        [trimmed, now, id],
      );
      _db.execute('COMMIT;');
    } catch (e, st) {
      AppLogger.instance.error(
        'CollectionsStore',
        'Playlist transaction failed',
        e,
        st,
      );
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> deletePlaylist(int id) async {
    _requireWritable('deletePlaylist');
    final u = _userSchema();
    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      _db.execute(
        'DELETE FROM $u.playlist_items WHERE playlist_id = ?;',
        [id],
      );
      _db.execute('DELETE FROM $u.playlists WHERE id = ?;', [id]);
      _db.execute('COMMIT;');
    } catch (e, st) {
      AppLogger.instance.error(
        'CollectionsStore',
        'Playlist transaction failed',
        e,
        st,
      );
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<List<PlaylistSummary>> listPlaylists() async {
    final u = _userSchema();
    final sql = '''
      SELECT p.id, p.name, p.created_at_ms, p.updated_at_ms,
             COUNT(pi.id) AS track_count,
             COALESCE(SUM(t.duration_ms), 0) AS total_duration_ms,
             (
               SELECT t2.cover_key FROM $u.playlist_items pi2
               INNER JOIN main.tracks t2 ON pi2.path = t2.path
               WHERE pi2.playlist_id = p.id AND t2.cover_key IS NOT NULL AND t2.cover_key != ''
               ORDER BY pi2.position ASC
               LIMIT 1
             ) AS cover_key
      FROM $u.playlists p
      LEFT JOIN $u.playlist_items pi ON p.id = pi.playlist_id
      LEFT JOIN main.tracks t ON pi.path = t.path
      GROUP BY p.id
      ORDER BY p.name COLLATE NOCASE ASC;
    ''';
    final rows = _db.select(sql);
    return rows
        .map(
          (r) => PlaylistSummary(
            id: r['id'] as int,
            name: r['name'] as String,
            trackCount: r['track_count'] as int,
            totalDurationMs: r['total_duration_ms'] as int,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              r['created_at_ms'] as int,
              isUtc: true,
            ),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              r['updated_at_ms'] as int,
              isUtc: true,
            ),
            coverKey: r['cover_key'] as String?,
          ),
        )
        .toList();
  }

  Future<List<PlaylistEntry>> playlistEntries(int id) async {
    final u = _userSchema();
    final sql = '''
      SELECT pi.id AS entry_id, pi.position, pi.path,
             t.id AS t_id, t.path AS t_path, t.folder_id, t.title, t.artist, t.album_artist,
             t.album, t.track_no, t.disc_no, t.year, t.duration_ms, t.mtime_ms, t.size_bytes,
             t.cover_key, t.added_at
      FROM $u.playlist_items pi
      LEFT JOIN main.tracks t ON normalize_file_path(pi.path) = normalize_file_path(t.path)
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

  Future<int> addToPlaylist(int id, List<String> paths) async {
    _requireWritable('addToPlaylist');
    if (paths.isEmpty) return 0;
    final u = _userSchema();

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final countRow = _db.select(
        'SELECT COUNT(*) AS c FROM $u.playlist_items WHERE playlist_id = ?;',
        [id],
      ).first;
      final currentCount = countRow['c'] as int;
      if (currentCount + paths.length > 20000) {
        throw const PlaylistLimitException(
          'Playlist entry limit of 20000 exceeded',
        );
      }

      final maxPosRow = _db.select(
        'SELECT COALESCE(MAX(position), -1) AS max_pos FROM $u.playlist_items WHERE playlist_id = ?;',
        [id],
      ).first;
      var nextPos = (maxPosRow['max_pos'] as int) + 1;

      final now = DateTime.now().millisecondsSinceEpoch;
      final stmt = _db.prepare(
        'INSERT INTO $u.playlist_items (playlist_id, position, path, added_at_ms, path_key) VALUES (?, ?, ?, ?, ?);',
      );
      try {
        for (final p in paths) {
          stmt.execute([id, nextPos++, p, now, FilePathUtils.canonicalKey(p)]);
        }
      } finally {
        stmt.close();
      }

      _db.execute(
        'UPDATE $u.playlists SET updated_at_ms = ? WHERE id = ?;',
        [now, id],
      );
      _db.execute('COMMIT;');
      return paths.length;
    } catch (e, st) {
      AppLogger.instance.error(
        'CollectionsStore',
        'Playlist transaction failed',
        e,
        st,
      );
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> removePlaylistEntries(int id, List<int> entryIds) async {
    _requireWritable('removePlaylistEntries');
    if (entryIds.isEmpty) return;
    final u = _userSchema();

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final placeholders = List.filled(entryIds.length, '?').join(',');
      _db.execute(
        'DELETE FROM $u.playlist_items WHERE playlist_id = ? AND id IN ($placeholders);',
        [id, ...entryIds],
      );

      // Renumber positions without gaps
      final remaining = _db.select(
        'SELECT id FROM $u.playlist_items WHERE playlist_id = ? ORDER BY position ASC, id ASC;',
        [id],
      );
      final updateStmt = _db.prepare(
        'UPDATE $u.playlist_items SET position = ? WHERE id = ?;',
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
        'UPDATE $u.playlists SET updated_at_ms = ? WHERE id = ?;',
        [now, id],
      );
      _db.execute('COMMIT;');
    } catch (e, st) {
      AppLogger.instance.error(
        'CollectionsStore',
        'Playlist transaction failed',
        e,
        st,
      );
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> movePlaylistEntry(int id, int entryId, int newPosition) async {
    _requireWritable('movePlaylistEntry');
    final u = _userSchema();
    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final rows = _db.select(
        'SELECT id FROM $u.playlist_items WHERE playlist_id = ? ORDER BY position ASC, id ASC;',
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
        'UPDATE $u.playlist_items SET position = ? WHERE id = ?;',
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
        'UPDATE $u.playlists SET updated_at_ms = ? WHERE id = ?;',
        [now, id],
      );
      _db.execute('COMMIT;');
    } catch (e, st) {
      AppLogger.instance.error(
        'CollectionsStore',
        'Playlist transaction failed',
        e,
        st,
      );
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }
}
