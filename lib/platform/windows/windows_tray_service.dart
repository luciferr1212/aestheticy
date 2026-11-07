import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart' as tm;

import '../../diagnostics/app_logger.dart';
import '../tray_service.dart';

/// Real Windows implementation of [TrayService] backed by `tray_manager`.
class WindowsTrayService with tm.TrayListener implements TrayService {
  final StreamController<TrayEvent> _eventController =
      StreamController<TrayEvent>.broadcast();
  bool _isVisible = false;
  bool _listenerRegistered = false;

  @override
  Stream<TrayEvent> get events => _eventController.stream;

  @override
  Future<void> show({
    required TrayMenuLabels labels,
    String tooltip = 'Aestheticy',
  }) async {
    if (!Platform.isWindows) return;
    try {
      if (!_listenerRegistered) {
        tm.trayManager.addListener(this);
        _listenerRegistered = true;
      }
      await tm.trayManager.setIcon('assets/tray/app_icon.ico');
      await tm.trayManager.setToolTip(tooltip);
      await updateMenu(labels);
      _isVisible = true;
    } catch (e, st) {
      AppLogger.instance.warning('Tray', 'Failed to show tray: $e', e, st);
    }
  }

  @override
  Future<void> hide() async {
    if (!_isVisible) return;
    try {
      await tm.trayManager.destroy();
      _isVisible = false;
    } catch (e, st) {
      AppLogger.instance.warning('Tray', 'Failed to hide tray: $e', e, st);
    }
  }

  @override
  Future<void> updateMenu(TrayMenuLabels labels) async {
    if (!Platform.isWindows) return;
    try {
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
    } catch (e, st) {
      AppLogger.instance.warning('Tray', 'Failed to update tray menu: $e', e, st);
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
