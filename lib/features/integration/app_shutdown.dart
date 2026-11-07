import 'dart:async';

import '../../diagnostics/app_logger.dart';
import '../../platform/media_session_service.dart';
import '../../platform/sleep_inhibitor.dart';
import '../../platform/tray_service.dart';
import '../../ui/settings/settings_store.dart';
import '../history/play_recorder.dart';
import '../session/session_saver.dart';

/// Centralized, ordered, and idempotent shutdown coordinator for Aestheticy.
///
/// Ensures all volatile state (playback session, play history, settings, logs)
/// is flushed to disk before destroying the window or terminating the process.
class AppShutdownCoordinator {
  final SessionSaver? sessionSaver;
  final PlayRecorder? playRecorder;
  final SettingsStore? settingsStore;
  final AppLogger logger;
  final MediaSessionService? mediaSessionService;
  final SleepInhibitor? sleepInhibitor;
  final TrayService? trayService;

  bool _isShuttingDown = false;
  bool _hasShutdown = false;

  /// Creates an [AppShutdownCoordinator].
  AppShutdownCoordinator({
    this.sessionSaver,
    this.playRecorder,
    this.settingsStore,
    AppLogger? logger,
    this.mediaSessionService,
    this.sleepInhibitor,
    this.trayService,
  }) : logger = logger ?? AppLogger.instance;

  /// Whether shutdown has completed.
  bool get hasShutdown => _hasShutdown;

  /// Executes an ordered, failure-tolerant, idempotent application shutdown.
  Future<void> shutdown() async {
    if (_hasShutdown || _isShuttingDown) return;
    _isShuttingDown = true;

    // Step 1: Final session snapshot with synchronous write
    try {
      sessionSaver?.saveSnapshotSync();
    } catch (e, st) {
      logger.error('Shutdown', 'Step 1 (session snapshot) failed: $e', e, st);
    }

    // Step 2: Finalize open play recorder session
    try {
      if (playRecorder != null) {
        await playRecorder!.dispose();
      }
    } catch (e, st) {
      logger.error('Shutdown', 'Step 2 (play recorder) failed: $e', e, st);
    }

    // Step 3: Flush settings store
    try {
      if (settingsStore != null) {
        await settingsStore!.flush();
      }
    } catch (e, st) {
      logger.error('Shutdown', 'Step 3 (settings flush) failed: $e', e, st);
    }

    // Step 4: Flush logger
    try {
      await logger.flush();
    } catch (e, st) {
      logger.error('Shutdown', 'Step 4 (logger flush) failed: $e', e, st);
    }

    // Step 5: Disable media session and release sleep inhibitor
    try {
      if (mediaSessionService != null) {
        await mediaSessionService!.disable();
      }
    } catch (e, st) {
      logger.error('Shutdown', 'Step 5a (media session disable) failed: $e', e, st);
    }
    try {
      sleepInhibitor?.release();
    } catch (e, st) {
      logger.error('Shutdown', 'Step 5b (sleep inhibitor release) failed: $e', e, st);
    }

    // Step 6: Hide tray icon
    try {
      if (trayService != null) {
        await trayService!.hide();
      }
    } catch (e, st) {
      logger.error('Shutdown', 'Step 6 (tray hide) failed: $e', e, st);
    }

    _hasShutdown = true;
    _isShuttingDown = false;
  }
}
