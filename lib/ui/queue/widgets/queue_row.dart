import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../audio/audio_models.dart';
import '../../../audio/playback_controller.dart';
import '../../../features/collections/user_collections.dart';
import '../../../library/cover_cache.dart';
import '../../artist_names/artist_name_scope.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../shell/app_navigator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../theme/interactive_cursor.dart';
import 'queue_row_menu.dart';

/// Interactive queue entry row with drag handle, cover art, metadata, and actions.
class QueueRow extends StatefulWidget {
  /// Zero-based queue index.
  final int index;

  /// Queue entry data.
  final QueueEntry entry;

  /// Currently playing queue index.
  final int currentIndex;

  /// Currently playing queue entry, if any.
  final QueueEntry? currentEntry;

  /// Whether this row is selected.
  final bool isSelected;

  /// Whether rendered in compact side-panel mode.
  final bool compact;

  /// Playback controller.
  final PlaybackController controller;

  /// Application navigator.
  final AppNavigator navigator;

  /// Optional explicit user collections store.
  final UserCollections? userCollections;

  /// Total number of items in the queue.
  final int totalCount;

  /// Selection/activation callback.
  final void Function({bool playIfPlain}) onSelect;

  /// Creates a [QueueRow].
  const QueueRow({
    super.key,
    required this.index,
    required this.entry,
    required this.currentIndex,
    required this.currentEntry,
    required this.isSelected,
    required this.compact,
    required this.controller,
    required this.navigator,
    required this.userCollections,
    required this.totalCount,
    required this.onSelect,
  });

