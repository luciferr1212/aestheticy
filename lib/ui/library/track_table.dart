import 'dart:io';

import 'package:flutter/material.dart';

import '../../audio/playback_controller.dart';
import '../../features/collections/user_collections.dart';
import '../../library/cover_cache.dart';
import '../../library/models.dart';
import '../artist_names/artist_name_scope.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'track_actions_menu.dart';

/// Data model representing a row in [TrackTable].
class TrackTableRow {
  /// The audio track metadata.
  final Track track;

  /// Whether the file is missing or not indexed in the library.
  final bool isMissing;

  /// Optional display index override (e.g. playlist position 1-based).
  final int? indexOverride;

  /// Optional playlist entry ID if this row represents a playlist entry.
  final int? entryId;

  /// Optional custom formatted duration string.
  final String? formattedDuration;

  /// Creates a [TrackTableRow].
  const TrackTableRow({
    required this.track,
    this.isMissing = false,
    this.indexOverride,
    this.entryId,
    this.formattedDuration,
  });

  /// Factory from a [Track].
  factory TrackTableRow.fromTrack(
    Track track, {
    bool isMissing = false,
    int? indexOverride,
    int? entryId,
  }) {
    return TrackTableRow(
      track: track,
      isMissing: isMissing,
      indexOverride: indexOverride,
      entryId: entryId,
    );
  }
}

/// Reusable virtualized track table widget for library, albums, playlists, and favorites views.
class TrackTable extends StatelessWidget {
  /// The list of rows to display.
  final List<TrackTableRow> rows;

  /// The URI or path of the currently playing track, if any.
  final String? currentPlayingPath;

  /// Whether playback is currently active.
  final bool isPlaying;

  /// Whether to reduce animations.
  final bool reduceMotion;

  /// Callback when a row is tapped or double-tapped to play.
  final void Function(int index, TrackTableRow row)? onPlay;

  /// Optional builder for trailing row action widgets (e.g. custom button).
  final Widget Function(BuildContext context, TrackTableRow row, int index)?
      rowActionsBuilder;

  /// Audio playback controller for contextual actions.
  final PlaybackController? controller;

  /// User collections store (optional, defaults to ambient scope).
  final UserCollections? userCollections;

  /// Playlist context ID if viewing a playlist.
  final int? playlistId;

  /// Key passed to the internal [ListView].
  final Key? listViewKey;

  /// Padding for the [ListView].
  final EdgeInsetsGeometry padding;

  /// Placeholder widget when [rows] is empty.
  final Widget? emptyPlaceholder;

  /// Height of each row item.
  final double itemExtent;

  /// Scroll controller for the list.
  final ScrollController? scrollController;

  /// Whether to display the track number / equalizer column.
  final bool showTrackNumber;

  /// Whether to display cover thumbnails.
  final bool showCover;

  /// Whether to display the album column.
  final bool showAlbum;

  /// Whether to display the artist column.
  final bool showArtist;

  /// Whether to show trailing action column & context menu.
  final bool showActions;

  /// Callbacks for playlist items.
  final void Function(int index, TrackTableRow row)? onRemoveFromPlaylist;
  final void Function(int index, TrackTableRow row)? onMoveUp;
  final void Function(int index, TrackTableRow row)? onMoveDown;
  final void Function(int index, TrackTableRow row)? onPlayNext;
  final void Function(int index, TrackTableRow row)? onAddToQueue;

