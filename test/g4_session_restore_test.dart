import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/session/saved_session.dart';
import 'package:aestheticy/features/session/session_restorer.dart';
import 'package:aestheticy/features/session/session_saver.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  group('G4: Session persistence and position restore tests', () {
    late Directory tempDir;
    late SettingsStore settingsStore;
    late SessionStore sessionStore;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('g4_test_');
      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();

      sessionStore = SessionStore(directory: tempDir);
      await sessionStore.init();

      engine = FakeAudioEngine();
      await engine.init();

      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
    });

    tearDown(() async {
      await controller.dispose();
      await engine.dispose();
      sessionStore.dispose();
      settingsStore.dispose();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('3-second cadence saves position while playing', () async {
      var currentTime = DateTime.utc(2026, 11, 6, 12, 0, 0);
      final saver = SessionSaver(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        clock: () => currentTime,
      );

      final tracks = [
        const AudioSource('/music/song1.mp3'),
      ];
      await controller.playQueue(tracks);
      await sessionStore.flush();

      // Tick 2 seconds (not 3s yet)
      currentTime = currentTime.add(const Duration(seconds: 2));
      engine.simulateTick(const Duration(seconds: 2));
      await sessionStore.flush();
      expect(sessionStore.session.positionMs, isNot(equals(2000)));

      // Tick 1 more second (total 3 seconds reached)
      currentTime = currentTime.add(const Duration(seconds: 1));
      engine.simulateTick(const Duration(seconds: 1));
      await sessionStore.flush();
      expect(sessionStore.session.positionMs, equals(3000));

      await saver.dispose();
    });

    test('Cold start: early idle or zero-position events do not overwrite armed position; applied once on play', () async {
      // 1. Prepare a saved session with positionMs: 45000 (45s)
      final saved = SavedSession(
        queue: const [
          SavedSessionItem(uri: '/music/song1.mp3'),
          SavedSessionItem(uri: '/music/song2.mp3'),
        ],
        currentIndex: 1,
        currentUri: '/music/song2.mp3',
        positionMs: 45000,
        shuffle: false,
        repeatMode: 'off',
        savedAt: DateTime.utc(2026, 11, 6, 10, 0, 0),
      );
      sessionStore.saveSync(saved);

      // 2. Simulate restore at cold start
      final result = await restoreSession(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        fileExistsChecker: (_) async => true,
      );

      expect(result.restoredCount, equals(2));
      expect(result.armedPositionMs, equals(45000));
      expect(controller.currentPosition, equals(const Duration(milliseconds: 45000)));
      expect(engine.openCallCount, equals(0)); // No sound during restore!

      // 3. Mount SessionSaver at startup
      final saver = SessionSaver(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
      );

      // Early startup state/position events
      engine.simulateTick(Duration.zero);
      saver.saveSnapshot(debounce: false);

      // Position must SURVIVE and not be zero
      expect(sessionStore.session.positionMs, equals(45000));

      // 4. User presses play: position is applied lazily once
      engine.fakeDuration = const Duration(minutes: 3);
      await controller.play();

      expect(engine.position, equals(const Duration(milliseconds: 45000)));
      expect(controller.armedResumePosition, isNull);

      await saver.dispose();
    });

    test('Shuffle round trip preserves same active track by URI', () async {
      final tracks = [
        const AudioSource('/music/song1.mp3'),
        const AudioSource('/music/song2.mp3'),
        const AudioSource('/music/song3.mp3'),
      ];
      await controller.playQueue(tracks, startIndex: 2); // currently on song3
      controller.queue.setShuffle(true);
      expect(controller.queue.current?.uri, equals('/music/song3.mp3'));

      final saver = SessionSaver(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
      );
      saver.saveSnapshotSync();
      await saver.dispose();

      expect(sessionStore.session.currentUri, equals('/music/song3.mp3'));

      // New controller simulating cold start
      final freshQueue = PlaybackQueue();
      final freshEngine = FakeAudioEngine();
      final freshController = PlaybackController(engine: freshEngine, queue: freshQueue);
      await freshController.init();

      await restoreSession(
        controller: freshController,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        fileExistsChecker: (_) async => true,
      );

      expect(freshController.queue.isShuffled, isTrue);
      expect(freshController.queue.current?.uri, equals('/music/song3.mp3'));

      await freshController.dispose();
      await freshEngine.dispose();
    });

    test('Synchronous flush writes file immediately and atomically', () {
      final session = SavedSession(
        queue: const [SavedSessionItem(uri: '/music/song1.mp3')],
        currentIndex: 0,
        currentUri: '/music/song1.mp3',
        positionMs: 12000,
        savedAt: DateTime.utc(2026, 11, 6, 12, 0, 0),
      );

      sessionStore.saveSync(session);

      final file = File('${tempDir.path}/session.json');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync().contains('"positionMs": 12000'), isTrue);
      expect(File('${tempDir.path}/session.json.tmp').existsSync(), isFalse);
    });
  });
}