  @override
  State<QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<QueueRow> {
  final MenuController _menuController = MenuController();
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isHistory =
        widget.currentIndex >= 0 && widget.index < widget.currentIndex;
    final isCurrent = widget.currentEntry != null &&
        widget.entry.id == widget.currentEntry!.id;

    final source = widget.entry.source;
    final extras = source.extras;
    final title = extras?['title'] ?? context.t('library.unknownTitle');
    final rawArtist = extras?['artist'];
    final artist = (rawArtist != null && rawArtist.isNotEmpty)
        ? context.displayArtist(rawArtist)
        : '—';
    final album = extras?['album'] ?? '';
    final durationMsStr = extras?['durationMs'];
    final durationMs = int.tryParse(durationMsStr ?? '');
    final durationText = durationMs != null
        ? context.formatDurationLocalized(Duration(milliseconds: durationMs))
        : '—';
    final coverKey = extras?['coverKey'];

    return MouseRegion(
      cursor: isHistory ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onSecondaryTapUp: (details) {
          widget.onSelect();
          if (!_menuController.isOpen) {
            _menuController.open(position: details.localPosition);
          }
        },
        child: Opacity(
          opacity: isHistory ? 0.50 : 1.0,
          child: Container(
            height: 56.0,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AppColors.accentFill
                  : (isCurrent ? AppColors.fillControl : Colors.transparent),
              borderRadius: BorderRadius.circular(AppSpacing.r10),
              border: Border.all(
                color: widget.isSelected
                    ? AppColors.accent
                    : (isCurrent
                        ? AppColors.accent.withValues(alpha: 0.3)
                        : Colors.transparent),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                mouseCursor: isHistory
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                hoverColor: const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(AppSpacing.r10),
                onTap: () {
                  widget.onSelect(playIfPlain: true);
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? 6 : 8,
                  ),
                  child: Row(
                    children: [
                      // Drag handle
                      ReorderableDragStartListener(
                        index: widget.index,
                        child: DragHandleCursor(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: widget.compact ? 2 : 4,
                            ),
                            child: const Icon(
                              Icons.drag_indicator,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Cover thumbnail (36x36)
                      _buildCover(coverKey),
                      SizedBox(width: widget.compact ? 10 : 12),

                      // Current playing/paused indicator
                      if (isCurrent)
                        QueuePlayingIndicator(controller: widget.controller),

                      // Title & Artist
                      Expanded(
                        flex: 4,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: textDirectionFor(title),
                              style: isCurrent
                                  ? AppTypography.bodyStrong
                                      .copyWith(color: AppColors.accent)
                                  : AppTypography.bodyStrong
                                      .copyWith(color: AppColors.text),
                            ),
                            Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: textDirectionFor(artist),
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!widget.compact) ...[
                        const SizedBox(width: 8),

                        // Album
                        Expanded(
                          flex: 3,
                          child: Text(
                            album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: textDirectionFor(album),
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textMuted),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Duration
                        SizedBox(
                          width: 48,
                          child: Text(
                            durationText,
                            textAlign: TextAlign.end,
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textMuted),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Favorite button
                        QueueFavoriteButton(path: source.uri),
                      ],
                      const SizedBox(width: 4),

                      if (widget.compact)
                        IconButton(
                          key: Key('queue_row_remove_${widget.index}'),
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            color: _isHovered
                                ? AppColors.text
                                : AppColors.textMuted,
                          ),
                          tooltip: context.t('queue.remove'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          onPressed: () => widget.controller
                              .removeEntryFromQueue(widget.entry.id),
                        ),

                      // More actions menu
                      QueueRowMenu(
                        menuController: _menuController,
                        isHovered: _isHovered,
                        compact: widget.compact,
                        index: widget.index,
                        entryId: widget.entry.id,
                        source: source,
                        controller: widget.controller,
                        navigator: widget.navigator,
                        userCollections: widget.userCollections,
                        totalCount: widget.totalCount,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(String? coverKey) {
    Widget imageWidget;
    File? coverFile;
    if (coverKey != null && coverKey.isNotEmpty) {
      try {
        if (CoverCache.hasCover(coverKey)) {
          coverFile = File(CoverCache.pathFor(coverKey));
        }
      } on StateError {
        // ignore-silent: reading optional cover cache falls back cleanly when uninitialized
        coverFile = null;
      }
    }
    if (coverFile != null) {
      imageWidget = Image.file(
        coverFile,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        cacheWidth: 72,
        cacheHeight: 72,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else {
      imageWidget = _buildPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.r10),
      child: SizedBox(
        width: 36,
        height: 36,
        child: imageWidget,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF22212C),
        borderRadius: BorderRadius.circular(AppSpacing.r10),
      ),
      child: const Center(
        child: Icon(
          Icons.music_note,
          color: Colors.white24,
          size: 18,
        ),
      ),
    );
  }
}

/// Favorite heart toggle inside a full-width [QueueRow].
class QueueFavoriteButton extends StatelessWidget {
  /// Track path/URI.
  final String path;

  /// Creates a [QueueFavoriteButton].
  const QueueFavoriteButton({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    final collections = UserCollectionsScope.maybeOf(context);
    if (collections == null || path.isEmpty) return const SizedBox(width: 24);

    return ListenableBuilder(
      listenable: collections,
      builder: (context, _) {
        final isFav = collections.isFavorite(path);
        return Tooltip(
          message:
              isFav ? context.t('track.unfavorite') : context.t('track.favorite'),
          child: InkResponse(
            radius: 12,
            onTap: () => collections.toggleFavorite(path),
            child: SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  size: 16,
                  color: isFav ? AppColors.accent : AppColors.textMuted,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Play/pause icon indicator shown next to the active track in [QueueRow].
class QueuePlayingIndicator extends StatefulWidget {
  /// Active playback controller.
  final PlaybackController controller;

  /// Creates a [QueuePlayingIndicator].
  const QueuePlayingIndicator({super.key, required this.controller});

  @override
  State<QueuePlayingIndicator> createState() => _QueuePlayingIndicatorState();
}

class _QueuePlayingIndicatorState extends State<QueuePlayingIndicator> {
  StreamSubscription<PlaybackState>? _sub;
  late PlaybackState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.controller.currentState;
    _sub = widget.controller.stateStream.listen((s) {
      if (mounted) {
        setState(() {
          _state = s;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _state == PlaybackState.playing;
    return Container(
      key: const Key('queue_playing_indicator'),
      margin: const EdgeInsetsDirectional.only(end: 8),
      child: Icon(
        isPlaying ? Icons.play_arrow : Icons.pause,
        size: 16,
        color: AppColors.accent,
      ),
    );
  }
}
