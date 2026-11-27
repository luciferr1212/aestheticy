import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/app/app_bootstrap.dart';
import 'package:aestheticy/app/window_lifecycle.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/integration/app_shutdown.dart';
import 'package:aestheticy/features/integration/tray_window_controller.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/audio_panels/eq_store.dart';
import 'package:aestheticy/ui/mini_player/mini_player_controller.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('aestheticy_bootstrap_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AppBootstrap & WindowLifecycleCoordinator (S1)', () {
    test('initializes all services in exact documented order and runs shutdown once', () async {
      final steps = <String>[];
      final fakeWindow = FakeWindowService();
      final fakeTray = FakeTrayService();
      final fakeMedia = FakeMediaSessionService();
      final fakeSleep = FakeSleepInhibitor();

      final result = await AppBootstrap.initialize(
        onStep: steps.add,
        factories: AppBootstrapFactories(
          createEngine: FakeAudioEngine.new,
          ensureCoverCacheInitialized: () async {},
          openRepository: () async => SqliteLibraryRepository.inMemory(),
          createSettingsStore: () => SettingsStore(directory: tempDir),
          createEqStore: () => EqStore(directory: tempDir),
          createArtistNameStore: () => ArtistNameStore(directory: tempDir),
          createSessionStore: () => SessionStore(directory: tempDir),
          createMediaSessionService: () => fakeMedia,
          createSleepInhibitor: () => fakeSleep,
          createTrayService: () => fakeTray,
          createWindowService: () => fakeWindow,
          openFolder: (_) async {},
        ),
      );

      expect(result, isA<AppBootstrapSuccess>());
      expect(steps, equals([
        'audio.init',
        'library.init',
        'settings.init',
        'audioSettings.apply',
        'eq.init',
        'artistNames.init',
        'session.init',
        'playEvents.init',
        'collections.init',
        'platform.init',
        'trayWindow.init',
      ]));

      final services = (result as AppBootstrapSuccess).services;
      expect(fakeWindow.isPreventClose, isTrue);

      await services.shutdownCoordinator.shutdown();
      final mediaCallsAfterFirst = List<String>.from(fakeMedia.calls);
      expect(mediaCallsAfterFirst, contains('disable'));

      // Idempotent second shutdown does not re-execute
      await services.shutdownCoordinator.shutdown();
      expect(fakeMedia.calls, equals(mediaCallsAfterFirst));

      await services.trayWindowController.dispose();
      await services.sleepController.dispose();
      await services.mediaSessionController.dispose();
      await services.playRecorder.dispose();
      await services.sessionSaver.dispose();
      services.sessionStore.dispose();
      services.artistNameStore.dispose();
      services.eqStore.dispose();
      services.settingsStore.dispose();
      await services.controller.dispose();
      await services.engine.dispose();
      await services.repository.close();
      await fakeMedia.dispose();
      await fakeTray.dispose();
      await fakeWindow.dispose();
    });

    test('returns AppBootstrapAudioFailure when engine init throws', () async {
      final result = await AppBootstrap.initialize(
        factories: AppBootstrapFactories(
          createEngine: () => _ThrowingInitAudioEngine(),
        ),
      );

      expect(result, isA<AppBootstrapAudioFailure>());
    });

    test('returns AppBootstrapLibraryFailure when repository open throws', () async {
      final result = await AppBootstrap.initialize(
        factories: AppBootstrapFactories(
          createEngine: FakeAudioEngine.new,
          ensureCoverCacheInitialized: () async {},
          openRepository: () async => throw StateError('db open failed'),
        ),
      );

      expect(result, isA<AppBootstrapLibraryFailure>());
    });

    test('WindowLifecycleCoordinator delegates exit to TrayWindowController (cancel on hide, exit on quit)', () async {
      final engine = FakeAudioEngine();
      await engine.init();
      final controller = PlaybackController(engine: engine, queue: PlaybackQueue());
      await controller.init();
      final settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(closeBehavior: 'tray'),
      );
      await settingsStore.init();
      final windowService = FakeWindowService();
      final trayService = FakeTrayService();
      final mediaService = FakeMediaSessionService();
      final sleepService = FakeSleepInhibitor();
      final shutdownCoordinator = AppShutdownCoordinator(
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
      );
      await trayWindowController.init();
      final miniController = MiniPlayerController(
        windowService: windowService,
        settingsStore: settingsStore,
      );
      final lifecycle = WindowLifecycleCoordinator(
        miniPlayerController: miniController,
        playbackController: controller,
        settingsStore: settingsStore,
        shutdownCoordinator: shutdownCoordinator,
        trayWindowController: trayWindowController,
        trayService: trayService,
        isMounted: () => true,
      );

      try {
        // Tray mode -> cancel exit and hide
        final trayResponse = await lifecycle.handleExitRequested();
        expect(trayResponse, equals(AppExitResponse.cancel));
        expect(windowService.isVisible, isFalse);

        // Switch to exit mode -> exit and destroy
        settingsStore.update((s) => s.copyWith(closeBehavior: 'exit'));
        final quitResponse = await lifecycle.handleExitRequested();
        expect(quitResponse, equals(AppExitResponse.exit));
        expect(windowService.isDestroyed, isTrue);
      } finally {
        lifecycle.dispose();
        miniController.dispose();
        await trayWindowController.dispose();
        settingsStore.dispose();
        await controller.dispose();
        await engine.dispose();
        await mediaService.dispose();
        await trayService.dispose();
        await windowService.dispose();
      }
    });
  });
}

class _ThrowingInitAudioEngine extends FakeAudioEngine {
  @override
  Future<void> init() async {
    throw StateError('Simulated audio init error');
  }
}
