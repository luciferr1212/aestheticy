import 'dart:async';
import 'dart:ui';

import 'file_association_service.dart';
import 'media_session_service.dart';
import 'sleep_inhibitor.dart';
import 'tray_service.dart';
import 'window_service.dart';

/// Production no-op [MediaSessionService] used on non-Windows platforms.
class NoopMediaSessionService implements MediaSessionService {
  final StreamController<MediaButton> _buttons =
      StreamController<MediaButton>.broadcast();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setMetadata({
    required String title,
    required String artist,
    required String album,
    String? coverPath,
  }) async {}

  @override
  Future<void> setPlaybackStatus(MediaPlaybackStatus status) async {}

  @override
  Future<void> setTimeline({
    required Duration position,
    required Duration duration,
  }) async {}

  @override
  Stream<MediaButton> get buttons => _buttons.stream;

  @override
  Future<void> disable() async {}

  @override
  Future<void> dispose() async {
    await _buttons.close();
  }
}

/// Production no-op [SleepInhibitor] used on non-Windows platforms.
class NoopSleepInhibitor implements SleepInhibitor {
  @override
  void acquire() {}

  @override
  void release() {}
}

/// Production no-op [TrayService] used on non-Windows platforms.
class NoopTrayService implements TrayService {
  final StreamController<TrayEvent> _events =
      StreamController<TrayEvent>.broadcast();

  @override
  bool get isVisible => false;

  @override
  Future<bool> show({
    required TrayMenuLabels labels,
    String tooltip = 'Aestheticy',
  }) async =>
      false;

  @override
  Future<void> hide() async {}

  @override
  Future<void> updateMenu(TrayMenuLabels labels) async {}

  @override
  Stream<TrayEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

/// Production no-op [WindowService] used on non-Windows platforms.
class NoopWindowService implements WindowService {
  final StreamController<void> _close = StreamController<void>.broadcast();

  @override
  Future<void> setPreventClose(bool prevent) async {}

  @override
  Stream<void> get closeRequested => _close.stream;

  @override
  Future<void> show() async {}

  @override
  Future<void> hide() async {}

  @override
  Future<void> focus() async {}

  @override
  Future<void> destroy() async {}

  @override
  Future<WindowGeometry> getGeometry() async => const WindowGeometry(
        position: Offset.zero,
        size: Size(1280, 800),
        isMaximized: false,
        isFullScreen: false,
      );

  @override
  Future<void> applyGeometry(Offset position, Size size) async {}

  @override
  Future<void> setAlwaysOnTop(bool isAlwaysOnTop) async {}

  @override
  Future<void> setResizable(bool isResizable) async {}

  @override
  Future<void> setFullScreen(bool isFullScreen) async {}

  @override
  Future<void> maximize() async {}

  @override
  Future<void> unmaximize() async {}

  @override
  Future<Size> getDisplaySize() async => const Size(1920, 1080);

  @override
  Future<void> setFrameless(bool frameless) async {}

  @override
  Future<void> startDragging() async {}

  @override
  Future<void> dispose() async {
    await _close.close();
  }
}

/// Production no-op [FileAssociationService] used on non-Windows platforms.
class NoopFileAssociationService implements FileAssociationService {
  @override
  bool get isSupported => false;

  @override
  Future<bool> isRegistered(String extension) async => false;

  @override
  Future<bool> registerExtensions(List<String> extensions) async => false;
}
