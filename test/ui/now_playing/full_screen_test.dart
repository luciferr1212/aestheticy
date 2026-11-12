import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import '../../library/fake_library_repository.dart';
import 'package:aestheticy/ui/glass/glass_blur_budget.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/glass/glass_surface.dart';
import 'package:aestheticy/ui/now_playing/full_screen_view.dart';
import 'package:aestheticy/ui/now_playing/now_playing_view.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/shell/volume_hud.dart';

class FullScreenTestEngine extends FakeAudioEngine {
  Duration? lastSeekTarget;
  final List<Duration> seekHistory = <Duration>[];

  @override
  Future<void> seek(Duration position) async {
    lastSeekTarget = position;
    seekHistory.add(position);
    await super.seek(position);
  }
}

void main() {
  group('FullScreenView Tests', () {
    late SettingsStore settingsStore;
    late FullScreenTestEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late AppNavigator navigator;
    late FakeLibraryRepository fakeRepo;
    late UserCollections collections;

    setUp(() async {
      GlassBlurBudget.instance.resetForTesting();
      settingsStore = SettingsStore();
      await settingsStore.init();

      engine = FullScreenTestEngine();
      await engine.init();

      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();

      navigator = AppNavigator();

      fakeRepo = FakeLibraryRepository();
      collections = UserCollections(repository: fakeRepo);
      await collections.init();
    });

    tearDown(() async {
      collections.dispose();
      await settingsStore.flush();
      await controller.dispose();
      await engine.dispose();
      settingsStore.dispose();
    });

    void setupDesktopViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    List<AudioSource> createSampleTracks() {
      return [
        const AudioSource(
          'track1.flac',
          extras: {
            'title': 'Track One',
            'artist': 'Artist One',
            'album': 'Album One',
            'durationMs': '180000',
          },
        ),
      ];
    }

    Widget buildTestWidget({
      VoidCallback? onTickerFrame,
      WidgetBuilder? debugProbeBuilder,
      TextDirection textDirection = TextDirection.ltr,
    }) {
      return MaterialApp(
        home: UserCollectionsScope(
          collections: collections,
          child: GlassScope(
            controller: GlassController(quality: GlassQuality.full),
            child: Directionality(
              textDirection: textDirection,
              child: FullScreenView(
                controller: controller,
                engine: engine,
                navigator: navigator,
                settingsStore: settingsStore,
                onTickerFrame: onTickerFrame,
                debugProbeBuilder: debugProbeBuilder,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Floating glass shapes toggle adds / removes 2 GlassSurface shapes', (tester) async {
      setupDesktopViewport(tester);
      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);

      // By default fullScreenGlassShapes is true -> exactly 2 decorative floating GlassSurface widgets
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      expect(settingsStore.settings.fullScreenGlassShapes, isTrue);
      expect(find.byType(GlassSurface), findsNWidgets(2));

      // Toggle off via button
      await tester.tap(find.byKey(const Key('fullscreen_toggle_glass_shapes')));
      await tester.pump(const Duration(milliseconds: 50));

      expect(settingsStore.settings.fullScreenGlassShapes, isFalse);
      expect(find.byType(GlassSurface), findsNothing);

      // Toggle on via button
      await tester.tap(find.byKey(const Key('fullscreen_toggle_glass_shapes')));
      await tester.pump(const Duration(milliseconds: 50));

      expect(settingsStore.settings.fullScreenGlassShapes, isTrue);
      expect(find.byType(GlassSurface), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox());
      await settingsStore.flush();
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Ticker is disabled when reduceMotion is true', (tester) async {
      setupDesktopViewport(tester);
      settingsStore.update((s) => s.copyWith(reduceMotion: true));
      await settingsStore.flush();

      int tickerFrames = 0;
      await tester.pumpWidget(buildTestWidget(onTickerFrame: () => tickerFrames++));
      await tester.pump(const Duration(milliseconds: 100));

      final state = tester.state<FullScreenViewState>(find.byType(FullScreenView));
      expect(state.isTickerActive, isFalse);
      expect(tickerFrames, equals(0));

      await tester.pumpWidget(const SizedBox());
      await settingsStore.flush();
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Ticker pauses on app lifecycle inactive/paused and resumes on resumed', (tester) async {
      setupDesktopViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<FullScreenViewState>(find.byType(FullScreenView));
      expect(state.isTickerActive, isTrue);

      // Simulate app inactive
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.isTickerActive, isFalse);

      // Simulate app paused
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.isTickerActive, isFalse);

      // Simulate app resumed
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.isTickerActive, isTrue);

      await tester.pumpWidget(const SizedBox());
      await settingsStore.flush();
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Hover fade: top bar fades out after 3s inactivity and mouse move restores it', (tester) async {
      setupDesktopViewport(tester);
      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final animatedOpacityFinder = find.byType(AnimatedOpacity);
      AnimatedOpacity opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, equals(1.0));

      // Advance 3.5 seconds
      await tester.pump(const Duration(milliseconds: 3500));

      opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, equals(0.0));

      // Simulate mouse move
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 50));

      opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, equals(1.0));

      await gesture.removePointer();
      await tester.pumpWidget(const SizedBox());
      await settingsStore.flush();
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Keyboard shortcuts in Full Screen: Space, Left, Right, Esc', (tester) async {
      setupDesktopViewport(tester);
      final repo = SqliteLibraryRepository.inMemory();
      await repo.addFolder('C:\\Music');
      final scanService = ScanService(repository: repo);

      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);
      navigator.openFullScreen();

      await tester.pumpWidget(
        MaterialApp(
          home: GlassScope(
            controller: GlassController(quality: GlassQuality.full),
            child: AppShell(
              engine: engine,
              controller: controller,
              repository: repo,
              scanService: scanService,
              settingsStore: settingsStore,
              navigator: navigator,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Space: toggle play/pause
      expect(controller.currentState, equals(PlaybackState.playing));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.currentState, equals(PlaybackState.paused));

      // Left arrow: seek
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 50));
      expect(engine.lastSeekTarget, isNotNull);

      // Right arrow: seek
      engine.lastSeekTarget = null;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 50));
      expect(engine.lastSeekTarget, isNotNull);

      // Esc: go back
      bool wentBack = false;
      navigator.addListener(() => wentBack = true);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 50));
      expect(wentBack, isTrue);
      expect(navigator.current, equals(AppDestination.albums));

      await tester.pumpWidget(const SizedBox());
      await settingsStore.flush();
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Navigation: open Full screen from Now Playing, press Exit, returns to Now Playing', (tester) async {
      setupDesktopViewport(tester);
      final repo = SqliteLibraryRepository.inMemory();
      await repo.addFolder('C:\\Music');
      final scanService = ScanService(repository: repo);

      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: GlassScope(
            controller: GlassController(quality: GlassQuality.full),
            child: AppShell(
              engine: engine,
              controller: controller,
              repository: repo,
              scanService: scanService,
              settingsStore: settingsStore,
              navigator: navigator,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Navigate to Now Playing
      navigator.openNowPlaying();
      await tester.pump(const Duration(milliseconds: 100));
      expect(navigator.current, equals(AppDestination.nowPlaying));
      expect(find.byType(NowPlayingView), findsOneWidget);

      // Open Full Screen from Now Playing
      await tester.tap(find.byKey(const Key('now_playing_fullscreen_button')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(navigator.current, equals(AppDestination.fullScreen));
      expect(find.byType(FullScreenView), findsOneWidget);

      // Exit full screen via exit button
      await tester.tap(find.byKey(const Key('fullscreen_exit_button')));
      await tester.pump(const Duration(milliseconds: 100));

      // Returns to Now Playing!
      expect(navigator.current, equals(AppDestination.nowPlaying));
      expect(find.byType(NowPlayingView), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await repo.close();
      await settingsStore.flush();
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Navigation: open Full screen from Albums, press Esc, returns to Albums', (tester) async {
      setupDesktopViewport(tester);
      final repo = SqliteLibraryRepository.inMemory();
      await repo.addFolder('C:\\Music');
      final scanService = ScanService(repository: repo);

      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: GlassScope(
            controller: GlassController(quality: GlassQuality.full),
            child: AppShell(
              engine: engine,
              controller: controller,
              repository: repo,
              scanService: scanService,
              settingsStore: settingsStore,
              navigator: navigator,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(navigator.current, equals(AppDestination.albums));

      // Open Full screen directly
      navigator.openFullScreen();
      await tester.pump(const Duration(milliseconds: 100));
      expect(navigator.current, equals(AppDestination.fullScreen));

      // Press Esc
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 100));

      // Returns to Albums
      expect(navigator.current, equals(AppDestination.albums));

      await tester.pumpWidget(const SizedBox());
      await repo.close();
      await settingsStore.flush();
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Heart button toggles favorite in FullScreenView', (tester) async {
      setupDesktopViewport(tester);
      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('fullscreen_favorite_button')), findsOneWidget);
      expect(collections.isFavorite('track1.flac'), isFalse);

      await tester.tap(find.byKey(const Key('fullscreen_favorite_button')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(collections.isFavorite('track1.flac'), isTrue);

      await tester.tap(find.byKey(const Key('fullscreen_favorite_button')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(collections.isFavorite('track1.flac'), isFalse);
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Ticker does not rebuild FullScreenView subtree across multiple ticks', (tester) async {
      setupDesktopViewport(tester);
      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);

      int tickerFrames = 0;
      int probeBuilds = 0;
      await tester.pumpWidget(
        buildTestWidget(
          onTickerFrame: () => tickerFrames++,
          debugProbeBuilder: (_) => _BuildProbe(onBuild: () => probeBuilds++),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final buildsBeforeTicks = probeBuilds;

      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(tickerFrames, greaterThanOrEqualTo(5));
      expect(probeBuilds, equals(buildsBeforeTicks));

      await tester.pumpWidget(const SizedBox());
      await settingsStore.flush();
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Decorative glass shapes are static and inside RepaintBoundary', (tester) async {
      setupDesktopViewport(tester);
      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final shapes = find.byType(GlassSurface);
      expect(shapes, findsNWidgets(2));
      final firstPos = tester.getTopLeft(shapes.at(0));
      final secondPos = tester.getTopLeft(shapes.at(1));
      expect(
        find.ancestor(of: shapes.at(0), matching: find.byType(RepaintBoundary)),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.ancestor(of: shapes.at(1), matching: find.byType(RepaintBoundary)),
        findsAtLeastNWidgets(1),
      );

      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 45));
      }

      expect(tester.getTopLeft(shapes.at(0)), equals(firstPos));
      expect(tester.getTopLeft(shapes.at(1)), equals(secondPos));

      await tester.pumpWidget(const SizedBox());
      await settingsStore.flush();
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Toggling reduceMotion stops and resumes ticker cleanly and dispose leaves no active timers', (tester) async {
      setupDesktopViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<FullScreenViewState>(find.byType(FullScreenView));
      expect(state.isTickerActive, isTrue);

      settingsStore.update((s) => s.copyWith(reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.isTickerActive, isFalse);

      settingsStore.update((s) => s.copyWith(reduceMotion: false));
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.isTickerActive, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      await settingsStore.flush();
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets(
      'Seek bar hover expands to 6dp with thumb and times and pauses top-bar auto-hide',
      (tester) async {
        setupDesktopViewport(tester);
        await controller.playQueue(createSampleTracks(), startIndex: 0);
        await tester.pumpWidget(buildTestWidget());
        await tester.pump(const Duration(milliseconds: 50));

        final barFinder = find.byKey(const Key('fullscreen_seek_bar'));
        final trackFinder = find.byKey(const Key('fullscreen_seek_track'));
        expect(barFinder, findsOneWidget);
        expect(tester.getSize(barFinder).height, equals(28.0));
        expect(tester.getSize(trackFinder).height, equals(2.0));
        expect(find.byKey(const Key('fullscreen_seek_thumb')), findsNothing);
        expect(find.byKey(const Key('fullscreen_seek_times')), findsNothing);

        final gesture =
            await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);
        addTearDown(() => gesture.removePointer());
        await gesture.moveTo(tester.getCenter(barFinder));
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.getSize(trackFinder).height, equals(6.0));
        expect(find.byKey(const Key('fullscreen_seek_thumb')), findsOneWidget);
        expect(find.byKey(const Key('fullscreen_seek_times')), findsOneWidget);

        // Top-bar controls stay visible while hovering the scrubber beyond 3s.
        await tester.pump(const Duration(milliseconds: 3500));
        var topOpacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
        expect(topOpacity.opacity, equals(1.0));

        // Moving away collapses the track and resumes the 3s auto-hide timer.
        await gesture.moveTo(const Offset(100, 100));
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.getSize(trackFinder).height, equals(2.0));

        await tester.pump(const Duration(milliseconds: 3500));
        topOpacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
        expect(topOpacity.opacity, equals(0.0));

        await tester.pumpWidget(const SizedBox());
        await settingsStore.flush();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'Seek bar supports click seek, throttled drag scrub with tooltip, and release commit',
      (tester) async {
        setupDesktopViewport(tester);
        await controller.playQueue(createSampleTracks(), startIndex: 0);
        await tester.pumpWidget(buildTestWidget());
        await tester.pump(const Duration(milliseconds: 50));

        final barFinder = find.byKey(const Key('fullscreen_seek_bar'));
        final barRect = tester.getRect(barFinder);

        // Single click at 25% seeks to 45s (180s * 0.25).
        await tester.tapAt(Offset(barRect.width * 0.25, barRect.center.dy));
        await tester.pump(const Duration(milliseconds: 20));
        expect(engine.lastSeekTarget, isNotNull);
        expect(
          engine.lastSeekTarget!.inMilliseconds,
          closeTo(45000, 1500),
        );

        engine.seekHistory.clear();
        final dragGesture = await tester.startGesture(
          Offset(barRect.width * 0.25, barRect.center.dy),
        );
        await dragGesture.moveTo(Offset(barRect.width * 0.40, barRect.center.dy));
        await tester.pump(const Duration(milliseconds: 30));
        expect(find.byKey(const Key('fullscreen_seek_tooltip')), findsOneWidget);

        await dragGesture.moveTo(Offset(barRect.width * 0.50, barRect.center.dy));
        await tester.pump(const Duration(milliseconds: 30));
        await dragGesture.moveTo(Offset(barRect.width * 0.55, barRect.center.dy));
        await tester.pump(const Duration(milliseconds: 30));

        // Rapid drag moves within 120ms are throttled to at most one seek call.
        expect(engine.seekHistory.length, lessThanOrEqualTo(1));

        // After 120ms throttle window expires, pending target flushes.
        await tester.pump(const Duration(milliseconds: 125));
        expect(engine.seekHistory.length, equals(2));

        // Move to 75% and release -> final seek committed and tooltip dismissed.
        await dragGesture.moveTo(Offset(barRect.width * 0.75, barRect.center.dy));
        await dragGesture.up();
        await tester.pump(const Duration(milliseconds: 20));

        expect(find.byKey(const Key('fullscreen_seek_tooltip')), findsNothing);
        expect(
          engine.lastSeekTarget!.inMilliseconds,
          closeTo(135000, 2000),
        );

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 4));
        await settingsStore.flush();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'Seek bar idle armResume updates cleanly and RTL fills from right edge',
      (tester) async {
        setupDesktopViewport(tester);
        engine.fakeDuration = const Duration(seconds: 100);
        queue.replaceAll(const [
          AudioSource(
            'track1.flac',
            extras: {
              'title': 'Track One',
              'artist': 'Artist One',
              'album': 'Album One',
              'durationMs': '100000',
            },
          ),
        ]);
        controller.armResume(const Duration(seconds: 20));

        await tester.pumpWidget(
          buildTestWidget(textDirection: TextDirection.rtl),
        );
        await tester.pump(const Duration(milliseconds: 50));

        expect(controller.currentState, equals(PlaybackState.idle));
        final fillFinder = find.byKey(const Key('fullscreen_seek_fill'));
        final fillRectBefore = tester.getRect(fillFinder);
        expect(fillRectBefore.right, closeTo(1280.0, 0.5));
        expect(fillRectBefore.width, closeTo(1280.0 * 0.2, 2.0));

        // Tap at 25% from the left edge in RTL -> 75% progress = 75s.
        final barRect = tester.getRect(find.byKey(const Key('fullscreen_seek_bar')));
        await tester.tapAt(Offset(barRect.width * 0.25, barRect.center.dy));
        await tester.pump(const Duration(milliseconds: 20));

        expect(
          controller.armedResumePosition!.inMilliseconds,
          closeTo(75000, 1500),
        );
        final fillRectAfter = tester.getRect(fillFinder);
        expect(fillRectAfter.right, closeTo(1280.0, 0.5));
        expect(fillRectAfter.width, closeTo(1280.0 * 0.75, 4.0));

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 4));
        await settingsStore.flush();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'Seek bar Semantics exposes slider increase and decrease and dispose leaves no timers',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          setupDesktopViewport(tester);

          await controller.playQueue(createSampleTracks(), startIndex: 0);
          await controller.seek(const Duration(seconds: 30));

          await tester.pumpWidget(buildTestWidget());
          await tester.pump(const Duration(milliseconds: 50));

          final finder = find.bySemanticsLabel('Playback position');
          expect(finder, findsOneWidget);
          final node = tester.getSemantics(finder);
          final data = node.getSemanticsData();
          expect(data.hasAction(SemanticsAction.increase), isTrue);
          expect(data.hasAction(SemanticsAction.decrease), isTrue);

          final semanticsOwner =
              tester.renderObject(finder).owner!.semanticsOwner!;
          semanticsOwner.performAction(node.id, SemanticsAction.increase);
          await tester.pump(const Duration(milliseconds: 20));
          expect(engine.lastSeekTarget, equals(const Duration(seconds: 35)));

          semanticsOwner.performAction(node.id, SemanticsAction.decrease);
          await tester.pump(const Duration(milliseconds: 20));
          expect(engine.lastSeekTarget, equals(const Duration(seconds: 30)));

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 4));
          await settingsStore.flush();
        } finally {
          handle.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'Full screen plain ArrowUp/ArrowDown adjust volume and trigger VolumeHudOverlay via AppShell',
      (tester) async {
        setupDesktopViewport(tester);

        await fakeRepo.addFolder('C:\\Music');
        await controller.playQueue(createSampleTracks(), startIndex: 0);

        final hudCtrl = VolumeHudController();
        final scanService = ScanService(repository: fakeRepo);
        final glassController = GlassController();
        settingsStore.bindGlassController(glassController);
        addTearDown(() {
          hudCtrl.dispose();
          scanService.dispose();
        });

        await tester.pumpWidget(
          GlassScope(
            controller: glassController,
            child: SettingsScope(
              store: settingsStore,
              child: VolumeHudScope(
                controller: hudCtrl,
                child: MaterialApp(
                  home: VolumeHudOverlay(
                    controller: hudCtrl,
                    child: AppShell(
                      engine: engine,
                      controller: controller,
                      repository: fakeRepo,
                      scanService: scanService,
                      settingsStore: settingsStore,
                      navigator: navigator,
                      userCollections: collections,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Open Full Screen via navigator
        navigator.openFullScreen();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final startVol = settingsStore.settings.volume;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          settingsStore.settings.volume,
          closeTo((startVol - 0.05).clamp(0.0, 1.0), 0.001),
        );
        expect(hudCtrl.isVisible, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(startVol, 0.001));

        // Return to normal destination -> plain ArrowDown ignored
        navigator.goBack();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(startVol, 0.001));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await settingsStore.flush();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}

class _BuildProbe extends StatelessWidget {
  final VoidCallback onBuild;

  const _BuildProbe({required this.onBuild});

  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox.shrink();
  }
}
