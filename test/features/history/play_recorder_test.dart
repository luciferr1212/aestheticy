import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/history/play_recorder.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';

class _FakeHistoryRepository extends Fake implements LibraryRepository {
  final List<PlayEvent> events = [];
  bool shouldThrow = false;

  @override
  Future<int> insertPlayEvent(PlayEvent e) async {
    if (shouldThrow) throw Exception('Simulated DB failure');
    final id = events.length + 1;
    events.add(e.copyWith(id: id));
    return id;
  }

  @override
  Future<void> updatePlayEvent(
    int id, {
    required int listenedMs,
    required bool counted,
    required bool completed,
  }) async {
    if (shouldThrow) throw Exception('Simulated DB failure');
    final index = events.indexWhere((e) => e.id == id);
    if (index != -1) {
      events[index] = events[index].copyWith(
        listenedMs: listenedMs,
        counted: counted,
        completed: completed,
      );
    }
  }

  @override
  Future<int> playEventCount({bool countedOnly = false}) async {
    if (countedOnly) {
      return events.where((e) => e.counted).length;
    }
    return events.length;
  }

  @override
  Future<List<PlayEvent>> recentPlayEvents({int limit = 50}) async {
    return List.from(events.reversed.take(limit));
  }
}

void main() {
  group('PlayRecorder Unit Tests', () {
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late _FakeHistoryRepository repo;
    late DateTime currentTime;

    DateTime testClock() => currentTime;

    setUp(() async {
      currentTime = DateTime.utc(2026, 11, 5, 20, 0, 0);
      engine = FakeAudioEngine();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
      repo = _FakeHistoryRepository();
    });

    tearDown(() async {
      await controller.dispose();
      await engine.dispose();
    });

    AudioSource createTrack(String name, int durationSeconds) {
      return AudioSource(
        '/music/$name.mp3',
        extras: {
          'title': name,
          'artist': 'Artist $name',
          'album': 'Album $name',
          'albumArtist': 'Artist $name',
          'durationMs': (durationSeconds * 1000).toString(),
        },
      );
    }

    test('Counted at exactly the threshold, not counted below it', () async {
      // 100s track -> threshold is 50% = 50s (50,000 ms)
      final track = createTrack('track100', 100);
      engine.fakeDuration = const Duration(seconds: 100);

      final recorder = PlayRecorder(
        controller: controller,
        repository: repo,
        clock: testClock,
      );

      await controller.playQueue([track]);
      await Future<void>.delayed(Duration.zero);
      expect(recorder.isCurrentCounted, isFalse);
      expect(repo.events, isEmpty);

      // Advance clock by 49 seconds (below threshold)
      currentTime = currentTime.add(const Duration(seconds: 49));
      recorder.checkThreshold();
      expect(recorder.isCurrentCounted, isFalse);
      expect(repo.events, isEmpty);

      // Advance clock by 1 second (reaching exactly 50s)
      currentTime = currentTime.add(const Duration(seconds: 1));
      recorder.checkThreshold();
      expect(recorder.isCurrentCounted, isTrue);
      expect(repo.events, hasLength(1));
      expect(repo.events.first.counted, isTrue);
      expect(repo.events.first.completed, isFalse);
      expect(repo.events.first.listenedMs, equals(50000));

      await recorder.dispose();
    });

    test('30 second minimum rule: tracks under 30s are never counted', () async {
      // 28s track -> < 30s minimum -> never counted
      final track = createTrack('track28', 28);
      engine.fakeDuration = const Duration(seconds: 28);

      final recorder = PlayRecorder(
        controller: controller,
        repository: repo,
        clock: testClock,
      );

      await controller.playQueue([track]);
      await Future<void>.delayed(Duration.zero);

      // Played for the full 28 seconds
      currentTime = currentTime.add(const Duration(seconds: 28));
      recorder.checkThreshold();
      expect(recorder.isCurrentCounted, isFalse);
      expect(repo.events, isEmpty);

      // Natural track completion
      engine.simulateCompletion();
      await Future<void>.delayed(Duration.zero);

      // Ends session: since 28s >= 5s, creates a row with counted: false, completed: true
      expect(repo.events, hasLength(1));
      expect(repo.events.first.counted, isFalse);
      expect(repo.events.first.completed, isTrue);
      expect(repo.events.first.listenedMs, equals(28000));

      await recorder.dispose();
    });

    test('240 second cap for long tracks', () async {
      // 600s track (10 mins) -> 50% is 300s, but cap is 240s
      final track = createTrack('longTrack', 600);
      engine.fakeDuration = const Duration(seconds: 600);

      final recorder = PlayRecorder(
        controller: controller,
        repository: repo,
        clock: testClock,
      );

      await controller.playQueue([track]);
      await Future<void>.delayed(Duration.zero);

      // At 239s -> not counted
      currentTime = currentTime.add(const Duration(seconds: 239));
      recorder.checkThreshold();
      expect(recorder.isCurrentCounted, isFalse);

      // At 240s -> counted!
      currentTime = currentTime.add(const Duration(seconds: 1));
      recorder.checkThreshold();
      expect(recorder.isCurrentCounted, isTrue);
      expect(repo.events, hasLength(1));
      expect(repo.events.first.counted, isTrue);

      await recorder.dispose();
    });

    test('Pause does not add time and seeking does not add time', () async {
      // 100s track (threshold 50s)
      final track = createTrack('pauseTrack', 100);
      engine.fakeDuration = const Duration(seconds: 100);

      final recorder = PlayRecorder(
        controller: controller,
        repository: repo,
        clock: testClock,
      );

      await controller.playQueue([track]);
      await Future<void>.delayed(Duration.zero);

      // Play for 20 seconds
      currentTime = currentTime.add(const Duration(seconds: 20));
      await controller.pause();
      await Future<void>.delayed(Duration.zero);
      expect(recorder.currentListenedMs, equals(20000));

      // Advance clock by 300 seconds while paused
      currentTime = currentTime.add(const Duration(seconds: 300));
      recorder.checkThreshold();
      expect(recorder.currentListenedMs, equals(20000));
      expect(recorder.isCurrentCounted, isFalse);

      // Seek forward while paused does NOT add time
      await engine.seek(const Duration(seconds: 80));
      await Future<void>.delayed(Duration.zero);
      expect(recorder.currentListenedMs, equals(20000));

      // Resume playback and play for 10 more seconds
      await controller.play();
      await Future<void>.delayed(Duration.zero);
      currentTime = currentTime.add(const Duration(seconds: 10));
      expect(recorder.currentListenedMs, equals(30000));
      expect(recorder.isCurrentCounted, isFalse);

      await recorder.dispose();
    });

    test('Skipping early creates a counted=0 row only when listened >= 5 s', () async {
      final track1 = createTrack('t1', 100);
      final track2 = createTrack('t2', 100);
      final track3 = createTrack('t3', 100);

      final recorder = PlayRecorder(
        controller: controller,
        repository: repo,
        clock: testClock,
      );

      await controller.playQueue([track1, track2, track3]);
      await Future<void>.delayed(Duration.zero);

      // Track 1: listened for only 4 seconds (< 5s threshold) -> skipped
      currentTime = currentTime.add(const Duration(seconds: 4));
      await controller.skipNext();
      await Future<void>.delayed(Duration.zero);
      expect(repo.events, isEmpty); // Discarded!

      // Track 2: listened for 7 seconds (>= 5s, but < 50s threshold) -> skipped
      currentTime = currentTime.add(const Duration(seconds: 7));
      await controller.skipNext();
      await Future<void>.delayed(Duration.zero);
      expect(repo.events, hasLength(1));
      expect(repo.events.first.uri, equals(track2.uri));
      expect(repo.events.first.counted, isFalse);
      expect(repo.events.first.completed, isFalse);
      expect(repo.events.first.listenedMs, equals(7000));

      await recorder.dispose();
    });

    test('Completion sets completed = true', () async {
      final track = createTrack('completeTrack', 60);
      engine.fakeDuration = const Duration(seconds: 60);

      final recorder = PlayRecorder(
        controller: controller,
        repository: repo,
        clock: testClock,
      );

      await controller.playQueue([track]);
      await Future<void>.delayed(Duration.zero);

      // Play 60 seconds to complete
      currentTime = currentTime.add(const Duration(seconds: 60));
      engine.simulateCompletion();
      await Future<void>.delayed(Duration.zero);

      expect(repo.events, hasLength(1));
      expect(repo.events.first.counted, isTrue);
      expect(repo.events.first.completed, isTrue);
      expect(repo.events.first.listenedMs, equals(60000));

      await recorder.dispose();
    });

    test('Repeat-one produces separate sessions each time', () async {
      final track = createTrack('loopTrack', 40);
      engine.fakeDuration = const Duration(seconds: 40);

      final recorder = PlayRecorder(
        controller: controller,
        repository: repo,
        clock: testClock,
      );

      queue.repeatMode = RepeatMode.one;
      await controller.playQueue([track]);
      await Future<void>.delayed(Duration.zero);

      // 1st play: complete 40s
      currentTime = currentTime.add(const Duration(seconds: 40));
      engine.simulateCompletion();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(repo.events, hasLength(1));
      expect(repo.events.first.completed, isTrue);

      // Repeat-one automatically re-opens the track and starts playing
      // 2nd play: listen for 25s
      currentTime = currentTime.add(const Duration(seconds: 25));
      recorder.checkThreshold();

      expect(repo.events, hasLength(2));
      expect(repo.events[1].counted, isTrue);
      expect(repo.events[1].completed, isFalse);

      await recorder.dispose();
    });

    test('Repository failure does not break playback', () async {
      final track = createTrack('errorTrack', 60);
      engine.fakeDuration = const Duration(seconds: 60);
      repo.shouldThrow = true; // DB throws exceptions

      final recorder = PlayRecorder(
        controller: controller,
        repository: repo,
        clock: testClock,
      );

      // Playback operations should not throw or fail
      await controller.playQueue([track]);
      await Future<void>.delayed(Duration.zero);
      currentTime = currentTime.add(const Duration(seconds: 35));
      recorder.checkThreshold();

      expect(controller.currentState, equals(PlaybackState.playing));
      await controller.skipNext();
      await Future<void>.delayed(Duration.zero);

      await recorder.dispose();
    });

    test('Dispose finalizes open session', () async {
      final track = createTrack('disposeTrack', 80);
      engine.fakeDuration = const Duration(seconds: 80);

      final recorder = PlayRecorder(
        controller: controller,
        repository: repo,
        clock: testClock,
      );

      await controller.playQueue([track]);
      await Future<void>.delayed(Duration.zero);
      currentTime = currentTime.add(const Duration(seconds: 15));

      await recorder.dispose();

      expect(repo.events, hasLength(1));
      expect(repo.events.first.listenedMs, equals(15000));
      expect(repo.events.first.counted, isFalse);
      expect(repo.events.first.completed, isFalse);
    });
  });
}
