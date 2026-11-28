/// Immutable UI read models consumed by the Stats screen.
library;

import '../../library/history_models.dart';
import 'stats_date_range.dart';

/// A single bar in the Stats daily/monthly listening chart.
class StatsBarBucket {
  /// Local midnight of the day (for day granularity) or 1st of the month.
  final DateTime bucketStart;

  /// Granularity of this bar.
  final StatsBucketGranularity granularity;

  /// Total counted listening duration in milliseconds.
  final int totalListenedMs;

  /// Counted plays within this bucket.
  final int playCount;

  /// Creates a [StatsBarBucket].
  const StatsBarBucket({
    required this.bucketStart,
    required this.granularity,
    required this.totalListenedMs,
    required this.playCount,
  });

  /// Listening duration in fractional minutes.
  double get minutes => totalListenedMs / 60000.0;
}

/// Summary for the day with the highest total listening time in a period.
class StatsBusiestDay {
  /// Local calendar date (midnight).
  final DateTime date;

  /// Total counted listening duration on [date] in milliseconds.
  final int totalListenedMs;

  /// Number of counted plays on [date].
  final int playCount;

  /// Creates a [StatsBusiestDay].
  const StatsBusiestDay({
    required this.date,
    required this.totalListenedMs,
    required this.playCount,
  });
}

/// Complete, immutable snapshot rendered by the Stats view.
class StatsSnapshot {
  /// Active range used to compute this snapshot.
  final StatsRange range;

  /// Local-time window for summaries, heatmap, and rankings.
  final StatsTimeWindow window;

  /// Total counted listening duration inside [window] in milliseconds.
  final int totalListenedMs;

  /// Number of counted play events inside [window].
  final int playsCounted;

  /// Distinct tracks played (counted) inside [window].
  final int distinctTracks;

  /// Distinct artists played (counted) inside [window].
  final int distinctArtists;

  /// Distinct tracks whose very first counted play fell inside [window].
  final int newlyDiscoveredTracks;

  /// Day with the most listening time inside [window], or `null` when empty.
  final StatsBusiestDay? busiestDay;

  /// Comparison against the immediately preceding period, or `null` for
  /// [StatsRange.allTime].
  final StatsPeriodDelta? previousDelta;

  /// Ordered daily or monthly listening bars.
  final List<StatsBarBucket> bars;

  /// Raw weekday (`1..7`) x hour (`0..23`) activity cells inside [window].
  final List<WeekdayHourListeningStat> weekdayHourActivity;

  /// Ordered list of ISO weekdays matching the user's locale (`en` Mon..Sun,
  /// `ar` Sat..Fri).
  final List<int> orderedWeekdays;

  /// Up to 10 top tracks in [window].
  final List<RankedTrackStat> topTracks;

  /// Up to 10 top artists in [window].
  final List<RankedArtistStat> topArtists;

  /// Up to 10 top albums in [window].
  final List<RankedAlbumStat> topAlbums;

  /// Whether there is any counted history in the selected window or bars.
  final bool hasHistory;

  /// Creates a [StatsSnapshot].
  const StatsSnapshot({
    required this.range,
    required this.window,
    required this.totalListenedMs,
    required this.playsCounted,
    required this.distinctTracks,
    required this.distinctArtists,
    required this.newlyDiscoveredTracks,
    required this.busiestDay,
    required this.previousDelta,
    required this.bars,
    required this.weekdayHourActivity,
    required this.orderedWeekdays,
    required this.topTracks,
    required this.topArtists,
    required this.topAlbums,
    required this.hasHistory,
  });
}
