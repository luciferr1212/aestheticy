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

  Set<String> _tableColumns(String schema, String table) {
    return _db
        .select('PRAGMA $schema.table_info($table);')
        .map((r) => r['name'] as String)
        .toSet();
  }

  bool _hasTable(String schema, String table) {
    return _db
        .select(
          "SELECT 1 FROM $schema.sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
          [table],
        )
        .isNotEmpty;
  }

  ({String pathKeyExpr, String identityJoin}) _playEventTrackResolution(
    String schema,
  ) {
    final playCols = _tableColumns(schema, 'play_events');
    final hasTrackUid = playCols.contains('track_uid');
    final hasUriKey = playCols.contains('uri_key');
    final hasIdentity = hasTrackUid && _hasTable(schema, 'track_identity');
    final uriFallback = hasUriKey
        ? 'COALESCE(NULLIF(p.uri_key, \'\'), normalize_file_path(p.uri))'
        : 'normalize_file_path(p.uri)';
    if (!hasIdentity) {
      return (pathKeyExpr: uriFallback, identityJoin: '');
    }
    final idCols = _tableColumns(schema, 'track_identity');
    final idPathExpr = idCols.contains('path_key')
        ? 'COALESCE(NULLIF(ti.path_key, \'\'), normalize_file_path(ti.path))'
        : 'normalize_file_path(ti.path)';
    return (
      pathKeyExpr: "COALESCE(NULLIF($idPathExpr, ''), $uriFallback)",
      identityJoin:
          'LEFT JOIN $schema.track_identity ti ON p.track_uid IS NOT NULL AND ti.uid = p.track_uid',
    );
  }

  String _favoritesPathKeyExpr(String schema) {
    final favCols = _tableColumns(schema, 'favorites');
    if (favCols.contains('path_key')) {
      return "COALESCE(NULLIF(f.path_key, ''), normalize_file_path(f.path))";
    }
    return 'normalize_file_path(f.path)';
  }

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

  /// Returns distinct albums ordered by most recent counted play, skipping
  /// tracks no longer present in `main.tracks`.
  Future<List<AlbumSummary>> recentAlbumsPlayed({int limit = 8}) async {
    if (limit <= 0) return const [];
    final u = _userSchema();
    final res = _playEventTrackResolution(u);

    final rows = _db.select(
      '''
      WITH latest_track_play AS (
        SELECT
          ${res.pathKeyExpr} AS resolved_path_key,
          MAX(p.started_at_ms) AS last_played_ms
        FROM $u.play_events p
        ${res.identityJoin}
        WHERE p.counted = 1
        GROUP BY resolved_path_key
      ),
      recent_album_keys AS (
        SELECT
          album_identity_key(t.album, t.album_artist, t.artist, t.path) AS album_key,
          MAX(ltp.last_played_ms) AS last_played_ms,
          MIN(COALESCE(NULLIF(TRIM(t.album), ''), 'Unknown Album')) AS sort_album_name
        FROM latest_track_play ltp
        INNER JOIN main.tracks t ON normalize_file_path(t.path) = ltp.resolved_path_key
        GROUP BY album_key
        ORDER BY last_played_ms DESC, sort_album_name COLLATE NOCASE ASC
        LIMIT ?
      )
      SELECT
        rak.album_key,
        MIN(COALESCE(NULLIF(TRIM(t.album), ''), 'Unknown Album')) AS album_name,
        MAX(NULLIF(TRIM(t.album_artist), '')) AS album_artist,
        MAX(t.year) AS release_year,
        COUNT(*) AS track_count,
        MAX(t.cover_key) AS cover_key,
        COUNT(DISTINCT NULLIF(t.artist, '')) AS distinct_artist_count,
        MIN(NULLIF(t.artist, '')) AS single_artist,
        MAX(t.added_at) AS latest_added_at
      FROM recent_album_keys rak
      INNER JOIN main.tracks t
        ON album_identity_key(t.album, t.album_artist, t.artist, t.path) = rak.album_key
      GROUP BY rak.album_key
      ORDER BY MAX(rak.last_played_ms) DESC, album_name COLLATE NOCASE ASC;
      ''',
      [limit],
    );
    return rows.map(SqliteRowMappers.mapAlbum).toList();
  }

  /// Returns favorited tracks whose last counted play is older than
  /// [olderThan] or that have never been played (counted = 1).
  Future<List<Track>> forgottenFavorites({
    required Duration olderThan,
    int limit = 8,
    DateTime? now,
  }) async {
    if (limit <= 0) return const [];
    final u = _userSchema();
    final res = _playEventTrackResolution(u);
    final favKeyExpr = _favoritesPathKeyExpr(u);
    final cutoffMs =
        (now ?? DateTime.now()).toUtc().subtract(olderThan).millisecondsSinceEpoch;

    final rows = _db.select(
      '''
      WITH latest_track_play AS (
        SELECT
          ${res.pathKeyExpr} AS resolved_path_key,
          MAX(p.started_at_ms) AS last_played_ms
        FROM $u.play_events p
        ${res.identityJoin}
        WHERE p.counted = 1
        GROUP BY resolved_path_key
      ),
      dedup_favorites AS (
        SELECT
          $favKeyExpr AS resolved_fav_key,
          MIN(f.added_at_ms) AS added_at_ms
        FROM $u.favorites f
        GROUP BY resolved_fav_key
      )
      SELECT t.*
      FROM main.tracks t
      INNER JOIN dedup_favorites f
        ON f.resolved_fav_key = normalize_file_path(t.path)
      LEFT JOIN latest_track_play ltp
        ON ltp.resolved_path_key = normalize_file_path(t.path)
      WHERE ltp.last_played_ms IS NULL OR ltp.last_played_ms < ?
      ORDER BY
        CASE WHEN ltp.last_played_ms IS NULL THEN 0 ELSE 1 END ASC,
        COALESCE(ltp.last_played_ms, 0) ASC,
        f.added_at_ms ASC,
        COALESCE(NULLIF(TRIM(t.title), ''), t.path) COLLATE NOCASE ASC
      LIMIT ?;
      ''',
      [cutoffMs, limit],
    );
    return rows.map(SqliteRowMappers.mapTrack).toList();
  }

  /// Returns tracks played (counted = 1) on the same month/day as [today] in
  /// earlier years, ordered newest play first.
  Future<List<Track>> onThisDay(DateTime today, {int limit = 8}) async {
    if (limit <= 0) return const [];
    final u = _userSchema();
    final minRows = _db.select(
      'SELECT MIN(started_at_ms) AS min_ms FROM $u.play_events WHERE counted = 1;',
    );
    final minMs = minRows.first['min_ms'] as int?;
    if (minMs == null) return const [];

    final minDt = DateTime.fromMillisecondsSinceEpoch(minMs, isUtc: true);
    final minYear = ((today.isUtc ? minDt : minDt.toLocal()).year - 1)
        .clamp(1970, today.year);
    final res = _playEventTrackResolution(u);

    final byPath = <String, ({Track track, int lastPlayedMs})>{};
    for (var y = today.year - 1; y >= minYear; y--) {
      if (today.month == 2 && today.day == 29) {
        final isLeap = (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
        if (!isLeap) continue;
      }
      final dayStart = today.isUtc
          ? DateTime.utc(y, today.month, today.day)
          : DateTime(y, today.month, today.day);
      final dayEnd = today.isUtc
          ? DateTime.utc(y, today.month, today.day, 23, 59, 59, 999)
          : DateTime(y, today.month, today.day, 23, 59, 59, 999);
      final rows = _db.select(
        '''
        WITH year_day_plays AS (
          SELECT
            ${res.pathKeyExpr} AS resolved_path_key,
            MAX(p.started_at_ms) AS last_played_ms
          FROM $u.play_events p
          ${res.identityJoin}
          WHERE p.started_at_ms >= ? AND p.started_at_ms <= ? AND p.counted = 1
          GROUP BY resolved_path_key
        )
        SELECT t.*, ydp.last_played_ms AS event_last_played_ms
        FROM main.tracks t
        INNER JOIN year_day_plays ydp
          ON normalize_file_path(t.path) = ydp.resolved_path_key;
        ''',
        [
          dayStart.toUtc().millisecondsSinceEpoch,
          dayEnd.toUtc().millisecondsSinceEpoch,
        ],
      );
      for (final r in rows) {
        final track = SqliteRowMappers.mapTrack(r);
        final lastMs = r['event_last_played_ms'] as int;
        final existing = byPath[track.path];
        if (existing == null || lastMs > existing.lastPlayedMs) {
          byPath[track.path] = (track: track, lastPlayedMs: lastMs);
        }
      }
    }

    final sorted = byPath.values.toList()
      ..sort((a, b) {
        final timeCmp = b.lastPlayedMs.compareTo(a.lastPlayedMs);
        if (timeCmp != 0) return timeCmp;
        final aTitle = (a.track.title?.trim().isNotEmpty ?? false)
            ? a.track.title!.trim()
            : a.track.path;
        final bTitle = (b.track.title?.trim().isNotEmpty ?? false)
            ? b.track.title!.trim()
            : b.track.path;
        return aTitle.toLowerCase().compareTo(bTitle.toLowerCase());
      });
    return sorted.take(limit).map((e) => e.track).toList();
  }

  /// Returns tracks most played (counted = 1) in the current month up to [now].
  Future<List<Track>> mostPlayedThisMonth({
    int limit = 8,
    DateTime? now,
  }) async {
    if (limit <= 0) return const [];
    final u = _userSchema();
    final res = _playEventTrackResolution(u);
    final ref = now ?? DateTime.now();
    final monthStart = ref.isUtc
        ? DateTime.utc(ref.year, ref.month, 1)
        : DateTime(ref.year, ref.month, 1);
    final startMs = monthStart.toUtc().millisecondsSinceEpoch;
    final endMs = ref.toUtc().millisecondsSinceEpoch;

    final rows = _db.select(
      '''
      WITH month_plays AS (
        SELECT
          ${res.pathKeyExpr} AS resolved_path_key,
          COUNT(*) AS play_count,
          COALESCE(SUM(p.listened_ms), 0) AS total_listened_ms,
          MAX(p.started_at_ms) AS last_played_ms
        FROM $u.play_events p
        ${res.identityJoin}
        WHERE p.started_at_ms >= ? AND p.started_at_ms <= ? AND p.counted = 1
        GROUP BY resolved_path_key
      )
      SELECT t.*
      FROM main.tracks t
      INNER JOIN month_plays mp
        ON normalize_file_path(t.path) = mp.resolved_path_key
      ORDER BY
        mp.play_count DESC,
        mp.total_listened_ms DESC,
        mp.last_played_ms DESC,
        COALESCE(NULLIF(TRIM(t.title), ''), t.path) COLLATE NOCASE ASC
      LIMIT ?;
      ''',
      [startMs, endMs, limit],
    );
    return rows.map(SqliteRowMappers.mapTrack).toList();
  }

  /// Returns albums ordered by latest track `added_at` descending.
  Future<List<AlbumSummary>> recentlyAddedAlbums({int limit = 8}) async {
    if (limit <= 0) return const [];
    final rows = _db.select(
      '''
      SELECT
        album_identity_key(album, album_artist, artist, path) AS album_key,
        MIN(COALESCE(NULLIF(TRIM(album), ''), 'Unknown Album')) AS album_name,
        MAX(NULLIF(TRIM(album_artist), '')) AS album_artist,
        MAX(year) AS release_year,
        COUNT(*) AS track_count,
        MAX(cover_key) AS cover_key,
        COUNT(DISTINCT NULLIF(artist, '')) AS distinct_artist_count,
        MIN(NULLIF(artist, '')) AS single_artist,
        MAX(added_at) AS latest_added_at
      FROM main.tracks
      GROUP BY album_key
      ORDER BY latest_added_at DESC, album_name COLLATE NOCASE ASC
      LIMIT ?;
      ''',
      [limit],
    );
    return rows.map(SqliteRowMappers.mapAlbum).toList();
  }
}
