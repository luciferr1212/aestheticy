import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/features/lyrics/lrc_parser.dart';
import 'package:aestheticy/features/lyrics/lyrics_controller.dart';
import 'package:aestheticy/features/lyrics/lyrics_models.dart';
import 'package:aestheticy/features/lyrics/lyrics_offset_store.dart';
import 'package:aestheticy/features/lyrics/lyrics_repository.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/glass/glass_blur_budget.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/shell/side_panel_controller.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

class _FakeLyricsRepository extends LyricsRepository {
  LyricsResult result = const LyricsResultNotFound();

  @override
  Future<LyricsResult> resolve({
    required String filePath,
    required String title,
    required String artist,
    String? album,
    required int durationMs,
    required String mode,
  }) async {
    if (mode == 'off') return const LyricsResultOff();
    return result;
  }
}

AudioSource _track(String id, {String durationMs = '200000'}) {
  return AudioSource(
    'C:\\Music\\$id.mp3',
    extras: {
      'title': 'Song $id',
      'artist': 'Artist $id',
      'album': 'Album $id',
      'durationMs': durationMs,
    },
  );
}

void main() {
  group('SidePanelController & AppSettings persistence (S1)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_panel_unit_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('defaults are closed and queue, and copyWith/toggleTab update state cleanly', () {
      final controller = SidePanelController();
      addTearDown(controller.dispose);

      expect(controller.isOpen, isFalse);
      expect(controller.activeTab, SidePanelTab.queue);
      expect(controller.isVisibleForWidth(1280), isFalse);

      // Open onto lyrics
      controller.open(tab: SidePanelTab.lyrics);
      expect(controller.isOpen, isTrue);
      expect(controller.activeTab, SidePanelTab.lyrics);
      expect(controller.isVisibleForWidth(1280), isTrue);
      expect(controller.isVisibleForWidth(999), isFalse);
      expect(controller.isVisibleForWidth(1000), isTrue);

      // Switch tab while open
      controller.setTab(SidePanelTab.queue);
      expect(controller.isOpen, isTrue);
      expect(controller.activeTab, SidePanelTab.queue);

      // Toggle active tab closes; toggle other tab opens that tab
      controller.toggleTab(SidePanelTab.queue);
      expect(controller.isOpen, isFalse);
      expect(controller.activeTab, SidePanelTab.queue);

      controller.toggleTab(SidePanelTab.lyrics);
      expect(controller.isOpen, isTrue);
      expect(controller.activeTab, SidePanelTab.lyrics);

      // Toggle same tab closes
      controller.toggleTab(SidePanelTab.lyrics);
      expect(controller.isOpen, isFalse);

      // Close idempotency
      controller.close();
      expect(controller.isOpen, isFalse);
    });

    test('persistence round trip via SettingsStore and tolerant JSON fallback', () async {
      final store1 = SettingsStore(directory: tempDir);
      await store1.init();
      final panelCtrl1 = SidePanelController(settingsStore: store1);

      expect(panelCtrl1.isOpen, isFalse);
      expect(panelCtrl1.activeTab, SidePanelTab.queue);

      panelCtrl1.open(tab: SidePanelTab.lyrics);
      expect(store1.settings.sidePanelOpen, isTrue);
      expect(store1.settings.sidePanelTab, equals('lyrics'));

      await store1.flush();
      panelCtrl1.dispose();
      store1.dispose();

      // Reload from disk in new store & controller
      final store2 = SettingsStore(directory: tempDir);
      await store2.init();
      final panelCtrl2 = SidePanelController(settingsStore: store2);

      expect(store2.settings.sidePanelOpen, isTrue);
      expect(store2.settings.sidePanelTab, equals('lyrics'));
      expect(panelCtrl2.isOpen, isTrue);
      expect(panelCtrl2.activeTab, SidePanelTab.lyrics);

      panelCtrl2.dispose();
      store2.dispose();

      // Tolerant fallback on invalid types/values
      final fallback = AppSettings.fromJson(const {
        'sidePanelOpen': 'invalid_bool',
        'sidePanelTab': 'bogus_tab',
      });
      expect(fallback.sidePanelOpen, isFalse);
      expect(fallback.sidePanelTab, equals('queue'));
    });
  });

  group('Docked SidePanel Shell Integration (S1)', () {
    late Directory tempDir;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController playbackController;
    late SqliteLibraryRepository repository;
    late ScanService scanService;
    late SettingsStore settingsStore;
    late GlassController glassController;
    late AppNavigator navigator;
    late UserCollections userCollections;
    late _FakeLyricsRepository lyricsRepository;
    late LyricsOffsetStore offsetStore;
    late LyricsController lyricsController;
    late SidePanelController sidePanelController;

    setUp(() async {
      AppLogger.instance = AppLogger(customSink: StringBuffer());
      GlassBlurBudget.instance.resetForTesting();
      tempDir = await Directory.systemTemp.createTemp('aestheticy_panel_shell_');
      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      playbackController = PlaybackController(engine: engine, queue: queue);
      await playbackController.init();
      repository = SqliteLibraryRepository.inMemory();
      await repository.addFolder('C:\\Music');
      scanService = ScanService(repository: repository);
      settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(
          language: 'en',
          glassQuality: GlassQuality.off,
          reduceMotion: false,
        ),
      );
      await settingsStore.init();
      glassController = GlassController();
      settingsStore.bindGlassController(glassController);
      navigator = AppNavigator();
      userCollections = UserCollections(repository: repository);
      await userCollections.init();
      lyricsRepository = _FakeLyricsRepository();
      offsetStore = LyricsOffsetStore(directory: tempDir);
      await offsetStore.init();
      lyricsController = LyricsController(
        playbackController: playbackController,
        repository: lyricsRepository,
        settingsStore: settingsStore,
        offsetStore: offsetStore,
      );
      sidePanelController = SidePanelController(settingsStore: settingsStore);
    });

    tearDown(() async {
      sidePanelController.dispose();
      lyricsController.dispose();
      offsetStore.dispose();
      userCollections.dispose();
      settingsStore.dispose();
      scanService.dispose();
      await repository.close();
      await playbackController.dispose();
      await engine.dispose();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    void setViewport(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    Widget buildShell() {
      return GlassScope(
        controller: glassController,
        child: SettingsScope(
          store: settingsStore,
          child: MaterialApp(
            locale: const Locale('en'),
            theme: buildAppTheme(),
            home: AppShell(
              engine: engine,
              controller: playbackController,
              repository: repository,
              scanService: scanService,
              settingsStore: settingsStore,
              navigator: navigator,
              userCollections: userCollections,
              lyricsController: lyricsController,
              sidePanelController: sidePanelController,
            ),
          ),
        ),
      );
    }

    testWidgets(
      'opening and closing panel resizes content area without overlaying and respects reduceMotion',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 800));
        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        final contentFinder = find.byKey(const Key('app_shell_content_area'));
        expect(find.byKey(const Key('side_panel_surface')), findsNothing);
        final closedRect = tester.getRect(contentFinder);

        // Open with animation enabled
        sidePanelController.open(tab: SidePanelTab.queue);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));

        // Mid-animation: partially open, no overflow
        final midWidth = tester.getSize(find.byKey(const Key('app_shell_side_panel'))).width;
        expect(midWidth, greaterThan(0));
        expect(midWidth, lessThan(SidePanelController.kPanelWidth));
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();

        final panelRect = tester.getRect(find.byKey(const Key('side_panel_surface')));
        final openContentRect = tester.getRect(contentFinder);

        expect(
          tester.getSize(find.byKey(const Key('app_shell_side_panel'))).width,
          closeTo(SidePanelController.kPanelWidth, 0.5),
        );
        // Resizes content area rather than overlaying it
        expect(
          openContentRect.width,
          closeTo(closedRect.width - SidePanelController.kPanelWidth, 0.5),
        );
        expect(openContentRect.right, lessThanOrEqualTo(panelRect.left + 0.1));
        expect(tester.takeException(), isNull);

        // Reduce motion closes instantly on a single pump
        settingsStore.update((s) => s.copyWith(reduceMotion: true));
        await tester.pump();
        sidePanelController.close();
        await tester.pump();

        expect(find.byKey(const Key('side_panel_surface')), findsNothing);
        expect(tester.getRect(contentFinder).width, closeTo(closedRect.width, 0.5));

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'obeys GlassQuality full/light/off and stays within max 6 BackdropFilter budget',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 800));
        settingsStore.update(
          (s) => s.copyWith(glassQuality: GlassQuality.full, reduceMotion: true),
        );
        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        final closedBlurCount = find.byType(BackdropFilter).evaluate().length;
        expect(closedBlurCount, lessThanOrEqualTo(6));

        sidePanelController.open(tab: SidePanelTab.queue);
        await tester.pumpAndSettle();

        final openBlurCount = find.byType(BackdropFilter).evaluate().length;
        expect(openBlurCount, equals(closedBlurCount + 1));
        expect(openBlurCount, lessThanOrEqualTo(6));
        expect(GlassBlurBudget.instance.activeCount, lessThanOrEqualTo(6));

        // GlassQuality.light -> 0 BackdropFilter
        settingsStore.update((s) => s.copyWith(glassQuality: GlassQuality.light));
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);

        // GlassQuality.off -> 0 BackdropFilter
        settingsStore.update((s) => s.copyWith(glassQuality: GlassQuality.off));
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);

        // Closing panel releases blur slot cleanly even when restored to full
        settingsStore.update((s) => s.copyWith(glassQuality: GlassQuality.full));
        await tester.pumpAndSettle();
        sidePanelController.close();
        await tester.pumpAndSettle();
        expect(
          find.byType(BackdropFilter).evaluate().length,
          equals(closedBlurCount),
        );

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'narrow window hides panel without changing saved setting and restores when window grows',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 800));
        settingsStore.update((s) => s.copyWith(reduceMotion: true));
        sidePanelController.open(tab: SidePanelTab.lyrics);
        await tester.runAsync(() => settingsStore.flush());

        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('side_panel_surface')), findsOneWidget);
        expect(sidePanelController.isOpen, isTrue);
        expect(settingsStore.settings.sidePanelOpen, isTrue);
        expect(settingsStore.settings.sidePanelTab, equals('lyrics'));

        // Shrink window below 1000 px threshold (auto-hide)
        tester.view.physicalSize = const Size(900, 800);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('side_panel_surface')), findsNothing);
        expect(sidePanelController.isOpen, isTrue);
        expect(settingsStore.settings.sidePanelOpen, isTrue);
        expect(settingsStore.settings.sidePanelTab, equals('lyrics'));
        expect(tester.takeException(), isNull);

        // Grow back above threshold (restored without re-opening manually)
        tester.view.physicalSize = const Size(1280, 800);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('side_panel_surface')), findsOneWidget);
        expect(find.byKey(const ValueKey('side_panel_lyrics_content')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'Queue tab inside docked panel supports play-from-queue, remove, and drag-reorder',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 800));
        settingsStore.update((s) => s.copyWith(reduceMotion: true));
        await playbackController.playQueue([
          _track('Alpha'),
          _track('Beta'),
          _track('Gamma'),
        ], startIndex: 0);

        sidePanelController.open(tab: SidePanelTab.queue);
        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        final queueContentFinder =
            find.byKey(const ValueKey('side_panel_queue_content'));
        expect(queueContentFinder, findsOneWidget);
        expect(
          find.descendant(
            of: queueContentFinder,
            matching: find.text('Song Alpha'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: queueContentFinder,
            matching: find.text('Song Beta'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: queueContentFinder,
            matching: find.text('Song Gamma'),
          ),
          findsOneWidget,
        );

        // 1. Play from queue (tap row 2)
        await tester.tap(
          find.descendant(
            of: queueContentFinder,
            matching: find.text('Song Gamma'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(queue.currentIndex, equals(2));
        expect(engine.openedSource?.uri, equals('C:\\Music\\Gamma.mp3'));

        // 2. Remove row 1 via compact remove button
        await tester.tap(find.byKey(const Key('queue_row_remove_1')));
        await tester.pumpAndSettle();
        expect(
          queue.items.map((s) => s.extras?['title']),
          equals(['Song Alpha', 'Song Gamma']),
        );
        expect(
          find.descendant(
            of: queueContentFinder,
            matching: find.text('Song Beta'),
          ),
          findsNothing,
        );

        // 3. Drag-reorder row 1 above row 0 via drag handle
        final handleFinder = find.descendant(
          of: queueContentFinder,
          matching: find.byIcon(Icons.drag_indicator),
        );
        final dragStart = tester.getCenter(handleFinder.at(1));
        final dragEnd = tester.getCenter(handleFinder.at(0)) - const Offset(0, 20);
        final gesture = await tester.startGesture(dragStart);
        await tester.pump();
        final dy = (dragEnd.dy - dragStart.dy) / 6;
        for (var step = 0; step < 6; step++) {
          await gesture.moveBy(Offset(0, dy));
          await tester.pump(const Duration(milliseconds: 20));
        }
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          queue.items.map((s) => s.extras?['title']),
          equals(['Song Gamma', 'Song Alpha']),
        );

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'Lyrics tab inside docked panel supports synced lyrics, active line highlight, click-to-seek, and per-track offset',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 800));
        settingsStore.update((s) => s.copyWith(reduceMotion: true));

        const lrcContent = '''
[00:01.00]Panel Line One
[00:05.00]Panel Line Two
[00:10.00]Panel Line Three
''';
        lyricsRepository.result = LyricsResultFound(
          LyricsDocument(
            kind: LyricsKind.synced,
            lines: parseLrc(lrcContent).lines,
            source: LyricsSourceOrigin.local,
            hasWordTiming: false,
          ),
        );
        engine.fakeDuration = const Duration(seconds: 60);

        await tester.runAsync(() async {
          await playbackController.playQueue(
            [_track('Synced')],
            startIndex: 0,
          );
          await lyricsController.retry();
        });

        sidePanelController.open(tab: SidePanelTab.lyrics);
        await tester.pumpWidget(buildShell());
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const ValueKey('side_panel_lyrics_content')), findsOneWidget);
        expect(find.text('Panel Line One'), findsOneWidget);
        expect(find.text('Panel Line Two'), findsOneWidget);
        expect(find.text('Panel Line Three'), findsOneWidget);
        expect(find.byKey(const Key('lyrics_sync_control')), findsOneWidget);

        // Advance playback position to line 2 (6s) -> current line highlight
        lyricsController.updatePosition(const Duration(seconds: 6), forceNotify: true);
        await tester.pump();

        double opacityForLine(String text) {
          final opacityWidget = tester.widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.text(text),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          );
          return opacityWidget.opacity;
        }

        expect(opacityForLine('Panel Line Two'), equals(1.0));
        expect(opacityForLine('Panel Line One'), lessThan(1.0));

        // Click-to-seek to Panel Line Three (10s)
        await tester.tap(find.text('Panel Line Three'));
        await tester.pump();
        expect(engine.position.inSeconds, equals(10));
        expect(opacityForLine('Panel Line Three'), equals(1.0));

        // Per-track sync offset adjustment inside panel
        await tester.tap(find.byKey(const Key('lyrics_sync_plus')));
        await tester.pump();
        expect(lyricsController.offsetMs, equals(kLyricsOffsetStepMs));
        expect(find.text('+0.1 s'), findsOneWidget);

        await tester.tap(find.byKey(const Key('lyrics_sync_minus')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('lyrics_sync_minus')));
        await tester.pump();
        expect(lyricsController.offsetMs, equals(-kLyricsOffsetStepMs));
        expect(find.text('-0.1 s'), findsOneWidget);

        await tester.tap(find.byKey(const Key('lyrics_sync_reset')));
        await tester.pump();
        expect(lyricsController.offsetMs, equals(0));
        expect(find.text('0 s'), findsOneWidget);

        await tester.runAsync(() async {
          await offsetStore.flush();
          await settingsStore.flush();
        });
        await tester.pump(const Duration(milliseconds: 500));
      },
    );
  });
}
