import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/sqlite_row_mappers.dart';

/// Internal SQLite store for favorites, star ratings, and playlists.
class SqliteCollectionsStore {
  final Database _db;

  /// Creates a [SqliteCollectionsStore] backed by [_db].
  SqliteCollectionsStore(this._db);

  // ── Favorites ────────────────────────────────────────────────────────

  Future<Set<String>> favoritePaths() async {
    final rows = _db.select('SELECT path FROM favorites;');
    return rows.map((r) => r['path'] as String).toSet();
  }

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

  Future<List<Track>> favoriteTracks() async {
    final rows = _db.select('''
      SELECT t.* FROM tracks t
      INNER JOIN favorites f ON t.path = f.path
      ORDER BY f.added_at_ms DESC;
    ''');
    return rows.map(SqliteRowMappers.mapTrack).toList();
  }

  // ── Ratings ──────────────────────────────────────────────────────────

  Future<Map<String, int>> allRatings() async {
    final rows = _db.select('SELECT path, stars FROM ratings;');
    return {
      for (final r in rows) r['path'] as String: r['stars'] as int,
    };
  }

  Future<void> setRating(String path, int stars) async {
    if (stars < 0 || stars > 5) {
      throw ArgumentError.value(
        stars,
        'stars',
        'Rating stars must be between 0 and 5',
      );
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
    const sql = '''
      SELECT pi.id AS entry_id, pi.position, pi.path,
             t.id AS t_id, t.path AS t_path, t.folder_id, t.title, t.artist, t.album_artist,
             t.album, t.track_no, t.disc_no, t.year, t.duration_ms, t.mtime_ms, t.size_bytes,
             t.cover_key, t.added_at
      FROM playlist_items pi
      LEFT JOIN tracks t ON normalize_file_path(pi.path) = normalize_file_path(t.path)
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
    if (paths.isEmpty) return 0;

    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final countRow = _db.select(
        'SELECT COUNT(*) AS c FROM playlist_items WHERE playlist_id = ?;',
        [id],
      ).first;
      final currentCount = countRow['c'] as int;
      if (currentCount + paths.length > 20000) {
        throw const PlaylistLimitException(
          'Playlist entry limit of 20000 exceeded',
        );
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
}
