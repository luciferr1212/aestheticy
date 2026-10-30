/// Real [AudioEngine] implementation backed by `mpv_audio_kit`.
///
/// This is the **only** file in the project that imports the audio package.
/// Every mpv property or API used is annotated with a comment.
library;

import 'dart:async';

import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'audio_engine.dart';
import 'audio_models.dart';

/// Bit-depth heuristic: maps the mpv sample-format string to an integer
/// bit depth. Returns `null` for formats where "bit depth" is ambiguous
/// (e.g. compressed or planar float reported as generic "float").
int? _bitDepthFromFormat(mpv.Format? format) => switch (format) {
      mpv.Format.u8 || mpv.Format.u8Planar => 8,
      mpv.Format.s16 || mpv.Format.s16Planar => 16,
      mpv.Format.s32 || mpv.Format.s32Planar => 32,
      mpv.Format.s64 || mpv.Format.s64Planar => 64,
      mpv.Format.float32 || mpv.Format.float32Planar => 32,
      mpv.Format.float64 || mpv.Format.float64Planar => 64,
      _ => null,
    };

/// Lossless codec heuristic — checks the codec short name.
bool? _isLossless(String? codec) {
  if (codec == null || codec.isEmpty) return null;
  final lower = codec.toLowerCase();
  const lossless = ['flac', 'alac', 'ape', 'wav', 'pcm', 'wavpack', 'tta',
      'aiff', 'dsd', 'mlp', 'truehd'];
  for (final l in lossless) {
    if (lower.contains(l)) return true;
  }
  return false;
}

/// Audio engine backed by [mpv.Player] from the `mpv_audio_kit` package.
///
/// All interaction with libmpv goes through this class. Other code only
/// depends on [AudioEngine].
class MpvAudioEngine extends AudioEngine {
  mpv.Player? _player;

  // ── Cached state ────────────────────────────────────────────────────

  bool _eqEnabled = false;
  List<double> _eqGains = List<double>.filled(10, 0.0);
  double _preamp = 0.0;
  ReplayGainMode _replayGainMode = ReplayGainMode.off;
  double _replayGainPreamp = 0.0;
  bool _exclusiveMode = false;
  AudioDevice _currentDevice = AudioDevice.auto;
  AudioStreamInfo? _currentStreamInfo;
  double _volume = 1.0;

  // ── Stream controllers ──────────────────────────────────────────────

  final _playbackStateCtrl = StreamController<PlaybackState>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _volumeCtrl = StreamController<double>.broadcast();
  final _errorCtrl = StreamController<AudioError>.broadcast();
  final _devicesCtrl = StreamController<List<AudioDevice>>.broadcast();

  final List<StreamSubscription<dynamic>> _subs = [];

  // ── Lifecycle ───────────────────────────────────────────────────────

  @override
  Future<void> init() async {
    // MpvAudioKit.ensureInitialized() loads the native libmpv library.
    mpv.MpvAudioKit.ensureInitialized();

    _player = mpv.Player(
      configuration: const mpv.PlayerConfiguration(
        autoPlay: false,
        initialVolume: 100,
      ),
    );

    // Gapless default: mpv property `gapless-audio=weak` (already the
    // package default).

    _listenToStreams();
  }

  void _listenToStreams() {
    final p = _player!;

    // playbackState  →  derived from mpv.MpvPlaybackState
    _subs.add(p.stream.playbackState.listen((s) {
      _playbackStateCtrl.add(switch (s) {
        mpv.MpvPlaybackState.idle => PlaybackState.idle,
        mpv.MpvPlaybackState.loading => PlaybackState.loading,
        mpv.MpvPlaybackState.playing => PlaybackState.playing,
        mpv.MpvPlaybackState.paused => PlaybackState.paused,
        mpv.MpvPlaybackState.buffering => PlaybackState.loading,
        mpv.MpvPlaybackState.completed => PlaybackState.completed,
      });
    }));

    // position  →  mpv property `time-pos`
    _subs.add(p.stream.position.listen(_positionCtrl.add));

    // duration  →  mpv property `duration`
    _subs.add(p.stream.duration.listen(_durationCtrl.add));

    // volume  →  mpv property `volume` (0–100 → 0.0–1.0)
    _subs.add(p.stream.volume.listen((v) {
      _volume = v / 100.0;
      _volumeCtrl.add(_volume);
    }));

    // errors  →  mpv error stream (EndFileError | LogError)
    _subs.add(p.stream.error.listen((e) {
      final AudioErrorCode code;
      switch (e) {
        case mpv.EndFileError():
          code = e.isLoadingError
              ? AudioErrorCode.fileNotFound
              : e.isFormatError
                  ? AudioErrorCode.unsupportedFormat
                  : e.isAudioOutputError
                      ? AudioErrorCode.deviceUnavailable
                      : AudioErrorCode.engineFailure;
        case mpv.LogError():
          code = AudioErrorCode.engineFailure;
      }
      _errorCtrl.add(AudioError(code: code, message: e.message));
    }));

    // devices  →  mpv property `audio-device-list`
    _subs.add(p.stream.audioDevices.listen((list) {
      _devicesCtrl.add(
        list.map((d) => AudioDevice(id: d.name, name: d.description)).toList(),
      );
    }));

    // audio device  →  mpv property `audio-device`
    _subs.add(p.stream.audioDevice.listen((d) {
      _currentDevice = AudioDevice(id: d.name, name: d.description);
    }));

    // stream info  →  combined from audioParams, audioBitrate, fileFormat
    _subs.add(p.stream.audioParams.listen((params) {
      _rebuildStreamInfo(params: params);
    }));
    _subs.add(p.stream.audioBitrate.listen((bps) {
      _rebuildStreamInfo(bitrateOverride: bps);
    }));
    _subs.add(p.stream.fileFormat.listen((fmt) {
      _rebuildStreamInfo(containerOverride: fmt);
    }));
  }

