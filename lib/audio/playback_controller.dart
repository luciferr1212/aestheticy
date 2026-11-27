/// High-level playback controller: wires [AudioEngine] + [PlaybackQueue].
///
/// Pure Dart — depends only on the abstract [AudioEngine] and the
/// pure-Dart [PlaybackQueue]. No audio-package imports.
library;

import 'dart:async';
import 'dart:math' as math;

import '../diagnostics/app_logger.dart';
import 'audio_engine.dart';
import 'audio_models.dart';
import 'playback/playback_fade_handler.dart';
import 'playback/playback_gapless_preloader.dart';
import 'playback/playback_play_source_tracker.dart';
import 'playback/playback_queue_operations.dart';
import 'playback/playback_resume_state.dart';
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
  static const Duration kStopMaxFadeOutDuration = Duration(milliseconds: 130);

  /// Allowed play-event origin sources stored in `play_events.source`.
  static const Set<String> allowedPlaySources =
      PlaybackPlaySourceTracker.allowedPlaySources;

  /// The underlying audio engine (real or fake).
  final AudioEngine engine;

  /// The playback queue.
  final PlaybackQueue queue;

  /// Timer cadence used for fade gain interpolation.
  final Duration fadeTickInterval;

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
  int _consecutiveFatalErrors = 0;
  bool _isAdvancing = false;
  bool _disposed = false;

  late final PlaybackFadeHandler _fadeHandler;
  late final PlaybackGaplessPreloader _preloader;
  final PlaybackResumeState _resumeState = PlaybackResumeState();
  final PlaybackPlaySourceTracker _playSourceTracker =
      PlaybackPlaySourceTracker();
  late final PlaybackQueueOperations _queueOps;

  /// Creates a controller wired to [engine] and [queue].
  ///
  /// Defaults [fadeProfile] to [FadeProfile.off] for zero-delay standalone callers;
  /// app startup synchronizes this flag from `AppSettings.fadeProfile`.
  /// Call [init] before using.
  PlaybackController({
    required this.engine,
    required this.queue,
    FadeProfile? fadeProfile,
    bool smoothTransitions = false,
    this.fadeTickInterval = kDefaultFadeTickInterval,
  }) {
    final initialProfile =
        fadeProfile ?? (smoothTransitions ? FadeProfile.soft : FadeProfile.off);
    _fadeHandler = PlaybackFadeHandler(
      engine: engine,
      fadeTickInterval: fadeTickInterval,
      isDisposed: () => _disposed,
      initialProfile: initialProfile,
    );
    _preloader = PlaybackGaplessPreloader(
      engine: engine,
      queue: queue,
      isDisposed: () => _disposed,
      emitError: _errorCtrl.add,
    );
    _queueOps = PlaybackQueueOperations(
      queue: queue,
      fadeHandler: _fadeHandler,
      preloader: _preloader,
      resumeState: _resumeState,
      playSourceTracker: _playSourceTracker,
      resetFatalErrors: () => _consecutiveFatalErrors = 0,
      notifyQueueChanged: notifyQueueChanged,
      getOpenedUri: () => _openedUri,
      switchTrackInternal: _switchTrackInternal,
      stopInternal: _stopInternal,
      stop: stop,
    );
  }

  /// The active transition fade profile.
  FadeProfile get fadeProfile => _fadeHandler.fadeProfile;

  /// Origin source label (`album`, `artist`, `playlist`, `favorites`,
  /// `search`, `queue`, `mini`, or `unknown`) for the current playback context.
  String get currentPlaySource => _playSourceTracker.currentPlaySource;

  /// Updates the active transition fade profile.
  ///
  /// Takes effect on the next transition, never in the middle of a running fade.
  set fadeProfile(FadeProfile value) {
    _fadeHandler.fadeProfile = value;
  }

  /// Whether smooth volume fade transitions are applied on transport actions.
  bool get smoothTransitions => _fadeHandler.smoothTransitions;

  /// Updates whether smooth volume fade transitions are enabled.
  set smoothTransitions(bool value) {
    _fadeHandler.smoothTransitions = value;
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
    _resumeState.checkArmedResume(
      dur: dur,
      engineDuration: engine.currentDuration,
      openedUri: _openedUri,
      currentQueueUri: queue.current?.uri,
      seekEngine: engine.seek,
    );
  }

  /// Tears down subscriptions and timers. Does **not** dispose the engine.
  Future<void> dispose() async {
    _disposed = true;
    _fadeHandler.dispose();
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

  /// Restores a saved queue snapshot without re-shuffling and notifies listeners.
  void restoreQueueSnapshot({
    required List<QueueEntry> entries,
    int currentIndex = 0,
    bool shuffled = false,
    RepeatMode repeatMode = RepeatMode.off,
  }) {
    _resumeState.restoreQueueSnapshot(
      queue,
      entries: entries,
      currentIndex: currentIndex,
      shuffled: shuffled,
      repeatMode: repeatMode,
      notifyQueueChanged: notifyQueueChanged,
    );
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
    _resumeState.armResume(position, currentUri: queue.current?.uri);
  }

  /// The currently armed lazy seek position, if any.
  Duration? get armedResumePosition => _resumeState.armedResumePosition;

  /// The current playback position, or the armed resume position when nothing is loaded.
  Duration get currentPosition {
    if ((_currentState == PlaybackState.idle ||
            _currentState == PlaybackState.paused) &&
        _resumeState.armedResumePosition != null) {
      return _resumeState.armedResumePosition!;
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
    final gen = _fadeHandler.beginTransition();
    final profile = _fadeHandler.fadeProfile;
    return _fadeHandler
        .enqueueTransition(() => _playOrResumeInternal(source, gen, profile));
  }

  Future<void> _playOrResumeInternal(
    AudioSource source,
    int gen,
    FadeProfile profile,
  ) async {
    if (_fadeHandler.isStale(gen)) return;

    // When paused on the same track, resume playback without re-opening.
    if (_currentState == PlaybackState.paused && _openedUri == source.uri) {
      if (!profile.isOff && profile.resumeFadeIn > Duration.zero) {
        await _fadeHandler.setFadeGain(0.0);
        if (_fadeHandler.isStale(gen)) return;
        await engine.play();
        if (_fadeHandler.isStale(gen)) return;
        _fadeHandler.startFadeIn(profile.resumeFadeIn, gen, profile);
      } else {
        await _fadeHandler.ensureUnityFadeGain();
        if (_fadeHandler.isStale(gen)) return;
        await engine.play();
      }
      return;
    }

    // Resuming while already playing the same track (e.g. aborted pause fade).
    if (_currentState == PlaybackState.playing && _openedUri == source.uri) {
      if (!profile.isOff && profile.resumeFadeIn > Duration.zero) {
        _fadeHandler.startFadeIn(profile.resumeFadeIn, gen, profile);
      } else {
        await _fadeHandler.ensureUnityFadeGain();
      }
      return;
    }

    await _switchTrackInternal(source, gen, profile);
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
    _resumeState.clearIfDifferentUri(queue.items[index].uri);
    queue.jumpTo(index);
    final source = queue.current;
    if (source == null) return Future<void>.value();
    final gen = _fadeHandler.beginTransition();
    final profile = _fadeHandler.fadeProfile;
    return _fadeHandler
        .enqueueTransition(() => _switchTrackInternal(source, gen, profile));
  }

  // ── Queue Operations (delegated) ────────────────────────────────────

  /// Replaces the queue with [sources], starts playback at [startIndex],
  /// resets preload state, and preloads the next track for gapless transitions.
  Future<void> playQueue(
    List<AudioSource> sources, {
    int startIndex = 0,
    String? source,
  }) =>
      _queueOps.playQueue(sources, startIndex: startIndex, source: source);

  /// Replaces the queue with [sources], enables shuffle mode, starts playback on
  /// a randomly selected item, notifies queue listeners, and preloads the next track.
  Future<void> playShuffled(
    List<AudioSource> sources, {
    math.Random? random,
    String? source,
  }) =>
      _queueOps.playShuffled(sources, random: random, source: source);

  /// Stops playback, clears the entire queue, notifies listeners, and clears preload.
  Future<void> clearQueue() => _queueOps.clearQueue();

  /// Removes upcoming items from the queue while keeping the currently
  /// playing track active without restart.
  Future<void> clearUpcoming() => _queueOps.clearUpcoming();

  /// Inserts [sources] immediately after the currently playing track.
  Future<void> playNext(List<AudioSource> sources) =>
      _queueOps.playNext(sources);

  /// Appends [sources] to the playback queue after the current track and after any
  /// upcoming user-queued tracks.
  Future<void> addToQueue(List<AudioSource> sources) =>
      _queueOps.addToQueue(sources);

  /// Reorders the item at [from] to [to] in active playback order.
  Future<void> moveInQueue(int from, int to) => _queueOps.moveInQueue(from, to);

  /// Enables or disables shuffle mode, notifies queue listeners, and refreshes
  /// the gapless preload target.
  Future<void> setShuffle(bool enabled) => _queueOps.setShuffle(enabled);

  /// Cycles repeat mode (`off` -> `all` -> `one` -> `off`), notifies queue
  /// listeners, and refreshes the gapless preload target.
  Future<void> cycleRepeatMode() => _queueOps.cycleRepeatMode();

  /// Safely removes the entry identified by [entryId] from the queue.
  Future<void> removeEntryFromQueue(int entryId) =>
      _queueOps.removeEntryFromQueue(entryId);

  /// Safely removes all entries matching [entryIds] in a single operation.
  Future<void> removeEntriesFromQueue(Iterable<int> entryIds) =>
      _queueOps.removeEntriesFromQueue(entryIds);

  /// Safely removes the track at [index] in active playback order.
  Future<void> removeFromQueue(int index) => _queueOps.removeFromQueue(index);

  /// Moves the item at [index] in active playback order to directly after the current track.
  Future<void> playNextFromQueue(int index) =>
      _queueOps.playNextFromQueue(index);

  /// Pauses playback.
  Future<void> pause() {
    final gen = _fadeHandler.beginTransition();
    final profile = _fadeHandler.fadeProfile;
    return _fadeHandler.enqueueTransition(() => _pauseInternal(gen, profile));
  }

  Future<void> _pauseInternal(int gen, FadeProfile profile) async {
    if (_fadeHandler.isStale(gen)) return;
    if (!profile.isOff &&
        profile.pauseFadeOut > Duration.zero &&
        _currentState == PlaybackState.playing) {
      await _fadeHandler.rampOut(profile.pauseFadeOut, gen);
      if (_fadeHandler.isStale(gen)) return;
      await engine.pause();
      if (!_disposed && !_fadeHandler.isStale(gen)) {
        await _fadeHandler.setFadeGain(1.0);
      }
      return;
    }

    await _fadeHandler.ensureUnityFadeGain();
    if (_fadeHandler.isStale(gen)) return;
    await engine.pause();
  }

  /// Stops playback and clears the active track.
  Future<void> stop() {
    _resumeState.clearArmedResume();
    final gen = _fadeHandler.beginTransition();
    final profile = _fadeHandler.fadeProfile;
    return _fadeHandler
        .enqueueTransition(() => _stopInternal(gen, profile: profile));
  }

  Future<void> _stopInternal(
    int gen, {
    bool clearResume = true,
    required FadeProfile profile,
  }) async {
    if (_fadeHandler.isStale(gen)) return;
    if (clearResume) {
      _resumeState.clearArmedResume();
    }
    if (!profile.isOff &&
        profile.stopFadeOut > Duration.zero &&
        _currentState == PlaybackState.playing) {
      final stopMax = Duration(
        milliseconds: (profile.stopFadeOut.inMilliseconds * 1.3)
            .round()
            .clamp(10, 10000),
      );
      await _fadeHandler.rampOut(
        profile.stopFadeOut,
        gen,
        maxDuration: stopMax,
      );
      if (_fadeHandler.isStale(gen)) return;
    }
    _openedUri = null;
    await engine.stop();
    if (!_disposed) {
      _emitCurrent(null);
    }
    if (!_disposed && !_fadeHandler.isStale(gen)) {
      await _fadeHandler.setFadeGain(1.0);
    }
  }

  /// Skips to the next track.
  Future<void> skipNext() {
    _consecutiveFatalErrors = 0;
    _resumeState.clearArmedResume();
    final next = queue.next();
    final gen = _fadeHandler.beginTransition();
    final profile = _fadeHandler.fadeProfile;
    if (next == null) {
      return _fadeHandler
          .enqueueTransition(() => _stopInternal(gen, profile: profile));
    }
    return _fadeHandler
        .enqueueTransition(() => _switchTrackInternal(next, gen, profile));
  }

  /// Skips to the previous track, or restarts current track if played past 3 seconds.
  Future<void> skipPrevious() async {
    _consecutiveFatalErrors = 0;
    _resumeState.clearArmedResume();
    if (_currentPosition > const Duration(seconds: 3)) {
      _currentPosition = Duration.zero;
      await engine.seek(Duration.zero);
      return;
    }

    final prev = queue.previous();
    final gen = _fadeHandler.beginTransition();
    final profile = _fadeHandler.fadeProfile;
    if (prev == null) {
      _currentPosition = Duration.zero;
      await engine.seek(Duration.zero);
      return;
    }
    _currentPosition = Duration.zero;
    await _fadeHandler
        .enqueueTransition(() => _switchTrackInternal(prev, gen, profile));
  }

  // ── Internal track switching & engine listeners ─────────────────────

  Future<void> _switchTrackInternal(
    AudioSource source,
    int gen,
    FadeProfile profile,
  ) async {
    if (_fadeHandler.isStale(gen)) return;

    final wasPlaying = _currentState == PlaybackState.playing;
    if (!profile.isOff || (_fadeHandler.currentFadeGain - 1.0).abs() > 1e-6) {
      await _fadeHandler.prepareForTrackSwitch(
        wasPlaying: wasPlaying,
        gen: gen,
        profile: profile,
      );
      if (_fadeHandler.isStale(gen)) return;
    }

    _openedUri = source.uri;
    try {
      await engine.open(source, autoPlay: true);
    } catch (e, st) {
      AppLogger.instance.error(
        'PlaybackController',
        'Failed opening track in playback path',
        e,
        st,
      );
      if (!_disposed && !_fadeHandler.isStale(gen)) {
        await _fadeHandler.setFadeGain(1.0);
        // Schedule asynchronously outside enqueueTransition so _onError
        // can safely advance past the broken track without deadlocking.
        Timer.run(() {
          if (!_disposed) {
            unawaited(
              _onError(
                AudioError(
                  code: AudioErrorCode.engineFailure,
                  message: 'Failed opening track: $e',
                  isFatal: true,
                ),
              ),
            );
          }
        });
      }
      return;
    }
    if (_fadeHandler.isStale(gen)) return;

    _checkArmedResume();
    _emitCurrent(source);
    unawaited(_preloader.preloadNext());
    final fadeInDuration =
        wasPlaying ? profile.switchFadeIn : profile.startFadeIn;
    _fadeHandler.startFadeIn(fadeInDuration, gen, profile);
  }

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
    if (_consecutiveFatalErrors > queue.length ||
        _consecutiveFatalErrors >= 3) {
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
      final gen = _fadeHandler.beginTransition();
      await _fadeHandler.enqueueTransition(() async {
        if (_fadeHandler.isStale(gen)) return;
        await _fadeHandler.ensureUnityFadeGain();
        if (_fadeHandler.isStale(gen)) return;
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
        if (_fadeHandler.isStale(gen)) return;
        _emitCurrent(next);
        unawaited(_preloader.preloadNext());
      });
    } finally {
      _isAdvancing = false;
    }
  }

  void _emitCurrent(AudioSource? source) {
    if (_lastEmittedUri == source?.uri && source != null) return;
    _lastEmittedUri = source?.uri;
    _currentCtrl.add(source);
  }
}
