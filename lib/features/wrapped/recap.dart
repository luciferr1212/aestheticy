/// Pure-Dart domain models for Monthly Wrapped and Weekly Listening Recaps.
library;

import '../../library/history_models.dart';

/// Granularity of a generated listening [Recap].
enum RecapPeriodKind {
  /// Calendar month Wrapped recap (requires >= 20 counted plays).
  monthly,

  /// Locale week listening activity recap.
  weekly,
}

/// Deterministic listener personality badge derived strictly from local rules.
enum RecapPersonality {
  /// Strong concentration of listening between 21:00 and 03:59.
  nightOwl,

  /// Strong concentration of listening between 05:00 and 10:59.
  earlyBird,

  /// Deep focus on a single album across the period.
  albumListener,

  /// High share or volume of newly discovered tracks.
  explorer,

  /// Balanced listening rhythm across days and albums.
  steadyListener,
}

/// Highlighted single local calendar day inside a [Recap].
class RecapDayHighlight {
  /// Local calendar date at midnight (`00:00:00`).
  final DateTime date;

  /// Counted plays recorded on [date].
  final int playCount;

  /// Total counted listening duration on [date] in milliseconds.
  final int totalListenedMs;

  /// Creates a [RecapDayHighlight].
  const RecapDayHighlight({
    required this.date,
    required this.playCount,
    required this.totalListenedMs,
  });

  /// Whole rounded listening minutes on [date].
  int get totalMinutes => (totalListenedMs / 60000).round();
}

/// Selectable month entry returned by `RecapBuilder.availableMonths`.
class RecapMonthOption {
  /// Calendar year.
  final int year;

  /// Calendar month (`1..12`).
  final int month;

  /// Counted plays recorded in this month.
  final int playsCounted;

  /// Total counted listening time recorded in this month.
  final int totalListenedMs;

  /// Creates a [RecapMonthOption].
  const RecapMonthOption({
    required this.year,
    required this.month,
    required this.playsCounted,
    required this.totalListenedMs,
  });

  /// Stable `yyyy-MM` identifier for this month.
  String get key => '$year-${month.toString().padLeft(2, '0')}';

  /// Whether this month meets the 20-counted-play Wrapped threshold.
  bool get isEligible => playsCounted >= 20;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecapMonthOption &&
          runtimeType == other.runtimeType &&
          year == other.year &&
          month == other.month &&
          playsCounted == other.playsCounted &&
          totalListenedMs == other.totalListenedMs;

  @override
  int get hashCode =>
      Object.hash(year, month, playsCounted, totalListenedMs);
}

/// Complete immutable listening recap for a calendar month or locale week.
class Recap {
  /// Minimum counted plays required before a monthly Wrapped is unlocked.
  static const int minMonthlyCountedPlays = 20;

  /// Minimum counted plays required before a weekly recap has content.
  static const int minWeeklyCountedPlays = 1;

  /// Monthly Wrapped or weekly recap.
  final RecapPeriodKind kind;

  /// Calendar year (`year` for monthly, or end-of-week year for weekly).
  final int year;

  /// Calendar month (`1..12`) for monthly recaps, or end-of-week month.
  final int month;

  /// ISO-8601 week-numbering year (used in weekly export filenames).
  final int isoYear;

  /// ISO-8601 week number (`1..53`) (used in weekly export filenames).
  final int isoWeek;

  /// Inclusive local start timestamp (`00:00:00.000`).
  final DateTime periodStart;

  /// Inclusive local end timestamp (`23:59:59.999`).
  final DateTime periodEnd;

  /// Total counted listening duration across the period in milliseconds.
  final int totalListenedMs;

  /// Total counted plays in the period.
  final int playsCounted;

  /// Number of distinct tracks played in the period.
  final int distinctTracks;

  /// Number of distinct artists played in the period.
  final int distinctArtists;

  /// Count of distinct tracks whose first-ever counted play fell in this period.
  final int newTracksDiscovered;

  /// Top ranked artist by listening time, or `null` when empty.
  final RankedArtistStat? topArtist;

  /// Up to 5 top tracks ranked by listening time.
  final List<RankedTrackStat> topTracks;

  /// Top ranked album by listening time, or `null` when empty.
  final RankedAlbumStat? topAlbum;

  /// Local day with the highest counted play count (tie-broken by listening ms).
  final RecapDayHighlight? busiestDay;

  /// Local day with the highest cumulative listening time.
  final RecapDayHighlight? longestListeningDay;

  /// Deterministic listener personality badge for the period.
  final RecapPersonality personality;

  /// Minimum counted plays required to treat this recap as eligible.
  final int requiredCountedPlays;

  /// Creates a [Recap].
  const Recap({
    required this.kind,
    required this.year,
    required this.month,
    required this.isoYear,
    required this.isoWeek,
    required this.periodStart,
    required this.periodEnd,
    required this.totalListenedMs,
    required this.playsCounted,
    required this.distinctTracks,
    required this.distinctArtists,
    required this.newTracksDiscovered,
    required this.topArtist,
    required this.topTracks,
    required this.topAlbum,
    required this.busiestDay,
    required this.longestListeningDay,
    required this.personality,
    required this.requiredCountedPlays,
  });

  /// Rounded total minutes listened across the period.
  int get totalMinutes => (totalListenedMs / 60000).round();

  /// True when the period meets its minimum counted-play threshold.
  bool get isEligible => playsCounted >= requiredCountedPlays;

  /// True when at least one counted play exists in the period.
  bool get hasAnyActivity => playsCounted > 0;

  /// Default `.png` filename required for sharing/exporting this recap:
  /// `aestheticy-wrapped-<yyyy-MM>.png` or `aestheticy-week-<yyyy-Www>.png`.
  String get suggestedExportFileName {
    if (kind == RecapPeriodKind.monthly) {
      final mm = month.toString().padLeft(2, '0');
      return 'aestheticy-wrapped-$year-$mm.png';
    }
    final ww = isoWeek.toString().padLeft(2, '0');
    return 'aestheticy-week-$isoYear-W$ww.png';
  }
}
