import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:window_manager/window_manager.dart' as wm;

import '../../diagnostics/app_logger.dart';
import '../window_service.dart';

/// Default logical display size provider resolving primary screen metrics.
Size defaultDisplaySizeProvider() {
  final dispatcher = PlatformDispatcher.instance;
  if (dispatcher.displays.isNotEmpty) {
    final display = dispatcher.displays.first;
    final dpr = display.devicePixelRatio > 0 ? display.devicePixelRatio : 1.0;
    return Size(display.size.width / dpr, display.size.height / dpr);
  }
  if (dispatcher.views.isNotEmpty) {
    final view = dispatcher.views.first;
    final dpr = view.devicePixelRatio > 0 ? view.devicePixelRatio : 1.0;
    return Size(view.physicalSize.width / dpr, view.physicalSize.height / dpr);
  }
  return const Size(1920, 1080);
}

/// Real Windows implementation of [WindowService] backed by `window_manager`.
class WindowsWindowService with wm.WindowListener implements WindowService {
  final StreamController<void> _closeController =
      StreamController<void>.broadcast();
  final DisplaySizeProvider _displaySizeProvider;
  bool _initialized = false;

  /// Creates a [WindowsWindowService] with an optional injected [displaySizeProvider].
  WindowsWindowService({DisplaySizeProvider? displaySizeProvider})
      : _displaySizeProvider =
            displaySizeProvider ?? defaultDisplaySizeProvider;

  @override
  Stream<void> get closeRequested => _closeController.stream;

  @override
  Future<void> setPreventClose(bool prevent) async {
    if (!Platform.isWindows) return;
    try {
      if (!_initialized) {
        await wm.windowManager.ensureInitialized();
        wm.windowManager.addListener(this);
        _initialized = true;
      }
      await wm.windowManager.setPreventClose(prevent);
    } catch (e, st) {
      AppLogger.instance.warning(
        'Window',
        'Failed to setPreventClose: ${e.runtimeType}',
        e,
        st,
      );
    }
  }

  @override
  void onWindowClose() {
    _closeController.add(null);
  }

  @override
  Future<void> show() async {
    if (!Platform.isWindows) return;
    try {
      await wm.windowManager.show();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Window',
        'Failed to show window: ${e.runtimeType}',
        e,
        st,
      );
    }
  }

  @override
  Future<void> hide() async {
    if (!Platform.isWindows) return;
    try {
      await wm.windowManager.hide();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Window',
        'Failed to hide window: ${e.runtimeType}',
        e,
        st,
      );
    }
  }

  @override
  Future<void> focus() async {
    if (!Platform.isWindows) return;
    try {
      await wm.windowManager.focus();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Window',
        'Failed to focus window: ${e.runtimeType}',
        e,
        st,
      );
    }
  }

  @override
  Future<void> destroy() async {
    if (!Platform.isWindows) return;
    try {
      await wm.windowManager.destroy();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Window',
        'Failed to destroy window: ${e.runtimeType}',
        e,
        st,
      );
    }
  }

  @override
  Future<WindowGeometry> getGeometry() async {
    if (!Platform.isWindows) {
      return const WindowGeometry(
        position: Offset.zero,
        size: Size(1280, 800),
        isMaximized: false,
        isFullScreen: false,
      );
    }
    try {
      final bounds = await wm.windowManager.getBounds();
      final isMax = await wm.windowManager.isMaximized();
      final isFull = await wm.windowManager.isFullScreen();
      return WindowGeometry(
        position: bounds.topLeft,
        size: bounds.size,
        isMaximized: isMax,
        isFullScreen: isFull,
      );
    } catch (e, st) {
      AppLogger.instance.warning(
        'Window',
        'Failed to getGeometry: ${e.runtimeType}',
        e,
        st,
      );
      return const WindowGeometry(
        position: Offset.zero,
        size: Size(1280, 800),
        isMaximized: false,
        isFullScreen: false,
      );
    }
  }

  @override
  Future<void> applyGeometry(Offset position, Size size) async {
    if (!Platform.isWindows) return;
    try {
      await wm.windowManager.setBounds(
        null,
        position: position,
        size: size,
      );
    } catch (e, st) {
      AppLogger.instance.warning(
        'Window',
        'Failed to applyGeometry: ${e.runtimeType}',
        e,
        st,
      );
    }
  }

  @override
  Future<void> setAlwaysOnTop(bool isAlwaysOnTop) async {
    if (!Platform.isWindows) return;
    try {
      await wm.windowManager.setAlwaysOnTop(isAlwaysOnTop);
    } catch (e, st) {
      AppLogger.instance.warning(
        'Window',
        'Failed to setAlwaysOnTop: ${e.runtimeType}',
        e,
        st,
      );
    }
  }

  @override
  Future<void> setResizable(bool isResizable) async {
    if (!Platform.isWindows) return;
    try {
      await wm.windowManager.setResizable(isResizable);
    } catch (e, st) {
      AppLogger.instance.warning(
        'Window',
        'Failed to setResizable: ${e.runtimeType}',
        e,
        st,
      );
    }
  }

  @override
  Future<void> setFullScreen(bool isFullScreen) async {
    if (!Platform.isWindows) return;
    try {
      await wm.windowManager.setFullScreen(isFullScreen);
    } catch (e, st) {
      AppLogger.instance.warning(
        'Window',
        'Failed to setFullScreen: ${e.runtimeType}',
        e,
        st,
      );
    }
  }

  @override
  Future<void> maximize() async {
    if (!Platform.isWindows) return;
    try {
      await wm.windowManager.maximize();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Window',
        'Failed to maximize: ${e.runtimeType}',
        e,
        st,
      );
    }
  }

  @override
  Future<void> unmaximize() async {
    if (!Platform.isWindows) return;
    try {
      await wm.windowManager.unmaximize();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Window',
        'Failed to unmaximize: ${e.runtimeType}',
        e,
        st,
      );
    }
  }

  @override
  Future<Size> getDisplaySize() async {
    try {
      return _displaySizeProvider();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Window',
        'Failed to getDisplaySize: ${e.runtimeType}',
        e,
        st,
      );
      return const Size(1920, 1080);
    }
  }

  @override
  Future<void> dispose() async {
    if (_initialized) {
      try {
        wm.windowManager.removeListener(this);
      } catch (e, st) {
        AppLogger.instance.warning(
          'Window',
          'Failed to removeListener: ${e.runtimeType}',
          e,
          st,
        );
      }
      _initialized = false;
    }
    await _closeController.close();
  }
}
