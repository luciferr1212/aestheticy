import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/lyrics/lyrics_controller.dart';
import 'package:aestheticy/features/lyrics/lyrics_models.dart';
import 'package:aestheticy/features/lyrics/lyrics_offset_store.dart';
import 'package:aestheticy/features/lyrics/lyrics_repository.dart';
import 'package:aestheticy/ui/lyrics/lyrics_view.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

class _FakeLyricsRepo extends LyricsRepository {
  LyricsResult resultToReturn = const LyricsResultNotFound();

  @override
  Future<LyricsResult> resolve({
    required String filePath,
    required String title,
    required String artist,
    String? album,
    required int durationMs,
    required String mode,
  }) async {
    return resultToReturn;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeAudioEngine engine;
  late PlaybackQueue queue;
  late PlaybackController playbackController;
  late SettingsStore settingsStore;
  late _FakeLyricsRepo fakeRepo;
  late LyricsController lyricsController;
  late AppNavigator navigator;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lyrics_idle_test_');
    engine = FakeAudioEngine();
    await engine.init();
    queue = PlaybackQueue();
    playbackController = PlaybackController(engine: engine, queue: queue);
    await playbackController.init();
    settingsStore = SettingsStore(directory: tempDir);
    await settingsStore.init();
    fakeRepo = _FakeLyricsRepo();
    lyricsController = LyricsController(
      playbackController: playbackController,
      settingsStore: settingsStore,
      repository: fakeRepo,
      offsetStore: LyricsOffsetStore(directory: tempDir),
    );
    navigator = AppNavigator();
  });

  tearDown(() async {
    lyricsController.dispose();
    await playbackController.dispose();
    await engine.dispose();
    settingsStore.dispose();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Widget buildLyricsView() {
    return SettingsScope(
      store: settingsStore,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: LyricsView(
            controller: lyricsController,
            playbackController: playbackController,
            navigator: navigator,
            settingsStore: settingsStore,
          ),
        ),
      ),
    );
  }

  const syncedDoc = LyricsDocument(
    source: LyricsSourceOrigin.local,
    kind: LyricsKind.synced,
    hasWordTiming: true,
    lines: [
      LyricsLine(
        startMs: 1000,
        text: 'First line text',
        words: [
          LyricsWord(text: 'First', startMs: 1000, endMs: 1500),
          LyricsWord(text: 'line', startMs: 1500, endMs: 2000),
          LyricsWord(text: 'text', startMs: 2000, endMs: 2500),
        ],
      ),
      LyricsLine(
        startMs: 3000,
        text: 'Second line text',
        words: [
          LyricsWord(text: 'Second', startMs: 3000, endMs: 3500),
          LyricsWord(text: 'line', startMs: 3500, endMs: 4000),
          LyricsWord(text: 'text', startMs: 4000, endMs: 4500),
        ],
      ),
      LyricsLine(
        startMs: 6000,
        text: 'Third line text',
        words: [
          LyricsWord(text: 'Third', startMs: 6000, endMs: 6500),
          LyricsWord(text: 'line', startMs: 6500, endMs: 7000),
          LyricsWord(text: 'text', startMs: 7000, endMs: 7500),
        ],
      ),
    ],
  );

  testWidgets(
    'Seeking while paused moves the active line and active word highlight immediately',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      fakeRepo.resultToReturn = const LyricsResultFound(syncedDoc);
      const source = AudioSource('C:\\music\\track.mp3', extras: {'title': 'Track', 'artist': 'Artist'});

      // Set up queue with track and pause
      queue.replaceAll([source]);
      await playbackController.pause();
      await lyricsController.retry();
      expect(playbackController.currentState, PlaybackState.paused);

      await tester.pumpWidget(buildLyricsView());
      await tester.pumpAndSettle();

      // Initially at position 0, line index should be -1 or 0
      // Now seek while paused to 3600ms (inside line 1, second word 'line')
      await playbackController.seek(const Duration(milliseconds: 3600));
      await tester.pump();

      // Active line and word in controller should immediately update
      expect(lyricsController.currentLineIndex, 1);
      expect(lyricsController.currentWordIndex, 1);
      expect(lyricsController.activeLineListenable.value, 1);
      expect(lyricsController.activeWordListenable.value, 1);

      // Playback state must remain paused
      expect(playbackController.currentState, PlaybackState.paused);
    },
  );

  testWidgets(
    'Clicking a line while paused moves highlight and does NOT start playing',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      fakeRepo.resultToReturn = const LyricsResultFound(syncedDoc);
      const source = AudioSource('C:\\music\\track.mp3', extras: {'title': 'Track', 'artist': 'Artist'});

      // Set up queue with track and pause
      queue.replaceAll([source]);
      await playbackController.pause();
      await lyricsController.retry();
      expect(playbackController.currentState, PlaybackState.paused);

      await tester.pumpWidget(buildLyricsView());
      await tester.pumpAndSettle();

      // Click the 3rd line ('Third line text' at 6000ms)
      final line3Finder = find.text('Third line text');
      expect(line3Finder, findsOneWidget);
      await tester.tap(line3Finder);
      await tester.pumpAndSettle();

      // Playback MUST still be paused (no auto-resume)
      expect(playbackController.currentState, PlaybackState.paused);

      // Engine position should now be at line 3 start (6000ms)
      expect(playbackController.currentPosition.inMilliseconds, 6000);

      // Controller highlight should immediately be line 2 (3rd line) and word 0
      expect(lyricsController.currentLineIndex, 2);
      expect(lyricsController.currentWordIndex, 0);
      expect(lyricsController.activeLineListenable.value, 2);
      expect(lyricsController.activeWordListenable.value, 0);
    },
  );

  testWidgets(
    'No periodic timers or tickers running while paused',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      fakeRepo.resultToReturn = const LyricsResultFound(syncedDoc);
      const source = AudioSource('C:\\music\\track.mp3', extras: {'title': 'Track', 'artist': 'Artist'});

      queue.replaceAll([source]);
      await playbackController.pause();
      await lyricsController.retry();
      expect(playbackController.currentState, PlaybackState.paused);

      await tester.pumpWidget(buildLyricsView());
      await tester.pumpAndSettle();

      // Seek to second line while paused
      await playbackController.seek(const Duration(milliseconds: 3200));
      await tester.pump();

      // Ticker must NOT be running continuously while paused.
      // If a periodic timer or continuous ticker was running, pump with duration would advance it or keep ticking.
      // pumpAndSettle should finish with 0 pending timers/frames!
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );
}
