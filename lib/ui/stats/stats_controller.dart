import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/result.dart';
import '../../diagnostics/app_logger.dart';
import '../../library/file_path_utils.dart';
import '../../library/history_models.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../library/library_data_cache.dart';
import '../settings/settings_store.dart';
import 'stats_date_range.dart';
import 'stats_models.dart';

/// Manages range selection, local-time aggregation, and error/retry state for
/// the Stats screen.
class StatsController extends ChangeNotifier {
  /// Library storage repository (all Stats queries are read-only).
  final LibraryRepository repository;

  /// Settings store providing active language and numeral preferences.
  final SettingsStore settingsStore;

  /// Shared library cache used for stale-while-revalidate refreshes.
  final LibraryDataCache dataCache;

  /// Injectable clock returning the current timestamp.
  final DateTime Function() clock;

  final AppLogger _logger;

  StatsRange _range = StatsRange.week;
  StatsSnapshot? _snapshot;
  AppError? _error;
  bool _isRefreshing = false;
  bool _hasLoaded = false;
  bool _disposed = false;
  int _lastCacheRevision = -1;
  String _lastLanguage = '';
  int _loadGeneration = 0;

  /// Creates a [StatsController].
  StatsController({
    required this.repository,
    required this.settingsStore,
    required this.dataCache,
    DateTime Function()? clock,
    AppLogger? logger,
  }) : clock = clock ?? DateTime.now,
       _logger = logger ?? AppLogger.instance {
    _lastCacheRevision = dataCache.revision;
    _lastLanguage = settingsStore.settings.language;
    dataCache.addListener(_onDataCacheChanged);
    settingsStore.addListener(_onSettingsChanged);
  }

  /// Active selected time range.
  StatsRange get range => _range;

  /// Most recently loaded stats snapshot, or `null` before first load.
  StatsSnapshot? get snapshot => _snapshot;

  /// Last error encountered while loading stats, or `null` when healthy.
  AppError? get error => _error;

  /// True while fetching without a previously loaded snapshot.
  bool get isInitialLoading => !_hasLoaded && _isRefreshing && _snapshot == null;

  /// True while any refresh is active.
  bool get isRefreshing => _isRefreshing;

  /// Whether at least one load cycle has completed cleanly.
  bool get hasLoaded => _hasLoaded;

  void _onDataCacheChanged() {
    if (_disposed) return;
    final nextRev = dataCache.revision;
    if (nextRev != _lastCacheRevision) {
      _lastCacheRevision = nextRev;
      unawaited(refresh());
    }
  }

  void _onSettingsChanged() {
    if (_disposed) return;
    final nextLang = settingsStore.settings.language;
    if (nextLang != _lastLanguage) {
      _lastLanguage = nextLang;
      unawaited(refresh());
    }
  }

  /// Switches the active range to [next] and reloads stats.
  Future<void> setRange(StatsRange next) async {
    if (_disposed) return;
    if (_range == next && _snapshot != null && _error == null) {
      return;
    }
    _range = next;
    _error = null;
    notifyListeners();
    await refresh();
  }

  /// Reloads all Stats metrics and chart buckets for the active [range].
  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    final activeRange = _range;
    final languageCode = settingsStore.settings.language;
    _isRefreshing = true;
    _error = null;
    notifyListeners();

