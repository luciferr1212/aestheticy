import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/sqlite_row_mappers.dart';

/// Internal SQLite store for play-event history and recently played tracks.
class SqliteHistoryStore {
  final Database _db;

  /// Creates a [SqliteHistoryStore] backed by [_db].
  SqliteHistoryStore(this._db);

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
    return rows.map(SqliteRowMappers.mapPlayEvent).toList();
  }

  Future<int> playEventCount({bool countedOnly = false}) async {
    final sql = countedOnly
        ? 'SELECT COUNT(*) AS total FROM play_events WHERE counted = 1;'
        : 'SELECT COUNT(*) AS total FROM play_events;';
    final row = _db.select(sql).first;
    return row['total'] as int;
  }

  Future<void> clearPlayEvents() async {
    _db.execute('DELETE FROM play_events;');
  }

  Future<List<Track>> recentlyPlayedTracks({int limit = 200}) async {
    const sql = '''
      SELECT t.* FROM tracks t
      INNER JOIN (
        SELECT normalize_file_path(uri) AS clean_uri,
               MAX(started_at_ms) AS last_played
        FROM play_events
        WHERE counted = 1
        GROUP BY clean_uri
      ) p ON normalize_file_path(t.path) = p.clean_uri
      ORDER BY p.last_played DESC
      LIMIT ?;
    ''';
    final rows = _db.select(sql, [limit]);
    return rows.map(SqliteRowMappers.mapTrack).toList();
  }
}
