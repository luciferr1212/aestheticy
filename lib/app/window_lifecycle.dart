import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/features/integration/app_shutdown.dart';
import 'package:aestheticy/features/integration/tray_window_controller.dart';
import 'package:aestheticy/features/session/session_saver.dart';
import 'package:aestheticy/platform/tray_service.dart';
import 'package:aestheticy/ui/mini_player/mini_player_controller.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

/// Coordinates main/mini window close requests, tray delegation, and
/// [AppLifecycleListener] hooks while keeping [TrayWindowController] as the
/// single close owner.
class WindowLifecycleCoordinator {
  final MiniPlayerController miniPlayerController;
  final PlaybackController playbackController;
  final SettingsStore settingsStore;
  final AppShutdownCoordinator shutdownCoordinator;
  final TrayWindowController? trayWindowController;
  final TrayService? trayService;
  final SessionSaver? sessionSaver;
  final bool Function() isMounted;

  StreamSubscription<void>? _windowCloseSub;
  AppLifecycleListener? _lifecycleListener;

  /// Creates and attaches a [WindowLifecycleCoordinator].
  WindowLifecycleCoordinator({
    required this.miniPlayerController,
    required this.playbackController,
    required this.settingsStore,
    required this.shutdownCoordinator,
    required this.isMounted,
    this.trayWindowController,
    this.trayService,
    this.sessionSaver,
  });

  /// Registers the window close listener and [AppLifecycleListener].
  void attach() {
    // TrayWindowController is the single owner of main-window close handling.
    // This listener only ensures the mini-player frame restores cleanly when
    // a close arrives while mini mode is active.
    _windowCloseSub = miniPlayerController.windowService.closeRequested.listen(
      (_) {
        if (miniPlayerController.isMini) {
          unawaited(miniPlayerController.restoreFrameForClose());
        }
      },
    );

    // Root cause fix: Flutter's WindowsLifecycleManager intercepts WM_CLOSE
    // before WindowManagerPlugin (because FlutterViewController is constructed
    // before RegisterPlugins() in windows/runner/flutter_window.cpp). Previously
    // this callback always paused, shut down, destroyed the window, and exited
    // even when closeBehavior == 'tray'. Delegate close handling to the single
    // owner (trayWindowController) and cancel exit when hiding to tray.
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: handleExitRequested,
      onDetach: () {
        sessionSaver?.saveSnapshotSync();
      },
      onHide: () {
        sessionSaver?.saveSnapshotSync();
      },
      onPause: () {
        sessionSaver?.saveSnapshotSync();
      },
    );
  }

  /// Handles Flutter's [AppLifecycleListener.onExitRequested].
  Future<AppExitResponse> handleExitRequested() async {
    AppLogger.instance.info(
      'Lifecycle',
      'App exit requested (onExitRequested)',
    );
    try {
      await miniPlayerController.restoreFrameForClose();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Lifecycle',
        'Failed restoring mini player frame on exit (exceptionType=${e.runtimeType})',
        e,
        st,
      );
    }

    final trayController = trayWindowController;
    if (trayController != null) {
      final hiddenToTray = await trayController.handleCloseRequested();
      return hiddenToTray ? AppExitResponse.cancel : AppExitResponse.exit;
    }

    final behavior = settingsStore.settings.closeBehavior;
    final trayVisible = trayService?.isVisible ?? false;
    AppLogger.instance.info(
      'Lifecycle',
      'Close fallback check: behavior=$behavior, trayVisible=$trayVisible',
    );
    if (behavior == 'tray' && trayVisible) {
      AppLogger.instance.info('Lifecycle', 'Final close action: hide');
      try {
        sessionSaver?.saveSnapshotSync();
      } catch (e, st) {
        AppLogger.instance.warning(
          'Lifecycle',
          'Snapshot failed on hide (exceptionType=${e.runtimeType})',
          e,
          st,
        );
      }
      try {
        await miniPlayerController.windowService.hide();
      } catch (e, st) {
        AppLogger.instance.warning(
          'Lifecycle',
          'Window hide failed (exceptionType=${e.runtimeType})',
          e,
          st,
        );
      }
      return AppExitResponse.cancel;
    }

    AppLogger.instance.info('Lifecycle', 'Final close action: quit');
    try {
      await playbackController.pause();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Lifecycle',
        'Playback pause failed on exit (exceptionType=${e.runtimeType})',
        e,
        st,
      );
    }
    try {
      await miniPlayerController.windowService.hide();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Lifecycle',
        'Window hide failed on exit (exceptionType=${e.runtimeType})',
        e,
        st,
      );
    }
    await shutdownCoordinator.shutdown();
    await miniPlayerController.windowService.destroy();
    return AppExitResponse.exit;
  }

  /// Handles close requests triggered from the mini-player chrome.
  Future<void> handleMiniCloseRequested() async {
    AppLogger.instance.info('Lifecycle', 'Mini player close requested');
    final win = miniPlayerController.windowService;
    await miniPlayerController.restoreFrameForClose();
    if (!isMounted()) return;

    final trayController = trayWindowController;
    if (trayController != null) {
      await trayController.handleCloseRequested();
      return;
    }

    final behavior = settingsStore.settings.closeBehavior;
    final trayVisible = trayService?.isVisible ?? false;
    AppLogger.instance.info(
      'Lifecycle',
      'Mini close fallback check: behavior=$behavior, trayVisible=$trayVisible',
    );
    if (behavior == 'tray' && trayVisible) {
      AppLogger.instance.info('Lifecycle', 'Mini close final action: hide');
      try {
        sessionSaver?.saveSnapshotSync();
      } catch (e, st) {
        AppLogger.instance.warning(
          'Lifecycle',
          'Snapshot failed on mini hide (exceptionType=${e.runtimeType})',
          e,
          st,
        );
      }
      await win.hide();
      return;
    }

    AppLogger.instance.info('Lifecycle', 'Mini close final action: quit');
    try {
      await playbackController.pause();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Lifecycle',
        'Playback pause failed on mini quit (exceptionType=${e.runtimeType})',
        e,
        st,
      );
    }
    try {
      await win.hide();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Lifecycle',
        'Window hide failed on mini quit (exceptionType=${e.runtimeType})',
        e,
        st,
      );
    }
    await shutdownCoordinator.shutdown();
    await win.destroy();
  }

  /// Detaches listeners and subscriptions.
  void dispose() {
    unawaited(_windowCloseSub?.cancel());
    _windowCloseSub = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }
}
