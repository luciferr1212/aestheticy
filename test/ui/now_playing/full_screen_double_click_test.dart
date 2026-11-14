import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/features/lyrics/lyrics_controller.dart';
import 'package:aestheticy/features/lyrics/lyrics_models.dart';
import 'package:aestheticy/features/lyrics/lyrics_repository.dart';
import 'package:aestheticy/ui/glass/glass_blur_budget.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/now_playing/full_screen_view.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import '../../library/fake_library_repository.dart';

class _FakeLyricsRepository extends LyricsRepository {
  final LyricsResult result;
  _FakeLyricsRepository(this.result);

  @override
  Future<LyricsResult> resolve({
    required String filePath,
    required String title,
    required String artist,
    String? album,
    required int durationMs,
    required String mode,
  }) async {
    return result;
  }
}

void main() {
  group('FullScreenView Double Click Play/Pause Tests', () {
    late SettingsStore settingsStore;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late AppNavigator navigator;
    late FakeLibraryRepository fakeRepo;
    late UserCollections collections;
    late LyricsController lyricsController;

    const sampleDoc = LyricsDocument(
      source: LyricsSourceOrigin.local,
      kind: LyricsKind.synced,
      hasWordTiming: false,
      lines: [
        LyricsLine(
          startMs: 2000,
          text: 'First test lyric line',
          words: [],
        ),
        LyricsLine(
          startMs: 5000,
          text: 'Second test lyric line',
          words: [],
        ),
      ],
    );

    setUp(() async {
      GlassBlurBudget.instance.resetForTesting();
      settingsStore = SettingsStore();
      await settingsStore.init();

      engine = FakeAudioEngine();
      await engine.init();

      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();

      navigator = AppNavigator();
      fakeRepo = FakeLibraryRepository();
      collections = UserCollections(repository: fakeRepo);
      await collections.init();

      lyricsController = LyricsController(
        playbackController: controller,
        repository: _FakeLyricsRepository(const LyricsResultFound(sampleDoc)),
        settingsStore: settingsStore,
      );
    });

    tearDown(() async {
      lyricsController.dispose();
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

    Widget buildTestWidget() {
      return MaterialApp(
        home: UserCollectionsScope(
          collections: collections,
          child: GlassScope(
            controller: GlassController(quality: GlassQuality.full),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: FullScreenView(
                controller: controller,
                engine: engine,
                navigator: navigator,
                settingsStore: settingsStore,
                lyricsController: lyricsController,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'Double clicking background toggles play/pause and displays confirmation indicator',
      (tester) async {
        setupDesktopViewport(tester);
        await controller.playQueue(createSampleTracks(), startIndex: 0);
        await tester.pumpWidget(buildTestWidget());
        await tester.pump(const Duration(milliseconds: 50));

        expect(controller.currentState, PlaybackState.playing);
        expect(find.byKey(const Key('fullscreen_play_pause_indicator')), findsNothing);

        // Double click empty space (e.g. x=640, y=400 in the center gap)
        await tester.tapAt(const Offset(640, 400));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(const Offset(640, 400));
        await tester.pump();

        // Controller should now be paused
        expect(controller.currentState, PlaybackState.paused);

        // Indicator should be visible
        expect(find.byKey(const Key('fullscreen_play_pause_indicator')), findsOneWidget);

        // Mid animation at 300 ms, indicator remains visible
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('fullscreen_play_pause_indicator')), findsOneWidget);

        // After completing total 600 ms, indicator is removed from widget tree
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byKey(const Key('fullscreen_play_pause_indicator')), findsNothing);

        // Double click again to resume playback
        await tester.tapAt(const Offset(640, 400));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(const Offset(640, 400));
        await tester.pump();

        expect(controller.currentState, PlaybackState.playing);
        expect(find.byKey(const Key('fullscreen_play_pause_indicator')), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 650));
        expect(find.byKey(const Key('fullscreen_play_pause_indicator')), findsNothing);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        await settingsStore.flush();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'Single click on empty area does nothing (no toggle, no indicator)',
      (tester) async {
        setupDesktopViewport(tester);
        await controller.playQueue(createSampleTracks(), startIndex: 0);
        await tester.pumpWidget(buildTestWidget());
        await tester.pump(const Duration(milliseconds: 50));

        expect(controller.currentState, PlaybackState.playing);

        // Single click at empty area
        await tester.tapAt(const Offset(640, 400));
        await tester.pump(const Duration(milliseconds: 500));

        expect(controller.currentState, PlaybackState.playing);
        expect(find.byKey(const Key('fullscreen_play_pause_indicator')), findsNothing);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        await settingsStore.flush();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'Double clicking seek bar does NOT toggle playback or show indicator',
      (tester) async {
        setupDesktopViewport(tester);
        await controller.playQueue(createSampleTracks(), startIndex: 0);
        await tester.pumpWidget(buildTestWidget());
        await tester.pump(const Duration(milliseconds: 50));

        expect(controller.currentState, PlaybackState.playing);

        final seekFinder = find.byKey(const Key('fullscreen_seek_bar'));
        expect(seekFinder, findsOneWidget);
        final seekCenter = tester.getCenter(seekFinder);

        // Double click on the seek bar
        await tester.tapAt(seekCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(seekCenter);
        await tester.pump(const Duration(milliseconds: 100));

        // State remains playing
        expect(controller.currentState, PlaybackState.playing);
        expect(find.byKey(const Key('fullscreen_play_pause_indicator')), findsNothing);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        await settingsStore.flush();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'Double clicking lyric line does NOT toggle playback or show indicator',
      (tester) async {
        setupDesktopViewport(tester);
        settingsStore.update((s) => s.copyWith(showLyricsInFullScreen: true));
        await settingsStore.flush();

        queue.replaceAll(createSampleTracks());
        await lyricsController.retry();
        await tester.pumpWidget(buildTestWidget());
        await tester.pump(const Duration(milliseconds: 100));

        final lineFinder = find.text('First test lyric line');
        expect(lineFinder, findsOneWidget);
        final lineCenter = tester.getCenter(lineFinder);

        expect(controller.currentState, PlaybackState.idle);

        // Double click directly on the lyric line
        await tester.tapAt(lineCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(lineCenter);
        await tester.pump(const Duration(milliseconds: 100));

        // State remains idle (does not toggle to play)
        expect(controller.currentState, PlaybackState.idle);
        expect(find.byKey(const Key('fullscreen_play_pause_indicator')), findsNothing);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        await settingsStore.flush();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'Reduce motion sets indicator duration to zero and does not linger',
      (tester) async {
        setupDesktopViewport(tester);
        settingsStore.update((s) => s.copyWith(reduceMotion: true));
        await settingsStore.flush();

        await controller.playQueue(createSampleTracks(), startIndex: 0);
        await tester.pumpWidget(buildTestWidget());
        await tester.pump(const Duration(milliseconds: 50));

        final state = tester.state<FullScreenViewState>(find.byType(FullScreenView));
        expect(state.indicatorController.duration, equals(Duration.zero));

        // Double click background
        await tester.tapAt(const Offset(640, 400));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(const Offset(640, 400));
        await tester.pump(const Duration(milliseconds: 100));

        // Toggled
        expect(controller.currentState, PlaybackState.paused);
        // Indicator should not linger in tree with reduceMotion
        expect(find.byKey(const Key('fullscreen_play_pause_indicator')), findsNothing);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        await settingsStore.flush();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
