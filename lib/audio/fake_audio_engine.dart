/// In-memory [AudioEngine] fake for unit tests.
///
/// Simulates playback with controllable time: call [simulateTick] to
/// advance the position, and [simulateCompletion] or [simulateError]
/// to trigger end-of-track or error scenarios.
///
/// No native code — runs anywhere `dart test` runs.
library;

import 'dart:async';

import 'audio_engine.dart';
import 'audio_models.dart';

/// A fully controllable fake that implements [AudioEngine] without any
/// native audio library.
class FakeAudioEngine extends AudioEngine {
  // ── State ───────────────────────────────────────────────────────────

  bool _initialized = false;
  AudioSource? _openedSource;
  AudioSource? _preloadedNext;
  PlaybackState _state = PlaybackState.idle;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(minutes: 3); // default fake track length
  double _volume = 1.0;
  double _fadeGain = 1.0;
  bool _muted = false;
  double _speed = 1.0;
  AudioDevice _currentDevice = AudioDevice.auto;
  bool _exclusiveMode = false;
  bool _eqEnabled = false;
  List<double> _eqGains = List<double>.filled(10, 0.0);
  double _preamp = 0.0;
  ReplayGainMode _replayGainMode = ReplayGainMode.off;
  double _replayGainPreamp = 0.0;
  AudioStreamInfo? _streamInfo;

  /// Devices the fake reports. Modify directly in tests.
  List<AudioDevice> fakeDevices = [AudioDevice.auto];

  // ── Stream controllers ──────────────────────────────────────────────

  final _playbackStateCtrl = StreamController<PlaybackState>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _volumeCtrl = StreamController<double>.broadcast();
  final _errorCtrl = StreamController<AudioError>.broadcast();
  final _devicesCtrl = StreamController<List<AudioDevice>>.broadcast();
  final _streamInfoCtrl = StreamController<AudioStreamInfo?>.broadcast();

  // ── Test helpers ────────────────────────────────────────────────────

  /// Updates fake devices and emits on the stream.
  void simulateDevices(List<AudioDevice> newDevices) {
    fakeDevices = List<AudioDevice>.from(newDevices);
    _devicesCtrl.add(devices);
  }

  /// How many times [open] has been called.
  int openCallCount = 0;

  /// Current playback position.
  Duration get position => _position;

  /// The source passed to [open], for assertions.
  AudioSource? get openedSource => _openedSource;

  /// The source passed to [preloadNext], for assertions.
  AudioSource? get preloadedNext => _preloadedNext;

  /// Current internal state, for assertions.
  PlaybackState get state => _state;

  /// Whether the engine has been initialized.
  bool get isInitialized => _initialized;

  /// Whether the engine output is muted.
  bool get isMuted => _muted;

  /// The current playback speed multiplier.
  double get speed => _speed;

  /// Current transient fade gain multiplier (0.0–1.0), for tests.
  double get fadeGain => _fadeGain;

  /// Effective volume after applying [fadeGain], for tests.
  double get effectiveVolume => (_volume * _fadeGain).clamp(0.0, 1.0);

  /// Sequence of fade gains passed to [setFadeGain], for tests.
  final List<double> fadeGainHistory = [];

  /// Set the fake duration before or after [open].
  set fakeDuration(Duration d) {
    _duration = d;
    _durationCtrl.add(d);
  }

  /// Advances position by [delta] and emits on the position stream.
  void simulateTick(Duration delta) {
    _position += delta;
    if (_position >= _duration) {
      _position = _duration;
      simulateCompletion();
      return;
    }
    _positionCtrl.add(_position);
  }

  /// Moves the engine into [PlaybackState.completed].
  void simulateCompletion() {
    _state = PlaybackState.completed;
    _playbackStateCtrl.add(_state);
  }

  /// Mimics the real engine moving by itself to the preloaded track:
  /// the preloaded source becomes the opened one WITHOUT an [open] call,
  /// a `completed` event is emitted (as `MpvAudioEngine` does for a
  /// playlist advance), then playback continues.
  void simulateGaplessAdvance() {
    final next = _preloadedNext;
    if (next == null) return;
    _openedSource = next;
    _preloadedNext = null;
    _position = Duration.zero;
    _positionCtrl.add(_position);
    _playbackStateCtrl.add(PlaybackState.completed);
    _state = PlaybackState.playing;
    _playbackStateCtrl.add(_state);
  }

  /// Emits an error. Only moves to error state if fatal.
  void simulateError(AudioError error) {
    if (error.isFatal) {
      _state = PlaybackState.error;
      _playbackStateCtrl.add(_state);
    }
    _errorCtrl.add(error);
  }

  // ── Lifecycle ───────────────────────────────────────────────────────

  @override
  Future<void> init() async {
    _initialized = true;
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
    await _playbackStateCtrl.close();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _volumeCtrl.close();
    await _errorCtrl.close();
    await _devicesCtrl.close();
    await _streamInfoCtrl.close();
  }

