import 'dart:async';
import 'dart:io';

import 'package:window_manager/window_manager.dart' as wm;

import '../../diagnostics/app_logger.dart';
import '../window_service.dart';

/// Real Windows implementation of [WindowService] backed by `window_manager`.
class WindowsWindowService with wm.WindowListener implements WindowService {
  final StreamController<void> _closeController =
      StreamController<void>.broadcast();
  bool _initialized = false;

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
      AppLogger.instance.warning('Window', 'Failed to setPreventClose: $e', e, st);
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
      AppLogger.instance.warning('Window', 'Failed to show window: $e', e, st);
    }
  }

  @override
  Future<void> hide() async {
    if (!Platform.isWindows) return;
    try {
      await wm.windowManager.hide();
    } catch (e, st) {
      AppLogger.instance.warning('Window', 'Failed to hide window: $e', e, st);
    }
  }

  @override
  Future<void> focus() async {
    if (!Platform.isWindows) return;
    try {
      await wm.windowManager.focus();
    } catch (e, st) {
      AppLogger.instance.warning('Window', 'Failed to focus window: $e', e, st);
    }
  }

  @override
  Future<void> destroy() async {
    if (!Platform.isWindows) return;
    try {
      await wm.windowManager.destroy();
    } catch (e, st) {
      AppLogger.instance.warning('Window', 'Failed to destroy window: $e', e, st);
    }
  }

  @override
  Future<void> dispose() async {
    if (_initialized) {
      wm.windowManager.removeListener(this);
      _initialized = false;
    }
    await _closeController.close();
  }
}
