import 'dart:convert';
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
  group('Session Resume Tests (S3)', () {
    late Directory tempDir;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late SettingsStore settingsStore;
    late SessionStore sessionStore;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('session_resume_test_');
      engine = FakeAudioEngine();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();

      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();

      sessionStore = SessionStore(directory: tempDir);
      await sessionStore.init();
    });

    tearDown(() async {
      await controller.dispose();
      await engine.dispose();
      sessionStore.dispose();
      settingsStore.dispose();
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

    AudioSource createTrack(String name) {
      return AudioSource(
        '/music/$name.mp3',
        extras: {
          'title': name,
          'artist': 'Artist $name',
          'album': 'Album $name',
          'durationMs': '180000',
        },
      );
    }

    test('Save then restore round trip, preserving queue, index, shuffle, and repeat', () async {
      final t1 = createTrack('track1');
      final t2 = createTrack('track2');
      final t3 = createTrack('track3');

      final saver = SessionSaver(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
      );

      // Setup controller state
      controller.queue.replaceAll([t1, t2, t3], startIndex: 1);
      controller.queue.repeatMode = RepeatMode.all;
      controller.queue.setShuffle(true);

      // Trigger save snapshot
      saver.saveSnapshot(debounce: false);
      await sessionStore.flush();

      // Verify file written to disk
      final sessionFile = File('${tempDir.path}/session.json');
      expect(sessionFile.existsSync(), isTrue);

      // Create a fresh controller & queue to simulate app restart
      final freshEngine = FakeAudioEngine();
      final freshQueue = PlaybackQueue();
      final freshController = PlaybackController(
        engine: freshEngine,
        queue: freshQueue,
      );
      await freshController.init();

      // Load sessionStore from disk
      final freshSessionStore = SessionStore(directory: tempDir);
      await freshSessionStore.init();

      final result = await restoreSession(
        controller: freshController,
        sessionStore: freshSessionStore,
        settingsStore: settingsStore,
        fileExistsChecker: (_) async => true,
      );

      expect(result.restoredCount, equals(3));
      expect(result.droppedCount, equals(0));
      expect(result.restoredIndex, equals(0));
      expect(freshQueue.items.length, equals(3));
      expect(freshQueue.currentIndex, equals(0));
      expect(freshQueue.current?.uri, equals(t2.uri));
      expect(freshQueue.repeatMode, equals(RepeatMode.all));
      expect(freshQueue.isShuffled, isTrue);

      // Asserts no audible output or play call occurred
      expect(freshEngine.openCallCount, equals(0));
      expect(freshEngine.state, equals(PlaybackState.idle));

      await saver.dispose();
      await freshController.dispose();
      await freshEngine.dispose();
    });

    test(
        'saveSnapshot(debounce: false) twice and flush immediately persists second snapshot',
        () async {
      final t1 = createTrack('track1');
      final t2 = createTrack('track2');

      final saver = SessionSaver(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
      );

      // Snapshot 1
      controller.queue.replaceAll([t1], startIndex: 0);
      saver.saveSnapshot(debounce: false);

      // Snapshot 2 immediately
      controller.queue.replaceAll([t1, t2], startIndex: 1);
      saver.saveSnapshot(debounce: false);

      await sessionStore.flush();

      final sessionFile = File('${tempDir.path}/session.json');
      expect(sessionFile.existsSync(), isTrue);

      final decoded =
          jsonDecode(await sessionFile.readAsString()) as Map<String, Object?>;
      final parsed = SavedSession.fromJson(decoded);
      expect(parsed.queue.length, equals(2));
      expect(parsed.queue[1].uri, equals(t2.uri));
      expect(parsed.currentIndex, equals(1));

      await saver.dispose();
    });

    test('Position applies lazily once after load only to the same track', () async {
      final t1 = createTrack('track1');
      final t2 = createTrack('track2');

      final session = SavedSession(
        queue: [
          SavedSessionItem(uri: t1.uri, extras: t1.extras),
          SavedSessionItem(uri: t2.uri, extras: t2.extras),
        ],
        currentIndex: 0,
        positionMs: 45000,
      );
      sessionStore.save(session, debounce: false);
      await sessionStore.flush();

      await restoreSession(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        fileExistsChecker: (_) async => true,
      );

      expect(controller.armedResumePosition, equals(const Duration(milliseconds: 45000)));

      // User presses play on current track (t1)
      await controller.play();
      await Future<void>.delayed(Duration.zero);

      // Seek was applied to the engine
      expect(engine.position, equals(const Duration(milliseconds: 45000)));
      // Armed resume was cleared and won't apply again
      expect(controller.armedResumePosition, isNull);
    });

    test('Different track chosen first discards armed resume position', () async {
      final t1 = createTrack('track1');
      final t2 = createTrack('track2');

      final session = SavedSession(
        queue: [
          SavedSessionItem(uri: t1.uri, extras: t1.extras),
          SavedSessionItem(uri: t2.uri, extras: t2.extras),
        ],
        currentIndex: 0,
        positionMs: 45000,
      );
      sessionStore.save(session, debounce: false);
      await sessionStore.flush();

      await restoreSession(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        fileExistsChecker: (_) async => true,
      );

      expect(controller.armedResumePosition, equals(const Duration(milliseconds: 45000)));

      // User chooses track 2 instead of track 1
      await controller.playTrack(1);
      await Future<void>.delayed(Duration.zero);

      // Armed resume was discarded
      expect(controller.armedResumePosition, isNull);
      // Engine starts at 0, not 45000
      expect(engine.position, equals(Duration.zero));
    });

    test('Missing files are dropped with index adjusted; position is 0 if current was dropped', () async {
      final t1 = createTrack('t1_gone');
      final t2 = createTrack('t2_exists');
      final t3 = createTrack('t3_gone');
      final t4 = createTrack('t4_exists');

      // Originally, current track was index 0 (t1_gone)
      final session = SavedSession(
        queue: [
          SavedSessionItem(uri: t1.uri),
          SavedSessionItem(uri: t2.uri),
          SavedSessionItem(uri: t3.uri),
          SavedSessionItem(uri: t4.uri),
        ],
        currentIndex: 0,
        positionMs: 30000,
      );
      sessionStore.save(session, debounce: false);
      await sessionStore.flush();

      final result = await restoreSession(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        fileExistsChecker: (path) async => path.contains('exists'),
      );

      // t1 and t3 were dropped
      expect(result.droppedCount, equals(2));
      expect(result.restoredCount, equals(2));
      // Cursor moved to next surviving item (t2_exists, now index 0)
      expect(result.restoredIndex, equals(0));
      expect(controller.queue.current?.uri, equals(t2.uri));
      // Position was reset to 0 because original current track was dropped
      expect(result.armedPositionMs, equals(0));
      expect(controller.armedResumePosition, isNull);
    });

    test('All files missing results in empty queue and nothing restored', () async {
      final t1 = createTrack('t1_missing');
      final session = SavedSession(
        queue: [SavedSessionItem(uri: t1.uri)],
        currentIndex: 0,
        positionMs: 10000,
      );
      sessionStore.save(session, debounce: false);
      await sessionStore.flush();

      final result = await restoreSession(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        fileExistsChecker: (_) async => false, // all missing
      );

      expect(result.restoredCount, equals(0));
      expect(result.droppedCount, equals(1));
      expect(controller.queue.isEmpty, isTrue);
    });

    test('Corrupt session.json handled: creates .bad copy and resets to empty session', () async {
      final sessionFile = File('${tempDir.path}/session.json');
      await sessionFile.writeAsString('{not valid json at all!!!');

      final freshStore = SessionStore(directory: tempDir);
      await freshStore.init();

      expect(freshStore.session.isEmpty, isTrue);
      expect(File('${tempDir.path}/session.json.bad').existsSync(), isTrue);

      final result = await restoreSession(
        controller: controller,
        sessionStore: freshStore,
        settingsStore: settingsStore,
      );
      expect(result.restoredCount, equals(0));
    });

    test('Setting resumeSession = false disables both saving and restoring', () async {
      settingsStore.update((s) => s.copyWith(resumeSession: false));

      final t1 = createTrack('t1');
      final session = SavedSession(
        queue: [SavedSessionItem(uri: t1.uri)],
        currentIndex: 0,
        positionMs: 20000,
      );
      sessionStore.save(session, debounce: false);
      await sessionStore.flush();

      // Saver does not save when setting is false
      final saver = SessionSaver(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
      );
      controller.queue.replaceAll([t1]);
      saver.saveSnapshot(debounce: false);

      // Restore does not restore when setting is false
      final result = await restoreSession(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        fileExistsChecker: (_) async => true,
      );
      expect(result.restoredCount, equals(0));
      expect(controller.queue.items.length, equals(1)); // unchanged from manual replaceAll above

      await saver.dispose();
    });

    test('Large queue (5000 items) restores in batches without error', () async {
      final largeQueue = List.generate(
        5000,
        (i) => SavedSessionItem(uri: '/music/item_$i.mp3'),
      );
      final session = SavedSession(
        queue: largeQueue,
        currentIndex: 2500,
        positionMs: 12000,
      );
      sessionStore.save(session, debounce: false);
      await sessionStore.flush();

      final result = await restoreSession(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        fileExistsChecker: (_) async => true,
      );

      expect(result.restoredCount, equals(5000));
      expect(result.restoredIndex, equals(2500));
      expect(controller.queue.length, equals(5000));
      expect(controller.queue.currentIndex, equals(2500));
    });
  });
}
