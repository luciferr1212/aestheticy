import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/history/play_recorder.dart';
import 'package:aestheticy/features/integration/app_shutdown.dart';
import 'package:aestheticy/features/integration/tray_window_controller.dart';
import 'package:aestheticy/features/session/session_restorer.dart';
import 'package:aestheticy/features/session/session_saver.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/platform/tray_service.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

/// Recording subclass of [FakeAudioEngine] that captures the exact ordered
/// sequence of engine calls without altering behavior.
class _RecordingFakeAudioEngine extends FakeAudioEngine {
  final List<String> calls = [];

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        exclusiveMode: false,
        gapless: true,
        equalizer: true,
        replayGain: true,
      );

  @override
  Future<void> init() async {
    calls.add('init');
    await super.init();
  }

  @override
  Future<void> open(
    AudioSource source, {
    bool autoPlay = true,
    bool continuingGapless = false,
  }) async {
    calls.add(
      'open(${source.uri}, autoPlay=$autoPlay, gapless=$continuingGapless)',
    );
    await super.open(
      source,
      autoPlay: autoPlay,
      continuingGapless: continuingGapless,
    );
  }

  @override
  Future<void> preloadNext(AudioSource? source) async {
    calls.add('preloadNext(${source?.uri})');
    await super.preloadNext(source);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    await super.play();
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    await super.pause();
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek(${position.inMilliseconds})');
    await super.seek(position);
  }

  @override
  Future<void> setFadeGain(double gain) async {
    if (gain == 0.0 || gain == 1.0) {
      calls.add('setFadeGain(${gain.toStringAsFixed(1)})');
    } else if (calls.isEmpty || calls.last != 'setFadeGain(mid)') {
      calls.add('setFadeGain(mid)');
    }
    await super.setFadeGain(gain);
  }
}

class _RecordingMediaSessionService extends FakeMediaSessionService {
  final List<String> log;
  _RecordingMediaSessionService(this.log);

  @override
  Future<void> disable() async {
    log.add('mediaSession.disable');
    await super.disable();
  }

  @override
  Future<void> dispose() async {
    log.add('mediaSession.dispose');
    await super.dispose();
  }
}

class _RecordingSleepInhibitor extends FakeSleepInhibitor {
  final List<String> log;
  _RecordingSleepInhibitor(this.log);

  @override
  void release() {
    log.add('sleep.release');
    super.release();
  }
}

class _RecordingTrayService extends FakeTrayService {
  final List<String> log;
  _RecordingTrayService(this.log);

  @override
  Future<bool> show({
    required TrayMenuLabels labels,
    String tooltip = 'Aestheticy',
  }) async {
    log.add('tray.show');
    return super.show(labels: labels, tooltip: tooltip);
  }

  @override
  Future<void> hide() async {
    log.add('tray.hide');
    await super.hide();
  }
}

class _RecordingWindowService extends FakeWindowService {
  final List<String> log;
  _RecordingWindowService(this.log);

  @override
  Future<void> setPreventClose(bool prevent) async {
    log.add('window.setPreventClose($prevent)');
    await super.setPreventClose(prevent);
  }

  @override
  Future<void> hide() async {
    log.add('window.hide');
    await super.hide();
  }

  @override
  Future<void> destroy() async {
    log.add('window.destroy');
    await super.destroy();
  }
}

AudioSource _track(String id) => AudioSource(
      'file:///music/$id.mp3',
      extras: {'title': 'Track $id', 'artist': 'Artist $id', 'durationMs': '180000'},
    );

