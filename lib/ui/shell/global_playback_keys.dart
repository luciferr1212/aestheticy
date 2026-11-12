import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/audio_engine.dart';
import '../../audio/playback_controller.dart';
import '../settings/app_shortcuts.dart';
import '../settings/settings_store.dart';
import 'volume_hud.dart';

/// Shared keyboard shortcut & playback-key handler for [AppShell] and [MiniPlayerView].
///
/// Centralizes media keys, Space/arrow chords, Ctrl+Up/Down global volume,
/// plain Up/Down volume in Full Screen & Mini Player, throttled repeat rates
/// (60 ms volume, 120 ms seek), editable-text guards, and cheat-sheet triggers.
class GlobalPlaybackKeysHandler {
  /// Active playback controller.
  final PlaybackController controller;

  /// Underlying audio engine.
  final AudioEngine engine;

  /// Persistent settings store.
  final SettingsStore settingsStore;

  /// Resolves the shared transient volume HUD controller, if mounted.
  final VolumeHudController? Function() volumeHudProvider;

  /// Returns `true` when Full Screen or Mini Player is active.
  final bool Function() isInFullScreenOrMini;

  /// Handles `Esc` when applicable; returns `true` if handled.
  final bool Function()? onEscape;

  /// Handles native full screen toggle (`F11`).
  final VoidCallback? onToggleFullScreen;

  /// Handles entering mini player (`Ctrl + M`).
  final VoidCallback? onEnterMiniPlayer;

  /// Opens the keyboard shortcuts cheat sheet (`?` / `Ctrl + /`).
  final VoidCallback? onShowShortcutsCheatSheet;

  /// Returns `true` if the cheat sheet dialog is currently open.
  final bool Function()? isShortcutsCheatSheetOpen;

  bool _isSpaceDown = false;
  bool _spaceChordUsed = false;
  int _arrowHeldDirection = 0;
  Timer? _seekCooldownTimer;
  Timer? _volumeCooldownTimer;

  /// Creates a [GlobalPlaybackKeysHandler].
  GlobalPlaybackKeysHandler({
    required this.controller,
    required this.engine,
    required this.settingsStore,
    required this.volumeHudProvider,
    required this.isInFullScreenOrMini,
    this.onEscape,
    this.onToggleFullScreen,
    this.onEnterMiniPlayer,
    this.onShowShortcutsCheatSheet,
    this.isShortcutsCheatSheetOpen,
  });

  /// Clears held key state and cancels active repeat timers.
  void reset() {
    _resetSpaceState();
    _arrowHeldDirection = 0;
    _seekCooldownTimer?.cancel();
    _seekCooldownTimer = null;
    _volumeCooldownTimer?.cancel();
    _volumeCooldownTimer = null;
  }

  /// Releases all timers when the owning widget disposes.
  void dispose() {
    reset();
  }

  void _resetSpaceState() {
    _isSpaceDown = false;
    _spaceChordUsed = false;
  }

