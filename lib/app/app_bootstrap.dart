import 'dart:async';
import 'dart:io';

import 'package:aestheticy/app/app_services.dart';
import 'package:aestheticy/audio/audio_engine.dart';
import 'package:aestheticy/audio/mpv_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/features/history/play_recorder.dart';
import 'package:aestheticy/features/integration/app_shutdown.dart';
import 'package:aestheticy/features/integration/media_session_controller.dart';
import 'package:aestheticy/features/integration/sleep_controller.dart';
import 'package:aestheticy/features/integration/tray_window_controller.dart';
import 'package:aestheticy/features/session/session_restorer.dart';
import 'package:aestheticy/features/session/session_saver.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/library/cover_cache.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/migrations.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite/userdata_backup_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';
import 'package:aestheticy/platform/media_session_service.dart';
import 'package:aestheticy/platform/platform_services.dart';
import 'package:aestheticy/platform/sleep_inhibitor.dart';
import 'package:aestheticy/platform/tray_service.dart';
import 'package:aestheticy/platform/window_service.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/audio_panels/eq_controller.dart';
import 'package:aestheticy/ui/audio_panels/eq_store.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/l10n/locale_controller.dart';
import 'package:aestheticy/ui/settings/audio_settings_applier.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

/// Result of [AppBootstrap.initialize].
sealed class AppBootstrapResult {
  const AppBootstrapResult();
}

/// Successful bootstrap carrying the initialized [services].
final class AppBootstrapSuccess extends AppBootstrapResult {
  final AppServices services;
  const AppBootstrapSuccess(this.services);
}

/// Audio engine failed to initialize during bootstrap.
final class AppBootstrapAudioFailure extends AppBootstrapResult {
  final Object error;
  final StackTrace stackTrace;
  const AppBootstrapAudioFailure(this.error, this.stackTrace);
}

/// Library database failed to initialize during bootstrap.
final class AppBootstrapLibraryFailure extends AppBootstrapResult {
  final Object error;
  final StackTrace stackTrace;
  const AppBootstrapLibraryFailure(this.error, this.stackTrace);
}

/// Optional dependency factories for testing [AppBootstrap.initialize] without
/// touching native audio, disk support directories, or OS window/tray APIs.
class AppBootstrapFactories {
  final AudioEngine Function()? createEngine;
  final Future<void> Function()? ensureCoverCacheInitialized;
  final Future<LibraryRepository> Function()? openRepository;
  final SettingsStore Function()? createSettingsStore;
  final EqStore Function()? createEqStore;
  final ArtistNameStore Function()? createArtistNameStore;
  final SessionStore Function()? createSessionStore;
  final MediaSessionService Function()? createMediaSessionService;
  final SleepInhibitor Function()? createSleepInhibitor;
  final TrayService Function()? createTrayService;
  final WindowService Function()? createWindowService;
  final Future<void> Function(String path)? openFolder;

  const AppBootstrapFactories({
    this.createEngine,
    this.ensureCoverCacheInitialized,
    this.openRepository,
    this.createSettingsStore,
    this.createEqStore,
    this.createArtistNameStore,
    this.createSessionStore,
    this.createMediaSessionService,
    this.createSleepInhibitor,
    this.createTrayService,
    this.createWindowService,
    this.openFolder,
  });
}

/// Ordered application startup wiring extracted from `main.dart`.
class AppBootstrap {
  AppBootstrap._();

  /// Initializes all long-lived application services in strict startup order.
  static Future<AppBootstrapResult> initialize({
    AppBootstrapFactories factories = const AppBootstrapFactories(),
    void Function(String step)? onStep,
  }) async {
    final AudioEngine engine;
    final PlaybackController controller;
    try {
      onStep?.call('audio.init');
      engine = factories.createEngine?.call() ?? MpvAudioEngine();
      await engine.init();
      final queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
      AppLogger.instance.info('Audio', 'Audio engine initialized');
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        'Audio',
        'Audio engine init failed: $error',
        error,
        stackTrace,
      );
      return AppBootstrapAudioFailure(error, stackTrace);
    }

    controller.errorStream.listen((err) {
      AppLogger.instance.warning('Playback', 'Playback error: $err');
    });

