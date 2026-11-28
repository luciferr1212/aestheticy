/// Shared localization and digit-formatting helpers for the Stats UI.
library;

import 'package:flutter/widgets.dart';

import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import 'stats_date_range.dart';
import 'stats_models.dart';

/// Pure formatting helpers shared across Stats tiles, charts, and ranked lists.
abstract final class StatsFormatters {
  /// Formats [milliseconds] as calm hours and minutes (e.g. `1h 25m` / `45m`),
  /// obeying `arabicNumerals` in [context].
  static String formatHoursMinutes(BuildContext context, int milliseconds) {
    if (milliseconds <= 0) {
      return context.localizeDigitsText(
        context.t('stats.duration.minutesOnly', args: {'minutes': '0'}),
      );
    }
    if (milliseconds < 60000) {
      return context.localizeDigitsText(
        context.t('stats.duration.lessThanMinute'),
      );
    }
    final totalMinutes = (milliseconds / 60000).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) {
      return context.localizeDigitsText(
        context.t('stats.duration.minutesOnly', args: {'minutes': '$minutes'}),
      );
    }
    if (minutes == 0) {
      return context.localizeDigitsText(
        context.t('stats.duration.hoursOnly', args: {'hours': '$hours'}),
      );
    }
    return context.localizeDigitsText(
      context.t(
        'stats.duration.hoursMinutes',
        args: {'hours': '$hours', 'minutes': '$minutes'},
      ),
    );
  }

  /// Formats [delta] as a localized percentage delta subtitle, or `null` when
  /// no comparison applies (e.g. `allTime` or zero in both periods).
  static String? formatDelta(BuildContext context, StatsPeriodDelta? delta) {
    if (delta == null) return null;
    if (delta.isNew) {
      return context.t('stats.summary.deltaNew');
    }
    final pct = delta.percentChange;
    if (pct == null) return null;
    final rounded = pct.round();
    if (rounded > 0) {
      return context.localizeDigitsText(
        context.t('stats.summary.deltaPlus', args: {'percent': '$rounded'}),
      );
    }
    if (rounded < 0) {
      return context.localizeDigitsText(
        context.t(
          'stats.summary.deltaMinus',
          args: {'percent': '${rounded.abs()}'},
        ),
      );
    }
    return context.localizeDigitsText(context.t('stats.summary.deltaFlat'));
  }

  /// Formats a [StatsBarBucket] label concisely for axis ticks or tooltips.
  static String formatBarLabel(
    BuildContext context,
    StatsBarBucket bucket, {
    bool compactAxis = false,
  }) {
    if (bucket.granularity == StatsBucketGranularity.month) {
      return context.t('stats.month.short.${bucket.bucketStart.month}');
    }
    if (compactAxis) {
      return context.formatCountLocalized(bucket.bucketStart.day);
    }
    final day = context.formatCountLocalized(bucket.bucketStart.day);
    final month = context.t('stats.month.short.${bucket.bucketStart.month}');
    return context.t(
      'stats.date.dayMonth',
      args: {'day': day, 'month': month},
    );
  }

  /// Formats a local calendar date for KPI tiles.
  static String formatCalendarDay(
    BuildContext context,
    DateTime date, {
    bool includeYear = false,
  }) {
    final day = context.formatCountLocalized(date.day);
    final month = context.t('stats.month.short.${date.month}');
    if (!includeYear) {
      return context.t(
        'stats.date.dayMonth',
        args: {'day': day, 'month': month},
      );
    }
    final year = context.formatCountLocalized(date.year);
    return context.t(
      'stats.date.dayMonthYear',
      args: {'day': day, 'month': month, 'year': year},
    );
  }

  /// Formats an hour (`0..23`) as localized `HH:00`.
  static String formatHour(BuildContext context, int hour) {
    final padded = hour.clamp(0, 23).toString().padLeft(2, '0');
    return context.localizeDigitsText('$padded:00');
  }

  /// Returns a localized short weekday name for ISO weekday (`1..7`).
  static String formatWeekdayShort(BuildContext context, int isoWeekday) {
    final safe = ((isoWeekday - 1) % 7) + 1;
    return context.t('stats.weekday.short.$safe');
  }
}
