/// Artist detail view showing tracklist and albums.
library;

import 'package:flutter/material.dart';

import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/features/library/artist_rules_sheet.dart';
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
    final tracks = await widget.repository.tracksOfArtist(
      widget.artist.name,
      artistKey: widget.artist.key,
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

  Future<void> _showUnmergeDialog() async {
    final allAliases = await widget.repository.listAliases();
    final artistAliases = allAliases
        .where(
          (a) =>
              a.canonicalKey == widget.artist.key ||
              a.aliasKey == widget.artist.key,
        )
        .toList();

    if (!mounted) return;

    if (artistAliases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No merged aliases found for this artist.'),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E22),
          title: const Text('Un-merge Artist'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: artistAliases.length,
              itemBuilder: (itemCtx, index) {
                final alias = artistAliases[index];
                return ListTile(
                  dense: true,
                  title: Text(alias.aliasKey),
                  subtitle: Text('Merged into ${alias.canonicalName}'),
                  trailing: TextButton(
                    key: Key('confirm_unmerge_${alias.aliasKey}'),
                    onPressed: () async {
                      final dialogNav = Navigator.of(dialogCtx);
                      await widget.repository.unmergeArtist(alias.aliasKey);
                      dialogNav.pop();
                      await _loadTracks();
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Un-merged ${alias.aliasKey}'),
                          ),
                        );
                      }
                    },
                    child: const Text('Un-merge'),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
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
        actions: [
          PopupMenuButton<String>(
            key: const Key('artist_detail_menu_button'),
            icon: const Icon(Icons.more_vert),
            onSelected: (val) async {
              if (val == 'unmerge') {
                await _showUnmergeDialog();
              } else if (val == 'rules') {
                await ArtistRulesSheet.show(
                  context,
                  repository: widget.repository,
                );
                await _loadTracks();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'unmerge',
                child: Row(
                  children: [
                    Icon(Icons.call_split, size: 16),
                    SizedBox(width: 8),
                    Text('Un-merge…'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'rules',
                child: Row(
                  children: [
                    Icon(Icons.rule, size: 16),
                    SizedBox(width: 8),
                    Text('Artist rules'),
                  ],
                ),
              ),
            ],
          ),
        ],
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
                        child: Icon(
                          Icons.person,
                          size: 40,
                          color: Color(0xFFC3B1E1),
                        ),
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
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed:
                                  _tracks.isEmpty ? null : () => _playTrackAt(0),
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
                          itemBuilder: (trackContext, index) {
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                track.album ?? 'Unknown Album',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatDuration(track.durationMs),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  if (track.artist != null &&
                                      track.artist!.trim().isNotEmpty)
                                    PopupMenuButton<String>(
                                      key: Key('track_menu_${track.id}'),
                                      icon: const Icon(
                                        Icons.more_vert,
                                        size: 16,
                                        color: Colors.grey,
                                      ),
                                      onSelected: (val) async {
                                        if (val == 'no_split' &&
                                            track.artist != null) {
                                          final messenger =
                                              ScaffoldMessenger.of(context);
                                          await widget.repository.addNoSplit(
                                            track.artist!,
                                          );
                                          if (mounted) {
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Treating "${track.artist}" as one artist',
                                                ),
                                              ),
                                            );
                                            await _loadTracks();
                                          }
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'no_split',
                                          child: Text(
                                            'Treat "${track.artist}" as one artist',
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
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
