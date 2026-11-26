/// Read-only date-range analytics queries over `userdata.play_events`.
library;

import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/history_models.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/sqlite_row_mappers.dart';

/// Internal SQLite store executing analytics queries over `play_events`.
class SqliteHistoryAnalytics {
  final Database _db;
  final String Function() _userSchema;

  /// Creates a [SqliteHistoryAnalytics] store backed by [_db].
  SqliteHistoryAnalytics(
    this._db, {
    String Function()? userSchema,
  }) : _userSchema = userSchema ?? (() => 'userdata');

  String _selectColumnsSql(String schema) {
    final cols = _db
        .select('PRAGMA $schema.table_info(play_events);')
        .map((r) => r['name'] as String)
        .toSet();
    final hasV2 = cols.contains('track_uid') &&
        cols.contains('source') &&
        cols.contains('session_id') &&
        cols.contains('ended_reason');
    if (hasV2) {
      return 'id, uri, title, artist, album, album_artist, duration_ms, '
          'started_at_ms, listened_ms, counted, completed, '
          'track_uid, source, session_id, ended_reason';
    }
    return 'id, uri, title, artist, album, album_artist, duration_ms, '
        'started_at_ms, listened_ms, counted, completed, '
        "NULL AS track_uid, 'unknown' AS source, NULL AS session_id, "
        'NULL AS ended_reason';
  }

  /// Returns all play events whose `started_at_ms` falls within `[start, end]`,
  /// ordered chronologically (`started_at_ms ASC, id ASC`).
  Future<List<PlayEvent>> playEventsBetween(
    DateTime start,
    DateTime end, {
    bool countedOnly = false,
  }) async {
    final u = _userSchema();
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;
    final cols = _selectColumnsSql(u);
    final countedClause = countedOnly ? ' AND counted = 1' : '';
    final rows = _db.select(
      '''
      SELECT $cols
      FROM $u.play_events
      WHERE started_at_ms >= ? AND started_at_ms <= ?$countedClause
      ORDER BY started_at_ms ASC, id ASC;
      ''',
      [startMs, endMs],
    );
    return rows.map(SqliteRowMappers.mapPlayEvent).toList();
  }

  /// Returns top tracks in `[start, end]` ordered by [metric].
  Future<List<RankedTrackStat>> topTracksInRange(
    DateTime start,
    DateTime end, {
    HistoryRankingMetric metric = HistoryRankingMetric.listenedMs,
    int limit = 20,
    bool countedOnly = false,
  }) async {
    final u = _userSchema();
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;
    final cols = _db
        .select('PRAGMA $u.table_info(play_events);')
        .map((r) => r['name'] as String)
        .toSet();
    final groupExpr = cols.contains('track_uid')
        ? 'COALESCE(track_uid, normalize_file_path(uri))'
        : 'normalize_file_path(uri)';
    final uidExpr = cols.contains('track_uid') ? 'MAX(track_uid)' : 'NULL';
    final countedClause = countedOnly ? ' AND counted = 1' : '';
    final orderExpr = metric == HistoryRankingMetric.playCount
        ? 'play_count DESC, total_listened_ms DESC'
        : 'total_listened_ms DESC, play_count DESC';

    final rows = _db.select(
      '''
      SELECT
        $uidExpr AS track_uid,
        MAX(uri) AS uri,
        MAX(NULLIF(TRIM(title), '')) AS title,
        MAX(NULLIF(TRIM(artist), '')) AS artist,
        MAX(NULLIF(TRIM(album), '')) AS album,
        COUNT(*) AS play_count,
        COALESCE(SUM(listened_ms), 0) AS total_listened_ms
      FROM $u.play_events
      WHERE started_at_ms >= ? AND started_at_ms <= ?$countedClause
      GROUP BY $groupExpr
      ORDER BY $orderExpr
      LIMIT ?;
      ''',
      [startMs, endMs, limit],
    );

    return rows
        .map(
          (r) => RankedTrackStat(
            trackUid: r['track_uid'] as String?,
            uri: r['uri'] as String,
            title: r['title'] as String?,
            artist: r['artist'] as String?,
            album: r['album'] as String?,
            playCount: r['play_count'] as int,
            totalListenedMs: r['total_listened_ms'] as int,
          ),
        )
        .toList();
  }

