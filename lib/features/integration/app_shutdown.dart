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
    final totalSw = Stopwatch()..start();

    // Step 1: Final session snapshot with synchronous write (first and synchronous)
    final step1Sw = Stopwatch()..start();
    try {
      sessionSaver?.saveSnapshotSync();
    } catch (e, st) {
      logger.error('Shutdown', 'Step 1 (session snapshot) failed: $e', e, st);
    }
    step1Sw.stop();
    logger.info('Shutdown',
        'Step 1 (session snapshot) finished in ${step1Sw.elapsedMilliseconds}ms');

    // Steps 2-6: Independent steps in parallel with 1.5-second timeout
    final parallelSw = Stopwatch()..start();
    await Future.wait([
      _runStep('Step 2 (play recorder)', () async {
        if (playRecorder != null) {
          await playRecorder!.dispose();
        }
      }),
      _runStep('Step 3 (settings flush)', () async {
        if (settingsStore != null) {
          await settingsStore!.flush();
        }
      }),
      _runStep('Step 4 (media session disable)', () async {
        if (mediaSessionService != null) {
          await mediaSessionService!.disable();
        }
      }),
      _runStep('Step 5 (sleep inhibitor release)', () async {
        sleepInhibitor?.release();
      }),
      _runStep('Step 6 (tray hide)', () async {
        if (trayService != null) {
          await trayService!.hide();
        }
      }),
    ]);
    parallelSw.stop();
    logger.info('Shutdown',
        'Parallel steps finished in ${parallelSw.elapsedMilliseconds}ms');

    totalSw.stop();
    logger.info('Shutdown',
        'Total shutdown finished in ${totalSw.elapsedMilliseconds}ms');

    // Final step: logger flush is LAST before window destruction
    final flushSw = Stopwatch()..start();
    try {
      await logger.flush();
    } catch (_) {
      // Ignore flush failure on exit
    }
    flushSw.stop();

    _hasShutdown = true;
    _isShuttingDown = false;
  }

  Future<void> _runStep(String name, FutureOr<void> Function() action) async {
    final sw = Stopwatch()..start();
    try {
      await Future<void>.sync(action)
          .timeout(const Duration(milliseconds: 1500));
      sw.stop();
      logger.info('Shutdown', '$name finished in ${sw.elapsedMilliseconds}ms');
    } on TimeoutException {
      sw.stop();
      logger.warning('Shutdown',
          '$name timed out after 1500ms (took ${sw.elapsedMilliseconds}ms)');
    } catch (e, st) {
      sw.stop();
      logger.error('Shutdown',
          '$name failed after ${sw.elapsedMilliseconds}ms: $e', e, st);
    }
  }
}
