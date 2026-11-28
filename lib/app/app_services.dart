import 'package:flutter/foundation.dart';

import 'package:aestheticy/audio/audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/features/history/play_recorder.dart';
import 'package:aestheticy/features/integration/app_shutdown.dart';
import 'package:aestheticy/features/integration/media_session_controller.dart';
import 'package:aestheticy/features/integration/sleep_controller.dart';
import 'package:aestheticy/features/integration/tray_window_controller.dart';
import 'package:aestheticy/features/session/session_saver.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite/userdata_backup_service.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';
import 'package:aestheticy/platform/media_session_service.dart';
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

/// Plain container holding all long-lived application services created during
/// startup in [AppBootstrap].
class AppServices {
  final AudioEngine engine;
  final PlaybackController controller;
  final LibraryRepository repository;
  final ScanService scanService;
  final SettingsStore settingsStore;
  final GlassController glassController;
  final LocaleController localeController;
  final AudioSettingsApplier audioSettingsApplier;
  final EqStore eqStore;
  final EqController eqController;
  final ArtistNameStore artistNameStore;
  final SessionStore sessionStore;
  final SessionSaver sessionSaver;
  final PlayRecorder playRecorder;
  final UserCollections userCollections;
  final MediaSessionService mediaSessionService;
  final SleepInhibitor sleepInhibitor;
  final TrayService trayService;
  final WindowService windowService;
  final AppShutdownCoordinator shutdownCoordinator;
  final MediaSessionController mediaSessionController;
  final SleepController sleepController;
  final TrayWindowController trayWindowController;
  final DatabaseStartupReport? startupReport;
  final UserDataBackupService? userDataBackupService;
  final VoidCallback? onOpenLogsFolder;
  final VoidCallback? onOpenBackupsFolder;
  final Future<void> Function(String path)? onOpenFolder;

  /// Creates an [AppServices] container.
  const AppServices({
    required this.engine,
    required this.controller,
    required this.repository,
    required this.scanService,
    required this.settingsStore,
    required this.glassController,
    required this.localeController,
    required this.audioSettingsApplier,
    required this.eqStore,
    required this.eqController,
    required this.artistNameStore,
    required this.sessionStore,
    required this.sessionSaver,
    required this.playRecorder,
    required this.userCollections,
    required this.mediaSessionService,
    required this.sleepInhibitor,
    required this.trayService,
    required this.windowService,
    required this.shutdownCoordinator,
    required this.mediaSessionController,
    required this.sleepController,
    required this.trayWindowController,
    this.startupReport,
    this.userDataBackupService,
    this.onOpenLogsFolder,
    this.onOpenBackupsFolder,
    this.onOpenFolder,
  });
}
