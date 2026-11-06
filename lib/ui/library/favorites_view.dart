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
import 'track_table.dart';

/// Screen displaying the user's favorite tracks with live update on toggle,
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

  /// Creates a [FavoritesView].
  const FavoritesView({
    super.key,
    required this.repository,
    required this.collections,
    required this.controller,
    required this.settingsStore,
  });

  @override
  State<FavoritesView> createState() => _FavoritesViewState();
}

class _FavoritesViewState extends State<FavoritesView> {
  List<Track> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    widget.collections.addListener(_onCollectionsChanged);
  }

  @override
  void dispose() {
    widget.collections.removeListener(_onCollectionsChanged);
    super.dispose();
  }

  void _onCollectionsChanged() {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final tracks = await widget.repository.favoriteTracks();
    if (mounted) {
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    }
  }

  Future<void> _playFavorites({bool shuffle = false, int startIndex = 0}) async {
    if (_tracks.isEmpty) return;
    final sources = _tracks.map((t) => t.toAudioSource()).toList();
    if (shuffle) {
      sources.shuffle();
      await widget.controller.playQueue(sources, startIndex: 0);
    } else {
      final safeIndex = (startIndex >= 0 && startIndex < sources.length)
          ? startIndex
          : 0;
      await widget.controller.playQueue(sources, startIndex: safeIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = widget.settingsStore.settings.reduceMotion;

    return ListenableBuilder(
      listenable: widget.collections,
      builder: (context, _) {
        final favoriteTracks = _tracks
            .where((t) => widget.collections.isFavorite(t.path))
            .toList();
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
                        : () => _playFavorites(),
                  ),
                  const SizedBox(width: 12),
                  GlassPillButton(
                    key: const Key('favorites_shuffle_button'),
                    label: context.t('album.shuffleAlbum'),
                    leadingIcon: Icons.shuffle,
                    size: GlassButtonSize.medium,
                    onPressed: favoriteTracks.isEmpty
                        ? null
                        : () => _playFavorites(shuffle: true),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // TrackTable
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : StreamBuilder<AudioSource?>(
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
                                  _playFavorites(startIndex: index);
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
                                        context
                                            .t('favorites.emptyDescription'),
                                        style: AppTypography.body.copyWith(
                                            color: AppColors.textMuted),
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
