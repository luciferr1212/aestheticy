/// Real [AudioEngine] implementation backed by `mpv_audio_kit`.
///
/// This is the **only** file in the project that imports the audio package.
/// Every mpv property or API used is annotated with a comment.
library;

import 'dart:async';

import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'audio_engine.dart';
import 'audio_models.dart';

/// Bit-depth heuristic: maps the mpv sample-format enum to an integer bit depth.
int? _bitDepthFromFormat(mpv.Format? format) => switch (format) {
      mpv.Format.u8 || mpv.Format.u8Planar => 8,
      mpv.Format.s16 || mpv.Format.s16Planar => 16,
      mpv.Format.s32 || mpv.Format.s32Planar => 32,
      mpv.Format.s64 || mpv.Format.s64Planar => 64,
      mpv.Format.float32 || mpv.Format.float32Planar => 32,
      mpv.Format.float64 || mpv.Format.float64Planar => 64,
      _ => null,
    };

/// Bit-depth parser from raw format name string (e.g. 's16', 's24', 's32', 'fltp').
int? _bitDepthFromFormatName(String? formatName) {
  if (formatName == null) return null;
  final f = formatName.toLowerCase();
  if (f.contains('16')) return 16;
  if (f.contains('24')) return 24;
  if (f.contains('32')) return 32;
  if (f.contains('64')) return 64;
  if (f.contains('8')) return 8;
  return null;
}

/// Cleans up raw container string from mpv.
///
/// For example, if mpv reports 'mov,mp4,m4a,3gp,3g2,mj2' and the file has extension
/// 'm4a', it returns 'm4a' instead of the long list.
String? _cleanContainer(String? rawFormat, String? pathOrUri) {
  if (rawFormat == null || rawFormat.trim().isEmpty) return null;

  String? ext;
  if (pathOrUri != null && pathOrUri.isNotEmpty) {
    final dot = pathOrUri.lastIndexOf('.');
    if (dot != -1 && dot < pathOrUri.length - 1) {
      ext = pathOrUri
          .substring(dot + 1)
          .toLowerCase()
          .split('?')
          .first
          .split('#')
          .first;
    }
  }

  final candidates = rawFormat
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toList();

  if (candidates.isEmpty) return null;
  if (candidates.length == 1) return candidates.first;

  if (ext != null) {
    if (candidates.contains(ext)) return ext;
    if (ext == 'm4a' || ext == 'alac') return 'm4a';
    if (ext == 'mp3') return 'mp3';
    if (ext == 'flac') return 'flac';
    if (ext == 'wav') return 'wav';
    if (ext == 'ogg') return 'ogg';
    if (ext == 'opus') return 'opus';
    if (ext == 'aac') return 'aac';
  }

  return candidates.first;
}

