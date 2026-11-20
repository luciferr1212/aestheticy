import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart' as tm;

import '../../diagnostics/app_logger.dart';
import '../tray_service.dart';

/// Real Windows implementation of [TrayService] backed by `tray_manager`.
///
/// Tray root-cause findings on Windows release builds:
/// 1. `tray_manager` (0.5.3) computes `path.joinAll([dirname(resolvedExecutable),
///    'data/flutter_assets', iconPath])` in Dart and passes it to native
///    `TrayManagerPlugin::SetIcon`, which calls `LoadImageW` and
///    `Shell_NotifyIcon(NIM_ADD)` without checking or surfacing errors. Passing a
///    verified existing `.ico` path (or extracting it from `rootBundle` if the
///    release asset path is unavailable/invalid) ensures `LoadImageW` receives a
///    valid Win32 ICO file, while `show` never swallows failures silently.
/// 2. Main-window close interception also depends on `AppLifecycleListener` in
///    `lib/main.dart` (see `_lifecycleListener`), because Flutter's
///    `WindowsLifecycleManager` handles `WM_CLOSE` before plugin delegates.
class WindowsTrayService with tm.TrayListener implements TrayService {
  /// Flutter asset key for the tray icon.
  static const String assetIconPath = 'assets/tray/app_icon.ico';

  final StreamController<TrayEvent> _eventController =
      StreamController<TrayEvent>.broadcast();
  bool _isVisible = false;
  bool _listenerRegistered = false;

  @override
  bool get isVisible => _isVisible;

  @override
  Stream<TrayEvent> get events => _eventController.stream;

  /// Checks whether [bytes] starts with a valid Windows ICO header (`reserved=0`,
  /// `type=1`, `count >= 1`, and enough bytes for its directory entries).
  @visibleForTesting
  static bool isValidIcoBytes(Uint8List bytes) {
    if (bytes.length < 6) return false;
    final reserved = bytes[0] | (bytes[1] << 8);
    final type = bytes[2] | (bytes[3] << 8);
    final count = bytes[4] | (bytes[5] << 8);
    if (reserved != 0 || type != 1 || count <= 0) return false;
    return bytes.length >= 6 + count * 16;
  }

