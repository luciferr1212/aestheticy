import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/collections/user_collections.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/track_audio_source_mapper.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/settings_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'library_data_cache.dart';
import 'library_placeholders.dart';
import 'library_view_controls.dart';
import 'sort_direction_button.dart';
import 'track_table.dart';

/// Screen displaying recently played tracks (up to 200) based on play events.
class RecentlyPlayedView extends StatefulWidget {
  /// Library repository for loading history.
  final LibraryRepository repository;

  /// Audio controller.
  final PlaybackController controller;

  /// Settings store.
  final SettingsStore settingsStore;

  /// User collections store.
  final UserCollections collections;

  /// Optional in-memory library data cache.
  final LibraryDataCache? dataCache;

  /// Creates a [RecentlyPlayedView].
  const RecentlyPlayedView({
    super.key,
    required this.repository,
    required this.controller,
    required this.settingsStore,
    required this.collections,
    this.dataCache,
  });

  @override
  State<RecentlyPlayedView> createState() => _RecentlyPlayedViewState();
}

class _RecentlyPlayedViewState extends State<RecentlyPlayedView> {
  List<Track> _tracks = [];
  bool _isLoading = true;
  LibraryDataCache? _activeCache;

  @override
  void initState() {
    super.initState();
    if (widget.dataCache?.recentTracks != null) {
      _tracks = List.from(widget.dataCache!.recentTracks!);
      _isLoading = false;
    }
    _loadRecentTracks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cache = widget.dataCache ?? LibraryDataCacheScope.maybeOf(context);
    if (cache != _activeCache) {
      _activeCache?.removeListener(_onCacheChanged);
      _activeCache = cache;
      _activeCache?.addListener(_onCacheChanged);
      if (_isLoading && cache != null && cache.recentTracks != null) {
        _tracks = List.from(cache.recentTracks!);
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
    if (cache.recentTracks != null) {
      if (!listEquals(_tracks, cache.recentTracks) || _isLoading) {
        setState(() {
          _tracks = List.from(cache.recentTracks!);
          _isLoading = false;
        });
      }
    } else {
      _loadRecentTracks();
    }
  }

  Future<void> _loadRecentTracks() async {
    final tracks = await widget.repository.recentlyPlayedTracks(limit: 200);
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

  Future<void> _playTracks({int startIndex = 0}) async {
    if (_tracks.isEmpty) return;
    final sources = _tracks.map((t) => t.toAudioSource()).toList();
    final safeIndex = (startIndex >= 0 && startIndex < sources.length)
        ? startIndex
        : 0;
    await widget.controller.playQueue(sources, startIndex: safeIndex);
  }

  List<Track> _sortRecent(List<Track> list, String sortKey, bool reversed) {
    if (sortKey == 'playedAt') {
      return reversed ? list.reversed.toList() : List<Track>.from(list);
    }
    final sorted = List<Track>.from(list);
    sorted.sort((a, b) {
      int cmp;
      switch (sortKey) {
        case 'title':
          cmp = compareLocaleAware(a.title ?? '', b.title ?? '');
          break;
        case 'artist':
          cmp = compareLocaleAware(a.artist ?? '', b.artist ?? '');
          break;
        case 'duration':
          cmp = a.durationMs.compareTo(b.durationMs);
          break;
        default:
          cmp = 0;
          break;
      }
      return reversed ? -cmp : cmp;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return RecentlyPlayedViewPlaceholder(settingsStore: widget.settingsStore);
    }

    final settings = widget.settingsStore.settings;
    final reduceMotion = settings.reduceMotion;
    final sortedTracks = _sortRecent(
      _tracks,
      settings.recentlyPlayedSort,
      settings.recentlyPlayedSortReversed,
    );
    final rows = sortedTracks.map((t) => TrackTableRow.fromTrack(t)).toList();

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('nav.recent'),
                      style: AppTypography.display
                          .copyWith(letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${context.formatCountLocalized(_tracks.length)} ${context.t('tracks.count')}',
                      style: AppTypography.body
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              GlassPillButton(
                key: const Key('recent_play_button'),
                label: context.t('album.playAlbum'),
                leadingIcon: Icons.play_arrow,
                variant: GlassButtonVariant.primary,
                size: GlassButtonSize.medium,
                onPressed: sortedTracks.isEmpty ? null : () => _playTracks(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          LibraryViewControls(
            sortOptions: const ['playedAt', 'title', 'artist', 'duration'],
            currentSort: settings.recentlyPlayedSort,
            onSortChanged: (newSort) {
              widget.settingsStore.update((s) => s.copyWith(recentlyPlayedSort: newSort));
            },
            sortDirection: SortDirection.fromReversed(settings.recentlyPlayedSortReversed),
            onSortDirectionChanged: (newDir) {
              widget.settingsStore.update((s) => s.copyWith(recentlyPlayedSortReversed: newDir.isReversed));
            },
            reduceMotion: reduceMotion,
          ),
          const SizedBox(height: 16),

          // TrackTable
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
                            rows: rows,
                            currentPlayingPath: activeSource?.uri,
                            isPlaying: isPlaying,
                            reduceMotion: reduceMotion,
                            controller: widget.controller,
                            userCollections: widget.collections,
                            listViewKey: const Key('recent_tracks_list'),
                            onPlay: (index, row) {
                              _playTracks(startIndex: index);
                            },
                            emptyPlaceholder: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.history,
                                    size: 64,
                                    color: AppColors.textMuted,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    context.t('recent.empty'),
                                    style: AppTypography.title
                                        .copyWith(color: AppColors.text),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    context.t('recent.emptyDescription'),
                                    style: AppTypography.body
                                        .copyWith(color: AppColors.textMuted),
                                  ),
                                ],
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
