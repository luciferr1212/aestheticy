import 'dart:async';

/// Supported media button commands originating from hardware media keys or OS media overlay.
enum MediaButton {
  play,
  pause,
  next,
  previous,
  stop,
}

/// Playback status reported to the OS media transport controls.
enum MediaPlaybackStatus {
  playing,
  paused,
  stopped,
}

/// Abstract contract for OS media transport controls and media key integration.
abstract interface class MediaSessionService {
  /// Initializes the underlying platform media session.
  Future<void> initialize();

  /// Updates media metadata displayed in the OS overlay.
  Future<void> setMetadata({
    required String title,
    required String artist,
    required String album,
    String? coverPath,
  });

  /// Updates current playback status (playing, paused, stopped).
  Future<void> setPlaybackStatus(MediaPlaybackStatus status);

  /// Updates playback position and track duration timeline.
  Future<void> setTimeline({
    required Duration position,
    required Duration duration,
  });

  /// Stream of user-initiated media transport button presses.
  Stream<MediaButton> get buttons;

  /// Temporarily hides or disables the media session controls without full destruction.
  Future<void> disable();

  /// Releases resources and unregisters the media session.
  Future<void> dispose();
}
