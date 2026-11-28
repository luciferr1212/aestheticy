/// Shared local-time date-range and calendar boundary helpers for Stats.
library;

/// Supported time windows on the Stats screen.
enum StatsRange {
  /// Current locale calendar week (bars display the last 7 days).
  week,

  /// Current calendar month (bars display the last 30 days).
  month,

  /// Current calendar year (bars display the 12 months of the year).
  year,

  /// All recorded listening history (bars display monthly totals).
  allTime,
}

/// Bucket granularity for listening bars.
enum StatsBucketGranularity {
  /// One bar per local calendar day.
  day,

  /// One bar per local calendar month.
  month,
}

/// Inclusive local-time window `[start, end]`.
class StatsTimeWindow {
  /// Inclusive local start boundary (typically `00:00:00.000`).
  final DateTime start;

  /// Inclusive local end boundary (typically `23:59:59.999`).
  final DateTime end;

  /// Creates a [StatsTimeWindow].
  const StatsTimeWindow({required this.start, required this.end});

  /// Returns whether [timestamp] (in local time) falls within `[start, end]`.
  bool contains(DateTime timestamp) {
    final ms = timestamp.millisecondsSinceEpoch;
    return ms >= start.millisecondsSinceEpoch &&
        ms <= end.millisecondsSinceEpoch;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatsTimeWindow &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Percentage comparison against the immediately preceding period.
class StatsPeriodDelta {
  /// Listened milliseconds in the active period.
  final int currentMs;

  /// Listened milliseconds in the preceding period.
  final int previousMs;

  /// Signed difference (`currentMs - previousMs`).
  final int deltaMs;

  /// Percentage change vs previous period, or `null` when [previousMs] is 0.
  final double? percentChange;

  /// True when the previous period had zero listening while the current period
  /// has positive listening time.
  final bool isNew;

  /// Creates a [StatsPeriodDelta].
  const StatsPeriodDelta({
    required this.currentMs,
    required this.previousMs,
    required this.deltaMs,
    required this.percentChange,
    required this.isNew,
  });

  /// Signed difference in minutes.
  double get deltaMinutes => deltaMs / 60000.0;
}

/// Pure, DST-safe local calendar calculations for the Stats feature.
abstract final class StatsDateRange {
  /// Returns the ISO weekday (`DateTime.monday`..`DateTime.sunday`) that
  /// starts the week for [languageCode] (Saturday for `'ar'`, Monday otherwise).
  static int firstDayOfWeekForLanguage(String languageCode) {
    return languageCode == 'ar' ? DateTime.saturday : DateTime.monday;
  }

  /// Returns ISO weekdays (`1..7`) ordered starting with the locale's first
  /// day of week.
  static List<int> orderedWeekdaysForLanguage(String languageCode) {
    final first = firstDayOfWeekForLanguage(languageCode);
    return List<int>.unmodifiable(
      List<int>.generate(7, (i) => ((first - 1 + i) % 7) + 1),
    );
  }

  /// Normalizes [dt] into local time without losing instant accuracy.
  static DateTime toLocal(DateTime dt) => dt.isUtc ? dt.toLocal() : dt;

  /// Returns local midnight (`00:00:00.000`) on [dt]'s local calendar date.
  static DateTime startOfLocalDay(DateTime dt) {
    final local = toLocal(dt);
    return DateTime(local.year, local.month, local.day);
  }

  /// Returns `23:59:59.999` on [dt]'s local calendar date, computed from the
  /// next local midnight so DST transitions never drift across days.
  static DateTime endOfLocalDay(DateTime dt) {
    final local = toLocal(dt);
    return DateTime(
      local.year,
      local.month,
      local.day + 1,
    ).subtract(const Duration(milliseconds: 1));
  }

  /// Adds [days] local calendar days at local midnight without DST drift.
  static DateTime addLocalDays(DateTime dt, int days) {
    final local = toLocal(dt);
    return DateTime(local.year, local.month, local.day + days);
  }

  /// Returns signed whole calendar days from [from] to [to] using local dates.
  static int localDayDifference(DateTime from, DateTime to) {
    final a = toLocal(from);
    final b = toLocal(to);
    final utcA = DateTime.utc(a.year, a.month, a.day);
    final utcB = DateTime.utc(b.year, b.month, b.day);
    return utcB.difference(utcA).inDays;
  }

  /// Returns local midnight of the week start containing [dt].
  static DateTime startOfLocalWeek(DateTime dt, {String languageCode = 'en'}) {
    final day = startOfLocalDay(dt);
    final first = firstDayOfWeekForLanguage(languageCode);
    final offset = (day.weekday - first + 7) % 7;
    return addLocalDays(day, -offset);
  }

  /// Returns the query/summary [StatsTimeWindow] for [range] at [now].
  static StatsTimeWindow windowFor(
    StatsRange range,
    DateTime now, {
    String languageCode = 'en',
  }) {
    final localNow = toLocal(now);
    final end = endOfLocalDay(localNow);
    switch (range) {
      case StatsRange.week:
        return StatsTimeWindow(
          start: startOfLocalWeek(localNow, languageCode: languageCode),
          end: end,
        );
      case StatsRange.month:
        return StatsTimeWindow(
          start: DateTime(localNow.year, localNow.month, 1),
          end: end,
        );
      case StatsRange.year:
        return StatsTimeWindow(start: DateTime(localNow.year, 1, 1), end: end);
      case StatsRange.allTime:
        return StatsTimeWindow(start: DateTime(1970, 1, 1), end: end);
    }
  }

  /// Returns the immediately preceding [StatsTimeWindow] for [range], or `null`
  /// for [StatsRange.allTime].
  static StatsTimeWindow? previousWindowFor(
    StatsRange range,
    DateTime now, {
    String languageCode = 'en',
  }) {
    final localNow = toLocal(now);
    switch (range) {
      case StatsRange.week:
        final currentStart = startOfLocalWeek(
          localNow,
          languageCode: languageCode,
        );
        return StatsTimeWindow(
          start: addLocalDays(currentStart, -7),
          end: endOfLocalDay(addLocalDays(currentStart, -1)),
        );
      case StatsRange.month:
        return StatsTimeWindow(
          start: DateTime(localNow.year, localNow.month - 1, 1),
          end: endOfLocalDay(DateTime(localNow.year, localNow.month, 0)),
        );
      case StatsRange.year:
        return StatsTimeWindow(
          start: DateTime(localNow.year - 1, 1, 1),
          end: endOfLocalDay(DateTime(localNow.year - 1, 12, 31)),
        );
      case StatsRange.allTime:
        return null;
    }
  }

  /// Returns the granularity used by the listening bar chart for [range].
  static StatsBucketGranularity barGranularityFor(StatsRange range) {
    switch (range) {
      case StatsRange.week:
      case StatsRange.month:
        return StatsBucketGranularity.day;
      case StatsRange.year:
      case StatsRange.allTime:
        return StatsBucketGranularity.month;
    }
  }

  /// Returns the span covered by the listening bar chart for [range] at [now].
  static StatsTimeWindow barsWindowFor(
    StatsRange range,
    DateTime now, {
    DateTime? earliestEventDate,
  }) {
    final localNow = toLocal(now);
    switch (range) {
      case StatsRange.week:
        return StatsTimeWindow(
          start: addLocalDays(localNow, -6),
          end: endOfLocalDay(localNow),
        );
      case StatsRange.month:
        return StatsTimeWindow(
          start: addLocalDays(localNow, -29),
          end: endOfLocalDay(localNow),
        );
      case StatsRange.year:
        return StatsTimeWindow(
          start: DateTime(localNow.year, 1, 1),
          end: endOfLocalDay(DateTime(localNow.year, 12, 31)),
        );
      case StatsRange.allTime:
        final earliestLocal = earliestEventDate == null
            ? DateTime(localNow.year, localNow.month, 1)
            : toLocal(earliestEventDate);
        var startMonth = DateTime(earliestLocal.year, earliestLocal.month, 1);
        final minAllowedStart = DateTime(localNow.year, localNow.month - 23, 1);
        if (startMonth.isBefore(minAllowedStart)) {
          startMonth = minAllowedStart;
        }
        return StatsTimeWindow(
          start: startMonth,
          end: endOfLocalDay(DateTime(localNow.year, localNow.month + 1, 0)),
        );
    }
  }

  /// Generates ordered bucket start dates (local midnight for day buckets,
  /// local 1st-of-month midnight for month buckets) for [range].
  static List<DateTime> barBucketStartsFor(
    StatsRange range,
    DateTime now, {
    DateTime? earliestEventDate,
  }) {
    final localNow = toLocal(now);
    switch (range) {
      case StatsRange.week:
        final start = addLocalDays(localNow, -6);
        return List<DateTime>.unmodifiable(
          List<DateTime>.generate(7, (i) => addLocalDays(start, i)),
        );
      case StatsRange.month:
        final start = addLocalDays(localNow, -29);
        return List<DateTime>.unmodifiable(
          List<DateTime>.generate(30, (i) => addLocalDays(start, i)),
        );
      case StatsRange.year:
        return List<DateTime>.unmodifiable(
          List<DateTime>.generate(12, (i) => DateTime(localNow.year, i + 1, 1)),
        );
      case StatsRange.allTime:
        if (earliestEventDate == null) {
          return const <DateTime>[];
        }
        final barsWindow = barsWindowFor(
          range,
          localNow,
          earliestEventDate: earliestEventDate,
        );
        final buckets = <DateTime>[];
        var cursor = DateTime(barsWindow.start.year, barsWindow.start.month, 1);
        final lastMonth = DateTime(localNow.year, localNow.month, 1);
        while (!cursor.isAfter(lastMonth)) {
          buckets.add(cursor);
          cursor = DateTime(cursor.year, cursor.month + 1, 1);
        }
        return List<DateTime>.unmodifiable(buckets);
    }
  }

  /// Computes previous-period minutes delta without NaN or division by zero.
  static StatsPeriodDelta computeDelta(int currentMs, int previousMs) {
    final safeCurrent = currentMs < 0 ? 0 : currentMs;
    final safePrevious = previousMs < 0 ? 0 : previousMs;
    final deltaMs = safeCurrent - safePrevious;
    if (safePrevious == 0) {
      return StatsPeriodDelta(
        currentMs: safeCurrent,
        previousMs: safePrevious,
        deltaMs: deltaMs,
        percentChange: null,
        isNew: safeCurrent > 0,
      );
    }
    return StatsPeriodDelta(
      currentMs: safeCurrent,
      previousMs: safePrevious,
      deltaMs: deltaMs,
      percentChange: (deltaMs / safePrevious) * 100.0,
      isNew: false,
    );
  }
}
