import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../library/models.dart';
import '../../artist_names/artist_name_scope.dart';
import '../../l10n/app_strings.dart';
import '../../library/widgets/album_tiles.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Calm horizontal shelf displaying either [AlbumSummary] or [Track] cards
/// using lazy [ListView.builder] and CoverCache thumbnails (no BackdropFilter).
class HomeMediaRow extends StatelessWidget {
  /// Localized section title.
  final String title;

  /// Optional small "why this row" caption.
  final String? whyCaption;

  /// Album items when rendering an album row.
  final List<AlbumSummary> albums;

  /// Track items when rendering a track row.
  final List<Track> tracks;

  /// Callback when an album card is activated.
  final ValueChanged<AlbumSummary>? onAlbumTap;

  /// Callback when a track card is activated.
  final ValueChanged<Track>? onTrackTap;

  /// Whether animations are disabled.
  final bool reduceMotion;

  /// Creates an album-based [HomeMediaRow].
  const HomeMediaRow.albums({
    super.key,
    required this.title,
    this.whyCaption,
    required this.albums,
    required ValueChanged<AlbumSummary> this.onAlbumTap,
    this.reduceMotion = false,
  })  : tracks = const [],
        onTrackTap = null;

  /// Creates a track-based [HomeMediaRow].
  const HomeMediaRow.tracks({
    super.key,
    required this.title,
    this.whyCaption,
    required this.tracks,
    required ValueChanged<Track> this.onTrackTap,
    this.reduceMotion = false,
  })  : albums = const [],
        onAlbumTap = null;

  @override
  Widget build(BuildContext context) {
    final isAlbumRow = albums.isNotEmpty;
    final itemCount = isAlbumRow ? albums.length : tracks.length;
    if (itemCount == 0) return const SizedBox.shrink();

    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
    const cardWidth = 152.0;
    final listHeight = cardWidth + 16 + (48 * textScale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.title.copyWith(color: AppColors.text),
        ),
        if (whyCaption != null && whyCaption!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            whyCaption!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
        ],
        const SizedBox(height: AppSpacing.s16),
        SizedBox(
          height: listHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: itemCount,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s16),
            itemBuilder: (context, index) {
              if (isAlbumRow) {
                final album = albums[index];
                final artist = context
                    .displayArtist(album.displayArtist ?? album.albumArtist);
                return _HomeMediaCard(
                  cardWidth: cardWidth,
                  coverKey: album.coverKey,
                  title: album.album,
                  subtitle: artist,
                  reduceMotion: reduceMotion,
                  onTap: () => onAlbumTap?.call(album),
                );
              }
              final track = tracks[index];
              final rawTitle = track.title?.trim();
              final trackTitle = (rawTitle != null && rawTitle.isNotEmpty)
                  ? rawTitle
                  : p.basenameWithoutExtension(track.path);
              final artist = context.displayArtist(track.artist);
              return _HomeMediaCard(
                cardWidth: cardWidth,
                coverKey: track.coverKey,
                title: trackTitle,
                subtitle: artist.isNotEmpty ? artist : (track.album ?? ''),
                reduceMotion: reduceMotion,
                onTap: () => onTrackTap?.call(track),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeMediaCard extends StatefulWidget {
  final double cardWidth;
  final String? coverKey;
  final String title;
  final String subtitle;
  final bool reduceMotion;
  final VoidCallback onTap;

  const _HomeMediaCard({
    required this.cardWidth,
    required this.coverKey,
    required this.title,
    required this.subtitle,
    required this.reduceMotion,
    required this.onTap,
  });

  @override
  State<_HomeMediaCard> createState() => _HomeMediaCardState();
}

class _HomeMediaCardState extends State<_HomeMediaCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = _focused
        ? AppColors.accent
        : (_hovered ? AppColors.border : Colors.transparent);
    final bgColor =
        _hovered || _focused ? const Color(0x0DFFFFFF) : Colors.transparent;

    return RepaintBoundary(
      child: SizedBox(
        width: widget.cardWidth,
        child: Semantics(
          button: true,
          label: widget.subtitle.isNotEmpty
              ? '${widget.title} — ${widget.subtitle}'
              : widget.title,
          child: AnimatedContainer(
            duration: widget.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppSpacing.r16),
              border: Border.all(
                color: borderColor,
                width: _focused ? 1.5 : 1.0,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.r16),
              mouseCursor: SystemMouseCursors.click,
              hoverColor: const Color(0x10FFFFFF),
              focusColor: const Color(0x14FFFFFF),
              onHover: (v) => setState(() => _hovered = v),
              onFocusChange: (v) => setState(() => _focused = v),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(
                      aspectRatio: 1.0,
                      child: AlbumCoverImage(
                        coverKey: widget.coverKey,
                        borderRadius: AppSpacing.r12,
                        cacheSize: 160,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: textDirectionFor(widget.title),
                      style:
                          AppTypography.bodyStrong.copyWith(color: AppColors.text),
                    ),
                    if (widget.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: textDirectionFor(widget.subtitle),
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
