/// High-level playback controller: wires [AudioEngine] + [PlaybackQueue].
///
/// Pure Dart — depends only on the abstract [AudioEngine] and the
/// pure-Dart [PlaybackQueue]. No audio-package imports.
library;

import 'dart:async';

import 'audio_engine.dart';
import 'audio_models.dart';
import 'playback_queue.dart';

/// Coordinates the [AudioEngine] with a [PlaybackQueue]: auto-advances
/// tracks, preloads the next item for gapless transitions, and skips
/// past errors without crashing.
class PlaybackController {
  /// The underlying audio engine (real or fake).
  final AudioEngine engine;

  /// The playback queue.
  final PlaybackQueue queue;

  final List<StreamSubscription<dynamic>> _subs = [];

  final _stateCtrl = StreamController<PlaybackState>.broadcast();
  final _currentCtrl = StreamController<AudioSource?>.broadcast();
  final _errorCtrl = StreamController<AudioError>.broadcast();

  PlaybackState _currentState = PlaybackState.idle;
  Duration _currentPosition = Duration.zero;
  String? _openedUri;
  String? _lastEmittedUri;
  int _consecutiveFatalErrors = 0;
  bool _isAdvancing = false;
  bool _disposed = false;

  /// Creates a controller wired to [engine] and [queue].
  ///
  /// Call [init] before using.
  PlaybackController({required this.engine, required this.queue});

  // ── Lifecycle ───────────────────────────────────────────────────────

  /// Initializes the controller and starts listening to engine events.
  Future<void> init() async {
    _subs.add(engine.playbackStateStream.listen(_onPlaybackState));
    _subs.add(engine.positionStream.listen((pos) {
      _currentPosition = pos;
      if (pos > Duration.zero) {
        _consecutiveFatalErrors = 0;
      }
    }));
    _subs.add(engine.errorStream.listen(_onError));
  }

  /// Tears down subscriptions. Does **not** dispose the engine.
  Future<void> dispose() async {
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _stateCtrl.close();
    await _currentCtrl.close();
    await _errorCtrl.close();
  }

  // ── Streams ─────────────────────────────────────────────────────────

  /// The playback state of the currently playing track.
  Stream<PlaybackState> get stateStream => _stateCtrl.stream;

  /// Current playback state snapshot.
  PlaybackState get currentState => _currentState;

  /// Emits whenever the current track changes (including `null` when
  /// the queue ends).
  Stream<AudioSource?> get currentStream => _currentCtrl.stream;

  /// Errors that occurred during playback.
  Stream<AudioError> get errorStream => _errorCtrl.stream;

  // ── Transport ───────────────────────────────────────────────────────

  /// Starts playback from the current queue position, or resumes if paused.
  Future<void> play() async {
    _consecutiveFatalErrors = 0;
    final source = queue.current;
    if (source == null) return;

    // When paused on the same track, simply resume playback without re-opening.
    if (_currentState == PlaybackState.paused && _openedUri == source.uri) {
      await engine.play();
      return;
    }

    _openedUri = source.uri;
    await engine.open(source, autoPlay: true);
    _emitCurrent(source);
    unawaited(_preloadNext());
  }

  /// Toggles between play and pause.
  Future<void> togglePlayPause() async {
    if (_currentState == PlaybackState.playing) {
      await pause();
    } else {
      await play();
    }
  }

  /// Starts the queue from scratch at index 0.
  Future<void> playFromStart() async {
    _consecutiveFatalErrors = 0;
    if (queue.isEmpty) return;
    queue.jumpTo(0);
    await play();
  }

  /// Jumps to track at [index] in active playback order and starts playback.
  Future<void> playTrack(int index) async {
    _consecutiveFatalErrors = 0;
    if (index < 0 || index >= queue.length) return;
    queue.jumpTo(index);
    final source = queue.current;
    if (source == null) return;
    _openedUri = source.uri;
    await engine.open(source, autoPlay: true);
    _emitCurrent(source);
    unawaited(_preloadNext());
  }

  /// Replaces the queue with [sources], starts playback at [startIndex],
  /// resets preload state, and preloads the next track for gapless transitions.
  Future<void> playQueue(List<AudioSource> sources, {int startIndex = 0}) async {
    _consecutiveFatalErrors = 0;
    if (sources.isEmpty) {
      queue.clear();
      _openedUri = null;
      await engine.stop();
      _emitCurrent(null);
      return;
    }

    queue.replaceAll(sources, startIndex: startIndex);
    final source = queue.current;
    if (source == null) {
      _openedUri = null;
      await engine.stop();
      _emitCurrent(null);
      return;
    }

    _openedUri = source.uri;
    await engine.open(source, autoPlay: true);
    _emitCurrent(source);
    unawaited(_preloadNext());
  }

