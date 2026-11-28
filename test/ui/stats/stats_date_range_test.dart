import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/ui/stats/stats_date_range.dart';

void main() {
  group('StatsDateRange', () {
    test('week starts Monday in en and Saturday in ar', () {
      // Wednesday 2026-11-25 15:30 local
      final wed = DateTime(2026, 11, 25, 15, 30);

      final enWin = StatsDateRange.windowFor(
        StatsRange.week,
        wed,
        languageCode: 'en',
      );
      expect(enWin.start, DateTime(2026, 11, 23, 0, 0, 0)); // Monday
      expect(enWin.start.weekday, DateTime.monday);
      expect(enWin.end, DateTime(2026, 11, 25, 23, 59, 59, 999));

      final arWin = StatsDateRange.windowFor(
        StatsRange.week,
        wed,
        languageCode: 'ar',
      );
      expect(arWin.start, DateTime(2026, 11, 21, 0, 0, 0)); // Saturday
      expect(arWin.start.weekday, DateTime.saturday);
      expect(arWin.end, DateTime(2026, 11, 25, 23, 59, 59, 999));

      expect(
        StatsDateRange.orderedWeekdaysForLanguage('en'),
        const [1, 2, 3, 4, 5, 6, 7],
      );
      expect(
        StatsDateRange.orderedWeekdaysForLanguage('ar'),
        const [6, 7, 1, 2, 3, 4, 5],
      );
    });

    test('week window and previousWindow cross month and year boundaries', () {
      // Thursday 2026-01-01: EN week starts Mon 2025-12-29, AR week starts Sat 2025-12-27.
      final newYearDay = DateTime(2026, 1, 1, 12, 0);

      final enWeek = StatsDateRange.windowFor(
        StatsRange.week,
        newYearDay,
        languageCode: 'en',
      );
      expect(enWeek.start, DateTime(2025, 12, 29));
      final enPrev = StatsDateRange.previousWindowFor(
        StatsRange.week,
        newYearDay,
        languageCode: 'en',
      )!;
      expect(enPrev.start, DateTime(2025, 12, 22));
      expect(enPrev.end, DateTime(2025, 12, 28, 23, 59, 59, 999));

      final arWeek = StatsDateRange.windowFor(
        StatsRange.week,
        newYearDay,
        languageCode: 'ar',
      );
      expect(arWeek.start, DateTime(2025, 12, 27));
      final arPrev = StatsDateRange.previousWindowFor(
        StatsRange.week,
        newYearDay,
        languageCode: 'ar',
      )!;
      expect(arPrev.start, DateTime(2025, 12, 20));
      expect(arPrev.end, DateTime(2025, 12, 26, 23, 59, 59, 999));
    });

    test('month and year boundaries handle leap years and Dec/Jan transitions', () {
      // Leap year March -> February
      final marLeap = DateTime(2024, 3, 15, 9, 0);
      final prevFebLeap = StatsDateRange.previousWindowFor(
        StatsRange.month,
        marLeap,
      )!;
      expect(prevFebLeap.start, DateTime(2024, 2, 1));
      expect(prevFebLeap.end, DateTime(2024, 2, 29, 23, 59, 59, 999));

      // Non-leap year March -> February
      final marNonLeap = DateTime(2026, 3, 15, 9, 0);
      final prevFeb = StatsDateRange.previousWindowFor(
        StatsRange.month,
        marNonLeap,
      )!;
      expect(prevFeb.start, DateTime(2026, 2, 1));
      expect(prevFeb.end, DateTime(2026, 2, 28, 23, 59, 59, 999));

      // January -> previous December
      final jan = DateTime(2026, 1, 10, 8, 0);
      final prevDec = StatsDateRange.previousWindowFor(StatsRange.month, jan)!;
      expect(prevDec.start, DateTime(2025, 12, 1));
      expect(prevDec.end, DateTime(2025, 12, 31, 23, 59, 59, 999));

      // Year and All-time
      final curYear = StatsDateRange.windowFor(StatsRange.year, marNonLeap);
      expect(curYear.start, DateTime(2026, 1, 1));
      final prevYear = StatsDateRange.previousWindowFor(
        StatsRange.year,
        marNonLeap,
      )!;
      expect(prevYear.start, DateTime(2025, 1, 1));
      expect(prevYear.end, DateTime(2025, 12, 31, 23, 59, 59, 999));

      expect(
        StatsDateRange.previousWindowFor(StatsRange.allTime, marNonLeap),
        isNull,
      );
    });

    test('local calendar day arithmetic preserves 00:00 boundaries across typical DST dates', () {
      // Covers US/EU/Egypt historical spring-forward & fall-back windows
      // (March, April, October, November). Every generated day must land at 00:00:00.000
      // with exact +1 calendar day progression.
      final probes = [
        DateTime(2026, 3, 15, 14, 0),
        DateTime(2026, 4, 28, 14, 0),
        DateTime(2026, 11, 3, 14, 0),
      ];
      for (final probe in probes) {
        final monthBuckets = StatsDateRange.barBucketStartsFor(
          StatsRange.month,
          probe,
        );
        expect(monthBuckets.length, 30);
        for (var i = 0; i < monthBuckets.length; i++) {
          final bucket = monthBuckets[i];
          // Must match the very first valid local instant of that calendar day
          // (00:00:00 everywhere normally, or 01:00:00 on a midnight spring-forward).
          expect(bucket, DateTime(bucket.year, bucket.month, bucket.day));
          expect(bucket.minute, 0);
          expect(bucket.second, 0);
          if (i > 0) {
            expect(
              StatsDateRange.localDayDifference(monthBuckets[i - 1], bucket),
              1,
            );
          }
        }
        final end = StatsDateRange.endOfLocalDay(probe);
        expect(end.year, probe.year);
        expect(end.month, probe.month);
        expect(end.day, probe.day);
        expect(end.hour, 23);
        expect(end.minute, 59);
      }
    });

    test('computeDelta handles positive, negative, flat, and zero-previous cases', () {
      final zeroBoth = StatsDateRange.computeDelta(0, 0);
      expect(zeroBoth.percentChange, isNull);
      expect(zeroBoth.isNew, isFalse);

      final zeroPrev = StatsDateRange.computeDelta(180000, 0);
      expect(zeroPrev.percentChange, isNull);
      expect(zeroPrev.isNew, isTrue);
      expect(zeroPrev.deltaMinutes, 3.0);

      final doubled = StatsDateRange.computeDelta(240000, 120000);
      expect(doubled.percentChange, closeTo(100.0, 0.001));
      expect(doubled.isNew, isFalse);

      final halved = StatsDateRange.computeDelta(60000, 120000);
      expect(halved.percentChange, closeTo(-50.0, 0.001));

      final flat = StatsDateRange.computeDelta(120000, 120000);
      expect(flat.percentChange, 0.0);
    });
  });
}
