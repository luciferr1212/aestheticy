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

  /// Target window size in logical pixels for wide mini layout.
  static const Size wideSize = Size(480, 170);

  /// Target window size in logical pixels for square mini layout.
  static const Size squareSize = Size(340, 440);

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
    settingsStore.addListener(_onSettingsChanged);
  }

  /// Current window mode.
  MiniPlayerMode get mode => _mode;

  /// Whether mini player mode is currently active.
  bool get isMini => _mode == MiniPlayerMode.mini;

  /// Remembered geometry of the normal window before entering mini mode.
  WindowGeometry? get rememberedGeometry => _rememberedGeometry;

  /// Returns the target window size for a given [shape].
  static Size sizeForShape(String shape) {
    return shape == 'square' ? squareSize : wideSize;
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

  /// Enters mini player mode, resizing and positioning the native window.
  Future<void> enter() async {
    if (_mode == MiniPlayerMode.mini) return;

    _rememberedGeometry = await windowService.getGeometry();
    if (_rememberedGeometry!.isFullScreen) {
      await windowService.setFullScreen(false);
    }
    if (_rememberedGeometry!.isMaximized) {
      await windowService.unmaximize();
    }

    await windowService.setResizable(false);

    final shape = settingsStore.settings.miniPlayerShape;
    final targetSize = sizeForShape(shape);
    final displaySize = await windowService.getDisplaySize();
    final positionPreset = settingsStore.settings.miniPlayerPosition;

    final targetPosition = computePosition(
      preset: positionPreset,
      targetSize: targetSize,
      displaySize: displaySize,
      lastX: settingsStore.settings.miniPlayerLastX,
      lastY: settingsStore.settings.miniPlayerLastY,
    );

    await windowService.applyGeometry(targetPosition, targetSize);
    await windowService.setAlwaysOnTop(settingsStore.settings.miniPlayerAlwaysOnTop);

    _mode = MiniPlayerMode.mini;
    notifyListeners();
  }

  /// Exits mini player mode, restoring original window dimensions and state.
  Future<void> exit() async {
    if (_mode != MiniPlayerMode.mini) return;

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

    _mode = MiniPlayerMode.normal;
    notifyListeners();
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

  /// Sets window shape and updates geometry live if in mini mode.
  Future<void> setShape(String shape) async {
    _lastShape = shape;
    settingsStore.update((s) => s.copyWith(miniPlayerShape: shape));
    if (isMini) {
      await _applyShape(shape);
    }
  }

  /// Toggles window shape between wide and square live.
  Future<void> toggleShape() async {
    final next = settingsStore.settings.miniPlayerShape == 'wide'
        ? 'square'
        : 'wide';
    await setShape(next);
  }

  Future<void> _applyShape(String shape) async {
    final currentGeo = await windowService.getGeometry();
    final targetSize = sizeForShape(shape);
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
      return;
    }

    final newAlwaysOnTop = settingsStore.settings.miniPlayerAlwaysOnTop;
    if (newAlwaysOnTop != _lastAlwaysOnTop) {
      _lastAlwaysOnTop = newAlwaysOnTop;
      windowService.setAlwaysOnTop(newAlwaysOnTop);
    }

    final newShape = settingsStore.settings.miniPlayerShape;
    if (newShape != _lastShape) {
      _lastShape = newShape;
      _applyShape(newShape);
    }
  }

  @override
  void dispose() {
    settingsStore.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
