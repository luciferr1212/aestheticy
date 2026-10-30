/// The contract every audio backend must satisfy.
///
/// The UI and all other code talk to this interface — they never import
/// the underlying audio package. Swap the implementation (e.g. for tests)
/// without touching any consumer code.
library;

import 'audio_models.dart';

/// Abstract audio engine that all player code programs against.
///
/// Implementations:
/// * [MpvAudioEngine] — real playback via `mpv_audio_kit` (Windows).
/// * [FakeAudioEngine] — deterministic in-memory fake for unit tests.
abstract class AudioEngine {
  // ── Lifecycle ───────────────────────────────────────────────────────

  /// Initializes the engine and its native resources.
  ///
  /// Must be called once before any other method. Calling it again after
  /// [dispose] is an error.
  Future<void> init();

  /// Tears down the engine and releases all resources.
  ///
  /// Idempotent — safe to call more than once.
  Future<void> dispose();

  // ── Capabilities ────────────────────────────────────────────────────

  /// Declares which optional features this implementation supports.
  EngineCapabilities get capabilities;

  // ── Transport ───────────────────────────────────────────────────────

  /// Loads [source] as the current track and optionally starts playback.
  Future<void> open(AudioSource source, {bool autoPlay = false});

  /// Starts or resumes playback.
  Future<void> play();

  /// Pauses playback, keeping the current position.
  Future<void> pause();

  /// Stops playback and unloads the current track.
  Future<void> stop();

  /// Seeks to [position] within the current track.
  Future<void> seek(Duration position);

  /// Sets the software volume. [volume] is clamped to 0.0–1.0.
  Future<void> setVolume(double volume);

  /// Mutes or unmutes the output.
  Future<void> setMuted(bool muted);

  /// Sets the playback speed multiplier (1.0 = normal).
  Future<void> setSpeed(double speed);

  // ── Gapless ─────────────────────────────────────────────────────────

  /// Preloads the [next] track so the transition from the current track
  /// is gapless. Pass `null` to cancel a pending preload.
  Future<void> preloadNext(AudioSource? next);

  // ── State streams ───────────────────────────────────────────────────

  /// The current playback lifecycle state.
  Stream<PlaybackState> get playbackStateStream;

  /// The current playback position, updated frequently.
  Stream<Duration> get positionStream;

  /// The total duration of the current track.
  Stream<Duration> get durationStream;

  /// The current software volume (0.0–1.0).
  Stream<double> get volumeStream;

  /// Typed errors from the engine.
  Stream<AudioError> get errorStream;

  // ── Output devices ──────────────────────────────────────────────────

  /// All output devices currently detected.
  Stream<List<AudioDevice>> get devicesStream;

  /// The currently selected output device.
  AudioDevice get currentDevice;

  /// Selects the output device by its [id].
  Future<void> selectDevice(String id);

  /// Enables or disables exclusive / WASAPI-exclusive mode.
  Future<void> setExclusiveMode(bool enabled);

  /// Whether exclusive mode is currently active.
  bool get isExclusiveMode;

  // ── DSP: Equalizer ──────────────────────────────────────────────────

  /// Standard 10-band center frequencies in Hz.
  ///
  /// 31, 63, 125, 250, 500, 1 k, 2 k, 4 k, 8 k, 16 k.
  static const List<int> eqFrequencies = [
    31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
  ];

  /// Enables or disables the 10-band equalizer.
  Future<void> setEqEnabled(bool enabled);

  /// Whether the equalizer is currently active.
  bool get isEqEnabled;

  /// Sets the gain for each of the 10 bands.
  ///
  /// [gains] must have exactly 10 elements, each clamped to –12 … +12 dB.
  Future<void> setEqGains(List<double> gains);

  /// The current 10-band gains.
  List<double> get eqGains;

  /// Sets the EQ pre-amplification in dB (–12 … +12).
  Future<void> setPreamp(double preampDb);

  /// The current pre-amp value in dB.
  double get preamp;

  // ── DSP: ReplayGain ─────────────────────────────────────────────────

  /// Sets the ReplayGain normalization mode.
  Future<void> setReplayGainMode(ReplayGainMode mode);

  /// The current ReplayGain mode.
  ReplayGainMode get replayGainMode;

  /// Sets an additional pre-amp in dB applied during ReplayGain
  /// normalization (–24 … +24).
  Future<void> setReplayGainPreamp(double preampDb);

  /// The current ReplayGain pre-amp in dB.
  double get replayGainPreamp;

  // ── Stream info ─────────────────────────────────────────────────────

  /// Information about the audio stream currently being decoded.
  ///
  /// Fields may be `null` when no track is loaded or the info is not
  /// available yet.
  AudioStreamInfo? get currentStreamInfo;

  /// Emits whenever stream information changes or is decoded.
  Stream<AudioStreamInfo?> get streamInfoStream;
}
