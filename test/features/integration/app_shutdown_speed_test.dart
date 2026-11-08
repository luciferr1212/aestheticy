import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/features/history/play_recorder.dart';
import 'package:aestheticy/features/integration/app_shutdown.dart';
import 'package:aestheticy/features/integration/tray_window_controller.dart';
import 'package:aestheticy/features/session/session_saver.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import '../../library/fake_library_repository.dart';

class _SlowPlayRecorder extends PlayRecorder {
  _SlowPlayRecorder({required super.controller, required super.repository});

  @override
  Future<void> dispose() async {
    await Future<void>.delayed(const Duration(seconds: 4));
  }
}

void main() {
  group('App Shutdown Speed & Timing Tests (I4)', () {
    late Directory tempDir;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late SessionStore sessionStore;
    late SettingsStore settingsStore;
    late FakeLibraryRepository repository;
    late SessionSaver sessionSaver;
    late FakeMediaSessionService fakeMediaSession;
    late FakeSleepInhibitor fakeSleepInhibitor;
    late FakeTrayService fakeTrayService;
    late FakeWindowService fakeWindowService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('shutdown_speed_test_');
      engine = FakeAudioEngine();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();

      sessionStore = SessionStore(directory: tempDir);
      await sessionStore.init();

      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();

      repository = FakeLibraryRepository();
      sessionSaver = SessionSaver(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
      );

      fakeMediaSession = FakeMediaSessionService();
      fakeSleepInhibitor = FakeSleepInhibitor();
      fakeTrayService = FakeTrayService();
      fakeWindowService = FakeWindowService();
    });

    tearDown(() async {
      await controller.dispose();
      sessionStore.dispose();
      settingsStore.dispose();
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('timing logs appear with ms durations for each step and total', () async {
      final sink = StringBuffer();
      final logger = AppLogger(customSink: sink);

      final coordinator = AppShutdownCoordinator(
        sessionSaver: sessionSaver,
        playRecorder: PlayRecorder(controller: controller, repository: repository),
        settingsStore: settingsStore,
        logger: logger,
        mediaSessionService: fakeMediaSession,
        sleepInhibitor: fakeSleepInhibitor,
        trayService: fakeTrayService,
      );

      await coordinator.shutdown();
      final logs = sink.toString();

      // Must contain duration logs in ms
      expect(logs, contains('ms'));
      expect(logs, contains('session snapshot'));
      expect(logs, contains('Total shutdown finished'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('slow dispose on one step does not delay others beyond 1.5s timeout', () async {
      final sink = StringBuffer();
      final logger = AppLogger(customSink: sink);
      final slowRecorder = _SlowPlayRecorder(controller: controller, repository: repository);

      final coordinator = AppShutdownCoordinator(
        sessionSaver: sessionSaver,
        playRecorder: slowRecorder,
        settingsStore: settingsStore,
        logger: logger,
        mediaSessionService: fakeMediaSession,
        sleepInhibitor: fakeSleepInhibitor,
        trayService: fakeTrayService,
      );

      fakeSleepInhibitor.acquire();
      final sw = Stopwatch()..start();
      await coordinator.shutdown();
      sw.stop();

      // Should finish well under 3 seconds even with a 4-second slow recorder
      expect(sw.elapsedMilliseconds, lessThan(2500));
      expect(fakeSleepInhibitor.isAcquired, isFalse, reason: 'sleep inhibitor must be released even if playRecorder timed out');
      expect(sink.toString(), contains('timed out after 1500ms'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('closing with closeBehavior=exit stops audio and destroys window', () async {
      settingsStore.update((s) => s.copyWith(closeBehavior: 'quit'));
      const track = AudioSource('file:///music/song.mp3');
      await controller.playQueue([track], startIndex: 0);
      expect(controller.currentState, PlaybackState.playing);

      final coordinator = AppShutdownCoordinator(
        sessionSaver: sessionSaver,
        playRecorder: PlayRecorder(controller: controller, repository: repository),
        settingsStore: settingsStore,
        mediaSessionService: fakeMediaSession,
        sleepInhibitor: fakeSleepInhibitor,
        trayService: fakeTrayService,
      );

      final trayController = TrayWindowController(
        windowService: fakeWindowService,
        trayService: fakeTrayService,
        playbackController: controller,
        settingsStore: settingsStore,
        shutdownCoordinator: coordinator,
        sessionSaver: sessionSaver,
      );
      await trayController.init();

      // Request close
      fakeWindowService.emitCloseRequested();
      await pumpEventQueue();
      await trayController.lastCloseFuture;

      expect(controller.currentState, isNot(PlaybackState.playing));
      expect(fakeWindowService.calls, contains('hide'));
      expect(fakeWindowService.calls, contains('destroy'));
      await trayController.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('closing with closeBehavior=tray keeps audio playing and hides window', () async {
      settingsStore.update((s) => s.copyWith(closeBehavior: 'tray'));
      const track = AudioSource('file:///music/song.mp3');
      await controller.playQueue([track], startIndex: 0);
      expect(controller.currentState, PlaybackState.playing);

      final coordinator = AppShutdownCoordinator(
        sessionSaver: sessionSaver,
        playRecorder: PlayRecorder(controller: controller, repository: repository),
        settingsStore: settingsStore,
        mediaSessionService: fakeMediaSession,
        sleepInhibitor: fakeSleepInhibitor,
        trayService: fakeTrayService,
      );

      final trayController = TrayWindowController(
        windowService: fakeWindowService,
        trayService: fakeTrayService,
        playbackController: controller,
        settingsStore: settingsStore,
        shutdownCoordinator: coordinator,
        sessionSaver: sessionSaver,
      );
      await trayController.init();

      // Request close
      fakeWindowService.emitCloseRequested();
      await pumpEventQueue();
      await trayController.lastCloseFuture;

      // Audio must keep playing
      expect(controller.currentState, equals(PlaybackState.playing));
      expect(fakeWindowService.calls, contains('hide'));
      expect(fakeWindowService.calls, isNot(contains('destroy')));
      expect(coordinator.hasShutdown, isFalse);
      await trayController.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