  /// Removes upcoming items from the queue while keeping the currently
  /// playing track active without restart.
  ///
  /// If nothing is currently playing, clears the entire queue and stops playback.
  /// Refreshes the gapless preload to reflect the new next track (or null).
  Future<void> clearUpcoming() async {
    if (_openedUri == null || queue.current == null) {
      queue.clear();
      await stop();
      return;
    }

    queue.clearUpcoming();
    await _preloadNext();
  }

  /// Pauses playback.
  Future<void> pause() async {
    await engine.pause();
  }

  /// Stops playback and clears the active track.
  Future<void> stop() async {
    _openedUri = null;
    await engine.stop();
    _emitCurrent(null);
  }

  /// Skips to the next track.
  Future<void> skipNext() async {
    _consecutiveFatalErrors = 0;
    final next = queue.next();
    if (next == null) {
      _openedUri = null;
      await engine.stop();
      _emitCurrent(null);
      return;
    }
    _openedUri = next.uri;
    await engine.open(next, autoPlay: true);
    _emitCurrent(next);
    unawaited(_preloadNext());
  }

  /// Skips to the previous track, or restarts current track if played past 3 seconds.
  Future<void> skipPrevious() async {
    _consecutiveFatalErrors = 0;
    if (_currentPosition > const Duration(seconds: 3)) {
      _currentPosition = Duration.zero;
      await engine.seek(Duration.zero);
      return;
    }

    final prev = queue.previous();
    if (prev == null) {
      _currentPosition = Duration.zero;
      await engine.seek(Duration.zero);
      return;
    }
    _openedUri = prev.uri;
    _currentPosition = Duration.zero;
    await engine.open(prev, autoPlay: true);
    _emitCurrent(prev);
    unawaited(_preloadNext());
  }

  // ── Internal ────────────────────────────────────────────────────────

  void _onPlaybackState(PlaybackState state) {
    if (_disposed) return;
    // Deduplicate rapid identical state emissions.
    if (_currentState == state) return;
    _currentState = state;
    _stateCtrl.add(state);

    if (state == PlaybackState.completed) {
      // Ignore a second completed event if an advance is already in progress.
      if (_isAdvancing) return;
      _autoAdvance();
    }
  }

  Future<void> _onError(AudioError error) async {
    if (_disposed) return;
    _errorCtrl.add(error);
    // Do not skip track for non-fatal errors (e.g. lyrics/subtitle file errors).
    if (!error.isFatal) {
      return;
    }
    // Ignore a second error event for the same track while an advance is in progress.
    if (_isAdvancing) return;

    _consecutiveFatalErrors++;
    if (_consecutiveFatalErrors > queue.length || _consecutiveFatalErrors >= 3) {
      await stop();
      _errorCtrl.add(AudioError(
        code: AudioErrorCode.engineFailure,
        message:
            'Playback stopped after $_consecutiveFatalErrors consecutive fatal errors.',
        isFatal: true,
      ));
      return;
    }

    await _autoAdvance();
  }

  Future<void> _autoAdvance() async {
    if (_disposed || _isAdvancing) return;
    _isAdvancing = true;
    try {
      final next = queue.advance();
      if (next == null) {
        _openedUri = null;
        await engine.stop();
        _emitCurrent(null);
        return;
      }
      _openedUri = next.uri;
      // continuingGapless: if the engine already moved on to this track by
      // itself, it only confirms the switch instead of reloading the file.
      await engine.open(next, autoPlay: true, continuingGapless: true);
      _emitCurrent(next);
      unawaited(_preloadNext());
    } finally {
      _isAdvancing = false;
    }
  }

  /// Asks the engine to prepare the next track. Never throws: a failure is
  /// reported as a non-fatal error on [errorStream] and playback continues
  /// (the next track will then start without the gapless preparation).
  Future<void> _preloadNext() async {
    if (_disposed || !engine.capabilities.gapless) return;
    try {
      await engine.preloadNext(queue.peekNext());
    } catch (e) {
      if (_disposed) return;
      _errorCtrl.add(AudioError(
        code: AudioErrorCode.engineFailure,
        message: 'Preloading the next track failed: $e',
        isFatal: false,
      ));
    }
  }

  void _emitCurrent(AudioSource? source) {
    if (_lastEmittedUri == source?.uri && source != null) return;
    _lastEmittedUri = source?.uri;
    _currentCtrl.add(source);
  }
}
