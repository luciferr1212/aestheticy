import 'dart:async';

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
import 'library_view_controls.dart';
import 'sort_direction_button.dart';
import 'track_table.dart';

/// Screen displaying the user's favorite tracks with synchronous updates on toggle,
/// playback controls, and track table.
class FavoritesView extends StatefulWidget {
  /// Library repository for loading favorite tracks.
  final LibraryRepository repository;

  /// User collections store.
  final UserCollections collections;

  /// Playback controller.
  final PlaybackController controller;

  /// Settings store.
  final SettingsStore settingsStore;

  /// Optional in-memory library data cache for automatic refresh after scans.
  final LibraryDataCache? dataCache;

  /// Creates a [FavoritesView].
  const FavoritesView({
    super.key,
    required this.repository,
    required this.collections,
    required this.controller,
    required this.settingsStore,
    this.dataCache,
  });

  @override
  State<FavoritesView> createState() => _FavoritesViewState();
}

class _FavoritesViewState extends State<FavoritesView> {
  LibraryDataCache? _activeCache;
  int _lastCacheRevision = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cache = widget.dataCache ?? LibraryDataCacheScope.maybeOf(context);
    if (cache != _activeCache) {
      _activeCache?.removeListener(_onCacheChanged);
      _activeCache = cache;
      _activeCache?.addListener(_onCacheChanged);
      _lastCacheRevision = _activeCache?.revision ?? -1;
    }
  }

  @override
  void didUpdateWidget(FavoritesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataCache != widget.dataCache) {
      final cache = widget.dataCache ?? LibraryDataCacheScope.maybeOf(context);
      if (cache != _activeCache) {
        _activeCache?.removeListener(_onCacheChanged);
        _activeCache = cache;
        _activeCache?.addListener(_onCacheChanged);
        _lastCacheRevision = _activeCache?.revision ?? -1;
      }
    }
  }

  @override
  void dispose() {
    _activeCache?.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() {
    final cache = _activeCache;
    if (!mounted || cache == null) return;
    if (cache.revision != _lastCacheRevision) {
      _lastCacheRevision = cache.revision;
      unawaited(widget.collections.refresh());
    }
  }

  Future<void> _playFavorites(List<Track> tracks,
      {bool shuffle = false, int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    final sources = tracks.map((t) => t.toAudioSource()).toList();
    if (shuffle) {
      await widget.controller.playShuffled(sources);
    } else {
      final safeIndex = (startIndex >= 0 && startIndex < sources.length)
          ? startIndex
          : 0;
      await widget.controller.playQueue(sources, startIndex: safeIndex);
    }
  }

  List<Track> _sortFavorites(List<Track> list, String sortKey, bool reversed) {
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
        case 'album':
          cmp = compareLocaleAware(a.album ?? '', b.album ?? '');
          break;
        case 'duration':
          cmp = a.durationMs.compareTo(b.durationMs);
          break;
        case 'recentlyAdded':
        default:
          cmp = b.addedAt.compareTo(a.addedAt);
          if (cmp == 0) cmp = compareLocaleAware(a.title ?? '', b.title ?? '');
          break;
      }
      return reversed ? -cmp : cmp;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settingsStore.settings;
    final reduceMotion = settings.reduceMotion;

    return ListenableBuilder(
      listenable: widget.collections,
      builder: (context, _) {
        final rawTracks = widget.collections.favoriteTracks;
        final favoriteTracks = _sortFavorites(
          rawTracks,
          settings.favoritesSort,
          settings.favoritesSortReversed,
        );
        final totalDurationMs =
            favoriteTracks.fold<int>(0, (sum, t) => sum + t.durationMs);

        final rows =
            favoriteTracks.map((t) => TrackTableRow.fromTrack(t)).toList();

        return Padding(
          padding:
              const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
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
                          context.t('nav.favorites'),
                          style: AppTypography.display
                              .copyWith(letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 4),
                        Builder(
                          builder: (context) {
                            final countStr = context
                                .formatCountLocalized(favoriteTracks.length);
                            final durStr = totalDurationMs > 0
                                ? ' • ${context.formatDurationLocalized(Duration(milliseconds: totalDurationMs))}'
                                : '';
                            return Text(
                              '$countStr ${context.t('tracks.count')}$durStr',
                              style: AppTypography.body
                                  .copyWith(color: AppColors.textMuted),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  GlassPillButton(
                    key: const Key('favorites_play_button'),
                    label: context.t('album.playAlbum'),
                    leadingIcon: Icons.play_arrow,
                    variant: GlassButtonVariant.primary,
                    size: GlassButtonSize.medium,
                    onPressed: favoriteTracks.isEmpty
                        ? null
                        : () => _playFavorites(favoriteTracks),
                  ),
                  const SizedBox(width: 12),
                  GlassPillButton(
                    key: const Key('favorites_shuffle_button'),
                    label: context.t('album.shuffleAlbum'),
                    leadingIcon: Icons.shuffle,
                    size: GlassButtonSize.medium,
                    onPressed: favoriteTracks.isEmpty
                        ? null
                        : () => _playFavorites(favoriteTracks, shuffle: true),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              LibraryViewControls(
                sortOptions: const ['recentlyAdded', 'title', 'artist', 'album', 'duration'],
                currentSort: settings.favoritesSort,
                onSortChanged: (newSort) {
                  widget.settingsStore.update((s) => s.copyWith(favoritesSort: newSort));
                },
                sortDirection: SortDirection.fromReversed(settings.favoritesSortReversed),
                onSortDirectionChanged: (newDir) {
                  widget.settingsStore.update((s) => s.copyWith(favoritesSortReversed: newDir.isReversed));
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
                          listViewKey: const Key('favorites_tracks_list'),
                          onPlay: (index, row) {
                            _playFavorites(favoriteTracks, startIndex: index);
                          },
                          emptyPlaceholder: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.favorite_border,
                                  size: 64,
                                  color: AppColors.textMuted,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  context.t('favorites.empty'),
                                  style: AppTypography.title
                                      .copyWith(color: AppColors.text),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  context.t('favorites.emptyDescription'),
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
      },
    );
  }
}
