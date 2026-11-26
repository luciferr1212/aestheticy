/// Read models for date-range play-event analytics queries.
library;

/// Metric used to rank top tracks, artists, and albums.
enum HistoryRankingMetric {
  /// Rank by cumulative listened duration (`SUM(listened_ms)`).
  listenedMs,

  /// Rank by play count (`COUNT(*)`).
  playCount,
}

/// Ranked track entry returned by `topTracksInRange`.
class RankedTrackStat {
  /// Track identity UID if available.
  final String? trackUid;

  /// Latest track URI/path.
  final String uri;

  /// Track title snapshot.
  final String? title;

  /// Artist snapshot.
  final String? artist;

  /// Album snapshot.
  final String? album;

  /// Total play events in range.
  final int playCount;

  /// Total listened milliseconds in range.
  final int totalListenedMs;

  /// Creates a [RankedTrackStat].
  const RankedTrackStat({
    this.trackUid,
    required this.uri,
    this.title,
    this.artist,
    this.album,
    required this.playCount,
    required this.totalListenedMs,
  });
}

/// Ranked artist entry returned by `topArtistsInRange`.
class RankedArtistStat {
  /// Artist display name.
  final String artist;

  /// Total play events in range.
  final int playCount;

  /// Total listened milliseconds in range.
  final int totalListenedMs;

  /// Creates a [RankedArtistStat].
  const RankedArtistStat({
    required this.artist,
    required this.playCount,
    required this.totalListenedMs,
  });
}

/// Ranked album entry returned by `topAlbumsInRange`.
class RankedAlbumStat {
  /// Album title.
  final String album;

  /// Album artist or primary artist.
  final String? artist;

  /// Total play events in range.
  final int playCount;

  /// Total listened milliseconds in range.
  final int totalListenedMs;

  /// Creates a [RankedAlbumStat].
  const RankedAlbumStat({
    required this.album,
    this.artist,
    required this.playCount,
    required this.totalListenedMs,
  });
}

/// Aggregated listening duration for a single UTC calendar day (`yyyy-MM-dd`).
class DailyListeningStat {
  /// UTC calendar date (`yyyy-MM-dd`).
  final String dateKey;

  /// Total listened milliseconds on that UTC day.
  final int totalListenedMs;

  /// Total listened minutes (`totalListenedMs / 60000.0`).
  double get minutes => totalListenedMs / 60000.0;

  /// Creates a [DailyListeningStat].
  const DailyListeningStat({
    required this.dateKey,
    required this.totalListenedMs,
  });
}
