import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/library/file_path_utils.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/sqlite_row_mappers.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

/// Internal SQLite store for play-event history and recently played tracks.
class SqliteHistoryStore {
  final Database _db;
  final String Function() _userSchema;
  final UserDataAccessMode Function() _accessMode;
  final AppLogger? logger;
  bool _loggedReadOnlyPlayWarning = false;

  /// Creates a [SqliteHistoryStore] backed by [_db].
  SqliteHistoryStore(
    this._db, {
    String Function()? userSchema,
    UserDataAccessMode Function()? accessMode,
    this.logger,
  })  : _userSchema = userSchema ?? (() => 'userdata'),
        _accessMode = accessMode ?? (() => UserDataAccessMode.normal);

  void _logReadOnlyPlaySkippedOnce() {
    if (_loggedReadOnlyPlayWarning) return;
    _loggedReadOnlyPlayWarning = true;
    (logger ?? AppLogger.instance).warning(
      'History',
      'Play event recording skipped: user data is in safe read-only mode',
    );
  }

  bool _hasV2Columns(String schema) {
    final cols = _db
        .select('PRAGMA $schema.table_info(play_events);')
        .map((r) => r['name'] as String)
        .toSet();
    return cols.contains('track_uid') &&
        cols.contains('source') &&
        cols.contains('session_id') &&
        cols.contains('ended_reason');
  }

  String? _resolveUidForUri(String schema, String uri) {
    final hasIdentity = _db
        .select(
          "SELECT 1 FROM $schema.sqlite_master WHERE type = 'table' AND name = 'track_identity' LIMIT 1;",
        )
        .isNotEmpty;
    if (!hasIdentity) return null;
    final canonical = FilePathUtils.canonicalKey(uri);
    if (canonical.isEmpty) return null;
    final rows = _db.select(
      'SELECT uid FROM $schema.track_identity WHERE normalize_file_path(path) = ? LIMIT 1;',
      [canonical],
    );
    if (rows.isEmpty) return null;
    return rows.first['uid'] as String;
  }

