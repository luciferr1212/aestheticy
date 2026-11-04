import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Representation of an active keyboard shortcut in Aestheticy.
class AppShortcutItem {
  /// Visual representation of the keys (e.g. 'Space', 'Ctrl + Shift + G').
  final String keyCombination;

  /// Localization key for the shortcut's function.
  final String descriptionKey;

  /// Activator used for runtime bindings where applicable.
  final ShortcutActivator? activator;

  /// Creates an [AppShortcutItem].
  const AppShortcutItem({
    required this.keyCombination,
    required this.descriptionKey,
    this.activator,
  });
}

/// Canonical, single source of truth for all implemented shortcuts in Aestheticy.
///
/// Every shortcut listed here corresponds to real key event or shortcut handlers
/// in the app. No unimplemented shortcuts are ever listed.
const List<AppShortcutItem> kAppShortcuts = [
  AppShortcutItem(
    keyCombination: 'Space',
    descriptionKey: 'shortcuts.playPause',
    activator: SingleActivator(LogicalKeyboardKey.space),
  ),
  AppShortcutItem(
    keyCombination: 'Esc',
    descriptionKey: 'shortcuts.back',
    activator: SingleActivator(LogicalKeyboardKey.escape),
  ),
  AppShortcutItem(
    keyCombination: '←',
    descriptionKey: 'shortcuts.seekBackward',
    activator: SingleActivator(LogicalKeyboardKey.arrowLeft),
  ),
  AppShortcutItem(
    keyCombination: '→',
    descriptionKey: 'shortcuts.seekForward',
    activator: SingleActivator(LogicalKeyboardKey.arrowRight),
  ),
  AppShortcutItem(
    keyCombination: 'Ctrl + Shift + G',
    descriptionKey: 'shortcuts.gallery',
    activator: SingleActivator(
      LogicalKeyboardKey.keyG,
      control: true,
      shift: true,
    ),
  ),
];