  // ── Capabilities ────────────────────────────────────────────────────

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        exclusiveMode: false,
        gapless: false,
        equalizer: true,
        replayGain: true,
      );

  // ── Transport ───────────────────────────────────────────────────────

  @override
  Future<void> open(
    AudioSource source, {
    bool autoPlay = false,
    bool continuingGapless = false,
  }) async {
    // Mimics the real engine: a gapless confirmation does not reload.
    if (continuingGapless &&
        _state == PlaybackState.playing &&
        _openedSource?.uri == source.uri) {
      return;
    }
    openCallCount++;
    _openedSource = source;
    _position = Duration.zero;
    _state = autoPlay ? PlaybackState.playing : PlaybackState.paused;
    _positionCtrl.add(_position);
    _durationCtrl.add(_duration);
    _playbackStateCtrl.add(_state);
    _streamInfo = const AudioStreamInfo(
      codec: 'fake',
      container: 'fake',
      sampleRate: 44100,
      bitDepth: 16,
      channels: 2,
    );
    _streamInfoCtrl.add(_streamInfo);
  }

  @override
  Future<void> play() async {
    if (_state == PlaybackState.completed) {
      _position = Duration.zero;
      _positionCtrl.add(_position);
    }
    _state = PlaybackState.playing;
    _playbackStateCtrl.add(_state);
  }

  @override
  Future<void> pause() async {
    _state = PlaybackState.paused;
    _playbackStateCtrl.add(_state);
  }

  @override
  Future<void> stop() async {
    _state = PlaybackState.idle;
    _position = Duration.zero;
    _openedSource = null;
    _preloadedNext = null;
    _streamInfo = null;
    _playbackStateCtrl.add(_state);
    _positionCtrl.add(_position);
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionCtrl.add(_position);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    _volumeCtrl.add(_volume);
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
  }

  // ── Gapless ─────────────────────────────────────────────────────────

  @override
  Future<void> preloadNext(AudioSource? next) async {
    _preloadedNext = next;
  }

  // ── State streams ───────────────────────────────────────────────────

  @override
  Stream<PlaybackState> get playbackStateStream => _playbackStateCtrl.stream;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<Duration> get durationStream => _durationCtrl.stream;

  @override
  Duration get currentDuration => _duration;

  @override
  Duration get currentPosition => _position;

  @override
  Stream<double> get volumeStream => _volumeCtrl.stream;

  @override
  double get currentVolume => _volume;

  @override
  double get currentFadeGain => _fadeGain;

  @override
  Future<void> setFadeGain(double gain) async {
    final clamped = gain.clamp(0.0, 1.0);
    _fadeGain = clamped;
    fadeGainHistory.add(clamped);
  }

  @override
  Stream<AudioError> get errorStream => _errorCtrl.stream;

  // ── Output devices ──────────────────────────────────────────────────

  @override
  Stream<List<AudioDevice>> get devicesStream async* {
    yield devices;
    yield* _devicesCtrl.stream;
  }

  @override
  List<AudioDevice> get devices => List<AudioDevice>.unmodifiable(fakeDevices);

  @override
  Future<void> refreshDevices() async {
    _devicesCtrl.add(devices);
  }

  @override
  AudioDevice get currentDevice => _currentDevice;

  @override
  Future<void> selectDevice(String id) async {
    final match = fakeDevices.where((d) => d.id == id).firstOrNull;
    _currentDevice = match ?? AudioDevice(id: id, name: id);
  }

  @override
  Future<void> setExclusiveMode(bool enabled) async {
    _exclusiveMode = enabled;
  }

  @override
  bool get isExclusiveMode => _exclusiveMode;

  // ── DSP: Equalizer ──────────────────────────────────────────────────

  @override
  Future<void> setEqEnabled(bool enabled) async {
    _eqEnabled = enabled;
  }

  @override
  bool get isEqEnabled => _eqEnabled;

  @override
  Future<void> setEqGains(List<double> gains) async {
    if (gains.length != 10) {
      throw ArgumentError('Expected exactly 10 EQ gains, got ${gains.length}');
    }
    _eqGains = gains.map((g) => g.clamp(-12.0, 12.0)).toList();
  }

  @override
  List<double> get eqGains => List<double>.unmodifiable(_eqGains);

  @override
  Future<void> setPreamp(double preampDb) async {
    _preamp = preampDb.clamp(-12.0, 12.0);
  }

  @override
  double get preamp => _preamp;

  // ── DSP: ReplayGain ─────────────────────────────────────────────────

  @override
  Future<void> setReplayGainMode(ReplayGainMode mode) async {
    _replayGainMode = mode;
  }

  @override
  ReplayGainMode get replayGainMode => _replayGainMode;

  @override
  Future<void> setReplayGainPreamp(double preampDb) async {
    _replayGainPreamp = preampDb.clamp(-24.0, 24.0);
  }

  @override
  double get replayGainPreamp => _replayGainPreamp;

  // ── Stream info ─────────────────────────────────────────────────────

  @override
  AudioStreamInfo? get currentStreamInfo => _streamInfo;

  @override
  Stream<AudioStreamInfo?> get streamInfoStream => _streamInfoCtrl.stream;
}
