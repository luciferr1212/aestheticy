import 'dart:io';

import 'package:flutter/material.dart';

import '../../../features/library_view/artist_page_model.dart';
import '../../../library/cover_cache.dart';
import '../../../library/models.dart';
import '../../glass/glass_button.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../shell/app_navigator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Displays an artist release section (Albums, Singles & EPs, Compilations, Appears On).
class ArtistAlbumSectionView extends StatelessWidget {
  /// Section model containing kind and albums.
  final ArtistAlbumSection section;

  /// Number of cards visible when collapsed.
  final int cardsPerRow;

  /// Computed width for each card.
  final double cardWidth;

  /// Card spacing between items.
  final double cardSpacing;

  /// Whether the section is currently expanded.
  final bool isExpanded;

  /// Whether animations should be reduced.
  final bool reduceMotion;

  /// Application navigator.
  final AppNavigator navigator;

  /// Callback toggling expansion for this section.
  final VoidCallback onToggleExpanded;

  /// Creates an [ArtistAlbumSectionView].
  const ArtistAlbumSectionView({
    super.key,
    required this.section,
    required this.cardsPerRow,
    required this.cardWidth,
    required this.cardSpacing,
    required this.isExpanded,
    required this.reduceMotion,
    required this.navigator,
    required this.onToggleExpanded,
  });

  String _sectionTitle(BuildContext context, ArtistPageSectionKind kind) {
    return switch (kind) {
      ArtistPageSectionKind.albums => context.t('artist.section.albums'),
      ArtistPageSectionKind.singlesAndEps =>
        context.t('artist.section.singlesAndEps'),
      ArtistPageSectionKind.compilations =>
        context.t('artist.section.compilations'),
      ArtistPageSectionKind.appearsOn => context.t('artist.section.appearsOn'),
      ArtistPageSectionKind.tracks => context.t('artist.section.tracks'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final hasOverflowRows = section.albums.length > cardsPerRow;
    final visibleAlbums =
        isExpanded ? section.albums : section.albums.take(cardsPerRow).toList();

    return Column(
      key: Key('artist_section_${section.kind.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ArtistSectionHeaderRow(
          title: _sectionTitle(context, section.kind),
          count: section.albums.length,
          countKey: Key('artist_section_count_${section.kind.name}'),
          trailing: hasOverflowRows
              ? GlassPillButton(
                  key: Key('artist_section_toggle_${section.kind.name}'),
                  label: isExpanded
                      ? context.t('artist.showLess')
                      : context.t('artist.showAll'),
                  size: GlassButtonSize.small,
                  onPressed: onToggleExpanded,
                )
              : null,
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeOut,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: AlignmentDirectional.topStart,
            children: [
              ...previousChildren,
              ?currentChild,
            ],
          ),
          child: KeyedSubtree(
            key: ValueKey<bool>(isExpanded),
            child: Wrap(
              spacing: cardSpacing,
              runSpacing: cardSpacing,
              children: [
                for (final album in visibleAlbums)
                  ArtistAlbumCard(
                    key: ValueKey<String>(
                      'artist_album_card_${section.kind.name}_${album.album}|${album.albumArtist ?? ''}',
                    ),
                    album: album,
                    width: cardWidth,
                    reduceMotion: reduceMotion,
                    onTap: () => navigator.openAlbumDetail(
                      album.album,
                      album: album,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Section header row with title, localized item count badge, and optional trailing action.
class ArtistSectionHeaderRow extends StatelessWidget {
  /// Section heading text.
  final String title;

  /// Number of items in this section.
  final int count;

  /// Key applied to the count pill.
  final Key countKey;

  /// Optional trailing control widget.
  final Widget? trailing;

  /// Creates an [ArtistSectionHeaderRow].
  const ArtistSectionHeaderRow({
    super.key,
    required this.title,
    required this.count,
    required this.countKey,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.title.copyWith(color: AppColors.text),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  key: countKey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.fillControl,
                    borderRadius: AppSpacing.brPill,
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Text(
                    context.formatCountLocalized(count),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

/// Interactive album release card rendered inside an [ArtistAlbumSectionView].
class ArtistAlbumCard extends StatefulWidget {
  /// Album summary data.
  final AlbumSummary album;

  /// Card width in logical pixels.
  final double width;

  /// Whether animations should be reduced.
  final bool reduceMotion;

  /// Callback invoked when the card is activated.
  final VoidCallback onTap;

  /// Creates an [ArtistAlbumCard].
  const ArtistAlbumCard({
    super.key,
    required this.album,
    required this.width,
    required this.reduceMotion,
    required this.onTap,
  });

  @override
  State<ArtistAlbumCard> createState() => _ArtistAlbumCardState();
}

class _ArtistAlbumCardState extends State<ArtistAlbumCard> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final hasYear = album.year != null && album.year! > 0;
    final tracksStr = context.formatCountLocalized(album.trackCount);
    final metaText = hasYear
        ? context.t(
            'artist.albumCardMeta',
            args: {
              'year': context.localizeDigitsText(album.year.toString()),
              'tracks': tracksStr,
            },
          )
        : context.t(
            'artist.albumCardTracksOnly',
            args: {'tracks': tracksStr},
          );

    return Semantics(
      button: true,
      label: '${album.album}, $metaText',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (hovered) {
          if (_isHovered != hovered) {
            setState(() => _isHovered = hovered);
          }
        },
        onShowFocusHighlight: (focused) {
          if (_isFocused != focused) {
            setState(() => _isFocused = focused);
          }
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: widget.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 120),
            width: widget.width,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _isHovered ? AppColors.fillControl : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.r12),
              border: Border.all(
                color: _isFocused
                    ? AppColors.accent
                    : (_isHovered
                        ? AppColors.borderSubtle
                        : Colors.transparent),
                width: 2.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 1.0,
                  child: ArtistAlbumCover(
                    coverKey: album.coverKey,
                    cacheWidth: 320,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  album.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: textDirectionFor(album.album),
                  style: AppTypography.bodyStrong.copyWith(
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metaText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
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

/// Square album cover image with cached decode and calm placeholder fallback.
class ArtistAlbumCover extends StatelessWidget {
  /// Cover cache key, if available.
  final String? coverKey;

  /// Decode width/height hint.
  final int cacheWidth;

  /// Creates an [ArtistAlbumCover].
  const ArtistAlbumCover({
    super.key,
    required this.coverKey,
    required this.cacheWidth,
  });

  File? _resolveCoverFile() {
    final key = coverKey;
    if (key == null || key.isEmpty) return null;
    try {
      if (!CoverCache.hasCover(key)) return null;
      return File(CoverCache.pathFor(key));
    } on StateError {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _resolveCoverFile();
    final Widget imageWidget;
    if (file != null) {
      imageWidget = Image.file(
        file,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        cacheWidth: cacheWidth,
        cacheHeight: cacheWidth,
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
      borderRadius: BorderRadius.circular(AppSpacing.r10),
      child: imageWidget,
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF22212C),
        borderRadius: BorderRadius.circular(AppSpacing.r10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: const Center(
        child: Icon(Icons.album_outlined, color: Colors.white24, size: 32),
      ),
    );
  }
}
