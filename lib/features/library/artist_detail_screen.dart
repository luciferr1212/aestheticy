/// Artist detail view showing tracklist and albums.
library;

import 'package:flutter/material.dart';

import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/track_audio_source_mapper.dart';

/// Screen displaying the tracklist for a specific artist.
class ArtistDetailScreen extends StatefulWidget {
  /// The artist summary to view.
  final ArtistSummary artist;

  /// The library repository for querying tracks.
  final LibraryRepository repository;

  /// The audio playback controller.
  final PlaybackController controller;

  /// Creates an [ArtistDetailScreen].
  const ArtistDetailScreen({
    super.key,
    required this.artist,
    required this.repository,
    required this.controller,
  });

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  List<Track> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    final tracks = await widget.repository.tracksOfArtist(widget.artist.name);
    if (mounted) {
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    }
  }

  Future<void> _playTrackAt(int index) async {
    if (_tracks.isEmpty) return;
    final sources = _tracks.map((t) => t.toAudioSource()).toList();
    await widget.controller.playQueue(sources, startIndex: index);
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.artist.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              'by mido',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Artist Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 36,
                        backgroundColor: Color(0xFF222226),
                        child: Icon(Icons.person, size: 40, color: Color(0xFFC3B1E1)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.artist.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.artist.albumCount} album${widget.artist.albumCount == 1 ? '' : 's'} • '
                              '${widget.artist.trackCount} track${widget.artist.trackCount == 1 ? '' : 's'}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: _tracks.isEmpty ? null : () => _playTrackAt(0),
                              icon: const Icon(Icons.play_arrow, size: 20),
                              label: const Text('Play Artist'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Tracks List
                Expanded(
                  child: _tracks.isEmpty
                      ? const Center(
                          child: Text(
                            'No tracks found for this artist.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _tracks.length,
                          itemBuilder: (context, index) {
                            final track = _tracks[index];
                            final title = track.title ?? 'Unknown Track';

                            return ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.music_note,
                                size: 20,
                                color: Colors.grey,
                              ),
                              title: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                track.album ?? 'Unknown Album',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              trailing: Text(
                                _formatDuration(track.durationMs),
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              onTap: () => _playTrackAt(index),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
