/// High-level playback controller: wires [AudioEngine] + [PlaybackQueue].
///
/// Pure Dart — depends only on the abstract [AudioEngine] and the
/// pure-Dart [PlaybackQueue]. No audio-package imports.
library;

import 'dart:async';
import 'dart:math' as math;

import 'audio_engine.dart';
import 'audio_models.dart';
import 'playback_queue.dart';

/// Coordinates the [AudioEngine] with a [PlaybackQueue]: auto-advances
/// tracks, preloads the next item for gapless transitions, skips
/// past errors without crashing, and manages smooth fade transitions.
class PlaybackController {
  /// Default timer cadence for fade gain envelopes (~60 Hz).
  static const Duration kDefaultFadeTickInterval = Duration(milliseconds: 16);

  /// Fade-in duration when starting a track from silence or after a switch.
  static const Duration kStartFadeInDuration = Duration(milliseconds: 250);

  /// Fade-in duration when resuming a paused track.
  static const Duration kResumeFadeInDuration = Duration(milliseconds: 120);

  /// Fade-out duration before a manual track switch while playing.
  static const Duration kSwitchFadeOutDuration = Duration(milliseconds: 120);

  /// Silent gap held at zero gain between outgoing fade-out and incoming open.
  static const Duration kSwitchGapDuration = Duration(milliseconds: 60);

  /// Fade-out duration before pausing an actively playing track.
  static const Duration kPauseFadeOutDuration = Duration(milliseconds: 100);

  /// Fade-out duration before stopping playback.
  static const Duration kStopFadeOutDuration = Duration(milliseconds: 100);

  /// Hard upper bound for stop/shutdown fade-out so exit stays responsive.
  static const Duration kStopMaxFadeOutDuration = Duration(milliseconds: 145);

  /// The underlying audio engine (real or fake).
  final AudioEngine engine;

  /// The playback queue.
  final PlaybackQueue queue;

  /// Timer cadence used for fade gain interpolation.
  final Duration fadeTickInterval;

  bool _smoothTransitions = false;

  final List<StreamSubscription<dynamic>> _subs = [];

  final _stateCtrl = StreamController<PlaybackState>.broadcast();
  final _currentCtrl = StreamController<AudioSource?>.broadcast();
  final _errorCtrl = StreamController<AudioError>.broadcast();
  final _seekCtrl = StreamController<Duration>.broadcast();
  final _queueChangeCtrl = StreamController<void>.broadcast();

  PlaybackState _currentState = PlaybackState.idle;
  Duration _currentPosition = Duration.zero;
  String? _openedUri;
  String? _lastEmittedUri;
  Duration? _armedResumePosition;
  String? _armedResumeUri;
  int _consecutiveFatalErrors = 0;
  bool _isAdvancing = false;
  bool _disposed = false;

  double _currentFadeGain = 1.0;
  int _transitionGen = 0;
  Future<void>? _activeTransition;
  Timer? _fadeTimer;
  Timer? _delayTimer;
  Timer? _deadlineTimer;
  Completer<void>? _activeWaitCompleter;

  /// Creates a controller wired to [engine] and [queue].
  ///
  /// Defaults [smoothTransitions] to `false` for zero-delay standalone callers;
  /// app startup synchronizes this flag from `AppSettings.smoothTransitions`.
  /// Call [init] before using.
  PlaybackController({
    required this.engine,
    required this.queue,
    bool smoothTransitions = false,
    this.fadeTickInterval = kDefaultFadeTickInterval,
  }) {
    _smoothTransitions = smoothTransitions;
  }

  /// Whether smooth volume fade transitions are applied on transport actions.
  bool get smoothTransitions => _smoothTransitions;

