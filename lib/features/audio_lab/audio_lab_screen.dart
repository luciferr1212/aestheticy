/// Developer screen exercising every feature of the [AudioEngine]
/// through [PlaybackController].
///
/// Plain Material widgets, calm dark theme, function over looks.
/// This screen strictly depends on [PlaybackController] and [AudioEngine]
/// and NEVER imports the audio package directly.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:aestheticy/audio/audio_engine.dart';
import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/features/audio_lab/widgets/audio_lab_diagnostics_sections.dart';
import 'package:aestheticy/features/audio_lab/widgets/audio_lab_dsp_sections.dart';
import 'package:aestheticy/features/audio_lab/widgets/audio_lab_playback_sections.dart';

/// Developer Audio Lab test bench screen.
class AudioLabScreen extends StatefulWidget {
  /// The audio engine instance.
  final AudioEngine engine;

  /// The playback controller coordinating queue and playback.
  final PlaybackController controller;

  /// Creates an [AudioLabScreen].
  const AudioLabScreen({
    super.key,
    required this.engine,
    required this.controller,
  });

  @override
  State<AudioLabScreen> createState() => _AudioLabScreenState();
}

class _AudioLabScreenState extends State<AudioLabScreen> {
  // ── Subscriptions ───────────────────────────────────────────────────
  final List<StreamSubscription<dynamic>> _subs = [];

  // ── State ───────────────────────────────────────────────────────────
  PlaybackState _playbackState = PlaybackState.idle;
  AudioSource? _currentSource;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  bool _isMuted = false;
  bool _isDraggingSeek = false;
  double _dragSeekMs = 0.0;

  // Devices & Exclusive
  List<AudioDevice> _devices = [AudioDevice.auto];
  String _selectedDeviceId = AudioDevice.auto.id;
  bool _isExclusive = false;

  // Equalizer
  bool _isEqEnabled = false;
  List<double> _eqGains = List<double>.filled(10, 0.0);
  double _preamp = 0.0;

  // ReplayGain
  ReplayGainMode _replayGainMode = ReplayGainMode.off;

  // Stream Info
  AudioStreamInfo? _streamInfo;

