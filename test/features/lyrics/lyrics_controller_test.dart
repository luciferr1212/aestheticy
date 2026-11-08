import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/lyrics/lrc_parser.dart';
import 'package:aestheticy/features/lyrics/lyrics_controller.dart';
import 'package:aestheticy/features/lyrics/lyrics_repository.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

class FakeLyricsRepository extends LyricsRepository {
  Future<LyricsResult> Function(String filePath)? onResolve;

  FakeLyricsRepository() : super();

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
    if (onResolve != null) {
      return onResolve!(filePath);
    }
    return const LyricsResultNotFound();
  }
}

void main() {
  group('LyricsController Tests (S4)', () {
    late Directory tempDir;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController playbackController;
    late SettingsStore settingsStore;
    late FakeLyricsRepository repository;
    late LyricsController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_lyrics_ctrl_');
      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      playbackController = PlaybackController(engine: engine, queue: queue);
      await playbackController.init();

      settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(lyricsSource: 'localThenOnline'),
      );
      await settingsStore.init();

      repository = FakeLyricsRepository();
    });

    tearDown(() async {
      controller.dispose();
      settingsStore.dispose();
      await playbackController.dispose();
      await engine.dispose();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('state transitions: loading -> found -> notFound -> error -> off', () async {
      final doc = parseLrc('[00:01.00]Hello world');
      repository.onResolve = (path) async => LyricsResultFound(doc);

      controller = LyricsController(
        playbackController: playbackController,
        repository: repository,
        settingsStore: settingsStore,
      );

      // 1. Initial state without track
      expect(controller.state, isA<LyricsStateNotFound>());

      // 2. Play track 1 -> transitions to Found
      queue.replaceAll([
        const AudioSource('file:///music/track1.mp3', extras: {'title': 'Track 1'}),
      ]);
      await playbackController.play();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.state, isA<LyricsStateFound>());
      expect(controller.document, equals(doc));

      // 3. Play track 2 returning not found
      repository.onResolve = (path) async => const LyricsResultNotFound();
      queue.replaceAll([
        const AudioSource('file:///music/track2.mp3', extras: {'title': 'Track 2'}),
      ]);
      await playbackController.play();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.state, isA<LyricsStateNotFound>());

      // 4. Play track 3 returning error
      repository.onResolve = (path) async => const LyricsResultError(LyricsErrorReason.timeout);
      queue.replaceAll([
        const AudioSource('file:///music/track3.mp3', extras: {'title': 'Track 3'}),
      ]);
      await playbackController.play();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.state, isA<LyricsStateError>());
      expect((controller.state as LyricsStateError).reason, equals(LyricsErrorReason.timeout));

      // 5. Change setting to off -> state switches to Off
      settingsStore.update((s) => s.copyWith(lyricsSource: 'off'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.state, isA<LyricsStateOff>());
    });

    test('stale result is ignored on quick track change', () async {
      final track1Completer = Completer<LyricsResult>();
      final doc2 = parseLrc('[00:01.00]Track 2 lyrics');

      repository.onResolve = (path) async {
        if (path.contains('track1')) {
          return track1Completer.future;
        }
        return LyricsResultFound(doc2);
      };

      controller = LyricsController(
        playbackController: playbackController,
        repository: repository,
        settingsStore: settingsStore,
      );

      // Start loading track 1 (hangs on completer)
      queue.replaceAll([
        const AudioSource('file:///music/track1.mp3', extras: {'title': 'Track 1'}),
      ]);
      await playbackController.play();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.state, isA<LyricsStateLoading>());

      // Quickly advance to track 2
      queue.replaceAll([
        const AudioSource('file:///music/track2.mp3', extras: {'title': 'Track 2'}),
      ]);
      await playbackController.play();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.state, isA<LyricsStateFound>());
      expect(controller.document, equals(doc2));

      // Now complete the delayed track 1 resolution
      final doc1 = parseLrc('[00:01.00]Stale track 1 lyrics');
      track1Completer.complete(LyricsResultFound(doc1));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // State MUST remain Track 2!
      expect(controller.state, isA<LyricsStateFound>());
      expect(controller.document, equals(doc2), reason: 'Stale track 1 result must be silently discarded');
    });

    test('line index at boundaries: before first, exact start, after last', () async {
      const lrc = '''
[00:02.00]Line 0
[00:05.00]Line 1
[00:08.00]Line 2
''';
      final doc = parseLrc(lrc);
      repository.onResolve = (path) async => LyricsResultFound(doc);

      controller = LyricsController(
        playbackController: playbackController,
        repository: repository,
        settingsStore: settingsStore,
      );

      queue.replaceAll([
        const AudioSource('file:///music/track.mp3', extras: {'title': 'Track'}),
      ]);
      await playbackController.play();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Boundary 1: before first line (< 2000 ms)
      controller.updatePosition(const Duration(milliseconds: 1000));
      expect(controller.currentLineIndex, equals(-1));

      // Boundary 2: exact start of line 0 (2000 ms)
      controller.updatePosition(const Duration(milliseconds: 2000));
      expect(controller.currentLineIndex, equals(0));

      // Intermediate position between line 0 and line 1
      controller.updatePosition(const Duration(milliseconds: 3500));
      expect(controller.currentLineIndex, equals(0));

      // Boundary 3: exact start of line 1 (5000 ms)
      controller.updatePosition(const Duration(milliseconds: 5000));
      expect(controller.currentLineIndex, equals(1));

      // Boundary 4: exact start of line 2 (8000 ms)
      controller.updatePosition(const Duration(milliseconds: 8000));
      expect(controller.currentLineIndex, equals(2));

      // Boundary 5: after last line (12000 ms)
      controller.updatePosition(const Duration(milliseconds: 12000));
      expect(controller.currentLineIndex, equals(2));
    });

    test('word index and progress for real word timing, and no word data for line-only documents', () async {
      // 1. Document with real word timing
      const enhancedLrc = '''
[00:02.00]<00:02.00>First <00:02.50>Second <00:03.00>Third
[00:05.00]Normal line without words
''';
      final doc = parseLrc(enhancedLrc);
      repository.onResolve = (path) async => LyricsResultFound(doc);

      controller = LyricsController(
        playbackController: playbackController,
        repository: repository,
        settingsStore: settingsStore,
      );

      queue.replaceAll([
        const AudioSource('file:///music/track.mp3', extras: {'title': 'Track'}),
      ]);
      await playbackController.play();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Before word start
      controller.updatePosition(const Duration(milliseconds: 1500));
      expect(controller.currentLineIndex, equals(-1));
      expect(controller.currentWordIndex, equals(-1));
      expect(controller.wordProgress, equals(0.0));

      // Word 0 at start (2000 ms)
      controller.updatePosition(const Duration(milliseconds: 2000));
      expect(controller.currentLineIndex, equals(0));
      expect(controller.currentWordIndex, equals(0));
      expect(controller.wordProgress, closeTo(0.0, 0.01));

      // Word 0 midway (2250 ms, end is 2500 ms)
      controller.updatePosition(const Duration(milliseconds: 2250));
      expect(controller.currentWordIndex, equals(0));
      expect(controller.wordProgress, closeTo(0.5, 0.05));

      // Word 1 at start (2500 ms)
      controller.updatePosition(const Duration(milliseconds: 2500));
      expect(controller.currentWordIndex, equals(1));
      expect(controller.wordProgress, closeTo(0.0, 0.01));

      // Line 1: Normal line without word timing -> word index -1, progress 0.0
      controller.updatePosition(const Duration(milliseconds: 5500));
      expect(controller.currentLineIndex, equals(1));
      expect(controller.currentWordIndex, equals(-1));
      expect(controller.wordProgress, equals(0.0));
    });

    test('live source change triggers re-resolve', () async {
      var resolveCount = 0;
      repository.onResolve = (path) async {
        resolveCount++;
        return LyricsResultFound(parseLrc('[00:01.00]Line'));
      };

      controller = LyricsController(
        playbackController: playbackController,
        repository: repository,
        settingsStore: settingsStore,
      );

      queue.replaceAll([
        const AudioSource('file:///music/track.mp3', extras: {'title': 'Track'}),
      ]);
      await playbackController.play();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(resolveCount, equals(1));

      // Change settings mode from localThenOnline to onlineThenLocal
      settingsStore.update((s) => s.copyWith(lyricsSource: 'onlineThenLocal'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(resolveCount, equals(2), reason: 'Changing lyricsSource must re-resolve lyrics for the current track');
    });
  });
}
