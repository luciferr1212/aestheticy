import 'dart:async';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../diagnostics/app_logger.dart';
import '../../library/cover_cache.dart';
import '../../platform/media_session_service.dart';
import '../../ui/artist_names/artist_name_store.dart';
import '../../ui/settings/settings_store.dart';

/// Pure-Dart controller bridging [PlaybackController] to [MediaSessionService].
///
/// Throttles timeline progress, resolves artist display names with active localization,
/// resolves cached cover artwork, and translates OS/hardware media keys into playback commands.
class MediaSessionController {
  final PlaybackController playbackController;
  final MediaSessionService mediaSessionService;
  final SettingsStore settingsStore;
  final ArtistNameStore artistNameStore;
  final DateTime Function() clock;

  final List<StreamSubscription<dynamic>> _subs = [];
  DateTime? _lastTimelineUpdate;
  bool _lastMediaControlsEnabled = true;
  bool _isAvailable = true;
  bool _disposed = false;

  /// Whether the media session service is operational without unhandled plugin errors.
  bool get isAvailable => _isAvailable;

  /// Whether media controls integration is currently enabled by user preference.
  bool get isEnabled => settingsStore.settings.mediaControls;

  /// Creates and initializes a [MediaSessionController].
  MediaSessionController({
    required this.playbackController,
    required this.mediaSessionService,
    required this.settingsStore,
    required this.artistNameStore,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    _lastMediaControlsEnabled = settingsStore.settings.mediaControls;

    _subs.add(mediaSessionService.buttons.listen(
      _onMediaButton,
      onError: (Object error, StackTrace stackTrace) {
        _isAvailable = false;
        AppLogger.instance.warning(
          'MediaSession',
          'Media button stream error: $error',
          error,
          stackTrace,
        );
      },
    ));

    _subs.add(playbackController.currentStream.listen(_onCurrentTrackChanged));
    _subs.add(playbackController.stateStream.listen(_onPlaybackStateChanged));
    _subs.add(playbackController.seekStream.listen((_) => _pushTimeline(immediate: true)));
    _subs.add(playbackController.engine.positionStream.listen((_) => _pushTimeline(immediate: false)));
    _subs.add(playbackController.engine.durationStream.listen((_) => _pushTimeline(immediate: false)));

    settingsStore.addListener(_onSettingsChanged);

    if (_lastMediaControlsEnabled) {
      unawaited(_safeInitAndSync());
    }
  }

  Future<void> _safeInitAndSync() async {
    try {
      await mediaSessionService.initialize();
      _isAvailable = true;
      await syncCurrentState();
    } catch (error, stackTrace) {
      _isAvailable = false;
      AppLogger.instance.warning(
        'MediaSession',
        'Failed to initialize media session: $error',
        error,
        stackTrace,
      );
    }
  }

  void _onSettingsChanged() {
    if (_disposed) return;
    final enabled = settingsStore.settings.mediaControls;
    if (enabled == _lastMediaControlsEnabled) return;
    _lastMediaControlsEnabled = enabled;

    if (!enabled) {
      unawaited(_safeDisable());
    } else {
      unawaited(_safeInitAndSync());
    }
  }

  Future<void> _safeDisable() async {
    try {
      await mediaSessionService.disable();
    } catch (error, stackTrace) {
      _isAvailable = false;
      AppLogger.instance.warning(
        'MediaSession',
        'Failed to disable media session: $error',
        error,
        stackTrace,
      );
    }
  }

  void _onMediaButton(MediaButton button) {
    if (_disposed || !settingsStore.settings.mediaControls) return;
    try {
      switch (button) {
        case MediaButton.play:
          playbackController.play();
        case MediaButton.pause:
          playbackController.pause();
        case MediaButton.next:
          playbackController.skipNext();
        case MediaButton.previous:
          playbackController.skipPrevious();
        case MediaButton.stop:
          playbackController.stop();
      }
    } catch (error, stackTrace) {
      AppLogger.instance.warning(
        'MediaSession',
        'Error handling media button: $error',
        error,
        stackTrace,
      );
    }
  }

  void _onCurrentTrackChanged(AudioSource? source) {
    if (_disposed || !settingsStore.settings.mediaControls) return;
    _pushMetadata(source);
    _pushTimeline(immediate: true);
  }

  void _pushMetadata(AudioSource? source) {
    if (source == null) {
      unawaited(_setMetadataSafe(
        title: '',
        artist: '',
        album: '',
        coverPath: null,
      ));
      return;
    }

    final extras = source.extras;
    final title = extras?['title'] ?? '';
    final rawArtist = extras?['artist'] ?? '';
    final resolvedArtist = artistNameStore.displayArtist(
      rawArtist,
      settings: settingsStore.settings,
    );
    final album = extras?['album'] ?? '';
    final coverKey = extras?['coverKey'];

    String? coverPath;
    if (coverKey != null && coverKey.isNotEmpty) {
      try {
        if (CoverCache.hasCover(coverKey)) {
          coverPath = CoverCache.pathFor(coverKey);
        }
      } catch (_) {
        coverPath = null;
      }
    }

    unawaited(_setMetadataSafe(
      title: title,
      artist: resolvedArtist,
      album: album,
      coverPath: coverPath,
    ));
  }

  Future<void> _setMetadataSafe({
    required String title,
    required String artist,
    required String album,
    String? coverPath,
  }) async {
    try {
      await mediaSessionService.setMetadata(
        title: title,
        artist: artist,
        album: album,
        coverPath: coverPath,
      );
    } catch (error, stackTrace) {
      _isAvailable = false;
      AppLogger.instance.warning(
        'MediaSession',
        'Failed to set media metadata: $error',
        error,
        stackTrace,
      );
    }
  }

  void _onPlaybackStateChanged(PlaybackState state) {
    if (_disposed || !settingsStore.settings.mediaControls) return;
    final status = switch (state) {
      PlaybackState.playing => MediaPlaybackStatus.playing,
      PlaybackState.paused => MediaPlaybackStatus.paused,
      PlaybackState.idle ||
      PlaybackState.loading ||
      PlaybackState.completed ||
      PlaybackState.error =>
        MediaPlaybackStatus.stopped,
    };

    unawaited(_setStatusSafe(status));
    if (state == PlaybackState.paused) {
      _pushTimeline(immediate: true);
    }
  }

  Future<void> _setStatusSafe(MediaPlaybackStatus status) async {
    try {
      await mediaSessionService.setPlaybackStatus(status);
    } catch (error, stackTrace) {
      _isAvailable = false;
      AppLogger.instance.warning(
        'MediaSession',
        'Failed to set playback status: $error',
        error,
        stackTrace,
      );
    }
  }

  void _pushTimeline({required bool immediate}) {
    if (_disposed || !settingsStore.settings.mediaControls) return;

    final now = clock();
    if (!immediate && _lastTimelineUpdate != null) {
      final elapsed = now.difference(_lastTimelineUpdate!).inMilliseconds;
      if (elapsed < 1000) {
        return;
      }
    }

    _lastTimelineUpdate = now;
    final position = playbackController.currentPosition;
    final duration = playbackController.currentDuration;

    unawaited(_setTimelineSafe(position: position, duration: duration));
  }

  Future<void> _setTimelineSafe({
    required Duration position,
    required Duration duration,
  }) async {
    try {
      await mediaSessionService.setTimeline(
        position: position,
        duration: duration,
      );
    } catch (error, stackTrace) {
      _isAvailable = false;
      AppLogger.instance.warning(
        'MediaSession',
        'Failed to set timeline: $error',
        error,
        stackTrace,
      );
    }
  }

  /// Pushes the current track metadata, playback status, and timeline to the media session.
  Future<void> syncCurrentState() async {
    if (_disposed || !settingsStore.settings.mediaControls) return;
    _pushMetadata(playbackController.queue.current);
    _onPlaybackStateChanged(playbackController.currentState);
    _pushTimeline(immediate: true);
  }

  /// Disposes of all stream subscriptions and releases resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    settingsStore.removeListener(_onSettingsChanged);
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }
}