  /// Merges the latest values into [_currentStreamInfo].
  void _rebuildStreamInfo({
    mpv.AudioParams? params,
    double? bitrateOverride,
    String? containerOverride,
  }) {
    final p = _player;
    if (p == null) return;

    final ap = params ?? p.state.audioParams;
    final codec = ap.codec ?? ap.codecName;
    final container = containerOverride ?? p.state.fileFormat;
    final bitrate = bitrateOverride ?? p.state.audioBitrate;

    _currentStreamInfo = AudioStreamInfo(
      codec: codec,
      container: container.isEmpty ? null : container,
      sampleRate: ap.sampleRate,
      bitDepth: _bitDepthFromFormat(ap.format),
      channels: ap.channelCount,
      bitrateKbps: bitrate != null ? bitrate / 1000.0 : null,
      isLossless: _isLossless(codec),
    );
  }

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _player?.dispose();
    _player = null;
    await _playbackStateCtrl.close();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _volumeCtrl.close();
    await _errorCtrl.close();
    await _devicesCtrl.close();
  }

  // ── Capabilities ────────────────────────────────────────────────────

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        exclusiveMode: true, // mpv property: audio-exclusive
        gapless: true, // mpv property: gapless-audio
        equalizer: true, // EqualizerEffect chain
        replayGain: true, // mpv property: replaygain
      );

  // ── Transport ───────────────────────────────────────────────────────

  @override
  Future<void> open(AudioSource source, {bool autoPlay = false}) async {
    // player.open()  →  mpv command `loadfile`
    await _player!.open(mpv.Media(source.uri, extras: source.extras),
        play: autoPlay);
  }

  @override
  Future<void> play() async {
    // player.play()  →  sets mpv property `pause=no`
    await _player!.play();
  }

  @override
  Future<void> pause() async {
    // player.pause()  →  sets mpv property `pause=yes`
    await _player!.pause();
  }

  @override
  Future<void> stop() async {
    // player.stop()  →  mpv command `stop`
    await _player!.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    // player.seek()  →  mpv command `seek <seconds> absolute`
    await _player!.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    // player.setVolume()  →  mpv property `volume` (0–100 scale)
    await _player!.setVolume(clamped * 100.0);
  }

  @override
  Future<void> setMuted(bool muted) async {
    // player.setMute()  →  mpv property `mute`
    await _player!.setMute(muted);
  }

  @override
  Future<void> setSpeed(double speed) async {
    // player.setRate()  →  mpv property `speed`
    await _player!.setRate(speed);
  }

  // ── Gapless ─────────────────────────────────────────────────────────

  @override
  Future<void> preloadNext(AudioSource? next) async {
    if (next == null) {
      // Disable prefetch  →  mpv property `prefetch-playlist=no`
      await _player!.setPrefetchPlaylist(false);
      return;
    }

    // Ensure the next track is in the playlist so mpv can prefetch it.
    final playlist = _player!.state.playlist;
    final currentIdx = playlist.index;

    // If there's already a "next" entry, replace it; otherwise append.
    if (currentIdx + 1 < playlist.items.length) {
      await _player!.replace(currentIdx + 1, mpv.Media(next.uri));
    } else {
      await _player!.add(mpv.Media(next.uri));
    }
    // Enable prefetch  →  mpv property `prefetch-playlist=yes`
    await _player!.setPrefetchPlaylist(true);
  }

  // ── State streams ───────────────────────────────────────────────────

  @override
  Stream<PlaybackState> get playbackStateStream => _playbackStateCtrl.stream;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<Duration> get durationStream => _durationCtrl.stream;

  @override
  Stream<double> get volumeStream => _volumeCtrl.stream;

  @override
  Stream<AudioError> get errorStream => _errorCtrl.stream;

  // ── Output devices ──────────────────────────────────────────────────

  @override
  Stream<List<AudioDevice>> get devicesStream => _devicesCtrl.stream;

  @override
  AudioDevice get currentDevice => _currentDevice;

  @override
  Future<void> selectDevice(String id) async {
    // player.setAudioDevice()  →  mpv property `audio-device`
    await _player!.setAudioDevice(mpv.Device(name: id, description: ''));
  }

  @override
  Future<void> setExclusiveMode(bool enabled) async {
    _exclusiveMode = enabled;
    // player.setAudioExclusive()  →  mpv property `audio-exclusive`
    await _player!.setAudioExclusive(enabled);
  }

  @override
  bool get isExclusiveMode => _exclusiveMode;

  // ── DSP: Equalizer ──────────────────────────────────────────────────

  @override
  Future<void> setEqEnabled(bool enabled) async {
    _eqEnabled = enabled;
    await _applyEq();
  }

  @override
  bool get isEqEnabled => _eqEnabled;

  @override
  Future<void> setEqGains(List<double> gains) async {
    if (gains.length != 10) {
      throw ArgumentError('Expected exactly 10 EQ gains, got ${gains.length}');
    }
    _eqGains = gains.map((g) => g.clamp(-12.0, 12.0)).toList();
    if (_eqEnabled) await _applyEq();
  }

  @override
  List<double> get eqGains => List<double>.unmodifiable(_eqGains);

  @override
  Future<void> setPreamp(double preampDb) async {
    _preamp = preampDb.clamp(-12.0, 12.0);
    if (_eqEnabled) await _applyEq();
  }

  @override
  double get preamp => _preamp;

  /// Builds a chain of 10 [mpv.EqualizerEffect] instances (one per band)
  /// plus an optional volume-gain for the preamp, and applies them
  /// atomically via [mpv.Player.setAudioEffects].
  ///
  /// Each [mpv.EqualizerEffect] maps to FFmpeg's `equalizer` filter:
  /// `frequency` = center Hz, `gain` = dB, `width` = octave bandwidth.
  Future<void> _applyEq() async {
    if (!_eqEnabled) {
      // Remove all audio effects
      await _player!.setAudioEffects([]);
      return;
    }

    final effects = <mpv.AudioEffect>[];

    // Preamp via volume-gain (mpv property: volume-gain, separate from EQ)
    // We apply it as a preamp adjustment before the EQ chain.
    if (_preamp != 0.0) {
      await _player!.setVolumeGain(_preamp);
    } else {
      await _player!.setVolumeGain(0.0);
    }

    // 10-band EQ: each band is a separate EqualizerEffect instance.
    // EqualizerEffect  →  FFmpeg `equalizer` filter
    //   frequency → center frequency in Hz
    //   gain      → boost/cut in dB
    //   width     → bandwidth (Q factor with widthType=q, default 1.0 ≈ 1 octave)
    for (var i = 0; i < 10; i++) {
      effects.add(mpv.EqualizerEffect(
        frequency: AudioEngine.eqFrequencies[i].toDouble(),
        gain: _eqGains[i],
        width: 1.0, // ~1 octave Q factor
      ));
    }

    // player.setAudioEffects()  →  mpv property `af` (audio filter chain)
    await _player!.setAudioEffects(effects);
  }

  // ── DSP: ReplayGain ─────────────────────────────────────────────────

  @override
  Future<void> setReplayGainMode(ReplayGainMode mode) async {
    _replayGainMode = mode;
    // player.setReplayGain()  →  mpv properties `replaygain`,
    //   `replaygain-preamp`, `replaygain-clip`, `replaygain-fallback`
    await _player!.setReplayGain(mpv.ReplayGainSettings(
      mode: switch (mode) {
        ReplayGainMode.off => mpv.ReplayGain.no,
        ReplayGainMode.track => mpv.ReplayGain.track,
        ReplayGainMode.album => mpv.ReplayGain.album,
      },
      preamp: _replayGainPreamp,
    ));
  }

  @override
  ReplayGainMode get replayGainMode => _replayGainMode;

  @override
  Future<void> setReplayGainPreamp(double preampDb) async {
    _replayGainPreamp = preampDb.clamp(-24.0, 24.0);
    if (_replayGainMode != ReplayGainMode.off) {
      await _player!.setReplayGain(mpv.ReplayGainSettings(
        mode: switch (_replayGainMode) {
          ReplayGainMode.off => mpv.ReplayGain.no,
          ReplayGainMode.track => mpv.ReplayGain.track,
          ReplayGainMode.album => mpv.ReplayGain.album,
        },
        preamp: _replayGainPreamp,
      ));
    }
  }

  @override
  double get replayGainPreamp => _replayGainPreamp;

  // ── Stream info ─────────────────────────────────────────────────────

  @override
  AudioStreamInfo? get currentStreamInfo => _currentStreamInfo;
}
