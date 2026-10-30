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

  bool _disposed = false;

  /// Creates a controller wired to [engine] and [queue].
  ///
  /// Call [init] before using.
  PlaybackController({required this.engine, required this.queue});

  // ── Lifecycle ───────────────────────────────────────────────────────

  /// Initializes the controller and starts listening to engine events.
  Future<void> init() async {
    _subs.add(engine.playbackStateStream.listen(_onPlaybackState));
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

  /// Emits whenever the current track changes (including `null` when
  /// the queue ends).
  Stream<AudioSource?> get currentStream => _currentCtrl.stream;

  /// Errors that occurred during playback (after skipping to the next
  /// track).
  Stream<AudioError> get errorStream => _errorCtrl.stream;

  // ── Transport ───────────────────────────────────────────────────────

  /// Starts playback from the current queue position (or the first item
  /// if nothing is selected).
  Future<void> play() async {
    final source = queue.current;
    if (source == null) return;
    await engine.open(source, autoPlay: true);
    _currentCtrl.add(source);
    _preloadNext();
  }

  /// Starts the queue from scratch at index 0.
  Future<void> playFromStart() async {
    if (queue.isEmpty) return;
    queue.jumpTo(0);
    await play();
  }

  /// Skips to the next track.
  Future<void> skipNext() async {
    final next = queue.next();
    if (next == null) {
      await engine.stop();
      _currentCtrl.add(null);
      return;
    }
    await engine.open(next, autoPlay: true);
    _currentCtrl.add(next);
    _preloadNext();
  }

  /// Skips to the previous track.
  Future<void> skipPrevious() async {
    final prev = queue.previous();
    if (prev == null) return;
    await engine.open(prev, autoPlay: true);
    _currentCtrl.add(prev);
    _preloadNext();
  }

  // ── Internal ────────────────────────────────────────────────────────

  void _onPlaybackState(PlaybackState state) {
    if (_disposed) return;
    _stateCtrl.add(state);

    if (state == PlaybackState.completed) {
      _autoAdvance();
    }
  }

  void _onError(AudioError error) {
    if (_disposed) return;
    _errorCtrl.add(error);
    // Skip to next track on error — do not crash.
    _autoAdvance();
  }

  Future<void> _autoAdvance() async {
    if (_disposed) return;
    final next = queue.next();
    if (next == null) {
      _currentCtrl.add(null);
      return;
    }
    await engine.open(next, autoPlay: true);
    _currentCtrl.add(next);
    _preloadNext();
  }

  void _preloadNext() {
    if (!engine.capabilities.gapless) return;
    final peeked = queue.peekNext();
    engine.preloadNext(peeked);
  }
}
