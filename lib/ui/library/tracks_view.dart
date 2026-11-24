import 'package:flutter/foundation.dart';
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
import 'library_data_cache.dart';
import 'library_header.dart';
import 'library_placeholders.dart';
import 'library_view_controls.dart';
import 'sort_direction_button.dart';
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

  /// Optional in-memory library data cache.
  final LibraryDataCache? dataCache;

  /// Creates a [TracksView].
  const TracksView({
    super.key,
    required this.repository,
    required this.controller,
    required this.settingsStore,
    this.dataCache,
  });

  @override
  State<TracksView> createState() => _TracksViewState();
}

class _TracksViewState extends State<TracksView> {
  List<Track> _tracks = [];
  List<Track> _searchResults = [];
  int _searchRequestId = 0;
  String _searchQuery = '';
  bool _isLoading = true;
  LibraryDataCache? _activeCache;

  @override
  void initState() {
    super.initState();
    if (widget.dataCache?.tracks != null) {
      _tracks = List.from(widget.dataCache!.tracks!);
      final sortKey = widget.settingsStore.settings.trackSort;
      final reversed = widget.settingsStore.settings.tracksSortReversed;
      _applySort(_tracks, sortKey, reversed);
      _isLoading = false;
    }
    _loadTracks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cache = widget.dataCache ?? LibraryDataCacheScope.maybeOf(context);
    if (cache != _activeCache) {
      _activeCache?.removeListener(_onCacheChanged);
      _activeCache = cache;
      _activeCache?.addListener(_onCacheChanged);
      if (_isLoading && cache != null && cache.tracks != null) {
        _tracks = List.from(cache.tracks!);
        final sortKey = widget.settingsStore.settings.trackSort;
        final reversed = widget.settingsStore.settings.tracksSortReversed;
        _applySort(_tracks, sortKey, reversed);
        _isLoading = false;
      }
    }
  }

  @override
  void dispose() {
    _activeCache?.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() {
    if (!mounted) return;
    final cache = _activeCache;
    if (cache == null) return;
    if (cache.tracks != null) {
      final sorted = List<Track>.from(cache.tracks!);
      final sortKey = widget.settingsStore.settings.trackSort;
      final reversed = widget.settingsStore.settings.tracksSortReversed;
      _applySort(sorted, sortKey, reversed);
      if (!listEquals(_tracks, sorted) || _isLoading) {
        setState(() {
          _tracks = sorted;
          _isLoading = false;
        });
      }
      if (_searchQuery.isNotEmpty) {
        _refreshSearch();
      }
    } else {
      _loadTracks();
    }
  }

  Future<void> _refreshSearch() async {
    final query = _searchQuery;
    if (query.isEmpty) return;
    final reqId = ++_searchRequestId;
    final results = await widget.repository.search(query);
    _applySort(
      results,
      widget.settingsStore.settings.trackSort,
      widget.settingsStore.settings.tracksSortReversed,
    );
    if (mounted &&
        _searchRequestId == reqId &&
        _searchQuery == query &&
        !listEquals(_searchResults, results)) {
      setState(() {
        _searchResults = results;
      });
    }
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
    final reversed = widget.settingsStore.settings.tracksSortReversed;
    final trackSort = _resolveSort(sortKey);
    final tracks = await widget.repository.listTracks(
      sort: trackSort,
      limit: 100000,
    );

    _applySort(tracks, sortKey, reversed);

    if (mounted) {
      final changed = !listEquals(_tracks, tracks) || _isLoading;
      if (changed) {
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onSearchChanged(String query) async {
    final trimmed = query.trim();
    final reqId = ++_searchRequestId;
    setState(() {
      _searchQuery = trimmed;
      if (trimmed.isEmpty) {
        _searchResults = [];
      }
    });

    if (trimmed.isEmpty) {
      return;
    }

    final results = await widget.repository.search(trimmed);
    _applySort(
      results,
      widget.settingsStore.settings.trackSort,
      widget.settingsStore.settings.tracksSortReversed,
    );

    if (mounted && _searchRequestId == reqId && _searchQuery == trimmed) {
      setState(() {
        _searchResults = results;
      });
    }
  }

  void _applySort(List<Track> list, String sortKey, bool reversed) {
    list.sort((a, b) {
      int cmp;
      switch (sortKey) {
        case 'artist':
          cmp = compareLocaleAware(a.artist ?? '', b.artist ?? '');
          break;
        case 'album':
          cmp = compareLocaleAware(a.album ?? '', b.album ?? '');
          break;
        case 'duration':
          cmp = a.durationMs.compareTo(b.durationMs);
          break;
        case 'recentlyAdded':
          cmp = b.addedAt.compareTo(a.addedAt);
          break;
        case 'title':
        default:
          cmp = compareLocaleAware(a.title ?? '', b.title ?? '');
          break;
      }
      return reversed ? -cmp : cmp;
    });
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
      return TracksViewPlaceholder(settingsStore: widget.settingsStore);
    }

    final tracks = _searchQuery.isNotEmpty ? _searchResults : _tracks;
    final settings = widget.settingsStore.settings;
    final currentSort = settings.trackSort;
    final reduceMotion = settings.reduceMotion;

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
            showControls: false,
          ),
          const SizedBox(height: 12),
          LibraryViewControls(
            sortOptions: const ['title', 'artist', 'album', 'duration', 'recentlyAdded'],
            currentSort: currentSort,
            onSortChanged: _onSortChanged,
            sortDirection: SortDirection.fromReversed(settings.tracksSortReversed),
            onSortDirectionChanged: (newDir) {
              widget.settingsStore.update(
                (s) => s.copyWith(tracksSortReversed: newDir.isReversed),
              );
              _loadTracks();
            },
            reduceMotion: reduceMotion,
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
                              ? context.t(
                                  'tracks.emptySearch',
                                  args: {'query': _searchQuery},
                                )
                              : context.t('tracks.emptyLibrary'),
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
