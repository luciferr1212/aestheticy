import 'dart:async';
import 'dart:io';

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
import 'package:aestheticy/ui/now_playing/now_playing_view.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/shell/bottom_now_playing_bar.dart';

/// Test engine allowing controlled stream info emission.
class TestControllableAudioEngine extends FakeAudioEngine {
  final _testStreamInfoCtrl = StreamController<AudioStreamInfo?>.broadcast();
  Duration? lastSeekTarget;

  void emitStreamInfo(AudioStreamInfo? info) {
    _testStreamInfoCtrl.add(info);
  }

  @override
  Stream<AudioStreamInfo?> get streamInfoStream => _testStreamInfoCtrl.stream;

  @override
  Future<void> seek(Duration position) async {
    lastSeekTarget = position;
    await super.seek(position);
  }
}

void main() {
  group('NowPlayingView Tests', () {
    late Directory tempDir;
    late SettingsStore settingsStore;
    late TestControllableAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late AppNavigator navigator;

    setUp(() async {
      GlassBlurBudget.instance.resetForTesting();
      tempDir = await Directory.systemTemp.createTemp('now_playing_test_');
      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();

      engine = TestControllableAudioEngine();
      await engine.init();

      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();

      navigator = AppNavigator();
    });

    tearDown(() async {
      await controller.dispose();
      await engine.dispose();
      settingsStore.dispose();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

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
        const AudioSource(
          'track2.flac',
          extras: {
            'title': 'Track Two',
            'artist': 'Artist Two',
            'album': 'Album Two',
            'durationMs': '240000',
          },
        ),
        const AudioSource(
          'track3.flac',
          extras: {
            'title': 'Track Three',
            'artist': 'Artist Three',
            'album': 'Album Three',
            'durationMs': '210000',
          },
        ),
      ];
    }

    Widget buildTestWidget({VoidCallback? onMetadataBuild}) {
      return MaterialApp(
        home: GlassScope(
          controller: GlassController(quality: GlassQuality.full),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: NowPlayingView(
              controller: controller,
              engine: engine,
              navigator: navigator,
              settingsStore: settingsStore,
              onMetadataBuild: onMetadataBuild,
            ),
          ),
        ),
      );
    }

    void setupDesktopViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    testWidgets('Tapping upcoming track plays it and updates queue cursor', (tester) async {
      setupDesktopViewport(tester);
      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Track One'), findsOneWidget);
      expect(find.text('Track Two'), findsOneWidget);

      // Tap 'Track Two' in upcoming list
      await tester.tap(find.text('Track Two'));
      await tester.pumpAndSettle();

      expect(controller.queue.currentIndex, equals(1));
      expect(controller.queue.current?.extras?['title'], equals('Track Two'));
    });

    testWidgets('Clear upcoming button removes upcoming tracks from queue', (tester) async {
      setupDesktopViewport(tester);
      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(controller.queue.length, equals(3));
      expect(find.text('Track Two'), findsOneWidget);

      // Tap 'Clear upcoming'
      await tester.tap(find.text('Clear upcoming'));
      await tester.pumpAndSettle();

      expect(controller.queue.length, equals(1));
      expect(find.text('Nothing is queued next'), findsOneWidget);
    });

    testWidgets('Repeat mode button cycles off -> all -> one -> off and displays badge', (tester) async {
      setupDesktopViewport(tester);
      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(controller.queue.repeatMode, equals(RepeatMode.off));
      expect(find.byIcon(Icons.repeat_one), findsNothing);

      // 1st tap -> all
      await tester.tap(find.byIcon(Icons.repeat));
      await tester.pumpAndSettle();
      expect(controller.queue.repeatMode, equals(RepeatMode.all));
      expect(find.byIcon(Icons.repeat_one), findsNothing);

      // 2nd tap -> one (shows '1' badge and repeat_one icon)
      await tester.tap(find.byIcon(Icons.repeat));
      await tester.pumpAndSettle();
      expect(controller.queue.repeatMode, equals(RepeatMode.one));
      expect(find.byIcon(Icons.repeat_one), findsOneWidget);

      // 3rd tap -> off
      await tester.tap(find.byIcon(Icons.repeat_one));
      await tester.pumpAndSettle();
      expect(controller.queue.repeatMode, equals(RepeatMode.off));
      expect(find.byIcon(Icons.repeat_one), findsNothing);
    });

    testWidgets('Shuffle button toggles queue shuffle state', (tester) async {
      setupDesktopViewport(tester);
      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(controller.queue.isShuffled, isFalse);

      await tester.tap(find.byIcon(Icons.shuffle));
      await tester.pumpAndSettle();
      expect(controller.queue.isShuffled, isTrue);

      await tester.tap(find.byIcon(Icons.shuffle));
      await tester.pumpAndSettle();
      expect(controller.queue.isShuffled, isFalse);
    });

    testWidgets('Audio stream info displays formatted string, fallback, and Lossless badge', (tester) async {
      setupDesktopViewport(tester);
      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Initially null -> 'Standard audio'
      expect(find.text('Standard audio'), findsOneWidget);

      // Emit high-res lossless stream info
      engine.emitStreamInfo(const AudioStreamInfo(
        codec: 'flac',
        sampleRate: 48000,
        bitDepth: 24,
        channels: 2,
        bitrateKbps: 920.0,
        isLossless: true,
      ));
      await tester.pumpAndSettle();

      expect(find.text('FLAC · 48 kHz · 24-bit · Stereo · 920 kbps'), findsOneWidget);
      expect(find.text('Lossless'), findsOneWidget);

      // Emit lossy info
      engine.emitStreamInfo(const AudioStreamInfo(
        codec: 'mp3',
        sampleRate: 44100,
        channels: 2,
        bitrateKbps: 320.0,
        isLossless: false,
      ));
      await tester.pumpAndSettle();

      expect(find.text('MP3 · 44.1 kHz · Stereo · 320 kbps'), findsOneWidget);
      expect(find.text('Lossless'), findsNothing);
    });

    testWidgets('Ticking seekbar emits position events with ZERO rebuilds of metadata area', (tester) async {
      setupDesktopViewport(tester);
      int metadataBuildCount = 0;
      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);

      await tester.pumpWidget(buildTestWidget(
        onMetadataBuild: () => metadataBuildCount++,
      ));
      await tester.pumpAndSettle();

      final initialBuildCount = metadataBuildCount;
      expect(initialBuildCount, greaterThan(0));

      // Simulate 10 seekbar ticks
      for (int i = 0; i < 10; i++) {
        engine.simulateTick(const Duration(seconds: 1));
        await tester.pump();
      }

      // Metadata build count MUST remain completely unchanged
      expect(metadataBuildCount, equals(initialBuildCount));
    });

    testWidgets('Keyboard shortcuts: Space, Left, Right, Esc', (tester) async {
      setupDesktopViewport(tester);
      final tracks = createSampleTracks();
      await controller.playQueue(tracks, startIndex: 0);
      navigator.openNowPlaying();

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Space: toggle play/pause
      expect(controller.currentState, equals(PlaybackState.playing));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(controller.currentState, equals(PlaybackState.paused));

      // Right arrow: seek +5s
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(engine.lastSeekTarget, isNotNull);

      // Esc: calls goBack on navigator
      bool wentBack = false;
      navigator.addListener(() {
        wentBack = true;
      });
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(wentBack, isTrue);
      expect(navigator.current, equals(AppDestination.albums));
    });

    testWidgets('AppShell integration: navigation to NowPlaying and back preserves state', (tester) async {
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
      await tester.pumpAndSettle();

      // Starts on Albums
      expect(navigator.current, equals(AppDestination.albums));
      expect(find.byType(BottomNowPlayingBar), findsOneWidget);

      // Tap player bar to open Now Playing
      await tester.tap(find.text('Track One'));
      await tester.pumpAndSettle();

      expect(navigator.current, equals(AppDestination.nowPlaying));
      expect(find.byType(NowPlayingView), findsOneWidget);
      // Bottom bar and sidebar are unmounted in Now Playing
      expect(find.byType(BottomNowPlayingBar), findsNothing);

      // Tap Back button ("Library")
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();

      expect(navigator.current, equals(AppDestination.albums));
      expect(find.byType(BottomNowPlayingBar), findsOneWidget);

      await repo.close();
    });
  });
}
