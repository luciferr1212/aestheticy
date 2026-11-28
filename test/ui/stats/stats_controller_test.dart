import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/core/result.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/library/library_data_cache.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/stats/stats_controller.dart';
import 'package:aestheticy/ui/stats/stats_date_range.dart';

import '../../library/fake_library_repository.dart';

class _ThrowingStatsRepo extends FakeLibraryRepository {
  bool shouldFail = true;

  @override
  Future<List<PlayEvent>> playEventsBetween(
    DateTime start,
    DateTime end, {
    bool countedOnly = false,
  }) async {
    if (shouldFail) {
      throw StateError('database failure during stats query');
    }
    return super.playEventsBetween(start, end, countedOnly: countedOnly);
  }
}

void main() {
  group('StatsController', () {
    test('aggregates summary, previous-period delta (incl zero), bars, heatmap, and rankings with fake clock', () async {
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);
      final settingsStore = SettingsStore(
        initialSettings: const AppSettings(language: 'en'),
      );
      addTearDown(settingsStore.dispose);
      final dataCache = LibraryDataCache(repository: repo);
      addTearDown(dataCache.dispose);

      // Clock: Friday 2026-11-27 18:00 local.
      // EN week starts Mon 2026-11-23; AR week starts Sat 2026-11-21.
      final fakeNow = DateTime(2026, 11, 27, 18, 0);

      // Discovery event earlier in November -> in month, NOT in current week
      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\track1.mp3',
          title: 'Track One',
          artist: 'Artist A',
          album: 'Album X',
          startedAt: DateTime(2026, 11, 10, 11, 0),
          listenedMs: 120000, // 2m
          counted: true,
          completed: true,
        ),
      );
      // Sunday 2026-11-22: part of AR week & EN previous week, NOT EN current week
      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\track2.mp3',
          title: 'Track Two',
          artist: 'Artist B',
          album: 'Album Y',
          startedAt: DateTime(2026, 11, 22, 20, 0),
          listenedMs: 240000, // 4m
          counted: true,
          completed: true,
        ),
      );
      // Current EN week: Monday 2026-11-23 (total 6m), Wednesday 2026-11-25 (total 3m)
      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\track1.mp3',
          title: 'Track One',
          artist: 'Artist A',
          album: 'Album X',
          startedAt: DateTime(2026, 11, 23, 9, 15),
          listenedMs: 180000,
          counted: true,
          completed: true,
        ),
      );
      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\track3.mp3',
          title: 'Track Three',
          artist: 'Artist C',
          album: 'Album Z',
          startedAt: DateTime(2026, 11, 23, 9, 45),
          listenedMs: 180000,
          counted: true,
          completed: true,
        ),
      );
      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\track3.mp3',
          title: 'Track Three',
          artist: 'Artist C',
          album: 'Album Z',
          startedAt: DateTime(2026, 11, 25, 16, 0),
          listenedMs: 180000,
          counted: true,
          completed: true,
        ),
      );
      // Uncounted quick skip inside current week -> must be ignored
      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\skip.mp3',
          title: 'Skipped',
          artist: 'Artist Skip',
          album: 'Album Skip',
          startedAt: DateTime(2026, 11, 26, 10, 0),
          listenedMs: 4000,
          counted: false,
          completed: false,
        ),
      );

      final controller = StatsController(
        repository: repo,
        settingsStore: settingsStore,
        dataCache: dataCache,
        clock: () => fakeNow,
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      final weekSnap = controller.snapshot!;

      expect(weekSnap.hasHistory, isTrue);
      expect(weekSnap.totalListenedMs, 540000); // 9m
      expect(weekSnap.playsCounted, 3);
      expect(weekSnap.distinctTracks, 2);
      expect(weekSnap.distinctArtists, 2);
      // track3 had its very first play inside this week (Nov 23)
      expect(weekSnap.newlyDiscoveredTracks, 1);
      expect(weekSnap.busiestDay?.date, DateTime(2026, 11, 23));
      expect(weekSnap.busiestDay?.totalListenedMs, 360000);

      // Previous EN week (Nov 16..22) had 240,000ms -> +125%
      expect(weekSnap.previousDelta?.previousMs, 240000);
      expect(weekSnap.previousDelta?.percentChange, closeTo(125.0, 0.01));
      expect(weekSnap.bars.length, 7);
      expect(weekSnap.topTracks.first.uri, 'C:\\Music\\track3.mp3');
      expect(weekSnap.weekdayHourActivity, isNotEmpty);

      // Switch to month: previous month (October) has 0ms -> isNew = true
      await controller.setRange(StatsRange.month);
      final monthSnap = controller.snapshot!;
      expect(monthSnap.playsCounted, 5);
      expect(monthSnap.totalListenedMs, 900000);
      expect(monthSnap.newlyDiscoveredTracks, 3);
      expect(monthSnap.previousDelta?.previousMs, 0);
      expect(monthSnap.previousDelta?.percentChange, isNull);
      expect(monthSnap.previousDelta?.isNew, isTrue);
      expect(monthSnap.bars.length, 30);

      // Year & All Time
      await controller.setRange(StatsRange.year);
      expect(controller.snapshot!.bars.length, 12);

      await controller.setRange(StatsRange.allTime);
      expect(controller.snapshot!.previousDelta, isNull);
      expect(controller.snapshot!.bars.length, 1);

      // Switching back to week and changing language to Arabic shifts week start to Saturday Nov 21
      await controller.setRange(StatsRange.week);
      settingsStore.update((s) => s.copyWith(language: 'ar'));
      await pumpEventQueue();
      final arWeekSnap = controller.snapshot!;
      expect(arWeekSnap.orderedWeekdays.first, DateTime.saturday);
      // Now Nov 22 (track2, 240s) falls inside AR current week!
      expect(arWeekSnap.playsCounted, 4);
      expect(arWeekSnap.totalListenedMs, 780000);
    });

    test('sets AppError on failure and recovers on retry', () async {
      final repo = _ThrowingStatsRepo();
      addTearDown(repo.close);
      final settingsStore = SettingsStore(
        initialSettings: const AppSettings(language: 'en'),
      );
      addTearDown(settingsStore.dispose);
      final dataCache = LibraryDataCache(repository: repo);
      addTearDown(dataCache.dispose);

      final controller = StatsController(
        repository: repo,
        settingsStore: settingsStore,
        dataCache: dataCache,
        clock: () => DateTime(2026, 11, 27, 12, 0),
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      expect(controller.error, isA<DatabaseFailure>());
      expect(controller.snapshot, isNull);

      repo.shouldFail = false;
      await controller.refresh();
      expect(controller.error, isNull);
      expect(controller.snapshot, isNotNull);
      expect(controller.snapshot!.hasHistory, isFalse);
    });
  });
}