  Future<int> insertPlayEvent(PlayEvent e) async {
    if (_accessMode() == UserDataAccessMode.safeReadOnly) {
      _logReadOnlyPlaySkippedOnce();
      return -1;
    }
    final u = _userSchema();
    final resolvedUid = e.trackUid ?? _resolveUidForUri(u, e.uri);
    _db.execute(
      '''
      INSERT INTO $u.play_events (
        uri, title, artist, album, album_artist,
        duration_ms, started_at_ms, listened_ms, counted, completed,
        track_uid, source, session_id, ended_reason
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
        resolvedUid,
        e.source,
        e.sessionId,
        e.endedReason,
      ],
    );
    return _db.lastInsertRowId;
  }

  Future<void> updatePlayEvent(
    int id, {
    required int listenedMs,
    required bool counted,
    required bool completed,
    String? endedReason,
  }) async {
    if (_accessMode() == UserDataAccessMode.safeReadOnly) {
      _logReadOnlyPlaySkippedOnce();
      return;
    }
    if (id <= 0) return;
    final u = _userSchema();
    _db.execute(
      '''
      UPDATE $u.play_events
      SET listened_ms = ?,
          counted = ?,
          completed = ?,
          ended_reason = COALESCE(?, ended_reason)
      WHERE id = ?;
      ''',
      [
        listenedMs,
        counted ? 1 : 0,
        completed ? 1 : 0,
        endedReason,
        id,
      ],
    );
  }

  /// Cheap single-statement heartbeat update for the active play session.
  Future<void> updatePlayEventHeartbeat(int id, int listenedMs) async {
    if (_accessMode() == UserDataAccessMode.safeReadOnly) {
      _logReadOnlyPlaySkippedOnce();
      return;
    }
    if (id <= 0) return;
    final u = _userSchema();
    _db.execute(
      'UPDATE $u.play_events SET listened_ms = ? WHERE id = ?;',
      [listenedMs, id],
    );
  }

  /// Marks any open play events (`ended_reason IS NULL`) from an unexpected
  /// termination as `'interrupted'`, keeping their last heartbeat `listened_ms`.
  Future<int> closeInterruptedPlayEvents() async {
    if (_accessMode() == UserDataAccessMode.safeReadOnly) {
      return 0;
    }
    final u = _userSchema();
    if (!_hasV2Columns(u)) return 0;
    _db.execute(
      "UPDATE $u.play_events SET ended_reason = 'interrupted' WHERE ended_reason IS NULL;",
    );
    return _db.updatedRows;
  }

  /// Backfills `track_uid` for existing play events using `track_identity`.
  Future<int> backfillPlayEventTrackUids() async {
    if (_accessMode() == UserDataAccessMode.safeReadOnly) {
      return 0;
    }
    final u = _userSchema();
    if (!_hasV2Columns(u)) return 0;
    final hasIdentity = _db
        .select(
          "SELECT 1 FROM $u.sqlite_master WHERE type = 'table' AND name = 'track_identity' LIMIT 1;",
        )
        .isNotEmpty;
    if (!hasIdentity) return 0;

    final identityMap = <String, String>{};
    for (final row in _db.select('SELECT uid, path FROM $u.track_identity;')) {
      final canonical = FilePathUtils.canonicalKey(row['path'] as String);
      if (canonical.isNotEmpty) {
        identityMap.putIfAbsent(canonical, () => row['uid'] as String);
      }
    }
    if (identityMap.isEmpty) return 0;

    final missing = _db.select(
      'SELECT id, uri FROM $u.play_events WHERE track_uid IS NULL;',
    );
    var updated = 0;
    final stmt = _db.prepare(
      'UPDATE $u.play_events SET track_uid = ? WHERE id = ?;',
    );
    try {
      for (final row in missing) {
        final canonical = FilePathUtils.canonicalKey(row['uri'] as String);
        final uid = identityMap[canonical];
        if (uid != null) {
          stmt.execute([uid, row['id'] as int]);
          updated++;
        }
      }
    } finally {
      stmt.close();
    }
    return updated;
  }

  Future<List<PlayEvent>> recentPlayEvents({int limit = 50}) async {
    final u = _userSchema();
    final cols = _hasV2Columns(u)
        ? 'id, uri, title, artist, album, album_artist, duration_ms, '
            'started_at_ms, listened_ms, counted, completed, '
            'track_uid, source, session_id, ended_reason'
        : 'id, uri, title, artist, album, album_artist, duration_ms, '
            'started_at_ms, listened_ms, counted, completed, '
            "NULL AS track_uid, 'unknown' AS source, NULL AS session_id, "
            'NULL AS ended_reason';
    final rows = _db.select(
      '''
      SELECT $cols
      FROM $u.play_events
      ORDER BY started_at_ms DESC, id DESC
      LIMIT ?;
      ''',
      [limit],
    );
    return rows.map(SqliteRowMappers.mapPlayEvent).toList();
  }

  Future<int> playEventCount({bool countedOnly = false}) async {
    final u = _userSchema();
    final sql = countedOnly
        ? 'SELECT COUNT(*) AS total FROM $u.play_events WHERE counted = 1;'
        : 'SELECT COUNT(*) AS total FROM $u.play_events;';
    final row = _db.select(sql).first;
    return row['total'] as int;
  }

  Future<void> clearPlayEvents() async {
    if (_accessMode() == UserDataAccessMode.safeReadOnly) {
      throw const UserDataReadOnlyException('clearPlayEvents');
    }
    final u = _userSchema();
    _db.execute('DELETE FROM $u.play_events;');
  }

  Future<List<Track>> recentlyPlayedTracks({int limit = 200}) async {
    final u = _userSchema();
    final sql = '''
      SELECT t.* FROM main.tracks t
      INNER JOIN (
        SELECT normalize_file_path(uri) AS clean_uri,
               MAX(started_at_ms) AS last_played
        FROM $u.play_events
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
