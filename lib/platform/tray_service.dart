import 'dart:async';

/// Identifiers for standard tray context menu actions.
enum TrayMenuItemId {
  show,
  playPause,
  next,
  previous,
  quit,
}

/// Category of tray interaction.
enum TrayEventType {
  iconClicked,
  menuItem,
}

/// An interaction event originating from the system tray icon or its context menu.
class TrayEvent {
  /// The kind of event.
  final TrayEventType type;

  /// Target menu item if this event was a menu item activation.
  final TrayMenuItemId? menuItem;

  /// Creates a tray icon click event.
  const TrayEvent.iconClicked()
      : type = TrayEventType.iconClicked,
        menuItem = null;

  /// Creates a tray context menu activation event.
  const TrayEvent.menuItem(TrayMenuItemId item)
      : type = TrayEventType.menuItem,
        menuItem = item;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrayEvent &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          menuItem == other.menuItem;

  @override
  int get hashCode => Object.hash(type, menuItem);

  @override
  String toString() =>
      type == TrayEventType.iconClicked ? 'TrayEvent.iconClicked' : 'TrayEvent.menuItem($menuItem)';
}

/// Localized labels for all tray context menu actions.
class TrayMenuLabels {
  final String show;
  final String playPause;
  final String next;
  final String previous;
  final String quit;

  /// Creates a [TrayMenuLabels] record.
  const TrayMenuLabels({
    required this.show,
    required this.playPause,
    required this.next,
    required this.previous,
    required this.quit,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrayMenuLabels &&
          runtimeType == other.runtimeType &&
          show == other.show &&
          playPause == other.playPause &&
          next == other.next &&
          previous == other.previous &&
          quit == other.quit;

  @override
  int get hashCode => Object.hash(show, playPause, next, previous, quit);
}

/// Abstract contract for Windows system tray icon and context menu lifecycle.
abstract interface class TrayService {
  /// Displays the system tray icon with tooltip and initial menu.
  Future<void> show({
    required TrayMenuLabels labels,
    String tooltip = 'Aestheticy',
  });

  /// Hides and removes the tray icon from the notification area.
  Future<void> hide();

  /// Updates visible labels in the tray context menu without recreating the icon.
  Future<void> updateMenu(TrayMenuLabels labels);

  /// Stream of user clicks on the tray icon or context menu items.
  Stream<TrayEvent> get events;

  /// Disposes of tray service resources.
  Future<void> dispose();
}
