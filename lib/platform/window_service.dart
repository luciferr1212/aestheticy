import 'dart:async';
import 'dart:ui';

/// Signature for providing the active display size in logical pixels.
typedef DisplaySizeProvider = Size Function();

/// Immutable representation of the window's geometry and display state.
class WindowGeometry {
  /// The top-left position of the window on the desktop.
  final Offset position;

  /// The dimensions of the window in logical pixels.
  final Size size;

  /// Whether the window is currently maximized.
  final bool isMaximized;

  /// Whether the window is currently occupying the full screen.
  final bool isFullScreen;

  /// Creates a [WindowGeometry] snapshot.
  const WindowGeometry({
    required this.position,
    required this.size,
    required this.isMaximized,
    required this.isFullScreen,
  });

  /// Creates a copy of this geometry with updated properties.
  WindowGeometry copyWith({
    Offset? position,
    Size? size,
    bool? isMaximized,
    bool? isFullScreen,
  }) {
    return WindowGeometry(
      position: position ?? this.position,
      size: size ?? this.size,
      isMaximized: isMaximized ?? this.isMaximized,
      isFullScreen: isFullScreen ?? this.isFullScreen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WindowGeometry &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          size == other.size &&
          isMaximized == other.isMaximized &&
          isFullScreen == other.isFullScreen;

  @override
  int get hashCode => Object.hash(position, size, isMaximized, isFullScreen);

  @override
  String toString() =>
      'WindowGeometry(pos: $position, size: $size, maximized: $isMaximized, fullScreen: $isFullScreen)';
}

/// Abstract contract for managing window lifecycle, visibility, focus, and geometry.
abstract interface class WindowService {
  /// Enables or disables intercepting native window close requests.
  Future<void> setPreventClose(bool prevent);

  /// Stream of user-initiated close requests (e.g. titlebar 'X' click or Alt+F4).
  Stream<void> get closeRequested;

  /// Shows the application window and un-minimizes if needed.
  Future<void> show();

  /// Hides the application window without destroying it.
  Future<void> hide();

  /// Brings the application window to foreground focus.
  Future<void> focus();

  /// Closes and terminates the native application window.
  Future<void> destroy();

  /// Reads the current window geometry (position, size, maximized, fullscreen).
  Future<WindowGeometry> getGeometry();

  /// Applies a window geometry (position and size).
  Future<void> applyGeometry(Offset position, Size size);

  /// Sets whether the window is pinned always on top of other windows.
  Future<void> setAlwaysOnTop(bool isAlwaysOnTop);

  /// Sets whether the window can be manually resized by the user.
  Future<void> setResizable(bool isResizable);

  /// Sets whether the window is in fullscreen mode.
  Future<void> setFullScreen(bool isFullScreen);

  /// Maximizes the window.
  Future<void> maximize();

  /// Restores the window from a maximized state.
  Future<void> unmaximize();

  /// Reads the primary display size in logical pixels for window placement.
  Future<Size> getDisplaySize();

  /// Disposes of window service listeners and controllers.
  Future<void> dispose();
}
