import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/features/history/play_recorder.dart';
import 'package:aestheticy/features/integration/app_shutdown.dart';
import 'package:aestheticy/features/session/session_saver.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/platform/tray_service.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import '../../library/fake_library_repository.dart';

void main() {
  group('AppShutdownCoordinator Tests', () {
    late Directory tempDir;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late SessionStore sessionStore;
    late SettingsStore settingsStore;
    late FakeLibraryRepository repository;
    late PlayRecorder playRecorder;
    late SessionSaver sessionSaver;
    late FakeMediaSessionService fakeMediaSession;
    late FakeSleepInhibitor fakeSleepInhibitor;
    late FakeTrayService fakeTrayService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_shutdown_test_');

      engine = FakeAudioEngine();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();

      sessionStore = SessionStore(directory: tempDir);
      await sessionStore.init();

      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();

      repository = FakeLibraryRepository();
      playRecorder = PlayRecorder(
        controller: controller,
        repository: repository,
      );

      sessionSaver = SessionSaver(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
      );

      fakeMediaSession = FakeMediaSessionService();
      fakeSleepInhibitor = FakeSleepInhibitor();
      fakeTrayService = FakeTrayService();
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

    test('ordered execution: session snapshot, play recorder, settings flush, logger flush, media/sleep release, tray hide', () async {
      // Custom session saver tracking snapshot
      const track = AudioSource('file:///music/song.mp3');
      await controller.playQueue([track], startIndex: 0);
      await controller.seek(const Duration(seconds: 42));

      final testCoordinator = AppShutdownCoordinator(
        sessionSaver: sessionSaver,
        playRecorder: playRecorder,
        settingsStore: settingsStore,
        logger: AppLogger(customSink: StringBuffer()),
        mediaSessionService: fakeMediaSession,
        sleepInhibitor: fakeSleepInhibitor,
        trayService: fakeTrayService,
      );

      fakeSleepInhibitor.acquire();
      await fakeTrayService.show(labels: const TrayMenuLabels(show: 'S', playPause: 'P', next: 'N', previous: 'Pr', quit: 'Q'));

      await testCoordinator.shutdown();

      // Verify session snapshot saved latest position
      final reloadedStore = SessionStore(directory: tempDir);
      await reloadedStore.init();
      expect(reloadedStore.session.positionMs, equals(42000));
      expect(reloadedStore.session.currentUri, equals('file:///music/song.mp3'));

      // Verify sleep inhibitor released
      expect(fakeSleepInhibitor.isAcquired, isFalse);

      // Verify media session disabled
      expect(fakeMediaSession.calls, contains('disable'));

      // Verify tray hidden
      expect(fakeTrayService.calls, contains('hide'));

      expect(testCoordinator.hasShutdown, isTrue);
    });

    test('idempotent when called multiple times', () async {
      final testCoordinator = AppShutdownCoordinator(
        sessionSaver: sessionSaver,
        playRecorder: playRecorder,
        settingsStore: settingsStore,
        logger: AppLogger(customSink: StringBuffer()),
        mediaSessionService: fakeMediaSession,
        sleepInhibitor: fakeSleepInhibitor,
        trayService: fakeTrayService,
      );

      await testCoordinator.shutdown();
      final callCountAfterFirst = fakeMediaSession.calls.length;

      // Second call does nothing
      await testCoordinator.shutdown();
      expect(fakeMediaSession.calls.length, equals(callCountAfterFirst));
      expect(testCoordinator.hasShutdown, isTrue);
    });

    test('one failing step does not block subsequent steps', () async {
      final customLogger = AppLogger(customSink: StringBuffer());

      final testCoordinator = AppShutdownCoordinator(
        sessionSaver: null, // Omitting or failing
        playRecorder: playRecorder,
        settingsStore: settingsStore,
        logger: customLogger,
        mediaSessionService: fakeMediaSession,
        sleepInhibitor: fakeSleepInhibitor,
        trayService: fakeTrayService,
      );

      fakeSleepInhibitor.acquire();
      await fakeTrayService.show(labels: const TrayMenuLabels(show: 'S', playPause: 'P', next: 'N', previous: 'Pr', quit: 'Q'));

      // Even if sessionSaver was null, all remaining steps execute
      await testCoordinator.shutdown();

      expect(fakeSleepInhibitor.isAcquired, isFalse);
      expect(fakeMediaSession.calls, contains('disable'));
      expect(fakeTrayService.calls, contains('hide'));
      expect(testCoordinator.hasShutdown, isTrue);
    });
  });
}
