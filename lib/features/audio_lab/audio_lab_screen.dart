/// Developer screen exercising every feature of the [AudioEngine]
/// through [PlaybackController].
///
/// Plain Material widgets, calm dark theme, function over looks.
/// This screen strictly depends on [PlaybackController] and [AudioEngine]
/// and NEVER imports the audio package directly.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';

import 'package:aestheticy/audio/audio_engine.dart';
import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';

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
  static const List<String> _eqLabels = [
    '31',
    '62',
    '125',
    '250',
    '500',
    '1k',
    '2k',
    '4k',
    '8k',
    '16k',
  ];
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

  void _cycleRepeat() {
    final next = switch (widget.controller.queue.repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    setState(() => widget.controller.queue.repeatMode = next);
    _log('RepeatMode: ${next.name}');
  }

  void _toggleShuffle() {
    final current = widget.controller.queue.isShuffled;
    setState(() => widget.controller.queue.setShuffle(!current));
    _log('Shuffle: ${!current ? 'ON' : 'OFF'}');
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
            _buildQueueSection(),
            const Divider(height: 32),
            _buildTransportSection(),
            const Divider(height: 32),
            _buildOutputSection(),
            const Divider(height: 32),
            _buildEqualizerSection(),
            const Divider(height: 32),
            _buildReplayGainSection(),
            const Divider(height: 32),
            _buildStreamInfoSection(),
            const Divider(height: 32),
            _buildEventLogSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Sections ────────────────────────────────────────────────────────

  Widget _buildQueueSection() {
    final queue = widget.controller.queue;
    final items = queue.items;
    final currentIdx = queue.currentIndex;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.queue_music, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Queue (${items.length} tracks)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _pickAudioFiles,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Files'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(
                  child: Text(
                    'No audio files in queue. Click "Add Files" to pick music.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: Material(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final isCurrent = i == currentIdx;
                      final title = item.extras?['title'] ?? item.uri;

                      return ListTile(
                        key: Key('queue_item_$i'),
                        dense: true,
                        selected: isCurrent,
                        selectedTileColor:
                            const Color(0xFF6B5B7B).withValues(alpha: 0.3),
                        leading: Icon(
                          isCurrent
                              ? (_playbackState == PlaybackState.playing
                                  ? Icons.volume_up
                                  : Icons.pause)
                              : Icons.music_note,
                          size: 18,
                          color:
                              isCurrent ? const Color(0xFFC3B1E1) : Colors.grey,
                        ),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isCurrent
                                ? const Color(0xFFE0D8E8)
                                : Colors.grey.shade300,
                          ),
                        ),
                        trailing: Text(
                          '#${i + 1}',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        onTap: () async {
                          _log('Queue tap track #$i: $title');
                          await widget.controller.playTrack(i);
                        },
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Shuffle (${queue.isShuffled ? "On" : "Off"})',
                  icon: Icon(
                    Icons.shuffle,
                    color: queue.isShuffled ? const Color(0xFFC3B1E1) : Colors.grey,
                  ),
                  onPressed: _toggleShuffle,
                ),
                IconButton(
                  tooltip: 'Repeat (${queue.repeatMode.name})',
                  icon: Icon(
                    switch (queue.repeatMode) {
                      RepeatMode.off => Icons.repeat,
                      RepeatMode.all => Icons.repeat,
                      RepeatMode.one => Icons.repeat_one,
                    },
                    color: queue.repeatMode != RepeatMode.off
                        ? const Color(0xFFC3B1E1)
                        : Colors.grey,
                  ),
                  onPressed: _cycleRepeat,
                ),
                IconButton(
                  tooltip: 'Previous Track',
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () => widget.controller.skipPrevious(),
                ),
                IconButton.filled(
                  tooltip: _playbackState == PlaybackState.playing
                      ? 'Pause'
                      : 'Play',
                  icon: Icon(
                    _playbackState == PlaybackState.playing
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  onPressed: _playPause,
                ),
                IconButton(
                  tooltip: 'Next Track',
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => widget.controller.skipNext(),
                ),
                TextButton.icon(
                  onPressed: () {
                    widget.controller.queue.clear();
                    widget.controller.stop();
                    setState(() {});
                    _log('Queue cleared');
                  },
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportSection() {
    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final currentMs = _isDraggingSeek
        ? _dragSeekMs
        : _position.inMilliseconds.clamp(0, _duration.inMilliseconds).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Playback & Volume',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Now Playing: ${_currentSource?.extras?['title'] ?? _currentSource?.uri ?? 'Nothing'}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFC3B1E1),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            // Seek bar
            Row(
              children: [
                Text(
                  _formatDuration(
                    _isDraggingSeek
                        ? Duration(milliseconds: _dragSeekMs.toInt())
                        : _position,
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: currentMs.clamp(0.0, maxMs),
                    min: 0.0,
                    max: maxMs,
                    onChanged: (val) {
                      setState(() {
                        _isDraggingSeek = true;
                        _dragSeekMs = val;
                      });
                    },
                    onChangeEnd: (val) async {
                      _isDraggingSeek = false;
                      await widget.engine.seek(
                        Duration(milliseconds: val.toInt()),
                      );
                      _log('Seek to ${_formatDuration(Duration(milliseconds: val.toInt()))}');
                    },
                  ),
                ),
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            // Volume bar
            Row(
              children: [
                IconButton(
                  tooltip: _isMuted ? 'Unmute' : 'Mute',
                  icon: Icon(
                    _isMuted || _volume == 0
                        ? Icons.volume_off
                        : (_volume < 0.5 ? Icons.volume_down : Icons.volume_up),
                  ),
                  onPressed: () async {
                    final next = !_isMuted;
                    setState(() => _isMuted = next);
                    await widget.engine.setMuted(next);
                    _log('Mute: ${next ? 'ON' : 'OFF'}');
                  },
                ),
                Expanded(
                  child: Slider(
                    value: _volume.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    divisions: 100,
                    label: '${(_volume * 100).toInt()}%',
                    onChanged: (val) async {
                      setState(() => _volume = val);
                      await widget.engine.setVolume(val);
                    },
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${(_volume * 100).toInt()}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Audio Output', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.speaker, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedDeviceId,
                    items: _devices.map((d) {
                      final displayName = d.name.trim().isNotEmpty ? d.name : d.id;
                      return DropdownMenuItem<String>(
                        value: d.id,
                        child: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (id) async {
                      if (id != null) {
                        setState(() => _selectedDeviceId = id);
                        await widget.engine.selectDevice(id);
                        _log('Selected audio device: $id');
                      }
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh devices',
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
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
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('WASAPI Exclusive Mode'),
              subtitle: const Text(
                'Direct hardware output. Warning: Exclusive mode gives direct DAC control and will silence audio from other Windows apps.',
                style: TextStyle(fontSize: 12, color: Colors.orangeAccent),
              ),
              value: _isExclusive,
              onChanged: (val) async {
                setState(() => _isExclusive = val);
                await widget.engine.setExclusiveMode(val);
                _log('WASAPI Exclusive mode: ${val ? 'ON' : 'OFF'}');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEqualizerSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.equalizer, size: 20),
                const SizedBox(width: 8),
                Text('10-Band Equalizer',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Switch(
                  value: _isEqEnabled,
                  onChanged: (val) async {
                    setState(() => _isEqEnabled = val);
                    await widget.engine.setEqEnabled(val);
                    _log('Equalizer: ${val ? 'ENABLED' : 'DISABLED'}');
                  },
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('eq_reset_button'),
                  onPressed: _resetEq,
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Preamp slider
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    'Preamp: ${_preamp.toStringAsFixed(1)} dB',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _preamp.clamp(-12.0, 12.0),
                    min: -12.0,
                    max: 12.0,
                    divisions: 48,
                    onChanged: _isEqEnabled
                        ? (val) async {
                            setState(() => _preamp = val);
                            await widget.engine.setPreamp(val);
                          }
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 10 band sliders
            for (var i = 0; i < 10; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 55,
                      child: Text(
                        '${_eqLabels[i]} Hz',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: _eqGains[i].clamp(-12.0, 12.0),
                        min: -12.0,
                        max: 12.0,
                        divisions: 48,
                        onChanged: _isEqEnabled
                            ? (val) async {
                                setState(() => _eqGains[i] = val);
                                await widget.engine.setEqGains(_eqGains);
                              }
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 55,
                      child: Text(
                        '${_eqGains[i] >= 0 ? "+" : ""}${_eqGains[i].toStringAsFixed(1)} dB',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplayGainSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            const Icon(Icons.graphic_eq, size: 20),
            const SizedBox(width: 8),
            Text('ReplayGain Mode',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            DropdownButton<ReplayGainMode>(
              value: _replayGainMode,
              items: const [
                DropdownMenuItem(
                  value: ReplayGainMode.off,
                  child: Text('Off'),
                ),
                DropdownMenuItem(
                  value: ReplayGainMode.track,
                  child: Text('Track'),
                ),
                DropdownMenuItem(
                  value: ReplayGainMode.album,
                  child: Text('Album'),
                ),
              ],
              onChanged: (mode) async {
                if (mode != null) {
                  setState(() => _replayGainMode = mode);
                  await widget.engine.setReplayGainMode(mode);
                  _log('ReplayGainMode set to ${mode.name}');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamInfoSection() {
    final info = _streamInfo;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Text('Stream Info',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.2),
                1: FlexColumnWidth(2.0),
              },
              children: [
                _buildInfoRow('Codec', info?.codec ?? 'Unknown'),
                _buildInfoRow('Container', info?.container ?? 'Unknown'),
                _buildInfoRow(
                  'Sample Rate',
                  info?.sampleRate != null ? '${info!.sampleRate} Hz' : 'Unknown',
                ),
                _buildInfoRow(
                  'Bit Depth',
                  info?.bitDepth != null ? '${info!.bitDepth}-bit' : 'Unknown',
                ),
                _buildInfoRow(
                  'Channels',
                  info?.channels != null ? '${info!.channels}' : 'Unknown',
                ),
                _buildInfoRow(
                  'Bitrate',
                  info?.bitrateKbps != null
                      ? '${info!.bitrateKbps!.toStringAsFixed(1)} kbps'
                      : 'Unknown',
                ),
                _buildInfoRow(
                  'Lossless',
                  info?.isLossless == true
                      ? 'Yes'
                      : (info?.isLossless == false ? 'No' : 'Unknown'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TableRow _buildInfoRow(String label, String value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Text(
            value,
            style: TextStyle(color: Colors.grey.shade300, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildEventLogSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terminal, size: 20),
                const SizedBox(width: 8),
                Text('Event Log',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${_logs.length} events',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _copyLog,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Log'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No events logged yet.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _logs.length,
                      padding: const EdgeInsets.all(8.0),
                      itemBuilder: (context, i) {
                        final logText = _logs[i];
                        final isErr = logText.contains('AudioError');
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            logText,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: isErr
                                  ? Colors.redAccent
                                  : Colors.grey.shade300,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
