/// Data models shared by the audio engine interface and its consumers.
///
/// No package imports here — these are plain Dart value types that keep
/// the [AudioEngine] contract free of any specific audio-library dependency.
library;

// ── Playback state ──────────────────────────────────────────────────────

/// Mutually-exclusive lifecycle of the audio engine.
enum PlaybackState {
  /// No track loaded.
  idle,

  /// A track is being opened / buffered.
  loading,

  /// Audio is being produced.
  playing,

  /// Playback is paused at the current position.
  paused,

  /// The current track reached its natural end.
  completed,

  /// An unrecoverable error occurred.
  error,
}

// ── Audio source ────────────────────────────────────────────────────────

/// A single piece of audio that can be opened by the engine.
///
/// Wraps a URI (file path, `file://`, `http://`, `asset:///`, …) and
/// optional consumer metadata the engine carries through but does not
/// interpret.
class AudioSource {
  /// The URI of the audio resource.
  final String uri;

  /// Optional application-level metadata (title, artist, …).
  ///
  /// The engine ignores these; they are carried through for the UI.
  final Map<String, String>? extras;

  /// Creates an [AudioSource] pointing at [uri].
  const AudioSource(this.uri, {this.extras});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioSource && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  String toString() => 'AudioSource($uri)';
}

// ── Errors ──────────────────────────────────────────────────────────────

/// Classification of audio-engine errors.
enum AudioErrorCode {
  /// The file was not found or could not be opened.
  fileNotFound,

  /// The file's codec or container is not supported.
  unsupportedFormat,

  /// The requested output device could not be opened.
  deviceUnavailable,

  /// An internal engine failure that does not fit the other codes.
  engineFailure,
}

/// A typed error emitted by the audio engine.
class AudioError {
  /// What category of failure occurred.
  final AudioErrorCode code;

  /// A human-readable description of the error.
  final String message;

  /// Whether this error aborts playback of the current track.
  ///
  /// Fatal errors cause the playback controller to skip to the next track.
  /// Non-fatal errors (e.g. failed external lyrics or subtitle files)
  /// are reported for diagnostics without interrupting playback.
  final bool isFatal;

  /// Creates a typed [AudioError].
  const AudioError({
    required this.code,
    required this.message,
    this.isFatal = true,
  });

  @override
  String toString() => 'AudioError($code: $message, fatal: $isFatal)';
}

// ── Stream info ─────────────────────────────────────────────────────────

/// Describes the audio stream currently being decoded.
///
/// Every field is nullable because the information may not be available
/// for every format.
class AudioStreamInfo {
  /// Codec short name (e.g. `flac`, `aac`, `mp3`).
  final String? codec;

  /// Container format (e.g. `mp4`, `flac`, `ogg`).
  final String? container;

  /// Sample rate in Hz.
  final int? sampleRate;

  /// Bits per sample (e.g. 16, 24, 32). `null` for lossy codecs that
  /// don't expose a fixed bit depth.
  final int? bitDepth;

  /// Number of audio channels.
  final int? channels;

  /// Average bitrate in kilobits per second.
  final double? bitrateKbps;

  /// Whether the stream is a lossless encoding (FLAC, ALAC, WAV, …).
  ///
  /// Determined heuristically from the codec name; may be `null` when
  /// the engine cannot decide.
  final bool? isLossless;

  /// Creates a stream-info snapshot.
  const AudioStreamInfo({
    this.codec,
    this.container,
    this.sampleRate,
    this.bitDepth,
    this.channels,
    this.bitrateKbps,
    this.isLossless,
  });

  @override
  String toString() =>
      'AudioStreamInfo(codec: $codec, container: $container, '
      'sampleRate: $sampleRate, bitDepth: $bitDepth, channels: $channels, '
      'bitrateKbps: $bitrateKbps, isLossless: $isLossless)';
}

// ── Output device ───────────────────────────────────────────────────────

/// An audio output device detected by the engine.
class AudioDevice {
  /// Internal identifier used by the engine to select this device.
  final String id;

  /// Human-readable name shown in device pickers.
  final String name;

  /// Creates an [AudioDevice].
  const AudioDevice({required this.id, required this.name});

  /// The system-default automatic device.
  static const AudioDevice auto = AudioDevice(id: 'auto', name: 'Auto');

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AudioDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AudioDevice($id, "$name")';
}

// ── ReplayGain ──────────────────────────────────────────────────────────

/// ReplayGain normalization mode.
enum ReplayGainMode {
  /// Disabled.
  off,

  /// Per-track gain normalization.
  track,

  /// Per-album gain normalization (preserves inter-track dynamics).
  album,
}

// ── Engine capabilities ─────────────────────────────────────────────────

/// Declares which optional features the engine implementation supports.
///
/// Other code can read this at runtime to hide UI for unsupported
/// features (e.g. hiding the exclusive-mode toggle on a fake engine).
class EngineCapabilities {
  /// Whether [AudioEngine.setExclusiveMode] does something.
  final bool exclusiveMode;

  /// Whether [AudioEngine.preloadNext] enables gapless transitions.
  final bool gapless;

  /// Whether the 10-band equalizer is functional.
  final bool equalizer;

  /// Whether ReplayGain normalization is supported.
  final bool replayGain;

  /// Creates a capability descriptor.
  const EngineCapabilities({
    required this.exclusiveMode,
    required this.gapless,
    required this.equalizer,
    required this.replayGain,
  });

  @override
  String toString() =>
      'EngineCapabilities(exclusive: $exclusiveMode, gapless: $gapless, '
      'eq: $equalizer, replayGain: $replayGain)';
}
