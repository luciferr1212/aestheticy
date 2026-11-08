import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Scope in which a shortcut is active.
enum AppShortcutScope {
  /// Active globally across the entire application window.
  global,

  /// Active when Now Playing or Full Screen views are focused.
  nowPlaying,
}

/// Identifiers for all supported shortcuts in Aestheticy.
enum AppShortcutId {
  /// Toggle play and pause.
  playPause,

  /// Navigate back or dismiss current view.
  back,

  /// Seek backward 5 seconds.
  seekBackward,

  /// Seek forward 5 seconds.
  seekForward,

  /// Open developer Design Gallery.
  gallery,

  /// Open quick search overlay (Ctrl+K).
  quickSearch,

  /// Global media key: toggle play and pause.
  mediaPlayPause,

  /// Global media key: skip to next track.
  mediaNext,

  /// Global media key: skip to previous track.
  mediaPrevious,

  /// Global shortcut: skip to next track (Ctrl + Right).
  nextTrack,

  /// Global shortcut: skip to previous track (Ctrl + Left).
  previousTrack,

  /// Global shortcut: increase volume by 5% (Ctrl + Up).
  volumeUp,

  /// Global shortcut: decrease volume by 5% (Ctrl + Down).
  volumeDown,

  /// Space chord: skip to next track (Space + →).
  chordNext,

  /// Space chord: skip to previous track (Space + ←).
  chordPrevious,
}

/// Representation of an active keyboard shortcut in Aestheticy.
class AppShortcutItem {
  /// Unique identifier of the shortcut.
  final AppShortcutId id;

  /// Visual representation of the keys (e.g. 'Space', 'Ctrl + Shift + G').
  final String keyCombination;

  /// Localization key for the shortcut's function.
  final String descriptionKey;

  /// Activator used for runtime bindings where applicable.
  final ShortcutActivator activator;

  /// Scope in which this shortcut is active.
  final AppShortcutScope scope;

  /// Creates an [AppShortcutItem].
  const AppShortcutItem({
    required this.id,
    required this.keyCombination,
    required this.descriptionKey,
    required this.activator,
    required this.scope,
  });
}

