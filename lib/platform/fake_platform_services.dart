import 'dart:async';

import 'media_session_service.dart';
import 'sleep_inhibitor.dart';
import 'tray_service.dart';
import 'window_service.dart';

/// Test fake recording all interactions with [MediaSessionService].
class FakeMediaSessionService implements MediaSessionService {
  final List<String> calls = [];
  final StreamController<MediaButton> _buttonController =
      StreamController<MediaButton>.broadcast();

  bool isInitialized = false;
  bool isDisposed = false;
  bool isDisabled = false;

  String? lastTitle;
  String? lastArtist;
  String? lastAlbum;
  String? lastCoverPath;
  MediaPlaybackStatus? lastStatus;
  Duration? lastPosition;
  Duration? lastDuration;

  bool throwOnSetMetadata = false;
  bool throwOnSetPlaybackStatus = false;
  bool throwOnSetTimeline = false;

  @override
  Future<void> initialize() async {
    calls.add('initialize');
    isInitialized = true;
    isDisabled = false;
  }

  @override
  Future<void> setMetadata({
    required String title,
    required String artist,
    required String album,
    String? coverPath,
  }) async {
    if (throwOnSetMetadata) {
      throw StateError('Simulated setMetadata failure');
    }
    calls.add('setMetadata(title: $title, artist: $artist, album: $album, cover: $coverPath)');
    lastTitle = title;
    lastArtist = artist;
    lastAlbum = album;
    lastCoverPath = coverPath;
  }

  @override
  Future<void> setPlaybackStatus(MediaPlaybackStatus status) async {
    if (throwOnSetPlaybackStatus) {
      throw StateError('Simulated setPlaybackStatus failure');
    }
    calls.add('setPlaybackStatus(${status.name})');
    lastStatus = status;
  }

  @override
  Future<void> setTimeline({
    required Duration position,
    required Duration duration,
  }) async {
    if (throwOnSetTimeline) {
      throw StateError('Simulated setTimeline failure');
    }
    calls.add('setTimeline(pos: ${position.inMilliseconds}ms, dur: ${duration.inMilliseconds}ms)');
    lastPosition = position;
    lastDuration = duration;
  }

  @override
  Stream<MediaButton> get buttons => _buttonController.stream;

  /// Simulates a button press from OS media overlay or hardware key.
  void emitButton(MediaButton button) {
    _buttonController.add(button);
  }

  @override
  Future<void> disable() async {
    calls.add('disable');
    isDisabled = true;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    isDisposed = true;
    await _buttonController.close();
  }
}

/// Test fake recording interactions with [SleepInhibitor].
class FakeSleepInhibitor implements SleepInhibitor {
  final List<String> calls = [];
  bool isAcquired = false;

  @override
  void acquire() {
    calls.add('acquire');
    isAcquired = true;
  }

  @override
  void release() {
    calls.add('release');
    isAcquired = false;
  }
}

/// Test fake recording interactions with [TrayService].
class FakeTrayService implements TrayService {
  final List<String> calls = [];
  final StreamController<TrayEvent> _eventController =
      StreamController<TrayEvent>.broadcast();

  bool isVisible = false;
  bool isDisposed = false;
  TrayMenuLabels? currentLabels;
  String? currentTooltip;

  @override
  Future<void> show({
    required TrayMenuLabels labels,
    String tooltip = 'Aestheticy',
  }) async {
    calls.add('show(show: "${labels.show}", playPause: "${labels.playPause}", quit: "${labels.quit}")');
    isVisible = true;
    currentLabels = labels;
    currentTooltip = tooltip;
  }

  @override
  Future<void> hide() async {
    calls.add('hide');
    isVisible = false;
  }

  @override
  Future<void> updateMenu(TrayMenuLabels labels) async {
    calls.add('updateMenu(show: "${labels.show}", playPause: "${labels.playPause}", quit: "${labels.quit}")');
    currentLabels = labels;
  }

  @override
  Stream<TrayEvent> get events => _eventController.stream;

  /// Simulates a tray event (icon clicked or menu item chosen).
  void emitEvent(TrayEvent event) {
    _eventController.add(event);
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    isDisposed = true;
    await _eventController.close();
  }
}

/// Test fake recording interactions with [WindowService].
class FakeWindowService implements WindowService {
  final List<String> calls = [];
  final StreamController<void> _closeController =
      StreamController<void>.broadcast();

  bool isPreventClose = false;
  bool isVisible = true;
  bool isFocused = true;
  bool isDestroyed = false;
  bool isDisposed = false;

  @override
  Future<void> setPreventClose(bool prevent) async {
    calls.add('setPreventClose($prevent)');
    isPreventClose = prevent;
  }

  @override
  Stream<void> get closeRequested => _closeController.stream;

  /// Simulates the user requesting window close (e.g. clicking 'X' or pressing Alt+F4).
  void emitCloseRequested() {
    calls.add('onCloseRequested');
    _closeController.add(null);
  }

  @override
  Future<void> show() async {
    calls.add('show');
    isVisible = true;
  }

  @override
  Future<void> hide() async {
    calls.add('hide');
    isVisible = false;
  }

  @override
  Future<void> focus() async {
    calls.add('focus');
    isFocused = true;
  }

  @override
  Future<void> destroy() async {
    calls.add('destroy');
    isDestroyed = true;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    isDisposed = true;
    await _closeController.close();
  }
}
