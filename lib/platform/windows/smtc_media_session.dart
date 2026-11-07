import 'dart:async';
import 'dart:io';

import 'package:smtc_windows/smtc_windows.dart';

import '../../diagnostics/app_logger.dart';
import '../media_session_service.dart';

/// Real Windows implementation of [MediaSessionService] backed by `smtc_windows`.
class SmtcMediaSession implements MediaSessionService {
  SMTCWindows? _smtc;
  StreamSubscription<PressedButton>? _buttonSub;
  final StreamController<MediaButton> _buttonController =
      StreamController<MediaButton>.broadcast();

  bool _initialized = false;
  bool _available = true;

  /// Whether the native SMTC integration is operational.
  bool get isAvailable => _available;

  @override
  Future<void> initialize() async {
    if (!Platform.isWindows) return;
    try {
      if (!_initialized) {
        await SMTCWindows.initialize();
        _initialized = true;
      }

      _smtc ??= SMTCWindows(
        config: const SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          nextEnabled: true,
          prevEnabled: true,
          stopEnabled: true,
          fastForwardEnabled: false,
          rewindEnabled: false,
        ),
      );

      await _buttonSub?.cancel();
      _buttonSub = _smtc!.buttonPressStream.listen(
        _onButtonPressed,
        onError: (Object error, StackTrace stackTrace) {
          _available = false;
          AppLogger.instance.warning('SMTC', 'Button stream error: $error', error, stackTrace);
        },
      );

      await _smtc!.enableSmtc();
      _available = true;
    } catch (error, stackTrace) {
      _available = false;
      AppLogger.instance.warning('SMTC', 'Failed to initialize SMTC: $error', error, stackTrace);
    }
  }

  void _onButtonPressed(PressedButton button) {
    switch (button) {
      case PressedButton.play:
        _buttonController.add(MediaButton.play);
      case PressedButton.pause:
        _buttonController.add(MediaButton.pause);
      case PressedButton.next:
        _buttonController.add(MediaButton.next);
      case PressedButton.previous:
        _buttonController.add(MediaButton.previous);
      case PressedButton.stop:
        _buttonController.add(MediaButton.stop);
      default:
        break;
    }
  }

  @override
  Future<void> setMetadata({
    required String title,
    required String artist,
    required String album,
    String? coverPath,
  }) async {
    final smtc = _smtc;
    if (smtc == null || !_available) return;

    try {
      String? thumbnailUri;
      if (coverPath != null && coverPath.isNotEmpty) {
        try {
          final file = File(coverPath);
          if (file.existsSync()) {
            thumbnailUri = file.uri.toString();
          }
        } catch (_) {
          // Fallback to no thumbnail if file check fails
        }
      }

      await smtc.updateMetadata(
        MusicMetadata(
          title: title,
          artist: artist,
          album: album,
          albumArtist: artist,
          thumbnail: thumbnailUri,
        ),
      );
    } catch (error, stackTrace) {
      _available = false;
      AppLogger.instance.warning('SMTC', 'Failed to update metadata: $error', error, stackTrace);
    }
  }

  @override
  Future<void> setPlaybackStatus(MediaPlaybackStatus status) async {
    final smtc = _smtc;
    if (smtc == null || !_available) return;

    try {
      final nativeStatus = switch (status) {
        MediaPlaybackStatus.playing => PlaybackStatus.playing,
        MediaPlaybackStatus.paused => PlaybackStatus.paused,
        MediaPlaybackStatus.stopped => PlaybackStatus.stopped,
      };
      await smtc.setPlaybackStatus(nativeStatus);
    } catch (error, stackTrace) {
      _available = false;
      AppLogger.instance.warning('SMTC', 'Failed to update playback status: $error', error, stackTrace);
    }
  }

  @override
  Future<void> setTimeline({
    required Duration position,
    required Duration duration,
  }) async {
    final smtc = _smtc;
    if (smtc == null || !_available) return;

    try {
      await smtc.updateTimeline(
        PlaybackTimeline(
          positionMs: position.inMilliseconds,
          startTimeMs: 0,
          endTimeMs: duration.inMilliseconds,
          minSeekTimeMs: 0,
          maxSeekTimeMs: duration.inMilliseconds,
        ),
      );
    } catch (error, stackTrace) {
      _available = false;
      AppLogger.instance.warning('SMTC', 'Failed to update timeline: $error', error, stackTrace);
    }
  }

  @override
  Stream<MediaButton> get buttons => _buttonController.stream;

  @override
  Future<void> disable() async {
    final smtc = _smtc;
    if (smtc == null) return;
    try {
      await smtc.disableSmtc();
    } catch (error, stackTrace) {
      AppLogger.instance.warning('SMTC', 'Failed to disable SMTC: $error', error, stackTrace);
    }
  }

  @override
  Future<void> dispose() async {
    await _buttonSub?.cancel();
    _buttonSub = null;
    final smtc = _smtc;
    _smtc = null;
    if (smtc != null) {
      try {
        await smtc.dispose();
      } catch (error, stackTrace) {
        AppLogger.instance.warning('SMTC', 'Failed to dispose SMTC: $error', error, stackTrace);
      }
    }
    await _buttonController.close();
  }
}
