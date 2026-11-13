import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/lyrics/lrc_parser.dart';
import 'package:aestheticy/features/lyrics/lyrics_controller.dart';
import 'package:aestheticy/features/lyrics/lyrics_offset_store.dart';
import 'package:aestheticy/features/lyrics/lyrics_repository.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

import '../../helpers/wait_for.dart';

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

class DelayedOffsetStore extends LyricsOffsetStore {
  final Map<String, Completer<int>> pendingLoads = {};

  DelayedOffsetStore({required Directory directory}) : super(directory: directory);

  @override
  Future<int> loadOffset(String trackPath) {
    final completer = Completer<int>();
    pendingLoads[trackPath] = completer;
    return completer.future;
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

    test('kLyricsLineLeadMs advances line activation by 120ms without shifting word timing', () async {
      const enhancedLrc = '''
[00:02.00]<00:02.00>First <00:02.50>Second
[00:05.00]<00:05.00>Next
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

      // Just before lead window (2000 - 120 - 1 = 1879ms)
      controller.updatePosition(const Duration(milliseconds: 2000 - kLyricsLineLeadMs - 1));
      expect(controller.currentLineIndex, equals(-1));
      expect(controller.activeLineListenable.value, equals(-1));
      expect(controller.currentWordIndex, equals(-1));

      // Exact lead boundary (1880ms): line switches early, word timing waits for 2000ms
      controller.updatePosition(const Duration(milliseconds: 2000 - kLyricsLineLeadMs));
      expect(controller.currentLineIndex, equals(0));
      expect(controller.activeLineListenable.value, equals(0));
      expect(controller.currentWordIndex, equals(-1));
      expect(controller.wordProgress, equals(0.0));

      // Real word timestamp reached (2000ms)
      controller.updatePosition(const Duration(milliseconds: 2000));
      expect(controller.currentLineIndex, equals(0));
      expect(controller.currentWordIndex, equals(0));

      // Next line switches 120ms early at 4880ms, word timing stays -1 until 5000ms
      controller.updatePosition(const Duration(milliseconds: 5000 - kLyricsLineLeadMs));
      expect(controller.currentLineIndex, equals(1));
      expect(controller.currentWordIndex, equals(-1));
    });
  });

  group('LyricsOffsetStore & Per-Track Offset Tests (S3)', () {
    late Directory tempDir;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController playbackController;
    late SettingsStore settingsStore;
    late FakeLyricsRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_lyrics_offset_');
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
      settingsStore.dispose();
      await playbackController.dispose();
      await engine.dispose();
      if (tempDir.existsSync()) {
        for (var i = 0; i < 5; i++) {
          try {
            await tempDir.delete(recursive: true);
            break;
          } on FileSystemException {
            if (i < 4) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }
        }
      }
    });

    test('store saves md5-keyed JSON with 300ms debounce, clamps, and removes 0', () async {
      final store = LyricsOffsetStore(directory: tempDir);
      LyricsOffsetStore? reloaded;
      try {
        await store.init();

        const trackPath = r'C:\Music\Artist\Song.flac';
        await store.setOffset(trackPath, 300);
        await store.setOffset(trackPath, 500);
        expect(await store.loadOffset(trackPath), equals(500));

        final file = File('${tempDir.path}${Platform.pathSeparator}lyrics_offsets.json');
        expect(file.existsSync(), isFalse);

        await waitFor(() => file.existsSync());
        expect(file.existsSync(), isTrue);

        final parsed = jsonDecode(await file.readAsString()) as Map<String, Object?>;
        expect(parsed[LyricsOffsetStore.keyForPath(trackPath)], equals(500));

        // Clamping beyond [-15000, +15000]
        await store.setOffset(trackPath, 25000);
        expect(await store.loadOffset(trackPath), equals(kMaxLyricsOffsetMs));
        await store.setOffset(trackPath, -25000);
        expect(await store.loadOffset(trackPath), equals(kMinLyricsOffsetMs));
        await store.flush();

        // Reload in a fresh instance
        reloaded = LyricsOffsetStore(directory: tempDir);
        await reloaded.init();
        expect(await reloaded.loadOffset(trackPath), equals(kMinLyricsOffsetMs));

        // Value 0 deletes the key from persisted JSON
        await reloaded.setOffset(trackPath, 0);
        await reloaded.flush();
        final parsedAfterZero =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        expect(parsedAfterZero.containsKey(LyricsOffsetStore.keyForPath(trackPath)), isFalse);
      } finally {
        await store.flush();
        store.dispose();
        if (reloaded != null) {
          await reloaded.flush();
          reloaded.dispose();
        }
      }
    });

    test('corrupt lyrics_offsets.json degrades cleanly to empty map', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}lyrics_offsets.json');
      await file.writeAsString('{not valid json!!!');

      final store = LyricsOffsetStore(directory: tempDir);
      await store.init();
      expect(await store.loadOffset('file:///music/any.mp3'), equals(0));
      store.dispose();
    });

    test('positive and negative offsets shift lines and words with line lead preserved', () async {
      final offsetStore = LyricsOffsetStore(directory: tempDir);
      await offsetStore.init();

      const lrc = '[00:00.00]<00:00.00>Start <00:00.50>now\n'
          '[00:05.00]<00:05.00>Second <00:05.50>line';
      repository.onResolve = (path) async => LyricsResultFound(parseLrc(lrc));

      final controller = LyricsController(
        playbackController: playbackController,
        repository: repository,
        settingsStore: settingsStore,
        offsetStore: offsetStore,
      );

      queue.replaceAll([
        const AudioSource('file:///music/t1.mp3', extras: {'title': 'T1'}),
      ]);
      await playbackController.play();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Positive offset (+1000ms): lyrics appear LATER -> at 500ms effective is -500ms, still -1
      await controller.setOffset(1000);
      controller.updatePosition(const Duration(milliseconds: 500));
      expect(controller.offsetMs, equals(1000));
      expect(controller.currentLineIndex, equals(-1));
      expect(controller.currentWordIndex, equals(-1));

      // Line lead (120ms) stays separate: at 880ms, effective is -120ms, line 0 activates
      controller.updatePosition(const Duration(milliseconds: 1000 - kLyricsLineLeadMs));
      expect(controller.currentLineIndex, equals(0));
      expect(controller.currentWordIndex, equals(-1));

      // Word 0 starts at 1000ms (effective 0ms), word 1 starts at 1500ms (effective 500ms)
      controller.updatePosition(const Duration(milliseconds: 1000));
      expect(controller.currentWordIndex, equals(0));
      controller.updatePosition(const Duration(milliseconds: 1500));
      expect(controller.currentWordIndex, equals(1));

      // Negative offset (-500ms): lyrics appear EARLIER -> 5000ms line triggers at 4380ms
      await controller.setOffset(-500);
      controller.updatePosition(const Duration(milliseconds: 4500 - kLyricsLineLeadMs));
      expect(controller.currentLineIndex, equals(1));
      // Line lead activates line 1 early, while word 0 still waits until 4500ms (effective 5000ms)
      expect(controller.currentWordIndex, equals(-1));
      controller.updatePosition(const Duration(milliseconds: 4500));
      expect(controller.currentWordIndex, equals(0));

      await controller.resetOffset();
      expect(controller.offsetMs, equals(0));

      await offsetStore.flush();
      offsetStore.dispose();
      controller.dispose();
    });

    test('offsets are isolated per track and stale load cannot overwrite newer track', () async {
      final offsetStore = LyricsOffsetStore(directory: tempDir);
      await offsetStore.init();
      await offsetStore.setOffset('/music/a.mp3', 400);
      await offsetStore.setOffset('/music/b.mp3', -700);
      await offsetStore.flush();

      repository.onResolve = (path) async => LyricsResultFound(parseLrc('[00:01.00]Line'));

      final controller = LyricsController(
        playbackController: playbackController,
        repository: repository,
        settingsStore: settingsStore,
        offsetStore: offsetStore,
      );

      queue.replaceAll([
        const AudioSource('/music/a.mp3', extras: {'title': 'A'}),
        const AudioSource('/music/b.mp3', extras: {'title': 'B'}),
      ]);
      await playbackController.play();
      await waitFor(() => controller.offsetMs == 400);
      expect(controller.offsetMs, equals(400));

      await playbackController.skipNext();
      await waitFor(() => controller.offsetMs == -700);
      expect(controller.offsetMs, equals(-700));

      await playbackController.skipPrevious();
      await waitFor(() => controller.offsetMs == 400);
      expect(controller.offsetMs, equals(400));
      controller.dispose();
      offsetStore.dispose();

      // Verify stale async loadOffset response is ignored after rapid track switch
      final delayedStore = DelayedOffsetStore(directory: tempDir);
      final staleController = LyricsController(
        playbackController: playbackController,
        repository: repository,
        settingsStore: settingsStore,
        offsetStore: delayedStore,
      );

      await playbackController.skipNext();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await playbackController.skipPrevious();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Complete track B late (after switching back to A), then complete track A
      delayedStore.pendingLoads['/music/b.mp3']!.complete(1200);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(staleController.offsetMs, equals(0));

      delayedStore.pendingLoads['/music/a.mp3']!.complete(-200);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(staleController.offsetMs, equals(-200));

      staleController.dispose();
      delayedStore.dispose();
    });
  });
}