  static Future<bool> _isValidIcoFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return false;
      final bytes = await file.readAsBytes();
      return isValidIcoBytes(bytes);
    } catch (_) {
      return false;
    }
  }

  /// Resolves an existing, valid `.ico` file path for `tray_manager`.
  ///
  /// Checks the release asset location (`<exeDir>/data/flutter_assets/...`),
  /// the working directory asset fallback, and finally extracts the bundled
  /// asset via `rootBundle` into the app-support folder if needed.
  @visibleForTesting
  static Future<String?> resolveIconFilePath({
    String? resolvedExecutablePath,
    String? currentDirectoryPath,
    Future<ByteData> Function(String key)? loadAsset,
    Future<Directory> Function()? supportDirProvider,
  }) async {
    final exeDir = p.dirname(resolvedExecutablePath ?? Platform.resolvedExecutable);
    final releaseCandidate = p.join(
      exeDir,
      'data',
      'flutter_assets',
      'assets',
      'tray',
      'app_icon.ico',
    );
    if (await _isValidIcoFile(releaseCandidate)) {
      return releaseCandidate;
    }

    final cwdCandidate = p.join(
      currentDirectoryPath ?? Directory.current.path,
      'assets',
      'tray',
      'app_icon.ico',
    );
    if (await _isValidIcoFile(cwdCandidate)) {
      return cwdCandidate;
    }

    try {
      final assetData = await (loadAsset ?? rootBundle.load)(assetIconPath);
      final bytes = assetData.buffer.asUint8List(
        assetData.offsetInBytes,
        assetData.lengthInBytes,
      );
      if (!isValidIcoBytes(bytes)) {
        return null;
      }
      final supportDir =
          await (supportDirProvider ?? getApplicationSupportDirectory)();
      final extractedDir = Directory(p.join(supportDir.path, 'tray'));
      if (!extractedDir.existsSync()) {
        await extractedDir.create(recursive: true);
      }
      final extractedFile = File(p.join(extractedDir.path, 'app_icon.ico'));
      await extractedFile.writeAsBytes(bytes, flush: true);
      if (await _isValidIcoFile(extractedFile.path)) {
        return extractedFile.path;
      }
    } catch (e, st) {
      AppLogger.instance.warning(
        'Tray',
        'Fallback tray icon extraction failed (exceptionType=${e.runtimeType})',
        e,
        st,
      );
    }

    return null;
  }

  @override
  Future<bool> show({
    required TrayMenuLabels labels,
    String tooltip = 'Aestheticy',
  }) async {
    if (!Platform.isWindows) {
      _isVisible = false;
      return false;
    }

    try {
      final iconPath = await resolveIconFilePath();
      if (iconPath == null) {
        throw StateError('Tray icon asset app_icon.ico is missing or invalid');
      }

      if (!_listenerRegistered) {
        tm.trayManager.addListener(this);
        _listenerRegistered = true;
      }
      await tm.trayManager.setIcon(iconPath);
      await tm.trayManager.setToolTip(tooltip);
      await _applyMenu(labels);
      _isVisible = true;
      AppLogger.instance.info('Tray', 'Tray show succeeded (icon=app_icon.ico)');
      return true;
    } catch (e, st) {
      _isVisible = false;
      AppLogger.instance.error(
        'Tray',
        'Tray show failed (exceptionType=${e.runtimeType})',
        e,
        st,
      );
      rethrow;
    }
  }

  @override
  Future<void> hide() async {
    if (!_isVisible) return;
    try {
      await tm.trayManager.destroy();
      _isVisible = false;
    } catch (e, st) {
      AppLogger.instance.warning(
        'Tray',
        'Failed to hide tray (exceptionType=${e.runtimeType})',
        e,
        st,
      );
    }
  }

  Future<void> _applyMenu(TrayMenuLabels labels) async {
    final menu = tm.Menu(
      items: [
        tm.MenuItem(
          key: 'show',
          label: labels.show,
        ),
        tm.MenuItem.separator(),
        tm.MenuItem(
          key: 'playPause',
          label: labels.playPause,
        ),
        tm.MenuItem(
          key: 'next',
          label: labels.next,
        ),
        tm.MenuItem(
          key: 'previous',
          label: labels.previous,
        ),
        tm.MenuItem.separator(),
        tm.MenuItem(
          key: 'quit',
          label: labels.quit,
        ),
      ],
    );
    await tm.trayManager.setContextMenu(menu);
  }

  @override
  Future<void> updateMenu(TrayMenuLabels labels) async {
    if (!Platform.isWindows) return;
    try {
      await _applyMenu(labels);
    } catch (e, st) {
      AppLogger.instance.warning(
        'Tray',
        'Failed to update tray menu (exceptionType=${e.runtimeType})',
        e,
        st,
      );
    }
  }

  @override
  void onTrayIconMouseDown() {
    _eventController.add(const TrayEvent.iconClicked());
  }

  @override
  void onTrayIconRightMouseDown() {
    tm.trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(tm.MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _eventController.add(const TrayEvent.menuItem(TrayMenuItemId.show));
      case 'playPause':
        _eventController.add(const TrayEvent.menuItem(TrayMenuItemId.playPause));
      case 'next':
        _eventController.add(const TrayEvent.menuItem(TrayMenuItemId.next));
      case 'previous':
        _eventController.add(const TrayEvent.menuItem(TrayMenuItemId.previous));
      case 'quit':
        _eventController.add(const TrayEvent.menuItem(TrayMenuItemId.quit));
    }
  }

  @override
  Future<void> dispose() async {
    if (_listenerRegistered) {
      tm.trayManager.removeListener(this);
      _listenerRegistered = false;
    }
    await hide();
    await _eventController.close();
  }
}