/// Lossless codec heuristic — checks the codec short name.
bool? _isLossless(String? codec) {
  if (codec == null || codec.isEmpty) return null;
  final lower = codec.toLowerCase();
  const lossless = [
    'flac',
    'alac',
    'ape',
    'wav',
    'pcm',
    'wavpack',
    'tta',
    'aiff',
    'dsd',
    'mlp',
    'truehd',
  ];
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
  String? _currentUri;
  int _lastMpvPlaylistIndex = 0;

  // ── Stream controllers ──────────────────────────────────────────────

  final _playbackStateCtrl = StreamController<PlaybackState>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _volumeCtrl = StreamController<double>.broadcast();
  final _errorCtrl = StreamController<AudioError>.broadcast();
  final _devicesCtrl = StreamController<List<AudioDevice>>.broadcast();
  final _streamInfoCtrl = StreamController<AudioStreamInfo?>.broadcast();

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

    // Disable automatic sidecar file loading (subtitles/.lrc and companion audio files).
    // This prevents mpv from failing when external .lrc lyrics or sidecar tracks are present.
    try {
      await _player!.setRawProperty('sub-auto', 'no');
    } catch (_) {
      // Fallback: the .lrc safety net filter in errorStream handles it if unsupported.
    }
    try {
      await _player!.setRawProperty('audio-file-auto', 'no');
    } catch (_) {
      // Fallback: safety net filter handles it.
    }

    _listenToStreams();
  }

  void _listenToStreams() {
    final p = _player!;

    // playbackState  →  derived from mpv.MpvPlaybackState
    _subs.add(p.stream.playbackState.listen((s) {
      final state = switch (s) {
        mpv.MpvPlaybackState.idle => PlaybackState.idle,
        mpv.MpvPlaybackState.loading => PlaybackState.loading,
        mpv.MpvPlaybackState.playing => PlaybackState.playing,
        mpv.MpvPlaybackState.paused => PlaybackState.paused,
        mpv.MpvPlaybackState.buffering => PlaybackState.loading,
        mpv.MpvPlaybackState.completed => PlaybackState.completed,
      };
      _playbackStateCtrl.add(state);

      // Refresh stream info once playback starts or resumes
      if (s == mpv.MpvPlaybackState.playing || s == mpv.MpvPlaybackState.paused) {
        _rebuildStreamInfo();
      }
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
      final msg = e.message;
      final isLyricsOrSubError = msg.toLowerCase().contains('.lrc') ||
          msg.toLowerCase().contains('external file') ||
          msg.toLowerCase().contains('subtitles') ||
          msg.toLowerCase().contains('sub track');

      if (isLyricsOrSubError) {
        // Non-fatal lyrics/subtitle warning. Do NOT abort or skip audio track!
        _errorCtrl.add(AudioError(
          code: AudioErrorCode.engineFailure,
          message: 'Lyrics file failed to load: $msg',
          isFatal: false,
        ));
        return;
      }

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
          _errorCtrl.add(AudioError(code: code, message: msg, isFatal: true));
        case mpv.LogError():
          // Internal mpv log warnings are non-fatal diagnostics.
          _errorCtrl.add(AudioError(
            code: AudioErrorCode.engineFailure,
            message: msg,
            isFatal: false,
          ));
      }
    }));

    // devices  →  mpv property `audio-device-list`
    _subs.add(p.stream.audioDevices.listen((list) {
      _devicesCtrl.add(
        list.map((d) => AudioDevice(id: d.name, name: d.description)).toList(),
      );
    }));

    // playlist  →  detects when mpv moves to the next preloaded playlist entry (gapless)
    _subs.add(p.stream.playlist.listen((playlist) {
      if (playlist.index >= 0 && playlist.index > _lastMpvPlaylistIndex) {
        _lastMpvPlaylistIndex = playlist.index;
        // Previous track reached EOF and mpv transitioned to the next entry.
        _playbackStateCtrl.add(PlaybackState.completed);
      }
    }));

    // audio device  →  mpv property `audio-device`
    _subs.add(p.stream.audioDevice.listen((d) {
      _currentDevice = AudioDevice(id: d.name, name: d.description);
    }));

    // stream info  →  combined from audioParams, audioBitrate, fileFormat, currentAudioTrack
    _subs.add(p.stream.audioParams.listen((params) {
      _rebuildStreamInfo(params: params);
    }));
    _subs.add(p.stream.audioBitrate.listen((bps) {
      _rebuildStreamInfo(bitrateOverride: bps);
    }));
    _subs.add(p.stream.fileFormat.listen((fmt) {
      _rebuildStreamInfo(containerOverride: fmt);
    }));
    _subs.add(p.stream.currentAudioTrack.listen((track) {
      _rebuildStreamInfo(trackOverride: track);
    }));
  }

  /// Merges the latest values into [_currentStreamInfo] and emits on [_streamInfoCtrl].
  void _rebuildStreamInfo({
    mpv.AudioParams? params,
    double? bitrateOverride,
    String? containerOverride,
    mpv.MpvTrack? trackOverride,
  }) {
    final p = _player;
    if (p == null) return;

    final ap = params ?? p.state.audioParams;
    final track = trackOverride ?? p.state.currentAudioTrack;

    final codec = ap.codec ?? ap.codecName ?? track?.codec ?? track?.codecDesc;
    final rawContainer = containerOverride ?? p.state.fileFormat;
    final container = _cleanContainer(rawContainer, _currentUri ?? p.state.path);

    final bitrate = bitrateOverride ??
        (p.state.audioBitrate != null && p.state.audioBitrate! > 0
            ? p.state.audioBitrate
            : track?.demuxBitrate);

    final sampleRate = ap.sampleRate ?? track?.sampleRate;
    final channels = ap.channelCount ?? track?.channelCount;
    final bitDepth =
        _bitDepthFromFormat(ap.format) ?? _bitDepthFromFormatName(track?.formatName);

    _currentStreamInfo = AudioStreamInfo(
      codec: (codec != null && codec.isNotEmpty) ? codec : null,
      container: container,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
      bitrateKbps: bitrate != null && bitrate > 0 ? bitrate / 1000.0 : null,
      isLossless: _isLossless(codec),
    );

    _streamInfoCtrl.add(_currentStreamInfo);
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
    await _streamInfoCtrl.close();
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
    _currentUri = source.uri;

    final p = _player;
    if (p != null) {
      final currentMpvPath = p.state.path;
      final playlist = p.state.playlist;
      // If mpv is already actively playing this track (via gapless playlist advance),
      // avoid re-opening the file from scratch which would kill seamless playback.
      if (p.state.playing &&
          (currentMpvPath == source.uri ||
              (playlist.index >= 0 &&
                  playlist.index < playlist.items.length &&
                  playlist.items[playlist.index].uri == source.uri))) {
        _rebuildStreamInfo();
        return;
      }
    }

    _lastMpvPlaylistIndex = 0;
    // player.open()  →  mpv command `loadfile`
    await _player!.open(
      mpv.Media(source.uri, extras: source.extras),
      play: autoPlay,
    );
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
    _currentUri = null;
    _currentStreamInfo = null;
    _lastMpvPlaylistIndex = 0;
    _streamInfoCtrl.add(null);
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
  /// Auto-protection against digital clipping:
  /// When positive band gains are used, reduces the preamp automatically so that
  /// the peak sum (preamp + maxPositiveGain) does not exceed 0.0 dBFS, avoiding
  /// digital distortion. When the EQ is disabled, volume gain is reset to 0.0 dB.
  Future<void> _applyEq() async {
    if (!_eqEnabled) {
      // Remove all audio effects and reset preamp volume gain to 0
      await _player!.setAudioEffects([]);
      await _player!.setVolumeGain(0.0);
      return;
    }

    final effects = <mpv.AudioEffect>[];

    // Auto-protection against clipping:
    // If positive band gains are present, lower the preamp so (effectivePreamp + maxPositiveGain) <= 0.0 dB.
    final maxPositiveGain = _eqGains.fold(0.0, (max, g) => g > max ? g : max);
    final double effectivePreamp;
    if (maxPositiveGain > 0.0 && (_preamp + maxPositiveGain > 0.0)) {
      effectivePreamp = -maxPositiveGain;
    } else {
      effectivePreamp = _preamp;
    }

    await _player!.setVolumeGain(effectivePreamp);

    // 10-band EQ: each band is a separate EqualizerEffect instance.
    for (var i = 0; i < 10; i++) {
      effects.add(mpv.EqualizerEffect(
        frequency: AudioEngine.eqFrequencies[i].toDouble(),
        gain: _eqGains[i],
        width: 1.0, // ~1 octave Q factor
      ));
    }

    await _player!.setAudioEffects(effects);
  }

  // ── DSP: ReplayGain ─────────────────────────────────────────────────

  @override
  Future<void> setReplayGainMode(ReplayGainMode mode) async {
    _replayGainMode = mode;
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

  @override
  Stream<AudioStreamInfo?> get streamInfoStream => _streamInfoCtrl.stream;
}