void main() {
  group('F4 Pre-Refactor Characterization Tests', () {
    late _RecordingFakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late List<PlaybackState> stateEvents;
    late List<String?> currentEvents;
    late int queueChangeCount;
    late List<Duration> seekEvents;
    late List<StreamSubscription<dynamic>> subs;

    setUp(() async {
      engine = _RecordingFakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      controller = PlaybackController(
        engine: engine,
        queue: queue,
        fadeProfile: FadeProfile.off,
        fadeTickInterval: const Duration(milliseconds: 5),
      );
      await controller.init();
      stateEvents = [];
      currentEvents = [];
      queueChangeCount = 0;
      seekEvents = [];
      subs = [
        controller.stateStream.listen(stateEvents.add),
        controller.currentStream.listen((s) => currentEvents.add(s?.uri)),
        controller.queueChangeStream.listen((_) => queueChangeCount++),
        controller.seekStream.listen(seekEvents.add),
      ];
      engine.calls.clear();
    });

    tearDown(() async {
      for (final s in subs) {
        await s.cancel();
      }
      await controller.dispose();
      await engine.dispose();
    });

    test('1. play from queue records exact open, preload, state and current sequence', () async {
      await controller.playQueue([_track('a'), _track('b'), _track('c')], startIndex: 0, source: 'album');
      await Future<void>.delayed(Duration.zero);

      expect(engine.calls, equals([
        'open(file:///music/a.mp3, autoPlay=true, gapless=false)',
        'preloadNext(file:///music/b.mp3)',
      ]));
      expect(stateEvents, equals([PlaybackState.playing]));
      expect(currentEvents, equals(['file:///music/a.mp3']));
      expect(queueChangeCount, equals(1));
      expect(controller.currentPlaySource, equals('album'));
    });

    test('2. next and previous (both <= 3s and > 3s) record exact engine calls and transitions', () async {
      await controller.playQueue([_track('a'), _track('b'), _track('c')]);
      await Future<void>.delayed(Duration.zero);
      engine.calls.clear();
      currentEvents.clear();

      await controller.skipNext();
      await Future<void>.delayed(Duration.zero);
      expect(engine.calls, equals([
        'open(file:///music/b.mp3, autoPlay=true, gapless=false)',
        'preloadNext(file:///music/c.mp3)',
      ]));
      expect(currentEvents, equals(['file:///music/b.mp3']));

      // Past 3 seconds: skipPrevious restarts current track via seek(0)
      engine.calls.clear();
      engine.simulateTick(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      await controller.skipPrevious();
      expect(engine.calls, equals(['seek(0)']));
      expect(queue.current?.uri, equals('file:///music/b.mp3'));

      // At 0 seconds: skipPrevious moves back to track a
      engine.calls.clear();
      currentEvents.clear();
      await controller.skipPrevious();
      await Future<void>.delayed(Duration.zero);
      expect(engine.calls, equals([
        'open(file:///music/a.mp3, autoPlay=true, gapless=false)',
        'preloadNext(file:///music/b.mp3)',
      ]));
      expect(currentEvents, equals(['file:///music/a.mp3']));
    });

    test('3. natural track end with gapless advance emits exact completed -> playing and gapless open', () async {
      await controller.playQueue([_track('a'), _track('b'), _track('c')]);
      await Future<void>.delayed(Duration.zero);
      engine.calls.clear();
      stateEvents.clear();
      currentEvents.clear();

      engine.simulateGaplessAdvance();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(stateEvents, equals([PlaybackState.completed, PlaybackState.playing]));
      expect(engine.calls, equals([
        'open(file:///music/b.mp3, autoPlay=true, gapless=true)',
        'preloadNext(file:///music/c.mp3)',
      ]));
      expect(currentEvents, equals(['file:///music/b.mp3']));
    });

    test('4. stop with fade ramps fadeGain down, calls stop, emits null current, restores gain', () async {
      controller.fadeProfile = FadeProfile.soft;
      await controller.playQueue([_track('a')]);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      engine.calls.clear();
      stateEvents.clear();
      currentEvents.clear();

      await controller.stop();
      await Future<void>.delayed(Duration.zero);

      expect(engine.calls.first, anyOf('setFadeGain(mid)', 'setFadeGain(0.0)'));
      expect(engine.calls, containsAllInOrder([
        'setFadeGain(0.0)',
        'stop',
        'setFadeGain(1.0)',
      ]));
      expect(stateEvents, equals([PlaybackState.idle]));
      expect(currentEvents, equals([null]));
    });

    test('5. pause and resume with fade preserve exact gain envelope and state sequence', () async {
      controller.fadeProfile = FadeProfile.soft;
      await controller.playQueue([_track('a')]);
      // Wait for start fade-in to finish so fadeGain is 1.0
      await Future<void>.delayed(const Duration(milliseconds: 300));
      engine.calls.clear();
      stateEvents.clear();

      await controller.pause();
      await Future<void>.delayed(Duration.zero);

      expect(engine.calls, containsAllInOrder([
        'setFadeGain(0.0)',
        'pause',
        'setFadeGain(1.0)',
      ]));
      expect(stateEvents, equals([PlaybackState.paused]));

      engine.calls.clear();
      stateEvents.clear();
      await controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(engine.calls.first, equals('setFadeGain(0.0)'));
      expect(engine.calls, containsAllInOrder([
        'setFadeGain(0.0)',
        'play',
        'setFadeGain(1.0)',
      ]));
      expect(stateEvents, equals([PlaybackState.playing]));
    });

    test('6. seek while idle arms resume and while playing delegates to engine and emits seekStream', () async {
      queue.replaceAll([_track('a')]);
      await controller.seek(const Duration(seconds: 42));
      await Future<void>.delayed(Duration.zero);
      expect(controller.armedResumePosition, equals(const Duration(seconds: 42)));
      expect(controller.currentPosition, equals(const Duration(seconds: 42)));
      expect(seekEvents, equals([const Duration(seconds: 42)]));

      engine.calls.clear();
      await controller.play();
      await Future<void>.delayed(Duration.zero);
      expect(engine.calls, containsAllInOrder([
        'open(file:///music/a.mp3, autoPlay=true, gapless=false)',
        'seek(42000)',
      ]));
      expect(controller.armedResumePosition, isNull);
    });

    test('7. queue add, remove, and reorder keep exact order, preload updates, and queueChangeStream count', () async {
      await controller.playQueue([_track('a'), _track('b')]);
      await Future<void>.delayed(Duration.zero);
      engine.calls.clear();
      queueChangeCount = 0;

      await controller.playNext([_track('x')]);
      await controller.addToQueue([_track('y')]);
      await Future<void>.delayed(Duration.zero);
      expect(
        queue.items.map((e) => e.uri).toList(),
        equals([
          'file:///music/a.mp3',
          'file:///music/x.mp3',
          'file:///music/y.mp3',
          'file:///music/b.mp3',
        ]),
      );
      expect(queueChangeCount, equals(2));
      expect(engine.preloadedNext?.uri, equals('file:///music/x.mp3'));

      // Reorder: move b (index 3) to index 1
      await controller.moveInQueue(3, 1);
      expect(
        queue.items.map((e) => e.uri).toList(),
        equals([
          'file:///music/a.mp3',
          'file:///music/b.mp3',
          'file:///music/x.mp3',
          'file:///music/y.mp3',
        ]),
      );
      expect(engine.preloadedNext?.uri, equals('file:///music/b.mp3'));

      // Remove non-current item x
      await controller.removeFromQueue(2);
      expect(
        queue.items.map((e) => e.uri).toList(),
        equals([
          'file:///music/a.mp3',
          'file:///music/b.mp3',
          'file:///music/y.mp3',
        ]),
      );

      // Remove current item a -> advances to b
      engine.calls.clear();
      await controller.removeFromQueue(0);
      await Future<void>.delayed(Duration.zero);
      expect(queue.current?.uri, equals('file:///music/b.mp3'));
      expect(engine.calls, contains('open(file:///music/b.mp3, autoPlay=true, gapless=false)'));
    });

    test('8. shuffle and repeat changes notify queueChangeStream and refresh gapless preload', () async {
      await controller.playQueue([_track('a'), _track('b'), _track('c')]);
      await Future<void>.delayed(Duration.zero);
      engine.calls.clear();
      queueChangeCount = 0;

      await controller.cycleRepeatMode();
      expect(queue.repeatMode, equals(RepeatMode.all));
      await controller.cycleRepeatMode();
      expect(queue.repeatMode, equals(RepeatMode.one));
      expect(engine.preloadedNext?.uri, equals('file:///music/a.mp3'));
      await controller.cycleRepeatMode();
      expect(queue.repeatMode, equals(RepeatMode.off));

      await controller.setShuffle(true);
      expect(queue.isShuffled, isTrue);
      await controller.setShuffle(false);
      expect(queue.isShuffled, isFalse);
      expect(queueChangeCount, equals(5));

      await controller.playShuffled(
        [_track('a'), _track('b'), _track('c')],
        random: math.Random(42),
        source: 'playlist',
      );
      expect(queue.isShuffled, isTrue);
      expect(controller.currentPlaySource, equals('playlist'));
    });

    test('9. session snapshot and restore preserve queue, shuffle, repeat, and armed position', () async {
      final tempDir = await Directory.systemTemp.createTemp('aestheticy_char_sess_');
      final settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(resumeSession: true),
      );
      final sessionStore = SessionStore(directory: tempDir);
      await settingsStore.init();
      await sessionStore.init();
      final saver = SessionSaver(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
      );

      try {
        await controller.playQueue([_track('a'), _track('b')]);
        await controller.cycleRepeatMode(); // RepeatMode.all
        engine.simulateTick(const Duration(seconds: 25));
        await Future<void>.delayed(Duration.zero);
        saver.saveSnapshot(debounce: false);
        await sessionStore.flush();

        // Restore into a fresh controller
        final engine2 = _RecordingFakeAudioEngine();
        await engine2.init();
        final queue2 = PlaybackQueue();
        final controller2 = PlaybackController(engine: engine2, queue: queue2);
        await controller2.init();
        final store2 = SessionStore(directory: tempDir);
        await store2.init();

        final result = await restoreSession(
          controller: controller2,
          sessionStore: store2,
          settingsStore: settingsStore,
          fileExistsChecker: (_) async => true,
        );

        expect(result.restoredCount, equals(2));
        expect(result.droppedCount, equals(0));
        expect(queue2.repeatMode, equals(RepeatMode.all));
        expect(queue2.current?.uri, equals('file:///music/a.mp3'));
        expect(controller2.armedResumePosition, equals(const Duration(seconds: 25)));

        store2.dispose();
        await controller2.dispose();
        await engine2.dispose();
      } finally {
        await saver.dispose();
        sessionStore.dispose();
        settingsStore.dispose();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });

    test('10. play-event recording captures completed and skipped tracks in exact order', () async {
      final repo = SqliteLibraryRepository.inMemory();
      var now = DateTime.utc(2026, 11, 27, 3, 0, 0);
      final recorder = PlayRecorder(
        controller: controller,
        repository: repo,
        clock: () => now,
      );

      try {
        // Track A: play for 100s then complete -> counted=true, completed=true, endedReason='completed'
        await controller.playQueue([_track('a'), _track('b')], source: 'album');
        await Future<void>.delayed(Duration.zero);
        now = now.add(const Duration(seconds: 100));
        engine.simulateCompletion();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Track B: play for 10s then skip/stop -> counted=false, completed=false, endedReason='stopped'
        now = now.add(const Duration(seconds: 10));
        await controller.stop();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final events = await repo.recentPlayEvents(limit: 10);
        expect(events, hasLength(2));
        // newest first
        expect(events[0].uri, equals('file:///music/b.mp3'));
        expect(events[0].counted, isFalse);
        expect(events[0].completed, isFalse);
        expect(events[0].endedReason, equals('stopped'));

        expect(events[1].uri, equals('file:///music/a.mp3'));
        expect(events[1].counted, isTrue);
        expect(events[1].completed, isTrue);
        expect(events[1].endedReason, equals('completed'));
        expect(events[1].source, equals('album'));
      } finally {
        await recorder.dispose();
        await repo.close();
      }
    });

    test('11. shutdown coordinator and tray window controller preserve exact init and shutdown order', () async {
      final tempDir = await Directory.systemTemp.createTemp('aestheticy_char_shut_');
      final log = <String>[];
      final settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(closeBehavior: 'exit'),
      );
      await settingsStore.init();
      final sessionStore = SessionStore(directory: tempDir);
      await sessionStore.init();
      final sessionSaver = SessionSaver(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
      );
      final mediaService = _RecordingMediaSessionService(log);
      final sleepService = _RecordingSleepInhibitor(log);
      final trayService = _RecordingTrayService(log);
      final windowService = _RecordingWindowService(log);

      final shutdownCoordinator = AppShutdownCoordinator(
        sessionSaver: sessionSaver,
        settingsStore: settingsStore,
        mediaSessionService: mediaService,
        sleepInhibitor: sleepService,
        trayService: trayService,
        windowService: windowService,
      );
      final trayWindowController = TrayWindowController(
        windowService: windowService,
        trayService: trayService,
        playbackController: controller,
        settingsStore: settingsStore,
        shutdownCoordinator: shutdownCoordinator,
        sessionSaver: sessionSaver,
      );

      try {
        await trayWindowController.init();
        expect(log, equals(['window.setPreventClose(true)']));

        log.clear();
        await trayWindowController.handleCloseRequested();
        // Verify exact ordered shutdown: hide -> mediaSession.disable -> sleep.release -> tray.hide -> window.destroy
        expect(log, equals([
          'window.hide',
          'mediaSession.disable',
          'sleep.release',
          'tray.hide',
          'window.destroy',
        ]));

        // Idempotent second shutdown does not re-run
        log.clear();
        await shutdownCoordinator.shutdown();
        expect(log, isEmpty);
      } finally {
        await trayWindowController.dispose();
        await sessionSaver.dispose();
        sessionStore.dispose();
        settingsStore.dispose();
        await mediaService.dispose();
        await trayService.dispose();
        await windowService.dispose();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });
  });
}
