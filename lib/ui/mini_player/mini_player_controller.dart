import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../platform/window_service.dart';
import '../settings/settings_store.dart';

/// Modes supported by the desktop window layout coordinator.
enum MiniPlayerMode {
  /// Regular full desktop window layout.
  normal,

  /// Compact floating mini player window layout.
  mini,
}

/// Controller coordinating desktop window mode (normal vs mini player).
///
/// Manages window resizing, positioning presets, always-on-top pinning,
/// and lossless geometry restoration when exiting mini mode.
class MiniPlayerController extends ChangeNotifier {
  final WindowService windowService;
  final SettingsStore settingsStore;

  MiniPlayerMode _mode = MiniPlayerMode.normal;
  WindowGeometry? _rememberedGeometry;
  String _lastShape = 'wide';
  bool _lastAlwaysOnTop = true;
  bool _lastShowLyrics = false;
  bool _disposed = false;
  bool? _desiredMini;
  bool _resizePending = false;
  bool _isTransitioning = false;
  final List<Completer<void>> _transitionWaiters = [];

  /// Target window size in logical pixels for wide mini layout.
  static const Size wideSize = Size(480, 170);

  /// Target window size in logical pixels for wide mini layout with lyrics panel.
  static const Size wideLyricsSize = Size(480, 320);

  /// Target window size in logical pixels for square mini layout.
  static const Size squareSize = Size(340, 440);

  /// Target window size in logical pixels for square mini layout with lyrics panel.
  static const Size squareLyricsSize = Size(340, 620);

  /// Outer side margin in logical pixels.
  static const double sideMargin = 16.0;

  /// Top margin in logical pixels for top-center placement.
  static const double topMargin = 16.0;

  /// Bottom margin in logical pixels reserved for Windows taskbar.
  static const double taskbarBottomMargin = 64.0;

  /// Creates a [MiniPlayerController].
  MiniPlayerController({
    required this.windowService,
    required this.settingsStore,
  }) {
    _lastShape = settingsStore.settings.miniPlayerShape;
    _lastAlwaysOnTop = settingsStore.settings.miniPlayerAlwaysOnTop;
    _lastShowLyrics = settingsStore.settings.miniPlayerShowLyrics;
    settingsStore.addListener(_onSettingsChanged);
  }

  /// Current window mode.
  MiniPlayerMode get mode => _mode;

  /// Whether mini player mode is currently active.
  bool get isMini => _mode == MiniPlayerMode.mini;

  /// Remembered geometry of the normal window before entering mini mode.
  WindowGeometry? get rememberedGeometry => _rememberedGeometry;

  /// Returns the target window size for a given [shape] and [showLyrics] state.
  static Size sizeForShape(String shape, {bool showLyrics = false}) {
    if (shape == 'square') {
      return showLyrics ? squareLyricsSize : squareSize;
    }
    return showLyrics ? wideLyricsSize : wideSize;
  }

  /// Calculates top-left placement coordinates for target window size and preset.
  static Offset computePosition({
    required String preset,
    required Size targetSize,
    required Size displaySize,
    double? lastX,
    double? lastY,
  }) {
    final defaultX = displaySize.width - targetSize.width - sideMargin;
    final defaultY = displaySize.height - targetSize.height - taskbarBottomMargin;
    final defaultPos = Offset(
      defaultX < 0 ? 0 : defaultX,
      defaultY < 0 ? 0 : defaultY,
    );

    switch (preset) {
      case 'topCenter':
        final cx = (displaySize.width - targetSize.width) / 2.0;
        return Offset(cx < 0 ? 0 : cx, topMargin);

      case 'remember':
        if (lastX != null && lastY != null) {
          final isInside = lastX >= 0 &&
              (lastX + targetSize.width) <= displaySize.width &&
              lastY >= 0 &&
              (lastY + targetSize.height) <= displaySize.height;
          if (isInside) {
            return Offset(lastX, lastY);
          }
        }
        return defaultPos;

      case 'bottomRight':
      default:
        return defaultPos;
    }
  }

  Future<void> _driveTransition({bool? targetMini, bool resize = false}) {
    if (_disposed) return Future<void>.value();
    if (targetMini != null) {
      _desiredMini = targetMini;
      _resizePending = false;
    } else if (resize) {
      _resizePending = true;
    }

    if (_isTransitioning) {
      final completer = Completer<void>();
      _transitionWaiters.add(completer);
      return completer.future;
    }

    return _runTransitionLoop();
  }

  Future<void> _runTransitionLoop() async {
    _isTransitioning = true;
    try {
      while (!_disposed) {
        final desired = _desiredMini;
        if (desired == true && _mode != MiniPlayerMode.mini) {
          await _performEnter();
        } else if (desired == false && _mode == MiniPlayerMode.mini) {
          await _performExit();
        } else if (_resizePending && _mode == MiniPlayerMode.mini) {
          _resizePending = false;
          await _applyLayoutSize(
            settingsStore.settings.miniPlayerShape,
            showLyrics: settingsStore.settings.miniPlayerShowLyrics,
          );
        } else {
          break;
        }
      }
    } finally {
      _isTransitioning = false;
      final waiters = List<Completer<void>>.of(_transitionWaiters);
      _transitionWaiters.clear();
      for (final waiter in waiters) {
        if (!waiter.isCompleted) {
          waiter.complete();
        }
      }
    }
  }

  /// Enters mini player mode, hiding the frame and resizing/positioning the native window.
  Future<void> enter() => _driveTransition(targetMini: true);

