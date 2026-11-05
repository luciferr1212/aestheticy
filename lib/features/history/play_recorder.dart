import 'dart:async';
import 'dart:math';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';

class _PlaybackSession {
  final AudioSource source;
  final DateTime startedAt;
  int? durationMs;
  int accumulatedMs = 0;
  DateTime? playSegmentStartTime;
  bool isCounted = false;
  int? playEventId;
  Future<int>? insertFuture;
  bool isCompleted = false;

  _PlaybackSession({
    required this.source,
    required this.startedAt,
    this.durationMs,
  });

  void onPlayingStarted(DateTime now) {
    playSegmentStartTime = now;
  }

  void onPlayingPausedOrStopped(DateTime now) {
    if (playSegmentStartTime != null) {
      final delta = now.difference(playSegmentStartTime!).inMilliseconds;
      if (delta > 0) {
        accumulatedMs += delta;
      }
      playSegmentStartTime = null;
    }
  }

  int currentListenedMs(DateTime now, bool isCurrentlyPlaying) {
    if (isCurrentlyPlaying && playSegmentStartTime != null) {
      final delta = now.difference(playSegmentStartTime!).inMilliseconds;
      return accumulatedMs + (delta > 0 ? delta : 0);
    }
    return accumulatedMs;
  }
}

/// Records listening history sessions and scrobble-like play counts.
class PlayRecorder {
  final PlaybackController? controller;
  final LibraryRepository repository;
  final DateTime Function() clock;
  final AppLogger? logger;

  final List<StreamSubscription<dynamic>> _subs = [];
  _PlaybackSession? _session;
  AudioSource? _lastSource;
  PlaybackState _currentState = PlaybackState.idle;
  Timer? _thresholdTimer;
  bool _disposed = false;

  /// Creates a [PlayRecorder] connected to controller or streams.
  PlayRecorder({
    this.controller,
    Stream<AudioSource?>? currentStream,
    Stream<PlaybackState>? stateStream,
    Stream<Duration>? durationStream,
    Stream<Duration>? positionStream,
    required this.repository,
    DateTime Function()? clock,
    AppLogger? logger,
  })  : clock = clock ?? DateTime.now,
        logger = logger ?? AppLogger.instance {
    if (controller != null) {
      _currentState = controller!.currentState;
      if (controller!.queue.current != null) {
        _lastSource = controller!.queue.current;
        _startSession(_lastSource!);
      }
    }

    final effectiveCurrentStream = currentStream ?? controller?.currentStream;
    final effectiveStateStream = stateStream ?? controller?.stateStream;
    final effectiveDurationStream =
        durationStream ?? controller?.engine.durationStream;
    final effectivePositionStream =
        positionStream ?? controller?.engine.positionStream;

    if (effectiveCurrentStream != null) {
      _subs.add(effectiveCurrentStream.listen(_onCurrentTrackChanged));
    }
    if (effectiveStateStream != null) {
      _subs.add(effectiveStateStream.listen(_onPlaybackStateChanged));
    }
    if (effectiveDurationStream != null) {
      _subs.add(effectiveDurationStream.listen(_onDurationChanged));
    }
    if (effectivePositionStream != null) {
      _subs.add(effectivePositionStream.listen((_) => checkThreshold()));
    }
  }

  bool get _isPlaying {
    if (_currentState == PlaybackState.playing) return true;
    if (controller?.currentState == PlaybackState.playing) return true;
    return false;
  }

  /// Current session's accumulated listened milliseconds (visible for tests).
  int get currentListenedMs {
    _syncWithController();
    return _session?.currentListenedMs(clock(), _isPlaying) ?? 0;
  }

  /// Whether the active session has crossed the counting threshold.
  bool get isCurrentCounted {
    _syncWithController();
    return _session?.isCounted ?? false;
  }

  void _syncWithController() {
    if (controller == null || _disposed) return;
    final cCurrent = controller!.queue.current;
    if (cCurrent != null) {
      if (_session == null || _session!.source.uri != cCurrent.uri) {
        _onCurrentTrackChanged(cCurrent);
      }
    }
    final cState = controller!.currentState;
    if (cState != _currentState) {
      _onPlaybackStateChanged(cState);
    }
  }

  void _onCurrentTrackChanged(AudioSource? source) {
    if (_disposed) return;
    _lastSource = source;

    if (_session != null) {
      // If the current track changed to a different URI (or null), end the active session.
      if (source == null || source.uri != _session!.source.uri) {
        _endSession();
      }
    }

    if (source != null && _session == null) {
      _startSession(source);
    }
  }