/// Canonical, single source of truth for all implemented shortcuts in Aestheticy.
///
/// Every shortcut listed here corresponds to real key event or shortcut handlers
/// in the app. No unimplemented shortcuts are ever listed.
const List<AppShortcutItem> kAppShortcuts = [
  AppShortcutItem(
    id: AppShortcutId.playPause,
    keyCombination: 'Space',
    descriptionKey: 'shortcuts.playPause',
    activator: SingleActivator(LogicalKeyboardKey.space),
    scope: AppShortcutScope.global,
  ),
  AppShortcutItem(
    id: AppShortcutId.back,
    keyCombination: 'Esc',
    descriptionKey: 'shortcuts.back',
    activator: SingleActivator(LogicalKeyboardKey.escape),
    scope: AppShortcutScope.nowPlaying,
  ),
  AppShortcutItem(
    id: AppShortcutId.seekBackward,
    keyCombination: '←',
    descriptionKey: 'shortcuts.seekBackward',
    activator: SingleActivator(LogicalKeyboardKey.arrowLeft),
    scope: AppShortcutScope.global,
  ),
  AppShortcutItem(
    id: AppShortcutId.seekForward,
    keyCombination: '→',
    descriptionKey: 'shortcuts.seekForward',
    activator: SingleActivator(LogicalKeyboardKey.arrowRight),
    scope: AppShortcutScope.global,
  ),
  AppShortcutItem(
    id: AppShortcutId.chordNext,
    keyCombination: 'Space + →',
    descriptionKey: 'shortcuts.chordNext',
    activator: SingleActivator(LogicalKeyboardKey.arrowRight),
    scope: AppShortcutScope.global,
  ),
  AppShortcutItem(
    id: AppShortcutId.chordPrevious,
    keyCombination: 'Space + ←',
    descriptionKey: 'shortcuts.chordPrevious',
    activator: SingleActivator(LogicalKeyboardKey.arrowLeft),
    scope: AppShortcutScope.global,
  ),
  AppShortcutItem(
    id: AppShortcutId.gallery,
    keyCombination: 'Ctrl + Shift + G',
    descriptionKey: 'shortcuts.gallery',
    activator: SingleActivator(
      LogicalKeyboardKey.keyG,
      control: true,
      shift: true,
    ),
    scope: AppShortcutScope.global,
  ),
  AppShortcutItem(
    id: AppShortcutId.quickSearch,
    keyCombination: 'Ctrl + K',
    descriptionKey: 'shortcuts.quickSearch',
    activator: SingleActivator(
      LogicalKeyboardKey.keyK,
      control: true,
    ),
    scope: AppShortcutScope.global,
  ),
  AppShortcutItem(
    id: AppShortcutId.mediaPlayPause,
    keyCombination: 'Media Play/Pause',
    descriptionKey: 'shortcuts.mediaPlayPause',
    activator: SingleActivator(LogicalKeyboardKey.mediaPlayPause),
    scope: AppShortcutScope.global,
  ),
  AppShortcutItem(
    id: AppShortcutId.mediaNext,
    keyCombination: 'Media Next',
    descriptionKey: 'shortcuts.mediaNext',
    activator: SingleActivator(LogicalKeyboardKey.mediaTrackNext),
    scope: AppShortcutScope.global,
  ),
  AppShortcutItem(
    id: AppShortcutId.mediaPrevious,
    keyCombination: 'Media Previous',
    descriptionKey: 'shortcuts.mediaPrevious',
    activator: SingleActivator(LogicalKeyboardKey.mediaTrackPrevious),
    scope: AppShortcutScope.global,
  ),
  AppShortcutItem(
    id: AppShortcutId.nextTrack,
    keyCombination: 'Ctrl + Right',
    descriptionKey: 'shortcuts.nextTrack',
    activator: SingleActivator(LogicalKeyboardKey.arrowRight, control: true),
    scope: AppShortcutScope.global,
  ),
  AppShortcutItem(
    id: AppShortcutId.previousTrack,
    keyCombination: 'Ctrl + Left',
    descriptionKey: 'shortcuts.previousTrack',
    activator: SingleActivator(LogicalKeyboardKey.arrowLeft, control: true),
    scope: AppShortcutScope.global,
  ),
  AppShortcutItem(
    id: AppShortcutId.volumeUp,
    keyCombination: 'Ctrl + Up',
    descriptionKey: 'shortcuts.volumeUp',
    activator: SingleActivator(LogicalKeyboardKey.arrowUp, control: true),
    scope: AppShortcutScope.global,
  ),
  AppShortcutItem(
    id: AppShortcutId.volumeDown,
    keyCombination: 'Ctrl + Down',
    descriptionKey: 'shortcuts.volumeDown',
    activator: SingleActivator(LogicalKeyboardKey.arrowDown, control: true),
    scope: AppShortcutScope.global,
  ),
];

/// Looks up an [AppShortcutItem] by its [id].
AppShortcutItem shortcutById(AppShortcutId id) {
  return kAppShortcuts.firstWhere((s) => s.id == id);
}

/// Checks whether a [KeyEvent] matches the shortcut identified by [id].
bool matchesShortcut(KeyEvent event, AppShortcutId id) {
  if (event is! KeyDownEvent) return false;
  for (final item in kAppShortcuts) {
    if (item.id == id) {
      return item.activator.accepts(event, HardwareKeyboard.instance);
    }
  }
  return false;
}

/// Checks whether a [KeyEvent] represents the Space key.
bool isSpaceKey(KeyEvent event) {
  return event.logicalKey == LogicalKeyboardKey.space;
}

/// Checks whether a [KeyEvent] represents the Left arrow key.
bool isArrowLeftKey(KeyEvent event) {
  return event.logicalKey == LogicalKeyboardKey.arrowLeft;
}

/// Checks whether a [KeyEvent] represents the Right arrow key.
bool isArrowRightKey(KeyEvent event) {
  return event.logicalKey == LogicalKeyboardKey.arrowRight;
}

/// Checks whether a [KeyEvent] represents the Up arrow key.
bool isArrowUpKey(KeyEvent event) {
  return event.logicalKey == LogicalKeyboardKey.arrowUp;
}

/// Checks whether a [KeyEvent] represents the Down arrow key.
bool isArrowDownKey(KeyEvent event) {
  return event.logicalKey == LogicalKeyboardKey.arrowDown;
}

/// Checks whether a [KeyEvent] represents the Enter key.
bool isEnterKey(KeyEvent event) {
  return event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.numpadEnter;
}