  // Event Log
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _initEngineState();
    _listenToStreams();
    _log('Audio Lab initialized');
  }

  void _initEngineState() {
    _isExclusive = widget.engine.isExclusiveMode;
    final initialDevices = widget.engine.devices;
    if (initialDevices.isNotEmpty) {
      _devices = initialDevices;
    }
    _selectedDeviceId = widget.engine.currentDevice.id;
    _isEqEnabled = widget.engine.isEqEnabled;
    _eqGains = List<double>.from(widget.engine.eqGains);
    _preamp = widget.engine.preamp;
    _replayGainMode = widget.engine.replayGainMode;
    _streamInfo = widget.engine.currentStreamInfo;
  }

  void _listenToStreams() {
    _subs.add(widget.controller.stateStream.listen((state) {
      setState(() {
        _playbackState = state;
        _streamInfo = widget.engine.currentStreamInfo;
      });
      _log('PlaybackState changed: ${state.name}');
    }));

    _subs.add(widget.controller.currentStream.listen((src) {
      setState(() {
        _currentSource = src;
        _streamInfo = widget.engine.currentStreamInfo;
      });
      _log('Current track: ${src?.extras?['title'] ?? src?.uri ?? 'None'}');
    }));

    _subs.add(widget.controller.errorStream.listen((err) {
      _log('AudioError: [${err.code.name}] ${err.message}');
    }));

    _subs.add(widget.engine.positionStream.listen((pos) {
      if (!_isDraggingSeek) {
        setState(() => _position = pos);
      }
    }));

    _subs.add(widget.engine.durationStream.listen((dur) {
      setState(() => _duration = dur);
    }));

    _subs.add(widget.engine.volumeStream.listen((vol) {
      setState(() => _volume = vol);
    }));

    _subs.add(widget.engine.devicesStream.listen((devs) {
      setState(() {
        _devices = devs.isEmpty ? [AudioDevice.auto] : devs;
        if (!_devices.any((d) => d.id == _selectedDeviceId)) {
          final previousId = _selectedDeviceId;
          _selectedDeviceId = AudioDevice.auto.id;
          widget.engine.selectDevice(_selectedDeviceId);
          _log('Selected device "$previousId" disappeared; fell back to auto');
        }
      });
      _log('Devices updated: ${_devices.length} device(s) found');
    }));

    _subs.add(widget.engine.streamInfoStream.listen((info) {
      setState(() => _streamInfo = info);
      if (info != null && (info.codec != null || info.container != null)) {
        _log('Stream info: ${info.codec ?? "unknown"} [${info.container ?? "unknown"}]');
      }
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }

  void _log(String event) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    setState(() {
      _logs.insert(0, '[$timeStr] $event');
    });
  }

  // ── Actions ─────────────────────────────────────────────────────────

  Future<void> _pickAudioFiles() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp3',
          'flac',
          'm4a',
          'aac',
          'wav',
          'ogg',
          'opus',
          'wma',
          'aiff',
        ],
      );

      if (files.isNotEmpty) {
        var addedCount = 0;
        for (final f in files) {
          final path = f.path;
          if (path != null && path.isNotEmpty) {
            final fileName = f.name;
            widget.controller.queue.add(
              AudioSource(path, extras: {'title': fileName}),
            );
            addedCount++;
          }
        }
        setState(() {});
        _log('Added $addedCount file(s) to queue');
      }
    } catch (e) {
      _log('File picker error: $e');
    }
  }

  Future<void> _playPause() async {
    await widget.controller.togglePlayPause();
  }

  Future<void> _cycleRepeat() async {
    await widget.controller.cycleRepeatMode();
    if (!mounted) return;
    setState(() {});
    _log('RepeatMode: ${widget.controller.queue.repeatMode.name}');
  }

  Future<void> _toggleShuffle() async {
    final next = !widget.controller.queue.isShuffled;
    await widget.controller.setShuffle(next);
    if (!mounted) return;
    setState(() {});
    _log('Shuffle: ${next ? 'ON' : 'OFF'}');
  }

  Future<void> _resetEq() async {
    setState(() {
      _eqGains = List<double>.filled(10, 0.0);
      _preamp = 0.0;
    });
    await widget.engine.setEqGains(_eqGains);
    await widget.engine.setPreamp(0.0);
    _log('Equalizer reset to 0 dB');
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _logs.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Log copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ── Build UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Aestheticy — Audio Lab',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              'by mido',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Library',
            icon: const Icon(Icons.library_music),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
          IconButton(
            tooltip: 'Pick Audio Files',
            icon: const Icon(Icons.file_open),
            onPressed: _pickAudioFiles,
          ),
          IconButton(
            tooltip: 'Copy Event Log',
            icon: const Icon(Icons.copy_all),
            onPressed: _copyLog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AudioLabQueueSection(
              controller: widget.controller,
              playbackState: _playbackState,
              onPickFiles: _pickAudioFiles,
              onToggleShuffle: _toggleShuffle,
              onCycleRepeat: _cycleRepeat,
              onPlayPause: _playPause,
              onClearUpcoming: () async {
                await widget.controller.clearUpcoming();
                setState(() {});
                _log('Upcoming queue cleared (current track preserved if playing)');
              },
              onLog: _log,
            ),
            const Divider(height: 32),
            AudioLabTransportSection(
              engine: widget.engine,
              currentSource: _currentSource,
              position: _position,
              duration: _duration,
              volume: _volume,
              isMuted: _isMuted,
              isDraggingSeek: _isDraggingSeek,
              dragSeekMs: _dragSeekMs,
              onSeekDragUpdate: (val) {
                setState(() {
                  _isDraggingSeek = true;
                  _dragSeekMs = val;
                });
              },
              onSeekDragEnd: (val) async {
                _isDraggingSeek = false;
                await widget.engine.seek(
                  Duration(milliseconds: val.toInt()),
                );
                _log('Seek to ${_formatDuration(Duration(milliseconds: val.toInt()))}');
              },
              onToggleMute: () async {
                final next = !_isMuted;
                setState(() => _isMuted = next);
                await widget.engine.setMuted(next);
                _log('Mute: ${next ? 'ON' : 'OFF'}');
              },
              onVolumeChanged: (val) async {
                setState(() => _volume = val);
                await widget.engine.setVolume(val);
              },
              formatDuration: _formatDuration,
            ),
            const Divider(height: 32),
            AudioLabOutputSection(
              devices: _devices,
              selectedDeviceId: _selectedDeviceId,
              isExclusive: _isExclusive,
              onSelectDevice: (id) async {
                if (id != null) {
                  setState(() => _selectedDeviceId = id);
                  await widget.engine.selectDevice(id);
                  _log('Selected audio device: $id');
                }
              },
              onRefreshDevices: () async {
                await widget.engine.refreshDevices();
                setState(() {
                  _devices = widget.engine.devices;
                  if (!_devices.any((d) => d.id == _selectedDeviceId)) {
                    final previousId = _selectedDeviceId;
                    _selectedDeviceId = AudioDevice.auto.id;
                    widget.engine.selectDevice(_selectedDeviceId);
                    _log(
                      'Selected device "$previousId" disappeared; fell back to auto',
                    );
                  }
                });
                _log(
                  'Devices refreshed: ${_devices.length} found (current: $_selectedDeviceId)',
                );
              },
              onToggleExclusive: (val) async {
                setState(() => _isExclusive = val);
                await widget.engine.setExclusiveMode(val);
                _log('WASAPI Exclusive mode: ${val ? 'ON' : 'OFF'}');
              },
            ),
            const Divider(height: 32),
            AudioLabEqualizerSection(
              isEqEnabled: _isEqEnabled,
              eqGains: _eqGains,
              preamp: _preamp,
              onToggleEq: (val) async {
                setState(() => _isEqEnabled = val);
                await widget.engine.setEqEnabled(val);
                _log('Equalizer: ${val ? 'ENABLED' : 'DISABLED'}');
              },
              onResetEq: _resetEq,
              onPreampChanged: (val) async {
                setState(() => _preamp = val);
                await widget.engine.setPreamp(val);
              },
              onBandChanged: (i, val) async {
                setState(() => _eqGains[i] = val);
                await widget.engine.setEqGains(_eqGains);
              },
            ),
            const Divider(height: 32),
            AudioLabReplayGainSection(
              replayGainMode: _replayGainMode,
              onChanged: (mode) async {
                if (mode != null) {
                  setState(() => _replayGainMode = mode);
                  await widget.engine.setReplayGainMode(mode);
                  _log('ReplayGainMode set to ${mode.name}');
                }
              },
            ),
            const Divider(height: 32),
            AudioLabStreamInfoSection(streamInfo: _streamInfo),
            const Divider(height: 32),
            AudioLabEventLogSection(
              logs: _logs,
              onCopyLog: _copyLog,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