  /// Updates whether smooth volume fade transitions are enabled.
  ///
  /// When disabled mid-fade, cancels active fade timers and restores full gain.
  set smoothTransitions(bool value) {
    if (_smoothTransitions == value) return;
    _smoothTransitions = value;
    if (!value) {
      _abortPendingWaiters();
      unawaited(_setFadeGain(1.0));
    }
  }

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
    _subs.add(engine.durationStream.listen((dur) {
      _checkArmedResume(dur);
    }));
    _subs.add(engine.errorStream.listen(_onError));
  }

  void _checkArmedResume([Duration? dur]) {
    final effectiveDur = dur ?? engine.currentDuration;
    if (_armedResumePosition != null &&
        effectiveDur > Duration.zero &&
        (_openedUri == null ||
            _openedUri == _armedResumeUri ||
            queue.current?.uri == _armedResumeUri)) {
      final pos = _armedResumePosition!;
      _armedResumePosition = null;
      _armedResumeUri = null;
      unawaited(engine.seek(pos));
    }
  }

  /// Tears down subscriptions and timers. Does **not** dispose the engine.
  Future<void> dispose() async {
    _disposed = true;
    _transitionGen++;
    _abortPendingWaiters();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _stateCtrl.close();
    await _currentCtrl.close();
    await _errorCtrl.close();
    await _seekCtrl.close();
    await _queueChangeCtrl.close();
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

  /// Seeks that occurred on this controller.
  Stream<Duration> get seekStream => _seekCtrl.stream;

  /// Emits whenever the playback queue is modified.
  Stream<void> get queueChangeStream => _queueChangeCtrl.stream;

  /// Notifies listeners that the queue has changed.
  void notifyQueueChanged() {
    if (!_disposed) {
      _queueChangeCtrl.add(null);
    }
  }

  /// Seeks to [position] within the current track.
  Future<void> seek(Duration position) async {
    _currentPosition = position;
    if (_currentState == PlaybackState.idle) {
      armResume(position);
    }
    await engine.seek(position);
    if (!_disposed) {
      _seekCtrl.add(position);
    }
  }

  /// Arms a lazy seek to [position] when the current track is next opened.
  void armResume(Duration position) {
    _armedResumePosition = position;
    _armedResumeUri = queue.current?.uri;
  }

  /// The currently armed lazy seek position, if any.
  Duration? get armedResumePosition => _armedResumePosition;

  /// The current playback position, or the armed resume position when nothing is loaded.
  Duration get currentPosition {
    if (_currentState == PlaybackState.idle && _armedResumePosition != null) {
      return _armedResumePosition!;
    }
    return engine.currentPosition;
  }

  /// The current track duration, or [Duration.zero] if none.
  Duration get currentDuration {
    final engineDur = engine.currentDuration;
    if (engineDur > Duration.zero) return engineDur;
    final extras = queue.current?.extras;
    if (extras != null && extras.containsKey('durationMs')) {
      final ms = int.tryParse(extras['durationMs'] ?? '');
      if (ms != null && ms > 0) return Duration(milliseconds: ms);
    }
    return Duration.zero;
  }

  /// The current software volume.
  double get currentVolume => engine.currentVolume;

  // ── Transport ───────────────────────────────────────────────────────

  /// Starts playback from the current queue position, or resumes if paused.
  Future<void> play() {
    _consecutiveFatalErrors = 0;
    final source = queue.current;
    if (source == null) return Future<void>.value();
    final gen = _beginTransition();
    return _enqueueTransition(() => _playOrResumeInternal(source, gen));
  }

  Future<void> _playOrResumeInternal(AudioSource source, int gen) async {
    if (_isStale(gen)) return;

    // When paused on the same track, resume playback without re-opening.
    if (_currentState == PlaybackState.paused && _openedUri == source.uri) {
      if (_smoothTransitions) {
        await _setFadeGain(0.0);
        if (_isStale(gen)) return;
        await engine.play();
        if (_isStale(gen)) return;
        _startFadeIn(kResumeFadeInDuration, gen);
      } else {
        await _ensureUnityFadeGain();
        if (_isStale(gen)) return;
        await engine.play();
      }
      return;
    }

    // Resuming while already playing the same track (e.g. aborted pause fade).
    if (_currentState == PlaybackState.playing && _openedUri == source.uri) {
      if (_smoothTransitions) {
        _startFadeIn(kResumeFadeInDuration, gen);
      } else {
        await _ensureUnityFadeGain();
      }
      return;
    }

    await _switchTrackInternal(source, gen);
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
  Future<void> playTrack(int index) {
    _consecutiveFatalErrors = 0;
    if (index < 0 || index >= queue.length) return Future<void>.value();
    if (_armedResumeUri != null && queue.items[index].uri != _armedResumeUri) {
      _armedResumePosition = null;
      _armedResumeUri = null;
    }
    queue.jumpTo(index);
    final source = queue.current;
    if (source == null) return Future<void>.value();
    final gen = _beginTransition();
    return _enqueueTransition(() => _switchTrackInternal(source, gen));
  }

  /// Replaces the queue with [sources], starts playback at [startIndex],
  /// resets preload state, and preloads the next track for gapless transitions.
  Future<void> playQueue(List<AudioSource> sources, {int startIndex = 0}) {
    _consecutiveFatalErrors = 0;
    _armedResumePosition = null;
    _armedResumeUri = null;
    if (sources.isEmpty) {
      queue.clear();
      final gen = _beginTransition();
      return _enqueueTransition(() => _stopInternal(gen, clearResume: false));
    }

    queue.replaceAll(sources, startIndex: startIndex);
    notifyQueueChanged();
    final source = queue.current;
    if (source == null) {
      final gen = _beginTransition();
      return _enqueueTransition(() => _stopInternal(gen, clearResume: false));
    }

    final gen = _beginTransition();
    return _enqueueTransition(() => _switchTrackInternal(source, gen));
  }

  /// Removes upcoming items from the queue while keeping the currently
  /// playing track active without restart.
  ///
  /// If nothing is currently playing, clears the entire queue and stops playback.
  /// Refreshes the gapless preload to reflect the new next track (or null).
  Future<void> clearUpcoming() async {
    if (_openedUri == null || queue.current == null) {
      queue.clear();
      notifyQueueChanged();
      await stop();
      return;
    }

    queue.clearUpcoming();
    notifyQueueChanged();
    await _preloadNext();
  }

  /// Inserts [sources] immediately after the currently playing track.
  ///
  /// If the queue is currently empty, behaves like [playQueue] starting at index 0.
  /// If the queue is non-empty, preserves the current track and active playback position.
  Future<void> playNext(List<AudioSource> sources) async {
    if (sources.isEmpty) return;
    if (queue.isEmpty || queue.current == null) {
      await playQueue(sources, startIndex: 0);
      return;
    }

    if (queue.isShuffled) {
      final currentIdx = queue.currentIndex;
      for (final s in sources) {
        queue.add(s);
      }
      for (var i = 0; i < sources.length; i++) {
        final s = sources[i];
        final from = queue.items.lastIndexOf(s);
        if (from != -1) {
          queue.move(from, currentIdx + 1 + i);
        }
      }
    } else {
      final targetIndex = queue.currentIndex + 1;
      for (var i = 0; i < sources.length; i++) {
        queue.insert(targetIndex + i, sources[i]);
      }
    }

    notifyQueueChanged();
    unawaited(_preloadNext());
  }

  /// Appends [sources] to the end of the playback queue.
  ///
  /// If the queue is currently empty, behaves like [playQueue] starting at index 0.
  Future<void> addToQueue(List<AudioSource> sources) async {
    if (sources.isEmpty) return;
    if (queue.isEmpty || queue.current == null) {
      await playQueue(sources, startIndex: 0);
      return;
    }

    if (queue.isShuffled) {
      for (final s in sources) {
        queue.add(s);
      }
      final baseTarget = queue.length - sources.length;
      for (var i = 0; i < sources.length; i++) {
        final s = sources[i];
        final from = queue.items.indexOf(s);
        if (from != -1) {
          queue.move(from, baseTarget + i);
        }
      }
    } else {
      for (final s in sources) {
        queue.add(s);
      }
    }

    notifyQueueChanged();
    unawaited(_preloadNext());
  }

  /// Reorders the item at [from] to [to] in active playback order.
  ///
  /// Validates indices, preserves the currently playing track without restarting,
  /// notifies listeners, and refreshes the gapless preload.
  Future<void> moveInQueue(int from, int to) async {
    if (from < 0 || from >= queue.length) return;
    if (to < 0 || to >= queue.length) return;
    if (from == to) return;

    queue.move(from, to);
    notifyQueueChanged();
    await _preloadNext();
  }

  /// Safely removes the track at [index] in active playback order.
  ///
  /// - If [index] is invalid, this is a no-op.
  /// - If [index] is not current, removes it, notifies listeners, and refreshes preload
  ///   without interrupting current playback.
  /// - If [index] is current and other items remain, removes it, resets error/resume state,
  ///   plays the item now at the cursor, and notifies listeners.
  /// - If [index] was the only item, clears the queue, stops the engine, and emits null current track.
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= queue.length) return;

    if (queue.length == 1) {
      queue.clear();
      _armedResumePosition = null;
      _armedResumeUri = null;
      notifyQueueChanged();
      final gen = _beginTransition();
      await _enqueueTransition(() => _stopInternal(gen, clearResume: false));
      await _preloadNext();
      return;
    }

    final isCurrent = index == queue.currentIndex;
    if (!isCurrent) {
      queue.remove(index);
      notifyQueueChanged();
      await _preloadNext();
      return;
    }

    queue.remove(index);
    notifyQueueChanged();
    _consecutiveFatalErrors = 0;
    _armedResumePosition = null;
    _armedResumeUri = null;
    final nextSource = queue.current;
    final gen = _beginTransition();
    await _enqueueTransition(() async {
      if (nextSource != null) {
        await _switchTrackInternal(nextSource, gen);
      } else {
        await _stopInternal(gen, clearResume: false);
      }
    });
    await _preloadNext();
  }

  /// Moves the item at [index] in active playback order to directly after the current track.
  ///
  /// No-op if [index] is invalid, is currently playing, or is already immediately next.
  Future<void> playNextFromQueue(int index) async {
    if (index < 0 || index >= queue.length) return;
    final cur = queue.currentIndex;
    if (cur < 0 || index == cur || index == cur + 1) return;
    final target = index > cur ? cur + 1 : cur;
    await moveInQueue(index, target);
  }

  /// Pauses playback.
  Future<void> pause() {
    final gen = _beginTransition();
    return _enqueueTransition(() => _pauseInternal(gen));
  }

  Future<void> _pauseInternal(int gen) async {
    if (_isStale(gen)) return;
    if (_smoothTransitions && _currentState == PlaybackState.playing) {
      await _rampOut(kPauseFadeOutDuration, gen);
      if (_isStale(gen)) return;
      await engine.pause();
      if (!_disposed && !_isStale(gen)) {
        await _setFadeGain(1.0);
      }
      return;
    }

    await _ensureUnityFadeGain();
    if (_isStale(gen)) return;
    await engine.pause();
  }

  /// Stops playback and clears the active track.
  Future<void> stop() {
    _armedResumePosition = null;
    _armedResumeUri = null;
    final gen = _beginTransition();
    return _enqueueTransition(() => _stopInternal(gen));
  }

  Future<void> _stopInternal(int gen, {bool clearResume = true}) async {
    if (_isStale(gen)) return;
    if (clearResume) {
      _armedResumePosition = null;
      _armedResumeUri = null;
    }
    if (_smoothTransitions && _currentState == PlaybackState.playing) {
      await _rampOut(
        kStopFadeOutDuration,
        gen,
        maxDuration: kStopMaxFadeOutDuration,
      );
      if (_isStale(gen)) return;
    }
    _openedUri = null;
    await engine.stop();
    if (!_disposed) {
      _emitCurrent(null);
    }
    if (!_disposed && !_isStale(gen)) {
      await _setFadeGain(1.0);
    }
  }

  /// Skips to the next track.
  Future<void> skipNext() {
    _consecutiveFatalErrors = 0;
    _armedResumePosition = null;
    _armedResumeUri = null;
    final next = queue.next();
    final gen = _beginTransition();
    if (next == null) {
      return _enqueueTransition(() => _stopInternal(gen));
    }
    return _enqueueTransition(() => _switchTrackInternal(next, gen));
  }

  /// Skips to the previous track, or restarts current track if played past 3 seconds.
  Future<void> skipPrevious() async {
    _consecutiveFatalErrors = 0;
    _armedResumePosition = null;
    _armedResumeUri = null;
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
    _currentPosition = Duration.zero;
    final gen = _beginTransition();
    await _enqueueTransition(() => _switchTrackInternal(prev, gen));
  }

  // ── Internal transition & fade helpers ──────────────────────────────

  int _beginTransition() {
    _transitionGen++;
    _abortPendingWaiters();
    return _transitionGen;
  }

  bool _isStale(int gen) => _disposed || gen != _transitionGen;

  Future<void> _enqueueTransition(Future<void> Function() task) {
    final prev = _activeTransition;
    final next = prev == null
        ? task()
        : prev.catchError((Object _) {}).then((_) => task());
    late final Future<void> tracked;
    tracked = next.whenComplete(() {
      if (identical(_activeTransition, tracked)) {
        _activeTransition = null;
      }
    });
    _activeTransition = tracked;
    return tracked;
  }

  void _abortPendingWaiters() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _delayTimer?.cancel();
    _delayTimer = null;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    final completer = _activeWaitCompleter;
    _activeWaitCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _setFadeGain(double gain) async {
    final clamped = gain.clamp(0.0, 1.0);
    _currentFadeGain = clamped;
    if (_disposed) return;
    await engine.setFadeGain(clamped);
  }

  Future<void> _ensureUnityFadeGain() async {
    if ((_currentFadeGain - 1.0).abs() > 1e-6) {
      await _setFadeGain(1.0);
    }
  }

  static double _smoothStep(double t) => 0.5 * (1.0 - math.cos(math.pi * t));

  double _fadeProgress(int step, int totalDurationUs, int swElapsedUs) {
    final tickUs = step * fadeTickInterval.inMicroseconds;
    final elapsedUs = math.max(tickUs, swElapsedUs);
    return (elapsedUs / totalDurationUs).clamp(0.0, 1.0);
  }

  Future<void> _rampOut(
    Duration duration,
    int gen, {
    Duration? maxDuration,
  }) async {
    if (_isStale(gen)) return;
    final startGain = _currentFadeGain.clamp(0.0, 1.0);
    if (startGain <= 0.0 || duration <= Duration.zero) {
      await _setFadeGain(0.0);
      return;
    }

    final scaledMs = (duration.inMilliseconds * startGain).round();
    final effectiveMs = maxDuration != null
        ? math.min(scaledMs, maxDuration.inMilliseconds)
        : scaledMs;
    if (effectiveMs <= 0) {
      await _setFadeGain(0.0);
      return;
    }

    final totalDurationUs = effectiveMs * 1000;
    final sw = Stopwatch()..start();
    var step = 0;
    final completer = Completer<void>();
    _activeWaitCompleter = completer;

    void finish() {
      _fadeTimer?.cancel();
      _fadeTimer = null;
      _deadlineTimer?.cancel();
      _deadlineTimer = null;
      if (identical(_activeWaitCompleter, completer)) {
        _activeWaitCompleter = null;
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    if (maxDuration != null) {
      _deadlineTimer = Timer(maxDuration, () {
        if (!_isStale(gen)) {
          unawaited(_setFadeGain(0.0));
        }
        finish();
      });
    }

    _fadeTimer = Timer.periodic(fadeTickInterval, (_) {
      if (_isStale(gen)) {
        finish();
        return;
      }
      step++;
      final t = _fadeProgress(step, totalDurationUs, sw.elapsedMicroseconds);
      final gain = startGain * (1.0 - _smoothStep(t));
      unawaited(_setFadeGain(gain));
      if (t >= 1.0) {
        finish();
      }
    });

    await completer.future;
    if (!_isStale(gen)) {
      await _setFadeGain(0.0);
    }
  }

  Future<void> _waitGap(Duration duration, int gen) async {
    if (_isStale(gen) || duration <= Duration.zero) return;
    final completer = Completer<void>();
    _activeWaitCompleter = completer;
    _delayTimer = Timer(duration, () {
      _delayTimer = null;
      if (identical(_activeWaitCompleter, completer)) {
        _activeWaitCompleter = null;
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    await completer.future;
  }

  void _startFadeIn(Duration duration, int gen) {
    if (_isStale(gen)) return;
    _fadeTimer?.cancel();
    _fadeTimer = null;

    if (!_smoothTransitions || duration <= Duration.zero) {
      if ((_currentFadeGain - 1.0).abs() > 1e-6) {
        unawaited(_setFadeGain(1.0));
      }
      return;
    }

    final startGain = _currentFadeGain.clamp(0.0, 1.0);
    if (startGain >= 1.0) {
      return;
    }

    final remainingFraction = 1.0 - startGain;
    final totalDurationUs =
        (duration.inMilliseconds * remainingFraction * 1000).round().clamp(1, 10000000);
    final sw = Stopwatch()..start();
    var step = 0;

    _fadeTimer = Timer.periodic(fadeTickInterval, (timer) {
      if (_isStale(gen) || !_smoothTransitions) {
        timer.cancel();
        if (identical(_fadeTimer, timer)) {
          _fadeTimer = null;
        }
        return;
      }
      step++;
      final t = _fadeProgress(step, totalDurationUs, sw.elapsedMicroseconds);
      final gain = startGain + (1.0 - startGain) * _smoothStep(t);
      unawaited(_setFadeGain(gain));
      if (t >= 1.0) {
        timer.cancel();
        if (identical(_fadeTimer, timer)) {
          _fadeTimer = null;
        }
      }
    });
  }

  Future<void> _switchTrackInternal(AudioSource source, int gen) async {
    if (_isStale(gen)) return;

    final wasPlaying = _currentState == PlaybackState.playing;
    if (_smoothTransitions) {
      if (wasPlaying) {
        await _rampOut(kSwitchFadeOutDuration, gen);
        if (_isStale(gen)) return;
        await _waitGap(kSwitchGapDuration, gen);
        if (_isStale(gen)) return;
      } else {
        await _setFadeGain(0.0);
        if (_isStale(gen)) return;
      }
    } else if ((_currentFadeGain - 1.0).abs() > 1e-6) {
      await _setFadeGain(1.0);
      if (_isStale(gen)) return;
    }

    _openedUri = source.uri;
    try {
      await engine.open(source, autoPlay: true);
    } catch (_) {
      if (!_disposed && !_isStale(gen)) {
        await _setFadeGain(1.0);
      }
      rethrow;
    }
    if (_isStale(gen)) return;

    _checkArmedResume();
    _emitCurrent(source);
    unawaited(_preloadNext());
    _startFadeIn(kStartFadeInDuration, gen);
  }

  // ── Internal listeners ──────────────────────────────────────────────

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
      if (!_disposed) {
        _errorCtrl.add(AudioError(
          code: AudioErrorCode.engineFailure,
          message:
              'Playback stopped after $_consecutiveFatalErrors consecutive fatal errors.',
          isFatal: true,
        ));
      }
      return;
    }

    await _autoAdvance();
  }

  Future<void> _autoAdvance() async {
    if (_disposed || _isAdvancing) return;
    _isAdvancing = true;
    try {
      final next = queue.advance();
      final gen = _beginTransition();
      await _enqueueTransition(() async {
        if (_isStale(gen)) return;
        await _ensureUnityFadeGain();
        if (_isStale(gen)) return;
        if (next == null) {
          _openedUri = null;
          _emitCurrent(null);
          await engine.stop();
          return;
        }
        _openedUri = next.uri;
        // continuingGapless: if the engine already moved on to this track by
        // itself, it only confirms the switch instead of reloading the file.
        await engine.open(next, autoPlay: true, continuingGapless: true);
        if (_isStale(gen)) return;
        _emitCurrent(next);
        unawaited(_preloadNext());
      });
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