  void _onPlaybackStateChanged(PlaybackState state) {
    if (_disposed) return;

    final previousState = _currentState;
    _currentState = state;

    final now = clock();

    if (state == PlaybackState.playing) {
      if (_session == null && _lastSource != null) {
        // Can occur on repeat-one or replay when currentStream doesn't re-emit
        _startSession(_lastSource!);
      }
      _session?.onPlayingStarted(now);
      _scheduleThresholdTimer();
      checkThreshold();
    } else if (previousState == PlaybackState.playing) {
      _session?.onPlayingPausedOrStopped(now);
      _thresholdTimer?.cancel();
      checkThreshold();
    }

    if (state == PlaybackState.completed) {
      if (_session != null) {
        _session!.isCompleted = true;
        _endSession();
      }
    } else if (state == PlaybackState.idle) {
      if (_session != null) {
        _endSession();
      }
    }
  }

  void _onDurationChanged(Duration duration) {
    if (_session != null && duration.inMilliseconds > 0) {
      if (_session!.durationMs == null || _session!.durationMs! <= 0) {
        _session!.durationMs = duration.inMilliseconds;
        _scheduleThresholdTimer();
        checkThreshold();
      }
    }
  }

  void _startSession(AudioSource source) {
    int? durMs;
    final extras = source.extras;
    if (extras != null && extras.containsKey('durationMs')) {
      durMs = int.tryParse(extras['durationMs'] ?? '');
    }

    _session = _PlaybackSession(
      source: source,
      startedAt: clock().toUtc(),
      durationMs: durMs,
    );

    if (_isPlaying) {
      _session!.onPlayingStarted(clock());
      _scheduleThresholdTimer();
    }
  }

  /// Checks whether the listening threshold has been crossed and persists if so.
  void checkThreshold() {
    _syncWithController();
    if (_disposed || _session == null || _session!.isCounted) return;

    final dur = _session!.durationMs;
    // Rule: track duration must be known and at least 30 seconds
    if (dur == null || dur < 30000) return;

    final thresholdMs = min(dur ~/ 2, 240000);
    final now = clock();
    final listened = _session!.currentListenedMs(now, _isPlaying);

    if (listened >= thresholdMs) {
      _markCounted(listened);
    }
  }

  void _scheduleThresholdTimer() {
    _thresholdTimer?.cancel();
    if (_disposed || _session == null || _session!.isCounted) return;

    final dur = _session!.durationMs;
    if (dur == null || dur < 30000) return;

    final thresholdMs = min(dur ~/ 2, 240000);
    final now = clock();
    final listened =
        _session!.currentListenedMs(now, _currentState == PlaybackState.playing);
    final remainingMs = thresholdMs - listened;

    if (remainingMs <= 0) {
      _markCounted(listened);
    } else {
      _thresholdTimer = Timer(Duration(milliseconds: remainingMs), () {
        checkThreshold();
      });
    }
  }

  void _markCounted(int listenedMs) {
    final sess = _session;
    if (sess == null || sess.isCounted) return;
    sess.isCounted = true;
    _thresholdTimer?.cancel();

    final source = sess.source;
    final extras = source.extras;
    final event = PlayEvent(
      uri: source.uri,
      title: extras?['title'],
      artist: extras?['artist'],
      album: extras?['album'],
      albumArtist: extras?['albumArtist'],
      durationMs: sess.durationMs,
      startedAt: sess.startedAt,
      listenedMs: listenedMs,
      counted: true,
      completed: sess.isCompleted,
    );

    sess.insertFuture = repository.insertPlayEvent(event).then((id) {
      sess.playEventId = id;
      return id;
    }).catchError((Object e, StackTrace st) {
      logger?.error('PlayRecorder', 'Failed to insert counted play event: $e', e, st);
      return -1;
    });
  }

  void _endSession() {
    final sess = _session;
    if (sess == null) return;
    _session = null;
    _thresholdTimer?.cancel();

    final now = clock();
    sess.onPlayingPausedOrStopped(now);
    final listened = sess.accumulatedMs;

    if (sess.isCounted) {
      // Already counted row: wait for insert to finish if needed, then update
      Future<void> updateOp() async {
        try {
          final id = sess.playEventId ?? await sess.insertFuture;
          if (id != null && id > 0) {
            await repository.updatePlayEvent(
              id,
              listenedMs: listened,
              counted: true,
              completed: sess.isCompleted,
            );
          }
        } catch (e, st) {
          logger?.error('PlayRecorder', 'Failed to update play event: $e', e, st);
        }
      }

      unawaited(updateOp());
    } else if (listened >= 5000) {
      // Did not cross threshold, but listened for at least 5 seconds
      final source = sess.source;
      final extras = source.extras;
      final event = PlayEvent(
        uri: source.uri,
        title: extras?['title'],
        artist: extras?['artist'],
        album: extras?['album'],
        albumArtist: extras?['albumArtist'],
        durationMs: sess.durationMs,
        startedAt: sess.startedAt,
        listenedMs: listened,
        counted: false,
        completed: sess.isCompleted,
      );

      unawaited(
        repository.insertPlayEvent(event).catchError((Object e, StackTrace st) {
          logger?.error('PlayRecorder', 'Failed to insert uncounted play event: $e', e, st);
          return -1;
        }),
      );
    }
  }

  /// Cleanly ends active session and cancels all stream listeners.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _thresholdTimer?.cancel();
    _endSession();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }
}
