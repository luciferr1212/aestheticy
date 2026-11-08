import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../platform/tray_service.dart';
import '../../platform/window_service.dart';
import '../../ui/l10n/app_strings.dart';
import '../../ui/settings/settings_store.dart';
import '../session/session_saver.dart';
import 'app_shutdown.dart';

/// Pure-Dart controller managing window close interception and system tray lifecycle.
class TrayWindowController {
  final WindowService windowService;
  final TrayService trayService;
  final PlaybackController playbackController;
  final SettingsStore settingsStore;
  final AppShutdownCoordinator shutdownCoordinator;
  final SessionSaver? sessionSaver;
  final VoidCallback? onExit;

  final List<StreamSubscription<dynamic>> _subs = [];
  bool _isWindowVisible = true;
  String _lastCloseBehavior = 'quit';
  String _lastLanguage = 'en';
  PlaybackState _lastPlaybackState = PlaybackState.idle;
  bool _disposed = false;
  Future<void>? _lastTrayEventFuture;
  Future<void>? _lastCloseFuture;

  /// Whether the main application window is currently visible.
  bool get isWindowVisible => _isWindowVisible;

  /// Visible for testing to await completion of asynchronous tray events.
  @visibleForTesting
  Future<void>? get lastTrayEventFuture => _lastTrayEventFuture;

  /// Visible for testing to await completion of close requests.
  @visibleForTesting
  Future<void>? get lastCloseFuture => _lastCloseFuture;

  /// Creates a [TrayWindowController].
  TrayWindowController({
    required this.windowService,
    required this.trayService,
    required this.playbackController,
    required this.settingsStore,
    required this.shutdownCoordinator,
    this.sessionSaver,
    this.onExit,
  });

  /// Initializes window close interception and watches tray settings.
  Future<void> init() async {
    _lastCloseBehavior = settingsStore.settings.closeBehavior;
    _lastLanguage = settingsStore.settings.language;
    _lastPlaybackState = playbackController.currentState;

    await windowService.setPreventClose(true);

    _subs.add(windowService.closeRequested.listen((_) {
      _lastCloseFuture = _onCloseRequested();
    }));
    _subs.add(trayService.events.listen(_onTrayEvent));
    _subs.add(playbackController.stateStream.listen(_onPlaybackStateChanged));

    settingsStore.addListener(_onSettingsChanged);

    if (_lastCloseBehavior == 'tray') {
      await _showTray();
    }
  }

  TrayMenuLabels _buildMenuLabels() {
    final lang = settingsStore.settings.language;
    final dict = lang == 'ar' ? AppStrings.ar : AppStrings.en;

    final isPlaying = playbackController.currentState == PlaybackState.playing;
    final playPauseLabel = isPlaying ? (dict['tray.pause'] ?? 'Pause') : (dict['tray.play'] ?? 'Play');

    return TrayMenuLabels(
      show: dict['tray.show'] ?? 'Show',
      playPause: playPauseLabel,
      next: dict['tray.next'] ?? 'Next',
      previous: dict['tray.previous'] ?? 'Previous',
      quit: dict['tray.quit'] ?? 'Quit',
    );
  }

  Future<void> _showTray() async {
    final labels = _buildMenuLabels();
    await trayService.show(labels: labels, tooltip: 'Aestheticy');
  }

  Future<void> _updateTrayMenu() async {
    if (settingsStore.settings.closeBehavior != 'tray') return;
    final labels = _buildMenuLabels();
    await trayService.updateMenu(labels);
  }

  void _onPlaybackStateChanged(PlaybackState state) {
    if (_disposed) return;
    final oldPlaying = _lastPlaybackState == PlaybackState.playing;
    final newPlaying = state == PlaybackState.playing;
    _lastPlaybackState = state;
    if (oldPlaying != newPlaying) {
      unawaited(_updateTrayMenu());
    }
  }

  void _onSettingsChanged() {
    if (_disposed) return;
    final currentBehavior = settingsStore.settings.closeBehavior;
    final currentLanguage = settingsStore.settings.language;

    if (currentBehavior != _lastCloseBehavior) {
      _lastCloseBehavior = currentBehavior;
      if (currentBehavior == 'tray') {
        unawaited(_showTray());
      } else {
        unawaited(trayService.hide());
      }
    } else if (currentLanguage != _lastLanguage) {
      _lastLanguage = currentLanguage;
      unawaited(_updateTrayMenu());
    }
  }

  Future<void> _onCloseRequested() async {
    if (_disposed) return;

    if (settingsStore.settings.closeBehavior == 'tray') {
      // Hide window, save session snapshot, keep running (do NOT stop playback or run shutdown)
      try {
        sessionSaver?.saveSnapshotSync();
      } catch (_) {}
      await windowService.hide();
      _isWindowVisible = false;
    } else {
      // (1) Immediately stop audio output and hide window for instant close feel
      try {
        await playbackController.pause();
      } catch (_) {}
      await windowService.hide();
      _isWindowVisible = false;

      // (2)-(4) Shutdown coordinator runs snapshot first, parallel steps, then logger flush
      await shutdownCoordinator.shutdown();
      await windowService.destroy();
      onExit?.call();
    }
  }

  void _onTrayEvent(TrayEvent event) {
    if (_disposed) return;
    _lastTrayEventFuture = handleTrayEvent(event);
  }

  /// Handles a [TrayEvent] in an awaited, deterministic sequence.
  Future<void> handleTrayEvent(TrayEvent event) async {
    if (_disposed) return;

    switch (event.type) {
      case TrayEventType.iconClicked:
        await _toggleWindowVisibility();
      case TrayEventType.menuItem:
        if (event.menuItem != null) {
          await handleMenuItem(event.menuItem!);
        }
    }
  }

  Future<void> _toggleWindowVisibility() async {
    if (_isWindowVisible) {
      await windowService.hide();
      _isWindowVisible = false;
    } else {
      await windowService.show();
      await windowService.focus();
      _isWindowVisible = true;
    }
  }

  /// Handles a specific tray [item] action in an awaited sequence.
  Future<void> handleMenuItem(TrayMenuItemId item) async {
    switch (item) {
      case TrayMenuItemId.show:
        await windowService.show();
        await windowService.focus();
        _isWindowVisible = true;
      case TrayMenuItemId.playPause:
        await playbackController.togglePlayPause();
      case TrayMenuItemId.next:
        await playbackController.skipNext();
      case TrayMenuItemId.previous:
        await playbackController.skipPrevious();
      case TrayMenuItemId.quit:
        try {
          await playbackController.pause();
        } catch (_) {}
        await windowService.hide();
        _isWindowVisible = false;
        await shutdownCoordinator.shutdown();
        await windowService.destroy();
        onExit?.call();
    }
  }

  /// Disposes of listeners and cleans up coordinator resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    settingsStore.removeListener(_onSettingsChanged);
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }
}
