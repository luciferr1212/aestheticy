import 'dart:io';

import 'package:flutter/material.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../library/cover_cache.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/track_audio_source_mapper.dart';
import '../artist_names/artist_name_scope.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/settings_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'library_header.dart';

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

          // Table column header
          const _TableHeaderRow(),
          const SizedBox(height: 4),

          // Virtualized track list
          Expanded(
            child: tracks.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isNotEmpty
                          ? 'No tracks match "$_searchQuery"'
                          : 'No tracks in library',
                      style: AppTypography.body.copyWith(color: AppColors.textMuted),
                    ),
                  )
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

                          return ListView.builder(
                            key: const Key('tracks_list_view'),
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: tracks.length,
                            itemExtent: 52.0,
                            itemBuilder: (context, index) {
                              final track = tracks[index];
                              final isCurrent = activeSource != null &&
                                  (activeSource.uri == track.path ||
                                      activeSource.uri == 'file://${track.path}');

                              return _TrackRowTile(
                                index: index,
                                track: track,
                                isPlaying: isCurrent && isPlaying,
                                isCurrent: isCurrent,
                                reduceMotion: reduceMotion,
                                formattedDuration:
                                    context.formatDurationLocalized(
                                        Duration(milliseconds: track.durationMs)),
                                onPlay: () => _playTrackAt(index),
                              );
                            },
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

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              context.t('tracks.headerNumber'),
              textAlign: TextAlign.center,
              style: AppTypography.micro.copyWith(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 48), // Width for cover thumb space
          Expanded(
            flex: 4,
            child: Text(
              context.t('tracks.headerTitle'),
              style: AppTypography.micro.copyWith(color: AppColors.textMuted),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              context.t('tracks.headerArtist'),
              style: AppTypography.micro.copyWith(color: AppColors.textMuted),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              context.t('tracks.headerAlbum'),
              style: AppTypography.micro.copyWith(color: AppColors.textMuted),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              context.t('tracks.headerDuration'),
              textAlign: TextAlign.end,
              style: AppTypography.micro.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackRowTile extends StatelessWidget {
  final int index;
  final Track track;
  final bool isPlaying;
  final bool isCurrent;
  final bool reduceMotion;
  final String formattedDuration;
  final VoidCallback onPlay;

  const _TrackRowTile({
    required this.index,
    required this.track,
    required this.isPlaying,
    required this.isCurrent,
    required this.reduceMotion,
    required this.formattedDuration,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final title = track.title ?? context.t('library.unknownTitle');
    final rawArtist = track.artist;
    final artist = rawArtist != null && rawArtist.isNotEmpty
        ? context.displayArtist(rawArtist)
        : context.t('library.unknownArtist');
    final album = track.album ?? context.t('library.unknownAlbum');

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isCurrent ? AppColors.accentFill : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.r10),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.r10),
          onTap: onPlay,
          onDoubleTap: onPlay,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // Index number or 3-bar equalizer
                SizedBox(
                  width: 36,
                  child: Center(
                    child: isCurrent
                        ? _AnimatedEqualizerBars(
                            isPlaying: isPlaying,
                            reduceMotion: reduceMotion,
                          )
                        : Text(
                            context.formatCountLocalized(index + 1),
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),

                // Cover thumbnail (36x36, radius 6)
                _TrackCoverThumbnail(coverKey: track.coverKey),
                const SizedBox(width: 12),

                // Title
                Expanded(
                  flex: 4,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDirectionFor(title),
                    style: AppTypography.body.copyWith(
                      color: isCurrent ? AppColors.accent : AppColors.text,
                      fontWeight:
                          isCurrent ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),

                // Artist
                Expanded(
                  flex: 3,
                  child: Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDirectionFor(artist),
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),

                // Album
                Expanded(
                  flex: 3,
                  child: Text(
                    album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDirectionFor(album),
                    style: AppTypography.body.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),

                // Duration
                SizedBox(
                  width: 56,
                  child: Text(
                    formattedDuration,
                    textAlign: TextAlign.end,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackCoverThumbnail extends StatelessWidget {
  final String? coverKey;

  const _TrackCoverThumbnail({required this.coverKey});

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (coverKey != null && CoverCache.hasCover(coverKey!)) {
      final file = File(CoverCache.pathFor(coverKey!));
      image = Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 72,
        cacheHeight: 72,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    } else {
      image = _placeholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 36,
        height: 36,
        child: image,
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFF22212C),
      child: const Center(
        child: Icon(Icons.music_note, size: 18, color: Colors.white24),
      ),
    );
  }
}

/// Animated 3-bar equalizer icon for currently-playing track row.
class _AnimatedEqualizerBars extends StatefulWidget {
  final bool isPlaying;
  final bool reduceMotion;

  const _AnimatedEqualizerBars({
    required this.isPlaying,
    required this.reduceMotion,
  });

  @override
  State<_AnimatedEqualizerBars> createState() => _AnimatedEqualizerBarsState();
}

class _AnimatedEqualizerBarsState extends State<_AnimatedEqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    if (widget.isPlaying && !widget.reduceMotion) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedEqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !widget.reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      if (_controller.isAnimating) _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduceMotion || !widget.isPlaying) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _bar(10),
          const SizedBox(width: 2),
          _bar(14),
          const SizedBox(width: 2),
          _bar(8),
        ],
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final val = _controller.value;
        final h1 = 6.0 + 8.0 * val;
        final h2 = 14.0 - 8.0 * val;
        final h3 = 8.0 + 6.0 * (1.0 - val);
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _bar(h1),
            const SizedBox(width: 2),
            _bar(h2),
            const SizedBox(width: 2),
            _bar(h3),
          ],
        );
      },
    );
  }

  Widget _bar(double height) {
    return Container(
      width: 3.0,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}