  /// Returns top artists in `[start, end]` ordered by [metric].
  Future<List<RankedArtistStat>> topArtistsInRange(
    DateTime start,
    DateTime end, {
    HistoryRankingMetric metric = HistoryRankingMetric.listenedMs,
    int limit = 20,
    bool countedOnly = false,
  }) async {
    final u = _userSchema();
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;
    final countedClause = countedOnly ? ' AND counted = 1' : '';
    final orderExpr = metric == HistoryRankingMetric.playCount
        ? 'play_count DESC, total_listened_ms DESC'
        : 'total_listened_ms DESC, play_count DESC';

    final rows = _db.select(
      '''
      SELECT
        TRIM(artist) AS artist_name,
        COUNT(*) AS play_count,
        COALESCE(SUM(listened_ms), 0) AS total_listened_ms
      FROM $u.play_events
      WHERE started_at_ms >= ? AND started_at_ms <= ?
        AND artist IS NOT NULL AND TRIM(artist) != ''$countedClause
      GROUP BY normalize_text(TRIM(artist))
      ORDER BY $orderExpr
      LIMIT ?;
      ''',
      [startMs, endMs, limit],
    );

    return rows
        .map(
          (r) => RankedArtistStat(
            artist: r['artist_name'] as String,
            playCount: r['play_count'] as int,
            totalListenedMs: r['total_listened_ms'] as int,
          ),
        )
        .toList();
  }

  /// Returns top albums in `[start, end]` ordered by [metric].
  Future<List<RankedAlbumStat>> topAlbumsInRange(
    DateTime start,
    DateTime end, {
    HistoryRankingMetric metric = HistoryRankingMetric.listenedMs,
    int limit = 20,
    bool countedOnly = false,
  }) async {
    final u = _userSchema();
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;
    final countedClause = countedOnly ? ' AND counted = 1' : '';
    final orderExpr = metric == HistoryRankingMetric.playCount
        ? 'play_count DESC, total_listened_ms DESC'
        : 'total_listened_ms DESC, play_count DESC';

    final rows = _db.select(
      '''
      SELECT
        TRIM(album) AS album_name,
        MAX(COALESCE(NULLIF(TRIM(album_artist), ''), NULLIF(TRIM(artist), ''))) AS artist_name,
        COUNT(*) AS play_count,
        COALESCE(SUM(listened_ms), 0) AS total_listened_ms
      FROM $u.play_events
      WHERE started_at_ms >= ? AND started_at_ms <= ?
        AND album IS NOT NULL AND TRIM(album) != ''$countedClause
      GROUP BY album_identity_key(album, album_artist, artist, uri)
      ORDER BY $orderExpr
      LIMIT ?;
      ''',
      [startMs, endMs, limit],
    );

    return rows
        .map(
          (r) => RankedAlbumStat(
            album: r['album_name'] as String,
            artist: r['artist_name'] as String?,
            playCount: r['play_count'] as int,
            totalListenedMs: r['total_listened_ms'] as int,
          ),
        )
        .toList();
  }

  /// Returns daily UTC listening totals within `[start, end]` ordered by day.
  Future<List<DailyListeningStat>> listeningMinutesPerDay(
    DateTime start,
    DateTime end, {
    bool countedOnly = false,
  }) async {
    final u = _userSchema();
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;
    final countedClause = countedOnly ? ' AND counted = 1' : '';

    final rows = _db.select(
      '''
      SELECT
        strftime('%Y-%m-%d', started_at_ms / 1000.0, 'unixepoch') AS date_key,
        COALESCE(SUM(listened_ms), 0) AS total_listened_ms
      FROM $u.play_events
      WHERE started_at_ms >= ? AND started_at_ms <= ?$countedClause
      GROUP BY date_key
      ORDER BY date_key ASC;
      ''',
      [startMs, endMs],
    );

    return rows
        .map(
          (r) => DailyListeningStat(
            dateKey: r['date_key'] as String,
            totalListenedMs: r['total_listened_ms'] as int,
          ),
        )
        .toList();
  }

  /// Returns the count of distinct tracks whose very first recorded play event
  /// occurred within `[start, end]`.
  Future<int> distinctTracksFirstPlayedInRange(
    DateTime start,
    DateTime end, {
    bool countedOnly = false,
  }) async {
    final u = _userSchema();
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;
    final cols = _db
        .select('PRAGMA $u.table_info(play_events);')
        .map((r) => r['name'] as String)
        .toSet();
    final groupExpr = cols.contains('track_uid')
        ? 'COALESCE(track_uid, normalize_file_path(uri))'
        : 'normalize_file_path(uri)';
    final countedClause = countedOnly ? 'WHERE counted = 1' : '';

    final rows = _db.select(
      '''
      SELECT COUNT(*) AS total
      FROM (
        SELECT MIN(started_at_ms) AS first_play_ms
        FROM $u.play_events
        $countedClause
        GROUP BY $groupExpr
      )
      WHERE first_play_ms >= ? AND first_play_ms <= ?;
      ''',
      [startMs, endMs],
    );
    return rows.first['total'] as int;
  }
}
