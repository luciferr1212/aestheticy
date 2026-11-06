import 'package:flutter/material.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/track_audio_source_mapper.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'library_header.dart';
import 'track_table.dart';

/// Tracks library screen displaying a virtualized table of all audio tracks with
/// currently-playing row highlight, 3-bar animated equalizer, and playback wiring.
class TracksView extends StatefulWidget {
  /// The library data repository.
  final LibraryRepository repository;

  /// The audio playback controller.
  final PlaybackController controller;

  /// The settings store for persisting trackSort.
  final SettingsStore settingsStore;

  /// Creates a [TracksView].
  const TracksView({
    super.key,
    required this.repository,
    required this.controller,
    required this.settingsStore,
  });

  @override
  State<TracksView> createState() => _TracksViewState();
}

class _TracksViewState extends State<TracksView> {
  List<Track> _tracks = [];
  List<Track> _searchResults = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  TrackSort _resolveSort(String key) {
    return switch (key) {
      'artist' => TrackSort.artistAsc,
      'album' => TrackSort.albumAsc,
      'title' => TrackSort.titleAsc,
      _ => TrackSort.titleAsc,
    };
  }

  Future<void> _loadTracks() async {
    final sortKey = widget.settingsStore.settings.trackSort;
    final trackSort = _resolveSort(sortKey);
    final tracks = await widget.repository.listTracks(
      sort: trackSort,
      limit: 100000,
    );

    if (sortKey == 'duration') {
      tracks.sort((a, b) => a.durationMs.compareTo(b.durationMs));
    }

    if (mounted) {
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    }
  }

  Future<void> _onSearchChanged(String query) async {
    setState(() {
      _searchQuery = query.trim();
    });

    if (_searchQuery.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    final results = await widget.repository.search(_searchQuery);
    _applySort(results, widget.settingsStore.settings.trackSort);

    if (mounted) {
      setState(() {
        _searchResults = results;
      });
    }
  }

  void _applySort(List<Track> list, String sortKey) {
    switch (sortKey) {
      case 'artist':
        list.sort((a, b) =>
            (a.artist ?? '').toLowerCase().compareTo((b.artist ?? '').toLowerCase()));
      case 'album':
        list.sort((a, b) =>
            (a.album ?? '').toLowerCase().compareTo((b.album ?? '').toLowerCase()));
      case 'duration':
        list.sort((a, b) => a.durationMs.compareTo(b.durationMs));
      case 'title':
      default:
        list.sort((a, b) =>
            (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase()));
        break;
    }
  }

  void _onSortChanged(String newSort) {
    widget.settingsStore.update((s) => s.copyWith(trackSort: newSort));
    _loadTracks();
  }

  Future<void> _playTrackAt(int index) async {
    final tracks = _searchQuery.isNotEmpty ? _searchResults : _tracks;
    if (tracks.isEmpty || index < 0 || index >= tracks.length) return;

    final sources = tracks.map((t) => t.toAudioSource()).toList();
    await widget.controller.playQueue(sources, startIndex: index);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final tracks = _searchQuery.isNotEmpty ? _searchResults : _tracks;
    final currentSort = widget.settingsStore.settings.trackSort;
    final reduceMotion = widget.settingsStore.settings.reduceMotion;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LibraryHeader(
            title: context.t('nav.tracks'),
            settingsStore: widget.settingsStore,
            itemCount: tracks.length,
            itemCountLabel: context.t('tracks.count'),
            searchQuery: _searchQuery,
            onSearchChanged: _onSearchChanged,
            sortOptions: const ['title', 'artist', 'album', 'duration'],
            currentSort: currentSort,
            onSortChanged: _onSortChanged,
          ),
          const SizedBox(height: 16),

          // Shared TrackTable
          Expanded(
            child: StreamBuilder<AudioSource?>(
              stream: widget.controller.currentStream,
              initialData: widget.controller.queue.current,
              builder: (context, trackSnapshot) {
                final activeSource = trackSnapshot.data;

                return StreamBuilder<PlaybackState>(
                  stream: widget.controller.stateStream,
                  initialData: widget.controller.currentState,
                  builder: (context, stateSnapshot) {
                    final isPlaying =
                        stateSnapshot.data == PlaybackState.playing;

                    return TrackTable(
                      rows: tracks
                          .map((t) => TrackTableRow.fromTrack(t))
                          .toList(),
                      currentPlayingPath: activeSource?.uri,
                      isPlaying: isPlaying,
                      reduceMotion: reduceMotion,
                      controller: widget.controller,
                      listViewKey: const Key('tracks_list_view'),
                      onPlay: (index, row) => _playTrackAt(index),
                      emptyPlaceholder: Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No tracks match "$_searchQuery"'
                              : 'No tracks in library',
                          style: AppTypography.body
                              .copyWith(color: AppColors.textMuted),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