  Future<void> _performEnter() async {
    if (_disposed || _desiredMini == false || _mode == MiniPlayerMode.mini) {
      return;
    }

    _rememberedGeometry = await windowService.getGeometry();
    if (_disposed || _desiredMini == false) return;
    if (_rememberedGeometry!.isFullScreen) {
      await windowService.setFullScreen(false);
    }
    if (_rememberedGeometry!.isMaximized) {
      await windowService.unmaximize();
    }

    await windowService.setResizable(false);

    final shape = settingsStore.settings.miniPlayerShape;
    final showLyrics = settingsStore.settings.miniPlayerShowLyrics;
    final targetSize = sizeForShape(shape, showLyrics: showLyrics);
    final displaySize = await windowService.getDisplaySize();
    final positionPreset = settingsStore.settings.miniPlayerPosition;

    final targetPosition = computePosition(
      preset: positionPreset,
      targetSize: targetSize,
      displaySize: displaySize,
      lastX: settingsStore.settings.miniPlayerLastX,
      lastY: settingsStore.settings.miniPlayerLastY,
    );

    await windowService.setFrameless(true);
    await windowService.applyGeometry(targetPosition, targetSize);
    await windowService.setAlwaysOnTop(settingsStore.settings.miniPlayerAlwaysOnTop);

    _mode = MiniPlayerMode.mini;
    notifyListeners();
  }

  /// Exits mini player mode, restoring original window dimensions, state, and frame.
  Future<void> exit() => _driveTransition(targetMini: false);

  Future<void> _performExit() async {
    if (_disposed || _desiredMini == true || _mode != MiniPlayerMode.mini) {
      return;
    }

    if (settingsStore.settings.miniPlayerPosition == 'remember') {
      final currentGeo = await windowService.getGeometry();
      settingsStore.update((s) => s.copyWith(
            miniPlayerLastX: currentGeo.position.dx,
            miniPlayerLastY: currentGeo.position.dy,
          ));
    }

    await windowService.setAlwaysOnTop(false);
    await windowService.setResizable(true);

    if (_rememberedGeometry != null) {
      await windowService.applyGeometry(
        _rememberedGeometry!.position,
        _rememberedGeometry!.size,
      );
      if (_rememberedGeometry!.isMaximized) {
        await windowService.maximize();
      }
    }

    await windowService.setFrameless(false);

    _mode = MiniPlayerMode.normal;
    notifyListeners();
  }

  /// Restores normal window frame if the app is closing or hiding while in mini mode.
  Future<void> restoreFrameForClose() {
    if (_mode == MiniPlayerMode.mini || _desiredMini == true) {
      return exit();
    }
    return Future<void>.value();
  }

  /// Toggles always-on-top pinning state live.
  Future<void> toggleAlwaysOnTop() async {
    final next = !settingsStore.settings.miniPlayerAlwaysOnTop;
    _lastAlwaysOnTop = next;
    settingsStore.update((s) => s.copyWith(miniPlayerAlwaysOnTop: next));
    if (isMini) {
      await windowService.setAlwaysOnTop(next);
    }
  }

  /// Toggles expanded lyrics display in mini player mode and resizes live.
  Future<void> toggleShowLyrics() async {
    final next = !settingsStore.settings.miniPlayerShowLyrics;
    _lastShowLyrics = next;
    settingsStore.update((s) => s.copyWith(miniPlayerShowLyrics: next));
    if (isMini) {
      await _driveTransition(resize: true);
    }
    notifyListeners();
  }

  /// Sets window shape and updates geometry live if in mini mode.
  Future<void> setShape(String shape) async {
    _lastShape = shape;
    settingsStore.update((s) => s.copyWith(miniPlayerShape: shape));
    if (isMini) {
      await _driveTransition(resize: true);
    }
  }

  /// Toggles window shape between wide and square live.
  Future<void> toggleShape() async {
    final next = settingsStore.settings.miniPlayerShape == 'wide'
        ? 'square'
        : 'wide';
    await setShape(next);
  }

  Future<void> _applyLayoutSize(
    String shape, {
    required bool showLyrics,
  }) async {
    final currentGeo = await windowService.getGeometry();
    final targetSize = sizeForShape(shape, showLyrics: showLyrics);
    final displaySize = await windowService.getDisplaySize();

    final maxX =
        (displaySize.width - targetSize.width).clamp(0.0, double.infinity);
    final maxY =
        (displaySize.height - targetSize.height).clamp(0.0, double.infinity);
    final clampedX = currentGeo.position.dx.clamp(0.0, maxX);
    final clampedY = currentGeo.position.dy.clamp(0.0, maxY);

    await windowService.applyGeometry(Offset(clampedX, clampedY), targetSize);
  }

  void _onSettingsChanged() {
    if (!isMini) {
      _lastShape = settingsStore.settings.miniPlayerShape;
      _lastAlwaysOnTop = settingsStore.settings.miniPlayerAlwaysOnTop;
      _lastShowLyrics = settingsStore.settings.miniPlayerShowLyrics;
      return;
    }

    final newAlwaysOnTop = settingsStore.settings.miniPlayerAlwaysOnTop;
    if (newAlwaysOnTop != _lastAlwaysOnTop) {
      _lastAlwaysOnTop = newAlwaysOnTop;
      windowService.setAlwaysOnTop(newAlwaysOnTop);
    }

    final newShape = settingsStore.settings.miniPlayerShape;
    final newShowLyrics = settingsStore.settings.miniPlayerShowLyrics;
    if (newShape != _lastShape || newShowLyrics != _lastShowLyrics) {
      _lastShape = newShape;
      _lastShowLyrics = newShowLyrics;
      _driveTransition(resize: true);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    settingsStore.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
