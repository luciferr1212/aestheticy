import 'dart:io';

import 'package:flutter/material.dart';

import '../../../library/cover_cache.dart';
import '../../../library/models.dart';
import '../../artist_names/artist_name_scope.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../album_year_grouping.dart';

/// Year group section header rendered when [AlbumsView] is sorted by year.
class AlbumYearSectionHeader extends StatelessWidget {
  /// Year group metadata.
  final AlbumYearGroup group;

  /// Creates an [AlbumYearSectionHeader].
  const AlbumYearSectionHeader({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final yearLabel = group.year != null
        ? context.localizeDigitsText(group.year.toString())
        : context.t('albums.unknownYear');
    final countLabel =
        '${context.formatCountLocalized(group.albums.length)} ${context.t('albums.count')}';

    return Semantics(
      header: true,
      child: Row(
        key: ValueKey<String>(
          'album_year_header_${group.year?.toString() ?? 'unknown'}',
        ),
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              yearLabel,
              style: AppTypography.title.copyWith(color: AppColors.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            countLabel,
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Square album grid tile.
class SquareAlbumTile extends StatelessWidget {
  /// Album summary item.
  final AlbumSummary album;

  /// Tap callback.
  final VoidCallback onTap;

  /// Creates a [SquareAlbumTile].
  const SquareAlbumTile({
    super.key,
    required this.album,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        hoverColor: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(AppSpacing.r12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.0,
              child: AlbumCoverImage(
                coverKey: album.coverKey,
                borderRadius: AppSpacing.r12,
                cacheSize: 180,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              album.album,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: textDirectionFor(album.album),
              style: AppTypography.bodyStrong.copyWith(color: AppColors.text),
            ),
            const SizedBox(height: 2),
            Builder(
              builder: (context) {
                final artist =
                    context.displayArtist(album.displayArtist ?? album.albumArtist);
                return Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: textDirectionFor(artist),
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textSecondary),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Wide horizontal album card tile.
class WideAlbumTile extends StatelessWidget {
  /// Album summary item.
  final AlbumSummary album;

  /// Tap callback.
  final VoidCallback onTap;

  /// Creates a [WideAlbumTile].
  const WideAlbumTile({
    super.key,
    required this.album,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.fillControl,
          borderRadius: BorderRadius.circular(AppSpacing.r12),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          hoverColor: const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(AppSpacing.r12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: AlbumCoverImage(
                    coverKey: album.coverKey,
                    borderRadius: AppSpacing.r10,
                    cacheSize: 90,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: textDirectionFor(album.album),
                        style: AppTypography.bodyStrong
                            .copyWith(color: AppColors.text),
                      ),
                      const SizedBox(height: 3),
                      Builder(
                        builder: (context) {
                          final artist = context.displayArtist(
                              album.displayArtist ?? album.albumArtist);
                          return Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: textDirectionFor(artist),
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textSecondary),
                          );
                        },
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (context) {
                          final countStr =
                              context.formatCountLocalized(album.trackCount);
                          final yearStr = album.year != null
                              ? ' • ${context.localizeDigitsText(album.year.toString())}'
                              : '';
                          return Text(
                            '$countStr ${context.t('album.tracksCount')}$yearStr',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.micro
                                .copyWith(color: AppColors.textMuted),
                          );
                        },
                      ),
                    ],
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

/// Compact list-mode album row tile.
class ListAlbumTile extends StatelessWidget {
  /// Album summary item.
  final AlbumSummary album;

  /// Tap callback.
  final VoidCallback onTap;

  /// Creates a [ListAlbumTile].
  const ListAlbumTile({
    super.key,
    required this.album,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        hoverColor: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(AppSpacing.r10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: AlbumCoverImage(
                  coverKey: album.coverKey,
                  borderRadius: AppSpacing.r10,
                  cacheSize: 50,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text(
                  album.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: textDirectionFor(album.album),
                  style: AppTypography.bodyStrong.copyWith(color: AppColors.text),
                ),
              ),
              Expanded(
                flex: 2,
                child: Builder(
                  builder: (context) {
                    final artist = context.displayArtist(
                        album.displayArtist ?? album.albumArtist);
                    return Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: textDirectionFor(artist),
                      style: AppTypography.body
                          .copyWith(color: AppColors.textSecondary),
                    );
                  },
                ),
              ),
              SizedBox(
                width: 60,
                child: Builder(
                  builder: (context) {
                    final yearStr = album.year != null
                        ? context.localizeDigitsText(album.year.toString())
                        : '—';
                    return Text(
                      yearStr,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textMuted),
                    );
                  },
                ),
              ),
              SizedBox(
                width: 70,
                child: Builder(
                  builder: (context) {
                    final countStr =
                        context.formatCountLocalized(album.trackCount);
                    return Text(
                      '$countStr ${context.t('album.tracksCount')}',
                      textAlign: TextAlign.end,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textMuted),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cached album cover thumbnail with calm placeholder fallback.
class AlbumCoverImage extends StatelessWidget {
  /// Cover cache key, if present.
  final String? coverKey;

  /// Clip corner radius.
  final double borderRadius;

  /// Logical size used to derive `cacheWidth` / `cacheHeight`.
  final int cacheSize;

  /// Creates an [AlbumCoverImage].
  const AlbumCoverImage({
    super.key,
    required this.coverKey,
    required this.borderRadius,
    required this.cacheSize,
  });

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (coverKey != null && CoverCache.hasCover(coverKey!)) {
      final file = File(CoverCache.pathFor(coverKey!));
      imageWidget = Image.file(
        file,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        cacheWidth: cacheSize * 2,
        cacheHeight: cacheSize * 2,
        frameBuilder: (context, child, frame, wasSync) {
          if (wasSync || frame != null) return child;
          return _buildPlaceholder();
        },
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else {
      imageWidget = _buildPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: imageWidget,
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF22212C),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: const Center(
        child: Icon(Icons.album_outlined, color: Colors.white24, size: 28),
      ),
    );
  }
}