  bool _isEditableTextFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _isPopupOrDialogFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    final route = ModalRoute.of(focusContext);
    return route is PopupRoute ||
        focusContext.findAncestorWidgetOfExactType<Dialog>() != null;
  }

  bool _isDeepWidgetConsumed({required bool isArrow}) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;

    if (focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null) {
      return true;
    }

    final route = ModalRoute.of(focusContext);
    if (route is PopupRoute ||
        focusContext.findAncestorWidgetOfExactType<Dialog>() != null) {
      return true;
    }

    if (isArrow &&
        focusContext.findAncestorWidgetOfExactType<Slider>() != null) {
      return true;
    }

    if (!isArrow &&
        (focusContext.findAncestorWidgetOfExactType<ButtonStyleButton>() !=
                null ||
            focusContext.findAncestorWidgetOfExactType<IconButton>() != null)) {
      return true;
    }

    return false;
  }

  void _performSeek(Duration delta) {
    final currentPos = controller.currentPosition;
    final totalDuration = controller.currentDuration;

    var target = currentPos + delta;
    if (target < Duration.zero) {
      target = Duration.zero;
    } else if (totalDuration > Duration.zero && target > totalDuration) {
      target = totalDuration;
    }
    controller.seek(target);
  }

  void _armSeekCooldown() {
    _seekCooldownTimer?.cancel();
    _seekCooldownTimer = Timer(const Duration(milliseconds: 120), () {
      _seekCooldownTimer = null;
    });
  }

  void _armVolumeCooldown() {
    _volumeCooldownTimer?.cancel();
    _volumeCooldownTimer = Timer(const Duration(milliseconds: 60), () {
      _volumeCooldownTimer = null;
    });
  }

  void _stepVolume(double delta) {
    adjustVolumeByStep(
      engine: engine,
      currentVolume: settingsStore.settings.volume,
      delta: delta,
      settingsStore: settingsStore,
      hudController: volumeHudProvider(),
    );
  }

  /// Processes a desktop [KeyEvent] across all playback & overlay shortcuts.
  KeyEventResult handleKeyEvent(FocusNode node, KeyEvent event) {
    // 1. Esc (Back / Exit overlay or mini mode)
    if (event is KeyDownEvent && matchesShortcut(event, AppShortcutId.back)) {
      if (!_isPopupOrDialogFocused() &&
          isShortcutsCheatSheetOpen?.call() != true &&
          onEscape?.call() == true) {
        return KeyEventResult.handled;
      }
    }

    // 2. Window mode shortcuts (F11 / Ctrl + M)
    if (event is KeyDownEvent &&
        matchesShortcut(event, AppShortcutId.toggleFullScreen)) {
      if (onToggleFullScreen != null) {
        onToggleFullScreen!();
        return KeyEventResult.handled;
      }
    }

    if (event is KeyDownEvent &&
        matchesShortcut(event, AppShortcutId.miniPlayer)) {
      if (onEnterMiniPlayer != null) {
        onEnterMiniPlayer!();
        return KeyEventResult.handled;
      }
    }

    // 3. Shortcuts cheat sheet (? or Ctrl + /), ignored in text fields & dialogs
    if (event is KeyDownEvent &&
        !_isEditableTextFocused() &&
        !_isPopupOrDialogFocused() &&
        isShortcutsCheatSheetOpen?.call() != true &&
        (matchesShortcut(event, AppShortcutId.shortcutsHelp) ||
            matchesShortcut(event, AppShortcutId.shortcutsHelpCtrl))) {
      if (onShowShortcutsCheatSheet != null) {
        onShowShortcutsCheatSheet!();
        return KeyEventResult.handled;
      }
    }

    // 4. Global Ctrl + Up / Down volume control (60ms repeat throttle)
    final isCtrlVolUp = matchesShortcut(event, AppShortcutId.volumeUp);
    final isCtrlVolDown = matchesShortcut(event, AppShortcutId.volumeDown);
    if (isCtrlVolUp || isCtrlVolDown) {
      final delta = isCtrlVolUp ? 0.05 : -0.05;
      if (event is KeyDownEvent) {
        _stepVolume(delta);
        _armVolumeCooldown();
        return KeyEventResult.handled;
      }
      if (event is KeyRepeatEvent) {
        if (_volumeCooldownTimer == null) {
          _stepVolume(delta);
          _armVolumeCooldown();
        }
        return KeyEventResult.handled;
      }
    }

    // 5. Plain ArrowUp / ArrowDown volume control ONLY in Full Screen & Mini Player
    if (isArrowUpKey(event) || isArrowDownKey(event)) {
      final isPlainUp = matchesShortcut(event, AppShortcutId.overlayVolumeUp);
      final isPlainDown =
          matchesShortcut(event, AppShortcutId.overlayVolumeDown);
      if ((isPlainUp || isPlainDown) &&
          isInFullScreenOrMini() &&
          !_isDeepWidgetConsumed(isArrow: true)) {
        final delta = isPlainUp ? 0.05 : -0.05;
        if (event is KeyDownEvent) {
          _stepVolume(delta);
          _armVolumeCooldown();
          return KeyEventResult.handled;
        }
        if (event is KeyRepeatEvent) {
          if (_volumeCooldownTimer == null) {
            _stepVolume(delta);
            _armVolumeCooldown();
          }
          return KeyEventResult.handled;
        }
      }
      if (event is KeyUpEvent && _volumeCooldownTimer != null) {
        _volumeCooldownTimer?.cancel();
        _volumeCooldownTimer = null;
      }
    }

    // 6. Media keys & Ctrl + Left / Right track skips
    if (event is KeyDownEvent) {
      if (matchesShortcut(event, AppShortcutId.mediaPlayPause)) {
        controller.togglePlayPause();
        return KeyEventResult.handled;
      }
      if (matchesShortcut(event, AppShortcutId.nextTrack) ||
          matchesShortcut(event, AppShortcutId.mediaNext)) {
        controller.skipNext();
        return KeyEventResult.handled;
      }
      if (matchesShortcut(event, AppShortcutId.previousTrack) ||
          matchesShortcut(event, AppShortcutId.mediaPrevious)) {
        controller.skipPrevious();
        return KeyEventResult.handled;
      }
    }

    // 7. Space play/pause toggle (fires on key up if not consumed as a chord)
    if (isSpaceKey(event)) {
      if (_isDeepWidgetConsumed(isArrow: false)) {
        _resetSpaceState();
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent) {
        _isSpaceDown = true;
        _spaceChordUsed = false;
        return KeyEventResult.handled;
      } else if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        final wasDown = _isSpaceDown;
        final chordUsed = _spaceChordUsed;
        _resetSpaceState();
        if (wasDown && !chordUsed) {
          controller.togglePlayPause();
        }
        return KeyEventResult.handled;
      }
    }

    // 8. Left / Right arrows (Space chord skip, or 120ms-throttled seek)
    if (isArrowLeftKey(event) || isArrowRightKey(event)) {
      final isRight = isArrowRightKey(event);

      if (_isSpaceDown) {
        if (event is KeyDownEvent) {
          if (isRight) {
            controller.skipNext();
          } else {
            controller.skipPrevious();
          }
          _spaceChordUsed = true;
          return KeyEventResult.handled;
        } else if (event is KeyRepeatEvent || event is KeyUpEvent) {
          return KeyEventResult.handled;
        }
      }

      if (matchesShortcut(event, AppShortcutId.seekForward) ||
          matchesShortcut(event, AppShortcutId.seekBackward)) {
        if (_isDeepWidgetConsumed(isArrow: true)) {
          _arrowHeldDirection = 0;
          _seekCooldownTimer?.cancel();
          _seekCooldownTimer = null;
          return KeyEventResult.ignored;
        }

        final direction = isRight ? 1 : -1;
        final stepSeconds = settingsStore.settings.seekStepSeconds;
        final delta = Duration(seconds: direction * stepSeconds);

        if (event is KeyDownEvent) {
          _arrowHeldDirection = direction;
          _performSeek(delta);
          _armSeekCooldown();
          return KeyEventResult.handled;
        } else if (event is KeyRepeatEvent) {
          if (_seekCooldownTimer == null) {
            _performSeek(delta);
            _armSeekCooldown();
          }
          return KeyEventResult.handled;
        }
      }

      if (event is KeyUpEvent && _arrowHeldDirection != 0) {
        _arrowHeldDirection = 0;
        _seekCooldownTimer?.cancel();
        _seekCooldownTimer = null;
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }
}
