/// Album detail view showing tracklist and metadata.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/library/cover_cache.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/track_audio_source_mapper.dart';

/// Screen displaying the tracklist and metadata for a specific album.
class AlbumDetailScreen extends StatefulWidget {
  /// The album summary to view.
  final AlbumSummary album;

  /// The library repository for querying tracks.
  final LibraryRepository repository;

  /// The audio playback controller.
  final PlaybackController controller;

  /// Creates an [AlbumDetailScreen].
  const AlbumDetailScreen({
    super.key,
    required this.album,
    required this.repository,
    required this.controller,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<Track> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    final tracks = await widget.repository.tracksOfAlbum(
      widget.album.album,
      albumArtist: widget.album.albumArtist,
    );
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

  Widget _buildCover() {
    final coverKey = widget.album.coverKey;
    if (coverKey != null && CoverCache.hasCover(coverKey)) {
      final file = File(CoverCache.pathFor(coverKey));
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          file,
          width: 140,
          height: 140,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildPlaceholder(),
        ),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: const Color(0xFF222226),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Icon(Icons.album, size: 54, color: Colors.white24),
      ),
    );
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
              widget.album.album,
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
                // Album Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCover(),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.album.album,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.album.albumArtist ?? 'Unknown Artist',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFFC3B1E1),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.album.trackCount} track${widget.album.trackCount == 1 ? '' : 's'}'
                              '${widget.album.year != null ? ' • ${widget.album.year}' : ''}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _tracks.isEmpty ? null : () => _playTrackAt(0),
                              icon: const Icon(Icons.play_arrow, size: 20),
                              label: const Text('Play Album'),
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
                            'No tracks found in this album.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _tracks.length,
                          itemBuilder: (context, index) {
                            final track = _tracks[index];
                            final trackNumber = track.trackNo?.toString() ?? '${index + 1}';
                            final title = track.title ?? 'Unknown Track';

                            return ListTile(
                              dense: true,
                              leading: SizedBox(
                                width: 28,
                                child: Text(
                                  trackNumber,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              title: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                track.artist ?? 'Unknown Artist',
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
