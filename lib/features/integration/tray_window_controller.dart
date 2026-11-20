import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../diagnostics/app_logger.dart';
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
  final AppLogger _logger;

  final ValueNotifier<bool> _trayUnavailableNotifier =
      ValueNotifier<bool>(false);
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _isWindowVisible = true;
  String _lastCloseBehavior = 'quit';
  String _lastLanguage = 'en';
  PlaybackState _lastPlaybackState = PlaybackState.idle;
  bool _disposed = false;
  Future<bool>? _pendingTrayShow;
  Future<bool>? _activeCloseFuture;
  Future<void>? _quitFuture;
  Future<void>? _lastTrayEventFuture;
  Future<void>? _lastCloseFuture;

  /// Whether the main application window is currently visible.
  bool get isWindowVisible => _isWindowVisible;

  /// Listenable notifying listeners (such as Settings) when tray icon creation fails.
  ValueListenable<bool> get trayUnavailableListenable => _trayUnavailableNotifier;

  /// Whether creating the tray icon failed so closing the window will quit instead.
  bool get isTrayUnavailable => _trayUnavailableNotifier.value;

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
    AppLogger? logger,
  }) : _logger = logger ?? AppLogger.instance;

  /// Initializes window close interception and watches tray settings.
  Future<void> init() async {
    _lastCloseBehavior = settingsStore.settings.closeBehavior;
    _lastLanguage = settingsStore.settings.language;
    _lastPlaybackState = playbackController.currentState;

    await windowService.setPreventClose(true);

    _subs.add(windowService.closeRequested.listen((_) {
      _lastCloseFuture = handleCloseRequested();
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

  Future<bool> _showTray() {
    final existing = _pendingTrayShow;
    if (existing != null) return existing;

    final future = _performShowTray();
    _pendingTrayShow = future;
    future.whenComplete(() {
      if (identical(_pendingTrayShow, future)) {
        _pendingTrayShow = null;
      }
    });
    return future;
  }

  Future<bool> _performShowTray() async {
    final labels = _buildMenuLabels();
    try {
      final created = await trayService.show(
        labels: labels,
        tooltip: 'Aestheticy',
      );
      final visible = created && trayService.isVisible;
      _trayUnavailableNotifier.value = !visible;
      if (visible) {
        _logger.info('Tray', 'Tray show result: success (isVisible=true)');
        return true;
      }
      _logger.warning(
        'Tray',
        'Tray show result: failure (isVisible=${trayService.isVisible}, exceptionType=none)',
      );
      return false;
    } catch (e, st) {
      _trayUnavailableNotifier.value = true;
      _logger.error(
        'Tray',
        'Tray show result: failure (exceptionType=${e.runtimeType})',
        e,
        st,
      );
      return false;
    }
  }

  Future<void> _updateTrayMenu() async {
    if (settingsStore.settings.closeBehavior != 'tray') return;
    if (!trayService.isVisible) return;
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

  /// Handles a window close request cleanly and deduplicates overlapping close
  /// signals (e.g. `WM_CLOSE` via both `AppLifecycleListener` and
  /// `window_manager`). Returns `true` if hidden to tray, `false` if quitting.
  Future<bool> handleCloseRequested() async {
    if (_disposed) return false;
    if (_quitFuture != null) {
      await _quitFuture;
      return false;
    }
    final inFlight = _activeCloseFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _performCloseRequested();
    _activeCloseFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_activeCloseFuture, future)) {
        _activeCloseFuture = null;
      }
    }
  }

  Future<bool> _performCloseRequested() async {
    _logger.info('Tray', 'Close requested');
    final behavior = settingsStore.settings.closeBehavior;
    _logger.info('Tray', 'Close behavior read: $behavior');

    if (behavior == 'tray') {
      if (_pendingTrayShow != null) {
        await _pendingTrayShow;
      }
      if (!trayService.isVisible && !isTrayUnavailable) {
        await _showTray();
      }
      _logger.info(
        'Tray',
        'Tray show status on close: isVisible=${trayService.isVisible}',
      );
    }

    if (behavior == 'tray' && trayService.isVisible) {
      // Hide window, save session snapshot, keep running (do NOT stop playback or run shutdown)
      _logger.info('Tray', 'Final close action: hide');
      try {
        sessionSaver?.saveSnapshotSync();
      } catch (e, st) {
        _logger.warning(
          'Tray',
          'Session snapshot failed on hide (exceptionType=${e.runtimeType})',
          e,
          st,
        );
      }
      await windowService.hide();
      _isWindowVisible = false;
      return true;
    }

    _logger.info(
      'Tray',
      'Final close action: quit (behavior=$behavior, trayVisible=${trayService.isVisible})',
    );
    await _quitApp();
    return false;
  }

  Future<void> _quitApp() {
    final existing = _quitFuture;
    if (existing != null) return existing;

    final future = () async {
      // (1) Immediately stop audio output and hide window for instant close feel
      try {
        await playbackController.pause();
      } catch (e, st) {
        _logger.warning(
          'Tray',
          'Playback pause failed on quit (exceptionType=${e.runtimeType})',
          e,
          st,
        );
      }
      await windowService.hide();
      _isWindowVisible = false;

      // (2)-(4) Shutdown coordinator runs snapshot first, parallel steps, then logger flush
      await shutdownCoordinator.shutdown();
      await windowService.destroy();
      onExit?.call();
    }();
    _quitFuture = future;
    return future;
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
        _logger.info('Tray', 'Quit selected from tray menu');
        await _quitApp();
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
    _trayUnavailableNotifier.dispose();
  }
}
