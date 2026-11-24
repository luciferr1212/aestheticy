import 'package:flutter/material.dart' hide RepeatMode;

import 'package:aestheticy/audio/audio_engine.dart';
import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';

/// Queue listing and transport quick-actions card for [AudioLabScreen].
class AudioLabQueueSection extends StatelessWidget {
  /// Active playback controller.
  final PlaybackController controller;

  /// Current playback state.
  final PlaybackState playbackState;

  /// Callback to pick and enqueue local audio files.
  final VoidCallback onPickFiles;

  /// Callback to toggle shuffle mode.
  final VoidCallback onToggleShuffle;

  /// Callback to cycle repeat mode.
  final VoidCallback onCycleRepeat;

  /// Callback to toggle play/pause.
  final VoidCallback onPlayPause;

  /// Callback to clear upcoming queue entries.
  final VoidCallback onClearUpcoming;

  /// Callback to log events in Audio Lab.
  final ValueChanged<String> onLog;

  /// Creates an [AudioLabQueueSection].
  const AudioLabQueueSection({
    super.key,
    required this.controller,
    required this.playbackState,
    required this.onPickFiles,
    required this.onToggleShuffle,
    required this.onCycleRepeat,
    required this.onPlayPause,
    required this.onClearUpcoming,
    required this.onLog,
  });

  @override
  Widget build(BuildContext context) {
    final queue = controller.queue;
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
                  onPressed: onPickFiles,
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
                              ? (playbackState == PlaybackState.playing
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
                          onLog('Queue tap track #$i: $title');
                          await controller.playTrack(i);
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
                  onPressed: onToggleShuffle,
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
                  onPressed: onCycleRepeat,
                ),
                IconButton(
                  tooltip: 'Previous Track',
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () => controller.skipPrevious(),
                ),
                IconButton.filled(
                  tooltip:
                      playbackState == PlaybackState.playing ? 'Pause' : 'Play',
                  icon: Icon(
                    playbackState == PlaybackState.playing
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  onPressed: onPlayPause,
                ),
                IconButton(
                  tooltip: 'Next Track',
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => controller.skipNext(),
                ),
                TextButton.icon(
                  onPressed: onClearUpcoming,
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
}

/// Seekbar and volume/mute card for [AudioLabScreen].
class AudioLabTransportSection extends StatelessWidget {
  /// Underlying audio engine.
  final AudioEngine engine;

  /// Currently loaded track source.
  final AudioSource? currentSource;

  /// Current playback position.
  final Duration position;

  /// Current track duration.
  final Duration duration;

  /// Current volume level (0.0 to 1.0).
  final double volume;

  /// Whether audio output is muted.
  final bool isMuted;

  /// Whether the user is actively dragging the seek slider.
  final bool isDraggingSeek;

  /// Current drag seek position in milliseconds.
  final double dragSeekMs;

  /// Called while dragging the seek slider.
  final ValueChanged<double> onSeekDragUpdate;

  /// Called when seek drag finishes.
  final ValueChanged<double> onSeekDragEnd;

  /// Called when mute button is toggled.
  final VoidCallback onToggleMute;

  /// Called when volume slider changes.
  final ValueChanged<double> onVolumeChanged;

  /// Formats a duration as `mm:ss`.
  final String Function(Duration) formatDuration;

  /// Creates an [AudioLabTransportSection].
  const AudioLabTransportSection({
    super.key,
    required this.engine,
    required this.currentSource,
    required this.position,
    required this.duration,
    required this.volume,
    required this.isMuted,
    required this.isDraggingSeek,
    required this.dragSeekMs,
    required this.onSeekDragUpdate,
    required this.onSeekDragEnd,
    required this.onToggleMute,
    required this.onVolumeChanged,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final currentMs = isDraggingSeek
        ? dragSeekMs
        : position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Playback & Volume',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Now Playing: ${currentSource?.extras?['title'] ?? currentSource?.uri ?? 'Nothing'}',
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
                  formatDuration(
                    isDraggingSeek
                        ? Duration(milliseconds: dragSeekMs.toInt())
                        : position,
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: currentMs.clamp(0.0, maxMs),
                    min: 0.0,
                    max: maxMs,
                    onChanged: onSeekDragUpdate,
                    onChangeEnd: onSeekDragEnd,
                  ),
                ),
                Text(
                  formatDuration(duration),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            // Volume bar
            Row(
              children: [
                IconButton(
                  tooltip: isMuted ? 'Unmute' : 'Mute',
                  icon: Icon(
                    isMuted || volume == 0
                        ? Icons.volume_off
                        : (volume < 0.5 ? Icons.volume_down : Icons.volume_up),
                  ),
                  onPressed: onToggleMute,
                ),
                Expanded(
                  child: Slider(
                    value: volume.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    divisions: 100,
                    label: '${(volume * 100).toInt()}%',
                    onChanged: onVolumeChanged,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${(volume * 100).toInt()}%',
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
}