    final LibraryRepository repository;
    final ScanService scanService;
    try {
      onStep?.call('library.init');
      if (factories.ensureCoverCacheInitialized != null) {
        await factories.ensureCoverCacheInitialized!();
      } else {
        await CoverCache.ensureInitialized();
      }
      repository = factories.openRepository != null
          ? await factories.openRepository!()
          : await SqliteLibraryRepository.openDefault();
      scanService = ScanService(repository: repository);
      AppLogger.instance.info(
        'Library',
        'Library opened successfully at schema v$kLibrarySchemaVersion',
      );
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        'Library',
        'Library init failed: $error',
        error,
        stackTrace,
      );
      return AppBootstrapLibraryFailure(error, stackTrace);
    }

    scanService.progressStream.listen((p) {
      if (p.done) {
        AppLogger.instance.info(
          'Scan',
          'Scan finished: found ${p.found}, added ${p.added}, updated ${p.updated}',
        );
      } else if (p.errors > 0 || p.unreadableDirs > 0) {
        AppLogger.instance.warning(
          'Scan',
          'Scan errors: errors ${p.errors}, unreadable ${p.unreadableDirs}',
        );
      }
    });

    onStep?.call('settings.init');
    final settingsStore =
        factories.createSettingsStore?.call() ?? SettingsStore();
    await settingsStore.init();
    final glassController = GlassController();
    settingsStore.bindGlassController(glassController);
    final localeController = LocaleController(settingsStore: settingsStore);

    onStep?.call('audioSettings.apply');
    final audioSettingsApplier = AudioSettingsApplier(
      engine: engine,
      settingsStore: settingsStore,
    );
    try {
      await audioSettingsApplier.applyAll();
    } catch (error, stackTrace) {
      AppLogger.instance.warning(
        'Audio',
        'AudioSettingsApplier failed: $error',
        error,
        stackTrace,
      );
    }

    onStep?.call('eq.init');
    final eqStore = factories.createEqStore?.call() ?? EqStore();
    await eqStore.init();
    final eqController = EqController(engine: engine, store: eqStore);
    await eqController.applyAll();

    onStep?.call('artistNames.init');
    final artistNameStore =
        factories.createArtistNameStore?.call() ?? ArtistNameStore();
    await artistNameStore.init();

    onStep?.call('session.init');
    final sessionStore = factories.createSessionStore?.call() ?? SessionStore();
    await sessionStore.init();

    if (settingsStore.settings.resumeSession) {
      final restoreResult = await restoreSession(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
      );
      AppLogger.instance.info(
        'Session',
        'Session restore: restored ${restoreResult.restoredCount}, dropped ${restoreResult.droppedCount}',
      );
    }

    final sessionSaver = SessionSaver(
      controller: controller,
      sessionStore: sessionStore,
      settingsStore: settingsStore,
    );

    onStep?.call('playEvents.init');
    await repository.closeInterruptedPlayEvents();

    final playRecorder = PlayRecorder(
      controller: controller,
      repository: repository,
    );

    onStep?.call('collections.init');
    final userCollections = UserCollections(repository: repository);
    await userCollections.init();

    onStep?.call('platform.init');
    final platform = PlatformServices.create();
    final MediaSessionService mediaSessionService =
        factories.createMediaSessionService?.call() ?? platform.mediaSession;
    final SleepInhibitor sleepInhibitor =
        factories.createSleepInhibitor?.call() ?? platform.sleepInhibitor;
    final TrayService trayService =
        factories.createTrayService?.call() ?? platform.tray;
    final WindowService windowService =
        factories.createWindowService?.call() ?? platform.window;

    final shutdownCoordinator = AppShutdownCoordinator(
      sessionSaver: sessionSaver,
      playRecorder: playRecorder,
      settingsStore: settingsStore,
      mediaSessionService: mediaSessionService,
      sleepInhibitor: sleepInhibitor,
      trayService: trayService,
      windowService: windowService,
    );

    final mediaSessionController = MediaSessionController(
      playbackController: controller,
      mediaSessionService: mediaSessionService,
      settingsStore: settingsStore,
      artistNameStore: artistNameStore,
    );

    final sleepController = SleepController(
      playbackController: controller,
      sleepInhibitor: sleepInhibitor,
      settingsStore: settingsStore,
    );

    onStep?.call('trayWindow.init');
    final trayWindowController = TrayWindowController(
      windowService: windowService,
      trayService: trayService,
      playbackController: controller,
      settingsStore: settingsStore,
      shutdownCoordinator: shutdownCoordinator,
      sessionSaver: sessionSaver,
    );
    await trayWindowController.init();

    final DatabaseStartupReport? startupReport = repository is SqliteLibraryRepository
        ? repository.startupReport
        : null;
    final UserDataBackupService? backupService = repository is SqliteLibraryRepository
        ? repository.createBackupService()
        : null;
    final Directory? backupsDirectory = repository is SqliteLibraryRepository
        ? repository.backupsDirectory
        : null;
    final folderOpener = factories.openFolder ?? platform.openFolder;

    return AppBootstrapSuccess(
      AppServices(
        engine: engine,
        controller: controller,
        repository: repository,
        scanService: scanService,
        settingsStore: settingsStore,
        glassController: glassController,
        localeController: localeController,
        audioSettingsApplier: audioSettingsApplier,
        eqStore: eqStore,
        eqController: eqController,
        artistNameStore: artistNameStore,
        sessionStore: sessionStore,
        sessionSaver: sessionSaver,
        playRecorder: playRecorder,
        userCollections: userCollections,
        mediaSessionService: mediaSessionService,
        sleepInhibitor: sleepInhibitor,
        trayService: trayService,
        windowService: windowService,
        shutdownCoordinator: shutdownCoordinator,
        mediaSessionController: mediaSessionController,
        sleepController: sleepController,
        trayWindowController: trayWindowController,
        startupReport: startupReport,
        userDataBackupService: backupService,
        onOpenLogsFolder: () {
          final logsPath = AppLogger.instance.logDirectory?.path;
          if (logsPath != null) {
            unawaited(folderOpener(logsPath));
          }
        },
        onOpenBackupsFolder: () {
          final backupsPath = backupsDirectory?.path;
          if (backupsPath != null) {
            unawaited(folderOpener(backupsPath));
          }
        },
        onOpenFolder: folderOpener,
      ),
    );
  }
}