    try {
      final now = StatsDateRange.toLocal(clock());
      final window = StatsDateRange.windowFor(
        activeRange,
        now,
        languageCode: languageCode,
      );
      final previousWindow = StatsDateRange.previousWindowFor(
        activeRange,
        now,
        languageCode: languageCode,
      );
      final barsWindow = StatsDateRange.barsWindowFor(activeRange, now);
      final queryStart = window.start.isBefore(barsWindow.start)
          ? window.start
          : barsWindow.start;
      final queryEnd = window.end.isAfter(barsWindow.end)
          ? window.end
          : barsWindow.end;

      final eventsFuture = repository.playEventsBetween(
        queryStart,
        queryEnd,
        countedOnly: true,
      );
      final prevEventsFuture = previousWindow == null
          ? Future<List<PlayEvent>>.value(const <PlayEvent>[])
          : repository.playEventsBetween(
              previousWindow.start,
              previousWindow.end,
              countedOnly: true,
            );
      final discoveredFuture = repository.distinctTracksFirstPlayedInRange(
        window.start,
        window.end,
        countedOnly: true,
      );
      final topTracksFuture = repository.topTracksInRange(
        window.start,
        window.end,
        metric: HistoryRankingMetric.listenedMs,
        limit: 10,
        countedOnly: true,
      );
      final topArtistsFuture = repository.topArtistsInRange(
        window.start,
        window.end,
        metric: HistoryRankingMetric.listenedMs,
        limit: 10,
        countedOnly: true,
      );
      final topAlbumsFuture = repository.topAlbumsInRange(
        window.start,
        window.end,
        metric: HistoryRankingMetric.listenedMs,
        limit: 10,
        countedOnly: true,
      );
      final weekdayHourFuture = repository.listeningByWeekdayAndHour(
        window.start,
        window.end,
        countedOnly: true,
      );

      final results = await Future.wait<Object?>([
        eventsFuture,
        prevEventsFuture,
        discoveredFuture,
        topTracksFuture,
        topArtistsFuture,
        topAlbumsFuture,
        weekdayHourFuture,
      ]);

      if (_disposed || generation != _loadGeneration) return;

      final fetchedEvents = results[0]! as List<PlayEvent>;
      final previousEvents = results[1]! as List<PlayEvent>;
      final newlyDiscovered = results[2]! as int;
      final topTracks = List<RankedTrackStat>.unmodifiable(
        results[3]! as List<RankedTrackStat>,
      );
      final topArtists = List<RankedArtistStat>.unmodifiable(
        results[4]! as List<RankedArtistStat>,
      );
      final topAlbums = List<RankedAlbumStat>.unmodifiable(
        results[5]! as List<RankedAlbumStat>,
      );
      final weekdayHourActivity = List<WeekdayHourListeningStat>.unmodifiable(
        results[6]! as List<WeekdayHourListeningStat>,
      );

      final nextSnapshot = _buildSnapshot(
        range: activeRange,
        now: now,
        languageCode: languageCode,
        window: window,
        previousWindow: previousWindow,
        fetchedEvents: fetchedEvents,
        previousEvents: previousEvents,
        newlyDiscovered: newlyDiscovered,
        topTracks: topTracks,
        topArtists: topArtists,
        topAlbums: topAlbums,
        weekdayHourActivity: weekdayHourActivity,
      );

      _snapshot = nextSnapshot;
      _hasLoaded = true;
      _error = null;
    } catch (e, st) {
      if (_disposed || generation != _loadGeneration) return;
      _logger.error(
        'StatsController',
        'Failed to load stats for ${activeRange.name}',
        e,
        st,
      );
      _error = AppError.fromException(e, st, 'stats.error.loadFailed');
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        _isRefreshing = false;
        notifyListeners();
      }
    }
  }

  StatsSnapshot _buildSnapshot({
    required StatsRange range,
    required DateTime now,
    required String languageCode,
    required StatsTimeWindow window,
    required StatsTimeWindow? previousWindow,
    required List<PlayEvent> fetchedEvents,
    required List<PlayEvent> previousEvents,
    required int newlyDiscovered,
    required List<RankedTrackStat> topTracks,
    required List<RankedArtistStat> topArtists,
    required List<RankedAlbumStat> topAlbums,
    required List<WeekdayHourListeningStat> weekdayHourActivity,
  }) {
    var totalListenedMs = 0;
    var playsCounted = 0;
    final trackKeys = <String>{};
    final artistKeys = <String>{};
    final dayTotals = <DateTime, _DayAggregate>{};
    final granularity = StatsDateRange.barGranularityFor(range);
    final barAggregates = <DateTime, _DayAggregate>{};
    DateTime? earliestEventDate;

    for (final event in fetchedEvents) {
      if (!event.counted) continue;
      final localStart = StatsDateRange.toLocal(event.startedAt);
      final safeListenedMs = math.max(0, event.listenedMs);

      if (window.contains(localStart)) {
        totalListenedMs += safeListenedMs;
        playsCounted += 1;

        final uid = event.trackUid?.trim();
        final trackKey = (uid != null && uid.isNotEmpty)
            ? 'uid:$uid'
            : 'uri:${FilePathUtils.canonicalKey(event.uri)}';
        trackKeys.add(trackKey);

        final artist = event.artist?.trim();
        if (artist != null && artist.isNotEmpty) {
          artistKeys.add(artist.toLowerCase());
        }

        final dayKey = DateTime(
          localStart.year,
          localStart.month,
          localStart.day,
        );
        final agg = dayTotals.putIfAbsent(dayKey, _DayAggregate.new);
        agg.listenedMs += safeListenedMs;
        agg.playCount += 1;

        if (earliestEventDate == null ||
            localStart.isBefore(earliestEventDate)) {
          earliestEventDate = localStart;
        }
      }

      final bucketKey = granularity == StatsBucketGranularity.day
          ? DateTime(localStart.year, localStart.month, localStart.day)
          : DateTime(localStart.year, localStart.month, 1);
      final bucketAgg = barAggregates.putIfAbsent(
        bucketKey,
        _DayAggregate.new,
      );
      bucketAgg.listenedMs += safeListenedMs;
      bucketAgg.playCount += 1;
    }

    StatsBusiestDay? busiestDay;
    for (final entry in dayTotals.entries) {
      final agg = entry.value;
      if (agg.listenedMs <= 0 && agg.playCount <= 0) continue;
      if (busiestDay == null ||
          agg.listenedMs > busiestDay.totalListenedMs ||
          (agg.listenedMs == busiestDay.totalListenedMs &&
              (agg.playCount > busiestDay.playCount ||
                  (agg.playCount == busiestDay.playCount &&
                      entry.key.isAfter(busiestDay.date))))) {
        busiestDay = StatsBusiestDay(
          date: entry.key,
          totalListenedMs: agg.listenedMs,
          playCount: agg.playCount,
        );
      }
    }

    StatsPeriodDelta? previousDelta;
    if (previousWindow != null) {
      var prevMs = 0;
      for (final event in previousEvents) {
        if (!event.counted) continue;
        prevMs += math.max(0, event.listenedMs);
      }
      previousDelta = StatsDateRange.computeDelta(totalListenedMs, prevMs);
    }

    final bucketStarts = StatsDateRange.barBucketStartsFor(
      range,
      now,
      earliestEventDate: earliestEventDate,
    );
    final bars = List<StatsBarBucket>.unmodifiable(
      bucketStarts.map((start) {
        final agg = barAggregates[start];
        return StatsBarBucket(
          bucketStart: start,
          granularity: granularity,
          totalListenedMs: agg?.listenedMs ?? 0,
          playCount: agg?.playCount ?? 0,
        );
      }),
    );

    final hasHistory =
        playsCounted > 0 ||
        topTracks.isNotEmpty ||
        bars.any((b) => b.totalListenedMs > 0 || b.playCount > 0);

    return StatsSnapshot(
      range: range,
      window: window,
      totalListenedMs: totalListenedMs,
      playsCounted: playsCounted,
      distinctTracks: trackKeys.length,
      distinctArtists: artistKeys.length,
      newlyDiscoveredTracks: newlyDiscovered,
      busiestDay: busiestDay,
      previousDelta: previousDelta,
      bars: bars,
      weekdayHourActivity: weekdayHourActivity,
      orderedWeekdays: StatsDateRange.orderedWeekdaysForLanguage(languageCode),
      topTracks: topTracks,
      topArtists: topArtists,
      topAlbums: topAlbums,
      hasHistory: hasHistory,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    dataCache.removeListener(_onDataCacheChanged);
    settingsStore.removeListener(_onSettingsChanged);
    super.dispose();
  }
}

class _DayAggregate {
  int listenedMs = 0;
  int playCount = 0;
}
