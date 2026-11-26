import 'dart:async';
import 'dart:math';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/sqlite_identity_store.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

class _PlaybackSession {
  final AudioSource source;
  final String playSource;
  final DateTime startedAt;
  String? trackUid;
  int? durationMs;
  int accumulatedMs = 0;
  DateTime? playSegmentStartTime;
  bool isCounted = false;
  int? playEventId;
  Future<int>? insertFuture;
  bool isCompleted = false;

  _PlaybackSession({
    required this.source,
    required this.playSource,
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

/// Records listening history sessions, periodic heartbeats, and scrobble-like
/// play counts into the user-data repository.
class PlayRecorder {
  /// Default interval for crash-safety heartbeat updates while playing.
  static const Duration kDefaultHeartbeatInterval = Duration(seconds: 30);

  final PlaybackController? controller;
  final LibraryRepository repository;
  final DateTime Function() clock;
  final AppLogger? logger;

  /// Random per-app-run session identifier attached to every recorded event.
  final String sessionId;

  /// Interval at which [sendHeartbeat] persists `listened_ms` during playback.
  final Duration heartbeatInterval;

  final List<StreamSubscription<dynamic>> _subs = [];
  _PlaybackSession? _session;
  AudioSource? _lastSource;
  PlaybackState _currentState = PlaybackState.idle;
  Timer? _thresholdTimer;
  Timer? _heartbeatTimer;
  bool _disposed = false;
  bool _loggedReadOnlyWarning = false;

  /// Creates a [PlayRecorder] connected to controller or streams.
  PlayRecorder({
    this.controller,
    Stream<AudioSource?>? currentStream,
    Stream<PlaybackState>? stateStream,
    Stream<Duration>? durationStream,
    Stream<Duration>? positionStream,
    Stream<AudioError>? errorStream,
    required this.repository,
    DateTime Function()? clock,
    AppLogger? logger,
    String? sessionId,
    this.heartbeatInterval = kDefaultHeartbeatInterval,
  })  : clock = clock ?? DateTime.now,
        logger = logger ?? AppLogger.instance,
        sessionId = sessionId ?? SqliteIdentityStore.generateUid() {
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
    final effectiveErrorStream = errorStream ?? controller?.errorStream;

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
    if (effectiveErrorStream != null) {
      _subs.add(effectiveErrorStream.listen(_onPlaybackError));
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
      // Switching to a different track (or null) before natural completion.
      if (source == null || source.uri != _session!.source.uri) {
        _endSession(endedReason: source == null ? 'stopped' : 'skipped');
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
        // Can occur on repeat-one or replay when currentStream doesn't re-emit.
        _startSession(_lastSource!);
      }
      _session?.onPlayingStarted(now);
      _scheduleThresholdTimer();
      _startHeartbeatTimer();
      _checkThresholdInternal();
    } else if (previousState == PlaybackState.playing) {
      _session?.onPlayingPausedOrStopped(now);
      _thresholdTimer?.cancel();
      _heartbeatTimer?.cancel();
      _checkThresholdInternal();
    }

    if (state == PlaybackState.completed) {
      if (_session != null) {
        _session!.isCompleted = true;
        _endSession(endedReason: 'completed');
      }
    } else if (state == PlaybackState.idle) {
      if (_session != null) {
        _endSession(endedReason: 'stopped');
      }
    }
  }

  void _onPlaybackError(AudioError _) {
    if (_disposed || _session == null) return;
    _endSession(endedReason: 'error');
  }

  void _onDurationChanged(Duration duration) {
    if (_session != null && duration.inMilliseconds > 0) {
      if (_session!.durationMs == null || _session!.durationMs! <= 0) {
        _session!.durationMs = duration.inMilliseconds;
        _scheduleThresholdTimer();
        _checkThresholdInternal();
      }
    }
  }

  void _startSession(AudioSource source) {
    int? durMs;
    final extras = source.extras;
    if (extras != null && extras.containsKey('durationMs')) {
      durMs = int.tryParse(extras['durationMs'] ?? '');
    }

    final sess = _PlaybackSession(
      source: source,
      playSource: controller?.currentPlaySource ?? 'unknown',
      startedAt: clock().toUtc(),
      durationMs: durMs,
    );
    _session = sess;

    unawaited(
      repository.resolveTrackUid(source.uri).then((uid) {
        sess.trackUid = uid;
      }).catchError((_) {}),
    );

    if (_isPlaying) {
      sess.onPlayingStarted(clock());
      _scheduleThresholdTimer();
      _startHeartbeatTimer();
    }
  }

  /// Checks whether the listening threshold has been crossed and persists if so.
  void checkThreshold() {
    _syncWithController();
    _checkThresholdInternal();
  }

  void _checkThresholdInternal() {
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

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    if (_disposed || _session == null || heartbeatInterval <= Duration.zero) {
      return;
    }
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      unawaited(sendHeartbeat());
    });
  }

  /// Persists the current accumulated listening duration for crash safety.
  ///
  /// Invoked automatically every [heartbeatInterval] while playing, and
  /// callable directly from tests.
  Future<void> sendHeartbeat() async {
    final sess = _session;
    if (_disposed || sess == null) return;

    final listened = sess.currentListenedMs(clock(), _isPlaying);
    if (repository.userDataAccessMode == UserDataAccessMode.safeReadOnly) {
      _logReadOnlySkipOnce();
      return;
    }

    try {
      final existingId = sess.playEventId ??
          (sess.insertFuture != null ? await sess.insertFuture! : null);
      if (existingId != null && existingId > 0) {
        await repository.updatePlayEventHeartbeat(existingId, listened);
        return;
      }

      if (sess.insertFuture == null) {
        final event = _buildEvent(
          sess,
          listenedMs: listened,
          counted: sess.isCounted,
          completed: sess.isCompleted,
          endedReason: null,
        );
        sess.insertFuture = repository.insertPlayEvent(event).then((id) {
          sess.playEventId = id;
          return id;
        }).catchError((Object e, StackTrace st) {
          logger?.error('PlayRecorder', 'Failed to insert heartbeat row: $e', e, st);
          return -1;
        });
        await sess.insertFuture;
      }
    } catch (e, st) {
      logger?.error('PlayRecorder', 'Heartbeat update failed: $e', e, st);
    }
  }

  void _logReadOnlySkipOnce() {
    if (_loggedReadOnlyWarning) return;
    _loggedReadOnlyWarning = true;
    logger?.warning(
      'PlayRecorder',
      'Play event recording skipped silently: user data is in safe read-only mode',
    );
  }

  PlayEvent _buildEvent(
    _PlaybackSession sess, {
    required int listenedMs,
    required bool counted,
    required bool completed,
    required String? endedReason,
  }) {
    final source = sess.source;
    final extras = source.extras;
    return PlayEvent(
      uri: source.uri,
      title: extras?['title'],
      artist: extras?['artist'],
      album: extras?['album'],
      albumArtist: extras?['albumArtist'],
      durationMs: sess.durationMs,
      startedAt: sess.startedAt,
      listenedMs: listenedMs,
      counted: counted,
      completed: completed,
      trackUid: sess.trackUid,
      source: sess.playSource,
      sessionId: sessionId,
      endedReason: endedReason,
    );
  }

  void _markCounted(int listenedMs) {
    final sess = _session;
    if (sess == null || sess.isCounted) return;
    sess.isCounted = true;
    _thresholdTimer?.cancel();

    if (repository.userDataAccessMode == UserDataAccessMode.safeReadOnly) {
      _logReadOnlySkipOnce();
      return;
    }

    if (sess.playEventId != null || sess.insertFuture != null) {
      unawaited(
        Future<void>(() async {
          try {
            final id = sess.playEventId ?? await sess.insertFuture;
            if (id != null && id > 0) {
              await repository.updatePlayEvent(
                id,
                listenedMs: listenedMs,
                counted: true,
                completed: sess.isCompleted,
              );
            }
          } catch (e, st) {
            logger?.error('PlayRecorder', 'Failed to update counted row: $e', e, st);
          }
        }),
      );
      return;
    }

    final event = _buildEvent(
      sess,
      listenedMs: listenedMs,
      counted: true,
      completed: sess.isCompleted,
      endedReason: null,
    );

    sess.insertFuture = repository.insertPlayEvent(event).then((id) {
      sess.playEventId = id;
      return id;
    }).catchError((Object e, StackTrace st) {
      logger?.error('PlayRecorder', 'Failed to insert counted play event: $e', e, st);
      return -1;
    });
  }

  void _endSession({String endedReason = 'stopped'}) {
    final sess = _session;
    if (sess == null) return;
    _session = null;
    _thresholdTimer?.cancel();
    _heartbeatTimer?.cancel();

    final now = clock();
    sess.onPlayingPausedOrStopped(now);
    final listened = sess.accumulatedMs;

    if (sess.isCounted || sess.playEventId != null || sess.insertFuture != null) {
      if (repository.userDataAccessMode == UserDataAccessMode.safeReadOnly) {
        _logReadOnlySkipOnce();
        return;
      }
      Future<void> updateOp() async {
        try {
          final id = sess.playEventId ?? await sess.insertFuture;
          if (id != null && id > 0) {
            await repository.updatePlayEvent(
              id,
              listenedMs: listened,
              counted: sess.isCounted,
              completed: sess.isCompleted,
              endedReason: endedReason,
            );
          }
        } catch (e, st) {
          logger?.error('PlayRecorder', 'Failed to update play event: $e', e, st);
        }
      }

      unawaited(updateOp());
    } else if (listened >= 5000) {
      if (repository.userDataAccessMode == UserDataAccessMode.safeReadOnly) {
        _logReadOnlySkipOnce();
        return;
      }
      final event = _buildEvent(
        sess,
        listenedMs: listened,
        counted: false,
        completed: sess.isCompleted,
        endedReason: endedReason,
      );

      unawaited(
        repository.insertPlayEvent(event).catchError((Object e, StackTrace st) {
          logger?.error('PlayRecorder', 'Failed to insert uncounted play event: $e', e, st);
          return -1;
        }),
      );
    }
  }

  /// Cleanly ends active session, cancels timers, and cancels all listeners.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _thresholdTimer?.cancel();
    _heartbeatTimer?.cancel();
    _endSession(endedReason: 'stopped');
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }
}
