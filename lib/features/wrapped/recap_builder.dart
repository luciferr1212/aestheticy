import 'dart:math' as math;

import '../../library/file_path_utils.dart';
import '../../library/history_models.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../ui/stats/stats_date_range.dart';
import 'recap.dart';

/// Pure-Dart builder computing Monthly Wrapped and Weekly Listening [Recap]s
/// from read-only repository history analytics queries and local calendar rules.
class RecapBuilder {
  /// Minimum counted plays required before a monthly Wrapped is eligible.
  static const int minWrappedCountedPlays = Recap.minMonthlyCountedPlays;

  /// Read-only library repository supplying play-event analytics queries.
  final LibraryRepository repository;

  /// Injectable clock returning the current timestamp.
  final DateTime Function() clock;

  /// Creates a [RecapBuilder].
  RecapBuilder({
    required this.repository,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// Computes ISO-8601 `(isoYear, isoWeek)` for local calendar date [date].
  static ({int isoYear, int isoWeek}) isoWeekForDate(DateTime date) {
    final local = StatsDateRange.startOfLocalDay(date);
    final thursday = StatsDateRange.addLocalDays(
      local,
      DateTime.thursday - local.weekday,
    );
    final jan1 = DateTime(thursday.year, 1, 1);
    final dayOfYear = StatsDateRange.localDayDifference(jan1, thursday) + 1;
    final isoWeek = ((dayOfYear - 1) ~/ 7) + 1;
    return (isoYear: thursday.year, isoWeek: isoWeek);
  }

  /// Deterministically classifies a listener personality from local stats.
  static RecapPersonality classifyPersonality({
    required int playsCounted,
    required int totalListenedMs,
    required int distinctTracks,
    required int newTracksDiscovered,
    required RankedAlbumStat? topAlbum,
    required List<WeekdayHourListeningStat> weekdayHourActivity,
  }) {
    if (playsCounted <= 0 || totalListenedMs <= 0) {
      return RecapPersonality.steadyListener;
    }

    var nightMs = 0;
    var morningMs = 0;
    for (final cell in weekdayHourActivity) {
      final ms = math.max(0, cell.totalListenedMs);
      if (cell.hour >= 21 || cell.hour <= 3) {
        nightMs += ms;
      } else if (cell.hour >= 5 && cell.hour <= 10) {
        morningMs += ms;
      }
    }

    if (nightMs * 100 >= totalListenedMs * 45) {
      return RecapPersonality.nightOwl;
    }
    if (morningMs * 100 >= totalListenedMs * 45) {
      return RecapPersonality.earlyBird;
    }

    if (topAlbum != null &&
        topAlbum.playCount >= 3 &&
        topAlbum.totalListenedMs * 100 >= totalListenedMs * 40) {
      return RecapPersonality.albumListener;
    }

    if (newTracksDiscovered >= 10 ||
        (playsCounted >= 10 &&
            distinctTracks > 0 &&
            newTracksDiscovered * 100 >= distinctTracks * 45)) {
      return RecapPersonality.explorer;
    }

    return RecapPersonality.steadyListener;
  }

  /// Lists distinct local calendar months containing counted play events,
  /// ordered newest-first. Returns `const []` when no counted plays exist.
  Future<List<RecapMonthOption>> availableMonths() async {
    final now = StatsDateRange.toLocal(clock());
    final events = await repository.playEventsBetween(
      DateTime(1970, 1, 1),
      StatsDateRange.endOfLocalDay(now),
      countedOnly: true,
    );

    final byMonth = <int, _MonthAgg>{};
    for (final event in events) {
      if (!event.counted) continue;
      final local = StatsDateRange.toLocal(event.startedAt);
      final key = local.year * 12 + (local.month - 1);
      final agg = byMonth.putIfAbsent(
        key,
        () => _MonthAgg(local.year, local.month),
      );
      agg.playsCounted += 1;
      agg.totalListenedMs += math.max(0, event.listenedMs);
    }

    final keys = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    return List<RecapMonthOption>.unmodifiable(
      keys.map((k) {
        final agg = byMonth[k]!;
        return RecapMonthOption(
          year: agg.year,
          month: agg.month,
          playsCounted: agg.playsCounted,
          totalListenedMs: agg.totalListenedMs,
        );
      }),
    );
  }

  /// Builds a monthly Wrapped [Recap] for local calendar `[year]-[month]`.
  Future<Recap> buildMonth({
    required int year,
    required int month,
  }) async {
    final start = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month + 1, 0);
    final end = StatsDateRange.endOfLocalDay(monthEnd);
    final iso = isoWeekForDate(start);

    return _buildForWindow(
      kind: RecapPeriodKind.monthly,
      year: year,
      month: month,
      isoYear: iso.isoYear,
      isoWeek: iso.isoWeek,
      start: start,
      end: end,
      requiredCountedPlays: Recap.minMonthlyCountedPlays,
    );
  }

  /// Builds a weekly listening [Recap] using `StatsDateRange.windowFor(StatsRange.week, ...)`.
  Future<Recap> buildWeek({
    required String languageCode,
    DateTime? referenceDate,
  }) async {
    final now = StatsDateRange.toLocal(referenceDate ?? clock());
    final window = StatsDateRange.windowFor(
      StatsRange.week,
      now,
      languageCode: languageCode,
    );
    final midWeek = StatsDateRange.addLocalDays(window.start, 3);
    final iso = isoWeekForDate(midWeek);

    return _buildForWindow(
      kind: RecapPeriodKind.weekly,
      year: window.end.year,
      month: window.end.month,
      isoYear: iso.isoYear,
      isoWeek: iso.isoWeek,
      start: window.start,
      end: window.end,
      requiredCountedPlays: Recap.minWeeklyCountedPlays,
    );
  }

  Future<Recap> _buildForWindow({
    required RecapPeriodKind kind,
    required int year,
    required int month,
    required int isoYear,
    required int isoWeek,
    required DateTime start,
    required DateTime end,
    required int requiredCountedPlays,
  }) async {
    final results = await Future.wait<Object?>([
      repository.playEventsBetween(start, end, countedOnly: true),
      repository.topTracksInRange(
        start,
        end,
        metric: HistoryRankingMetric.listenedMs,
        limit: 5,
        countedOnly: true,
      ),
      repository.topArtistsInRange(
        start,
        end,
        metric: HistoryRankingMetric.listenedMs,
        limit: 1,
        countedOnly: true,
      ),
      repository.topAlbumsInRange(
        start,
        end,
        metric: HistoryRankingMetric.listenedMs,
        limit: 5,
        countedOnly: true,
      ),
      repository.distinctTracksFirstPlayedInRange(
        start,
        end,
        countedOnly: true,
      ),
      repository.listeningByWeekdayAndHour(
        start,
        end,
        countedOnly: true,
      ),
    ]);

    final events = results[0]! as List<PlayEvent>;
    final topTracks = List<RankedTrackStat>.unmodifiable(
      results[1]! as List<RankedTrackStat>,
    );
    final topArtists = results[2]! as List<RankedArtistStat>;
    final topAlbums = results[3]! as List<RankedAlbumStat>;
    final newTracksDiscovered = results[4]! as int;
    final weekdayHours = results[5]! as List<WeekdayHourListeningStat>;

    var totalListenedMs = 0;
    var playsCounted = 0;
    final trackKeys = <String>{};
    final artistKeys = <String>{};
    final dayTotals = <DateTime, _DayAgg>{};

    for (final event in events) {
      if (!event.counted) continue;
      final local = StatsDateRange.toLocal(event.startedAt);
      if (local.millisecondsSinceEpoch < start.millisecondsSinceEpoch ||
          local.millisecondsSinceEpoch > end.millisecondsSinceEpoch) {
        continue;
      }

      final ms = math.max(0, event.listenedMs);
      totalListenedMs += ms;
      playsCounted += 1;

      final uid = event.trackUid?.trim();
      trackKeys.add(
        (uid != null && uid.isNotEmpty)
            ? 'uid:$uid'
            : 'uri:${FilePathUtils.canonicalKey(event.uri)}',
      );

      final artist = event.artist?.trim();
      if (artist != null && artist.isNotEmpty) {
        artistKeys.add(artist.toLowerCase());
      }

      final dayKey = DateTime(local.year, local.month, local.day);
      final day = dayTotals.putIfAbsent(dayKey, _DayAgg.new);
      day.playCount += 1;
      day.listenedMs += ms;
    }

    RecapDayHighlight? busiestDay;
    RecapDayHighlight? longestListeningDay;
    for (final entry in dayTotals.entries) {
      final candidate = RecapDayHighlight(
        date: entry.key,
        playCount: entry.value.playCount,
        totalListenedMs: entry.value.listenedMs,
      );

      if (busiestDay == null ||
          candidate.playCount > busiestDay.playCount ||
          (candidate.playCount == busiestDay.playCount &&
              (candidate.totalListenedMs > busiestDay.totalListenedMs ||
                  (candidate.totalListenedMs == busiestDay.totalListenedMs &&
                      candidate.date.isAfter(busiestDay.date))))) {
        busiestDay = candidate;
      }

      if (longestListeningDay == null ||
          candidate.totalListenedMs > longestListeningDay.totalListenedMs ||
          (candidate.totalListenedMs == longestListeningDay.totalListenedMs &&
              (candidate.playCount > longestListeningDay.playCount ||
                  (candidate.playCount == longestListeningDay.playCount &&
                      candidate.date.isAfter(longestListeningDay.date))))) {
        longestListeningDay = candidate;
      }
    }

    final topArtist = topArtists.isNotEmpty ? topArtists.first : null;
    final topAlbum = topAlbums.isNotEmpty ? topAlbums.first : null;
    final personality = classifyPersonality(
      playsCounted: playsCounted,
      totalListenedMs: totalListenedMs,
      distinctTracks: trackKeys.length,
      newTracksDiscovered: newTracksDiscovered,
      topAlbum: topAlbum,
      weekdayHourActivity: weekdayHours,
    );

    return Recap(
      kind: kind,
      year: year,
      month: month,
      isoYear: isoYear,
      isoWeek: isoWeek,
      periodStart: start,
      periodEnd: end,
      totalListenedMs: totalListenedMs,
      playsCounted: playsCounted,
      distinctTracks: trackKeys.length,
      distinctArtists: artistKeys.length,
      newTracksDiscovered: newTracksDiscovered,
      topArtist: topArtist,
      topTracks: topTracks,
      topAlbum: topAlbum,
      busiestDay: busiestDay,
      longestListeningDay: longestListeningDay,
      personality: personality,
      requiredCountedPlays: requiredCountedPlays,
    );
  }
}

class _MonthAgg {
  final int year;
  final int month;
  int playsCounted = 0;
  int totalListenedMs = 0;

  _MonthAgg(this.year, this.month);
}

class _DayAgg {
  int playCount = 0;
  int listenedMs = 0;
}
