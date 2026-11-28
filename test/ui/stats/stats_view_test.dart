import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/history_models.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite/legacy_userdata_migrator.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/l10n/app_strings.dart';
import 'package:aestheticy/ui/library/library_data_cache.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/stats/stats_date_range.dart';
import 'package:aestheticy/ui/stats/stats_models.dart';
import 'package:aestheticy/ui/stats/stats_view.dart';
import 'package:aestheticy/ui/stats/widgets/stats_activity_heatmap.dart';
import 'package:aestheticy/ui/stats/widgets/stats_bar_chart.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

import '../../library/fake_library_repository.dart';

class _FailOnceStatsRepo extends FakeLibraryRepository {
  bool shouldFail = true;

  @override
  Future<List<PlayEvent>> playEventsBetween(
    DateTime start,
    DateTime end, {
    bool countedOnly = false,
  }) async {
    if (shouldFail) {
      throw StateError('database read error');
    }
    return super.playEventsBetween(start, end, countedOnly: countedOnly);
  }
}

void main() {
  group('Stats Painters (golden-free checks)', () {
    test('StatsBarChartPainter produces proportional bar heights and zero baseline ticks', () {
      final bars = [
        StatsBarBucket(
          bucketStart: DateTime(2026, 11, 21),
          granularity: StatsBucketGranularity.day,
          totalListenedMs: 0,
          playCount: 0,
        ),
        StatsBarBucket(
          bucketStart: DateTime(2026, 11, 22),
          granularity: StatsBucketGranularity.day,
          totalListenedMs: 600000, // half of max
          playCount: 3,
        ),
        StatsBarBucket(
          bucketStart: DateTime(2026, 11, 23),
          granularity: StatsBucketGranularity.day,
          totalListenedMs: 1200000, // max
          playCount: 6,
        ),
      ];

      final ltrRects = StatsBarChartPainter.computeBarRects(
        const Size(300, 108),
        bars,
        textDirection: TextDirection.ltr,
      );
      expect(ltrRects.length, 3);
      expect(ltrRects[0].height, 2.0); // zero baseline
      expect(ltrRects[2].height, closeTo(100.0, 0.01));
      expect(ltrRects[1].height, closeTo(50.0, 0.01));
      expect(ltrRects[0].left < ltrRects[1].left, isTrue);
      expect(ltrRects[1].left < ltrRects[2].left, isTrue);

      final rtlRects = StatsBarChartPainter.computeBarRects(
        const Size(300, 108),
        bars,
        textDirection: TextDirection.rtl,
      );
      expect(rtlRects[0].left > rtlRects[2].left, isTrue);

      // Paints cleanly onto an offscreen canvas with all-zero bars and populated bars
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      StatsBarChartPainter(
        bars: bars,
        activeIndex: 1,
        textDirection: TextDirection.ltr,
      ).paint(canvas, const Size(300, 108));
      StatsBarChartPainter(
        bars: [bars[0]],
        activeIndex: null,
        textDirection: TextDirection.ltr,
      ).paint(canvas, const Size(300, 108));
      recorder.endRecording().dispose();
    });

    test('StatsHeatmapPainter maps intensities and paints 7x24 grid cleanly', () {
      expect(StatsHeatmapPainter.intensityLevel(0, 1000), 0);
      expect(StatsHeatmapPainter.intensityLevel(100, 1000), 1);
      expect(StatsHeatmapPainter.intensityLevel(300, 1000), 2);
      expect(StatsHeatmapPainter.intensityLevel(600, 1000), 3);
      expect(StatsHeatmapPainter.intensityLevel(900, 1000), 4);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const painter = StatsHeatmapPainter(
        orderedWeekdays: [1, 2, 3, 4, 5, 6, 7],
        cellLookup: {
          24 + 9: WeekdayHourListeningStat(
            weekday: 1,
            hour: 9,
            totalListenedMs: 120000,
            playCount: 2,
          ),
        },
        maxListenedMs: 120000,
        activeCellKey: 9,
        textDirection: TextDirection.ltr,
      );
      painter.paint(canvas, const Size(480, 148));
      recorder.endRecording().dispose();
    });
  });

  group('StatsView & Shell Widget Tests', () {
    late FakeAudioEngine engine;
    late PlaybackController controller;
    late SqliteLibraryRepository repo;
    late ScanService scanService;
    late LibraryDataCache dataCache;
    late SettingsStore settingsStore;
    late GlassController glassController;
    late ArtistNameStore artistNameStore;
    late AppNavigator navigator;
    final fakeNow = DateTime(2026, 11, 27, 15, 0);

    setUp(() async {
      engine = FakeAudioEngine();
      await engine.init();
      controller = PlaybackController(engine: engine, queue: PlaybackQueue());
      await controller.init();
      repo = SqliteLibraryRepository.inMemory();
      scanService = ScanService(repository: repo);
      dataCache = LibraryDataCache(repository: repo, scanService: scanService);
      settingsStore = SettingsStore(
        initialSettings: const AppSettings(
          language: 'en',
          arabicNumerals: false,
          glassQuality: GlassQuality.light,
          reduceMotion: true,
        ),
      );
      glassController = GlassController();
      settingsStore.bindGlassController(glassController);
      artistNameStore = ArtistNameStore();
      navigator = AppNavigator(initialDestination: AppDestination.home);
    });

    tearDown(() async {
      dataCache.dispose();
      scanService.dispose();
      settingsStore.dispose();
      artistNameStore.dispose();
      glassController.dispose();
      await repo.close();
      await controller.dispose();
      await engine.dispose();
    });

    Future<void> seedSampleHistory({SqliteLibraryRepository? target}) async {
      final db = target ?? repo;
      final folder = await db.addFolder('C:\\Music');
      final t1 = Track(
        path: 'C:\\Music\\dawn.mp3',
        folderId: folder.id!,
        title: 'Dawn Echoes',
        artist: 'Fairouz',
        albumArtist: 'Fairouz',
        album: 'Morning Dew',
        durationMs: 240000,
        mtimeMs: 1000,
        sizeBytes: 1024,
        addedAt: DateTime(2026, 11, 20),
      );
      final t2 = Track(
        path: 'C:\\Music\\dusk.mp3',
        folderId: folder.id!,
        title: 'Dusk Waves',
        artist: 'Omar Khairat',
        albumArtist: 'Omar Khairat',
        album: 'Evening Suite',
        durationMs: 300000,
        mtimeMs: 1000,
        sizeBytes: 2048,
        addedAt: DateTime(2026, 11, 21),
      );
      await db.upsertTracks([t1, t2]);
      await db.insertPlayEvent(
        PlayEvent(
          uri: t1.path,
          title: t1.title,
          artist: t1.artist,
          album: t1.album,
          albumArtist: t1.albumArtist,
          durationMs: t1.durationMs,
          startedAt: DateTime(2026, 11, 24, 10, 0),
          listenedMs: 3600000, // 1h
          counted: true,
          completed: true,
        ),
      );
      await db.insertPlayEvent(
        PlayEvent(
          uri: t2.path,
          title: t2.title,
          artist: t2.artist,
          album: t2.album,
          albumArtist: t2.albumArtist,
          durationMs: t2.durationMs,
          startedAt: DateTime(2026, 11, 25, 20, 0),
          listenedMs: 1500000, // 25m
          counted: true,
          completed: true,
        ),
      );
    }

    Widget wrapAppShell({LibraryRepository? customRepo}) {
      final useRepo = customRepo ?? repo;
      final useCache = customRepo != null
          ? LibraryDataCache(repository: useRepo)
          : dataCache;
      if (customRepo != null) {
        addTearDown(useCache.dispose);
      }
      return SettingsScope(
        store: settingsStore,
        child: GlassScope(
          controller: glassController,
          child: ArtistNameScope(
            store: artistNameStore,
            child: ListenableBuilder(
              listenable: settingsStore,
              builder: (context, _) {
                final lang = settingsStore.settings.language;
                return MaterialApp(
                  theme: buildAppTheme(),
                  locale: Locale(lang),
                  builder: (context, child) => Directionality(
                    textDirection: lang == 'ar'
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: child ?? const SizedBox.shrink(),
                  ),
                  home: AppShell(
                    engine: engine,
                    controller: controller,
                    repository: useRepo,
                    scanService: scanService,
                    settingsStore: settingsStore,
                    navigator: navigator,
                    dataCache: useCache,
                    statsClock: () => fakeNow,
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    Widget wrapStandaloneStats({
      LibraryRepository? customRepo,
      double mediaTextScale = 1.0,
    }) {
      final useRepo = customRepo ?? repo;
      final useCache = customRepo != null
          ? LibraryDataCache(repository: useRepo)
          : dataCache;
      if (customRepo != null) {
        addTearDown(useCache.dispose);
      }
      return SettingsScope(
        store: settingsStore,
        child: GlassScope(
          controller: glassController,
          child: ArtistNameScope(
            store: artistNameStore,
            child: ListenableBuilder(
              listenable: settingsStore,
              builder: (context, _) {
                final lang = settingsStore.settings.language;
                return MaterialApp(
                  theme: buildAppTheme(),
                  locale: Locale(lang),
                  builder: (context, child) {
                    final mq = MediaQuery.of(context);
                    return MediaQuery(
                      data: mq.copyWith(
                        textScaler: TextScaler.linear(mediaTextScale),
                      ),
                      child: Directionality(
                        textDirection: lang == 'ar'
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: child ?? const SizedBox.shrink(),
                      ),
                    );
                  },
                  home: Scaffold(
                    body: StatsView(
                      repository: useRepo,
                      playbackController: controller,
                      settingsStore: settingsStore,
                      navigator: navigator,
                      dataCache: useCache,
                      clock: () => fakeNow,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    testWidgets(
      'sidebar navigates to Stats in EN with seeded data, charts, ranked lists, track play, and detail nav',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await seedSampleHistory();
        await dataCache.refresh();

        await tester.pumpWidget(wrapAppShell());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('sidebar_stats')), findsOneWidget);
        await tester.tap(find.byKey(const Key('sidebar_stats')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('view_stats')), findsOneWidget);
        expect(find.text('Listening stats'), findsOneWidget);
        expect(find.byKey(const Key('stats_tile_listening_time')), findsOneWidget);
        expect(find.byKey(const Key('stats_tile_plays_counted')), findsOneWidget);
        expect(find.byKey(const Key('stats_tile_newly_discovered')), findsOneWidget);
        expect(find.byKey(const Key('stats_tile_busiest_day')), findsOneWidget);

        // Total time = 1h 25m, plays = 2
        expect(find.text('1h 25m'), findsOneWidget);
        expect(find.byKey(const Key('stats_bar_custom_paint')), findsOneWidget);
        expect(find.byKey(const Key('stats_heatmap_custom_paint')), findsOneWidget);

        // Scroll down past the floating bottom player bar so ranked rows sit cleanly in view.
        await tester.drag(
          find.byKey(const Key('stats_scroll_view')),
          const Offset(0, -450),
        );
        await tester.pumpAndSettle();

        // Ranked lists show seeded items
        expect(find.text('Dawn Echoes'), findsOneWidget);
        expect(find.text('Fairouz'), findsAtLeastNWidgets(1));
        expect(find.text('Morning Dew'), findsOneWidget);

        // Tapping a top track starts playback via PlaybackController
        await tester.tap(find.byKey(const Key('stats_top_track_0')));
        await tester.pumpAndSettle();
        expect(controller.queue.current?.uri, 'C:\\Music\\dawn.mp3');

        // Tapping a top album navigates to albumDetail
        await tester.tap(find.byKey(const Key('stats_top_album_0')));
        await tester.pumpAndSettle();
        expect(navigator.current, AppDestination.albumDetail);

        // Switch back to stats and test keyboard focus on first bar
        navigator.openStats();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'renders in Arabic RTL respecting arabicNumerals true and false without overflow',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await seedSampleHistory();
        await dataCache.refresh();
        settingsStore.update(
          (s) => s.copyWith(language: 'ar', arabicNumerals: true),
        );

        await tester.pumpWidget(wrapStandaloneStats());
        await tester.pumpAndSettle();

        expect(find.text('إحصائيات الاستماع'), findsOneWidget);
        expect(find.text('نشاط الاستماع الأسبوعي'), findsOneWidget);
        expect(find.text('١ س ٢٥ د'), findsOneWidget); // 1h 25m in Arabic-Indic
        expect(find.text('السبت'), findsOneWidget); // AR week start

        // Toggle arabicNumerals to false -> Western digits in Arabic UI
        settingsStore.update((s) => s.copyWith(arabicNumerals: false));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.text('1 س 25 د'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'empty history shows calm empty state in EN and AR',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await repo.addFolder('C:\\Music');
        await dataCache.refresh();

        await tester.pumpWidget(wrapStandaloneStats());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('stats_empty_state')), findsOneWidget);
        expect(
          find.text('Play something and your stats appear here'),
          findsOneWidget,
        );

        settingsStore.update((s) => s.copyWith(language: 'ar'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 450));
        expect(
          find.text(AppStrings.t('stats.empty.title', language: 'ar')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'works cleanly in safe read-only mode against legacy userdata tables',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final tempDir = Directory.systemTemp.createTempSync('aestheticy_stats_ui_ro_');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final libPath = p.join(tempDir.path, 'library.db');
        final backupsDir = Directory(p.join(tempDir.path, 'backups'));

        final db = sqlite3.open(libPath);
        db.execute('''
          CREATE TABLE folders (id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE, last_scan_at INTEGER);
          CREATE TABLE tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE,
            folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
            title TEXT, artist TEXT, album_artist TEXT, album TEXT,
            track_no INTEGER, disc_no INTEGER, year INTEGER,
            duration_ms INTEGER NOT NULL, mtime_ms INTEGER NOT NULL, size_bytes INTEGER NOT NULL,
            cover_key TEXT, added_at INTEGER NOT NULL, search_text TEXT NOT NULL
          );
          CREATE TABLE track_artists (
            track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
            artist_key TEXT NOT NULL, artist_name TEXT NOT NULL, PRIMARY KEY(track_id, artist_key)
          );
          CREATE TABLE artist_aliases (alias_key TEXT PRIMARY KEY, canonical_key TEXT NOT NULL, canonical_name TEXT NOT NULL);
          CREATE TABLE artist_no_split (artist_key TEXT PRIMARY KEY, artist_name TEXT NOT NULL);
          CREATE TABLE play_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT, uri TEXT NOT NULL, title TEXT, artist TEXT,
            album TEXT, album_artist TEXT, duration_ms INTEGER, started_at_ms INTEGER NOT NULL,
            listened_ms INTEGER NOT NULL, counted INTEGER NOT NULL, completed INTEGER NOT NULL
          );
          CREATE TABLE favorites (path TEXT PRIMARY KEY, added_at_ms INTEGER NOT NULL);
          CREATE TABLE ratings (path TEXT PRIMARY KEY, stars INTEGER NOT NULL CHECK(stars BETWEEN 1 AND 5), rated_at_ms INTEGER NOT NULL);
          CREATE TABLE playlists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL);
          CREATE TABLE playlist_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT, playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
            position INTEGER NOT NULL, path TEXT NOT NULL, added_at_ms INTEGER NOT NULL
          );
          PRAGMA user_version = 4;
        ''');
        db.execute("INSERT INTO folders (id, path) VALUES (1, 'C:\\Music');");
        db.execute(
          'INSERT INTO play_events (id, uri, title, artist, album, duration_ms, started_at_ms, listened_ms, counted, completed) '
          "VALUES (1, 'C:\\Music\\ro.mp3', 'Legacy Song', 'Legacy Artist', 'Legacy Album', 200000, ${DateTime(2026, 11, 24, 12, 0).millisecondsSinceEpoch}, 900000, 1, 1);",
        );
        db.close();

        final roRepo = SqliteLibraryRepository.openFile(
          libPath,
          backupsDir: backupsDir,
          migrationHooks: LegacyMigrationTestHooks(failBackup: () => true),
        );
        addTearDown(roRepo.close);
        expect(roRepo.userDataAccessMode, UserDataAccessMode.safeReadOnly);

        await tester.pumpWidget(wrapStandaloneStats(customRepo: roRepo));
        await tester.pumpAndSettle();

        expect(find.text('Legacy Song'), findsOneWidget);
        expect(find.text('15m'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'no overflow on narrow/wide windows and largest text scale, plus error retry recovery',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await seedSampleHistory();
        await dataCache.refresh();

        // Narrow + largest text scale
        tester.view.physicalSize = const Size(640, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(wrapStandaloneStats(mediaTextScale: 1.45));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Wide + large scale
        tester.view.physicalSize = const Size(1600, 960);
        await tester.pumpWidget(wrapStandaloneStats(mediaTextScale: 1.45));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Error card + Retry recovery (remount with fresh state)
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final failingRepo = _FailOnceStatsRepo();
        addTearDown(failingRepo.close);
        await tester.pumpWidget(wrapStandaloneStats(customRepo: failingRepo));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('stats_error_state')), findsOneWidget);
        failingRepo.shouldFail = false;
        await tester.tap(find.byKey(const Key('stats_retry_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('stats_empty_state')), findsOneWidget);
      },
    );
  });
}