  /// Creates a [TrackTable].
  const TrackTable({
    super.key,
    required this.rows,
    this.currentPlayingPath,
    this.isPlaying = false,
    this.reduceMotion = false,
    this.onPlay,
    this.rowActionsBuilder,
    this.controller,
    this.userCollections,
    this.playlistId,
    this.listViewKey,
    this.padding = const EdgeInsets.only(bottom: 120),
    this.emptyPlaceholder,
    this.itemExtent = 52.0,
    this.scrollController,
    this.showTrackNumber = true,
    this.showCover = true,
    this.showAlbum = true,
    this.showArtist = true,
    this.showActions = true,
    this.onRemoveFromPlaylist,
    this.onMoveUp,
    this.onMoveDown,
    this.onPlayNext,
    this.onAddToQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TrackTableHeader(
          showTrackNumber: showTrackNumber,
          showCover: showCover,
          showAlbum: showAlbum,
          showArtist: showArtist,
          hasActions: showActions,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: rows.isEmpty
              ? (emptyPlaceholder ?? const SizedBox.shrink())
              : ListView.builder(
                  key: listViewKey,
                  controller: scrollController,
                  padding: padding,
                  itemCount: rows.length,
                  itemExtent: itemExtent,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final isCurrent = currentPlayingPath != null &&
                        (currentPlayingPath == row.track.path ||
                            currentPlayingPath == 'file://${row.track.path}');

                    return TrackTableRowTile(
                      index: index,
                      row: row,
                      isCurrent: isCurrent,
                      isPlaying: isCurrent && isPlaying,
                      reduceMotion: reduceMotion,
                      showTrackNumber: showTrackNumber,
                      showCover: showCover,
                      showAlbum: showAlbum,
                      showArtist: showArtist,
                      showActions: showActions,
                      controller: controller,
                      userCollections: userCollections,
                      playlistId: playlistId,
                      totalCount: rows.length,
                      onPlay: row.isMissing
                          ? null
                          : () => onPlay?.call(index, row),
                      actionWidget: rowActionsBuilder?.call(context, row, index),
                      onPlayNext: onPlayNext != null
                          ? () => onPlayNext!(index, row)
                          : null,
                      onAddToQueue: onAddToQueue != null
                          ? () => onAddToQueue!(index, row)
                          : null,
                      onRemoveFromPlaylist: onRemoveFromPlaylist != null
                          ? () => onRemoveFromPlaylist!(index, row)
                          : null,
                      onMoveUp:
                          onMoveUp != null ? () => onMoveUp!(index, row) : null,
                      onMoveDown: onMoveDown != null
                          ? () => onMoveDown!(index, row)
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Column headers for [TrackTable].
class TrackTableHeader extends StatelessWidget {
  /// Whether to show track number column.
  final bool showTrackNumber;

  /// Whether to show cover column space.
  final bool showCover;

  /// Whether to show album column.
  final bool showAlbum;

  /// Whether to show artist column.
  final bool showArtist;

  /// Whether trailing actions column is present.
  final bool hasActions;

  /// Creates a [TrackTableHeader].
  const TrackTableHeader({
    super.key,
    this.showTrackNumber = true,
    this.showCover = true,
    this.showAlbum = true,
    this.showArtist = true,
    this.hasActions = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          if (showTrackNumber)
            SizedBox(
              width: 36,
              child: Text(
                context.t('tracks.headerNumber'),
                textAlign: TextAlign.center,
                style: AppTypography.micro.copyWith(color: AppColors.textMuted),
              ),
            ),
          if (showCover) const SizedBox(width: 48),
          Expanded(
            flex: 4,
            child: Text(
              context.t('tracks.headerTitle'),
              style: AppTypography.micro.copyWith(color: AppColors.textMuted),
            ),
          ),
          if (showArtist)
            Expanded(
              flex: 3,
              child: Text(
                context.t('tracks.headerArtist'),
                style: AppTypography.micro.copyWith(color: AppColors.textMuted),
              ),
            ),
          if (showAlbum)
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
          if (hasActions) const SizedBox(width: 40),
        ],
      ),
    );
  }
}

/// Individual row tile for [TrackTable].
class TrackTableRowTile extends StatelessWidget {
  /// Zero-based list index.
  final int index;

  /// The row data wrapper.
  final TrackTableRow row;

  /// Whether this track is currently active in the player.
  final bool isCurrent;

  /// Whether playback is actively running.
  final bool isPlaying;

  /// Whether animations should be reduced.
  final bool reduceMotion;

  /// Whether to show track number / equalizer.
  final bool showTrackNumber;

  /// Whether to show cover thumbnail.
  final bool showCover;

  /// Whether to show album column.
  final bool showAlbum;

  /// Whether to show artist column.
  final bool showArtist;

  /// Whether to show action button & enable context menu.
  final bool showActions;

  /// Audio controller.
  final PlaybackController? controller;

  /// User collections store.
  final UserCollections? userCollections;

  /// Playlist context ID.
  final int? playlistId;

  /// Total count in playlist.
  final int? totalCount;

  /// Play callback. Null if row is unplayable.
  final VoidCallback? onPlay;

  /// Optional trailing action widget override.
  final Widget? actionWidget;

  /// Playlist action callbacks.
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onRemoveFromPlaylist;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// Creates a [TrackTableRowTile].
  const TrackTableRowTile({
    super.key,
    required this.index,
    required this.row,
    required this.isCurrent,
    required this.isPlaying,
    required this.reduceMotion,
    this.showTrackNumber = true,
    this.showCover = true,
    this.showAlbum = true,
    this.showArtist = true,
    this.showActions = true,
    this.controller,
    this.userCollections,
    this.playlistId,
    this.totalCount,
    this.onPlay,
    this.actionWidget,
    this.onPlayNext,
    this.onAddToQueue,
    this.onRemoveFromPlaylist,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final track = row.track;
    final title = track.title ?? context.t('library.unknownTitle');
    final rawArtist = track.artist;
    final artist = rawArtist != null && rawArtist.isNotEmpty
        ? context.displayArtist(rawArtist)
        : context.t('library.unknownArtist');
    final album = track.album ?? context.t('library.unknownAlbum');
    final displayIndex = row.indexOverride ?? (index + 1);

    final formattedDur = row.formattedDuration ??
        context.formatDurationLocalized(
            Duration(milliseconds: track.durationMs));

    Widget buildTileContent(BuildContext context, MenuController? menuController) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isCurrent ? AppColors.accentFill : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.r10),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.r10),
          onTap: onPlay,
          onDoubleTap: onPlay,
          onSecondaryTapUp: menuController != null
              ? (details) => menuController.open(position: details.localPosition)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (showTrackNumber)
                  SizedBox(
                    width: 36,
                    child: Center(
                      child: isCurrent
                          ? AnimatedEqualizerBars(
                              isPlaying: isPlaying,
                              reduceMotion: reduceMotion,
                            )
                          : Text(
                              context.formatCountLocalized(displayIndex),
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                    ),
                  ),
                if (showCover) ...[
                  const SizedBox(width: 8),
                  TrackCoverThumbnail(coverKey: track.coverKey),
                  const SizedBox(width: 12),
                ],
                // Title (+ optional "Not in library" tag)
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: textDirectionFor(title),
                          style: AppTypography.body.copyWith(
                            color: isCurrent
                                ? AppColors.accent
                                : (row.isMissing
                                    ? AppColors.textMuted
                                    : AppColors.text),
                            fontWeight:
                                isCurrent ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (row.isMissing) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Text(
                            context.t('tracks.notInLibrary'),
                            style: AppTypography.micro
                                .copyWith(color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (showArtist)
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
                if (showAlbum)
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
                SizedBox(
                  width: 56,
                  child: Text(
                    formattedDur,
                    textAlign: TextAlign.end,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                if (showActions) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 32,
                    child: Center(
                      child: actionWidget ??
                          (menuController != null
                              ? IconButton(
                                  key: Key('track_more_button_$index'),
                                  icon: const Icon(Icons.more_horiz, size: 18),
                                  tooltip: context.t('tracks.moreOptions'),
                                  onPressed: () {
                                    if (menuController.isOpen) {
                                      menuController.close();
                                    } else {
                                      menuController.open();
                                    }
                                  },
                                )
                              : const SizedBox.shrink()),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    Widget content;
    if (showActions) {
      content = TrackActionsMenuAnchor(
        track: track,
        isMissing: row.isMissing,
        controller: controller,
        userCollections: userCollections,
        playlistId: playlistId,
        playlistEntryId: row.entryId,
        position: index,
        totalCount: totalCount,
        onPlay: onPlay,
        onPlayNext: onPlayNext,
        onAddToQueue: onAddToQueue,
        onRemoveFromPlaylist: onRemoveFromPlaylist,
        onMoveUp: onMoveUp,
        onMoveDown: onMoveDown,
        builder: (context, menuController) =>
            buildTileContent(context, menuController),
      );
    } else {
      content = buildTileContent(context, null);
    }

    content = RepaintBoundary(child: content);

    if (row.isMissing) {
      content = Opacity(opacity: 0.5, child: content);
    }

    return content;
  }
}

/// Thumbnail component for track row.
class TrackCoverThumbnail extends StatelessWidget {
  /// Cache key for the cover artwork.
  final String? coverKey;

  /// Creates a [TrackCoverThumbnail].
  const TrackCoverThumbnail({super.key, required this.coverKey});

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
class AnimatedEqualizerBars extends StatefulWidget {
  /// Whether playback is running.
  final bool isPlaying;

  /// Whether animations are reduced.
  final bool reduceMotion;

  /// Creates an [AnimatedEqualizerBars].
  const AnimatedEqualizerBars({
    super.key,
    required this.isPlaying,
    required this.reduceMotion,
  });

  @override
  State<AnimatedEqualizerBars> createState() => _AnimatedEqualizerBarsState();
}

class _AnimatedEqualizerBarsState extends State<AnimatedEqualizerBars>
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
  void didUpdateWidget(covariant AnimatedEqualizerBars oldWidget) {
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
