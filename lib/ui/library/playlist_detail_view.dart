import 'dart:io';

import 'package:flutter/material.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/collections/m3u.dart';
import '../../features/collections/user_collections.dart';
import '../../library/cover_cache.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/track_audio_source_mapper.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'track_table.dart';

/// Screen displaying the tracklist and metadata of a specific playlist.
class PlaylistDetailView extends StatefulWidget {
  /// Unique playlist ID.
  final int playlistId;

  /// Optional cached summary.
  final PlaylistSummary? initialPlaylist;

  /// Library repository for loading entries.
  final LibraryRepository repository;

  /// User collections store.
  final UserCollections collections;

  /// Audio controller.
  final PlaybackController controller;

  /// Settings store.
  final SettingsStore settingsStore;

  /// Navigation coordinator.
  final AppNavigator navigator;

  /// Optional M3U export handler.
  final Future<void> Function(BuildContext context, PlaylistSummary playlist)?
      onExportM3u;

  /// Creates a [PlaylistDetailView].
  const PlaylistDetailView({
    super.key,
    required this.playlistId,
    this.initialPlaylist,
    required this.repository,
    required this.collections,
    required this.controller,
    required this.settingsStore,
    required this.navigator,
    this.onExportM3u,
  });

  @override
  State<PlaylistDetailView> createState() => _PlaylistDetailViewState();
}

class _PlaylistDetailViewState extends State<PlaylistDetailView> {
  List<PlaylistEntry> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
    widget.collections.addListener(_onCollectionsChanged);
  }

  @override
  void dispose() {
    widget.collections.removeListener(_onCollectionsChanged);
    super.dispose();
  }

  void _onCollectionsChanged() {
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final entries = await widget.repository.playlistEntries(widget.playlistId);
    if (mounted) {
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    }
  }

  PlaylistSummary? _getPlaylist() {
    final list = widget.collections.playlists;
    final match = list.where((p) => p.id == widget.playlistId);
    if (match.isNotEmpty) return match.first;
    return widget.initialPlaylist;
  }

  Future<void> _playPlaylist({bool shuffle = false, int startIndex = 0}) async {
    final playable = _entries.where((e) => e.track != null).toList();
    if (playable.isEmpty) return;

    final sources = playable.map((e) => e.track!.toAudioSource()).toList();
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
    final playlist = _getPlaylist();
    final reduceMotion = widget.settingsStore.settings.reduceMotion;

    if (playlist == null && !_isLoading) {
      return Center(
        child: Text(
          context.t('playlists.empty'),
          style: AppTypography.body.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    final totalDurationMs = _entries.fold<int>(
      0,
      (sum, e) => sum + (e.track?.durationMs ?? 0),
    );

    final rows = _entries.map((entry) {
      final track = entry.track ??
          Track(
            path: entry.path,
            folderId: 0,
            durationMs: 0,
            mtimeMs: 0,
            sizeBytes: 0,
            addedAt: DateTime.fromMillisecondsSinceEpoch(0),
            title: entry.path.split(RegExp(r'[/\\]')).last,
          );

      return TrackTableRow(
        track: track,
        isMissing: entry.track == null,
        entryId: entry.entryId,
        indexOverride: entry.position,
      );
    }).toList();

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back navigation row
          Row(
            children: [
              GlassIconButton(
                key: const Key('playlist_detail_back_button'),
                icon: Icons.arrow_back,
                tooltip: context.t('common.back'),
                semanticLabel: context.t('common.back'),
                size: GlassButtonSize.small,
                onPressed: () => widget.navigator.goBack(),
              ),
              const SizedBox(width: 8),
              Text(
                context.t('common.back'),
                style:
                    AppTypography.body.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLargeCover(playlist?.coverKey),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      playlist?.name ?? '',
                      textDirection:
                          textDirectionFor(playlist?.name ?? ''),
                      style: AppTypography.display
                          .copyWith(letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        final countStr =
                            context.t('playlist.trackCount', args: {
                          'count': context.formatCountLocalized(rows.length),
                        });
                        final durStr = totalDurationMs > 0
                            ? ' • ${context.formatDurationLocalized(Duration(milliseconds: totalDurationMs))}'
                            : '';
                        return Text(
                          '$countStr$durStr',
                          style: AppTypography.body
                              .copyWith(color: AppColors.textMuted),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        GlassPillButton(
                          key: const Key('playlist_play_button'),
                          label: context.t('album.playAlbum'),
                          leadingIcon: Icons.play_arrow,
                          variant: GlassButtonVariant.primary,
                          size: GlassButtonSize.medium,
                          onPressed: rows.isEmpty
                              ? null
                              : () => _playPlaylist(),
                        ),
                        GlassPillButton(
                          key: const Key('playlist_shuffle_button'),
                          label: context.t('album.shuffleAlbum'),
                          leadingIcon: Icons.shuffle,
                          size: GlassButtonSize.medium,
                          onPressed: rows.isEmpty
                              ? null
                              : () => _playPlaylist(shuffle: true),
                        ),
                        if (playlist != null)
                          GlassPillButton(
                            key: const Key('playlist_export_m3u_button'),
                            label: context.t('playlist.exportM3u'),
                            leadingIcon: Icons.file_download_outlined,
                            size: GlassButtonSize.medium,
                            onPressed: () {
                              if (widget.onExportM3u != null) {
                                widget.onExportM3u!(context, playlist);
                              } else {
                                M3u.exportPlaylist(
                                  context,
                                  repository: widget.repository,
                                  playlist: playlist,
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Tracklist
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
                            playlistId: widget.playlistId,
                            listViewKey: const Key('playlist_tracks_list'),
                            onPlay: (index, row) {
                              _playPlaylist(startIndex: index);
                            },
                            onRemoveFromPlaylist: (index, row) {
                              if (row.entryId != null) {
                                widget.collections.removeFromPlaylist(
                                  widget.playlistId,
                                  [row.entryId!],
                                );
                              }
                            },
                            onMoveUp: (index, row) {
                              if (row.entryId != null && index > 0) {
                                widget.collections.moveEntry(
                                  widget.playlistId,
                                  row.entryId!,
                                  index - 1,
                                );
                              }
                            },
                            onMoveDown: (index, row) {
                              if (row.entryId != null &&
                                  index < rows.length - 1) {
                                widget.collections.moveEntry(
                                  widget.playlistId,
                                  row.entryId!,
                                  index + 1,
                                );
                              }
                            },
                            emptyPlaceholder: Center(
                              child: Text(
                                context.t('playlist.emptyTracklist'),
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

  Widget _buildLargeCover(String? coverKey) {
    Widget imageWidget;
    if (coverKey != null && CoverCache.hasCover(coverKey)) {
      final file = File(CoverCache.pathFor(coverKey));
      imageWidget = Image.file(
        file,
        width: 180,
        height: 180,
        fit: BoxFit.cover,
        cacheWidth: 360,
        cacheHeight: 360,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else {
      imageWidget = _buildPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.r16),
      child: Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.r16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 18.0,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: imageWidget,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF22212C),
      child: const Center(
        child: Icon(
          Icons.queue_music,
          size: 64,
          color: Colors.white24,
        ),
      ),
    );
  }
}
