import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/glass/glass_blur_budget.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/glass/glass_surface.dart';
import 'package:aestheticy/ui/now_playing/full_screen_view.dart';
import 'package:aestheticy/ui/now_playing/now_playing_view.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';

class FullScreenTestEngine extends FakeAudioEngine {
  Duration? lastSeekTarget;

  @override
  Future<void> seek(Duration position) async {
    lastSeekTarget = position;
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
    });

    tearDown(() async {
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

    Widget buildTestWidget({VoidCallback? onTickerFrame}) {
      return MaterialApp(
        home: GlassScope(
          controller: GlassController(quality: GlassQuality.full),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FullScreenView(
              controller: controller,
              engine: engine,
              navigator: navigator,
              settingsStore: settingsStore,
              onTickerFrame: onTickerFrame,
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
      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);
      navigator.openFullScreen();

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      // Space: toggle play/pause
      expect(controller.currentState, equals(PlaybackState.playing));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.currentState, equals(PlaybackState.paused));

      // Left arrow: seek -5s
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 50));
      expect(engine.lastSeekTarget, isNotNull);

      // Right arrow: seek +5s
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
  });
}
