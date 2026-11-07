import 'dart:async';

/// Abstract contract for managing window lifecycle, visibility, focus, and close interception.
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

  /// Disposes of window service listeners and controllers.
  Future<void> dispose();
}
