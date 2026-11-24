import 'dart:io';

import 'package:flutter/material.dart';

import '../../../features/collections/user_collections.dart';
import '../../../library/cover_cache.dart';
import '../../glass/glass_button.dart';
import '../../l10n/app_strings.dart';
import '../../mini_player/mini_player_controller.dart';
import '../../shell/app_navigator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../metadata_link.dart';

/// Top overlay bar in Full Screen mode showing credit text and window actions.
class FullScreenTopBar extends StatelessWidget {
  /// Whether the controls are currently visible.
  final bool showControls;

  /// Whether floating glass shapes are currently enabled.
  final bool showGlassShapes;

  /// Application navigator.
  final AppNavigator navigator;

  /// Optional mini player controller.
  final MiniPlayerController? miniPlayerController;

  /// Callback toggling glass shapes visibility.
  final VoidCallback onToggleGlassShapes;

  /// Creates a [FullScreenTopBar].
  const FullScreenTopBar({
    super.key,
    required this.showControls,
    required this.showGlassShapes,
    required this.navigator,
    required this.onToggleGlassShapes,
    this.miniPlayerController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            // Credit text "by mido"
            Text(
              context.t('app.credit'),
              style: AppTypography.caption.copyWith(
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),

            // Glass shapes toggle button
            GlassIconButton(
              key: const Key('fullscreen_toggle_glass_shapes'),
              icon: showGlassShapes ? Icons.grain : Icons.blur_off,
              tooltip: context.t('fullScreen.glassShapesTooltip'),
              semanticLabel: context.t('fullScreen.glassShapesTooltip'),
              variant: showGlassShapes
                  ? GlassButtonVariant.selected
                  : GlassButtonVariant.normal,
              onPressed: onToggleGlassShapes,
            ),
            if (miniPlayerController != null) ...[
              const SizedBox(width: 12),
              GlassIconButton(
                key: const Key('fullscreen_mini_player_button'),
                icon: Icons.picture_in_picture_alt_outlined,
                tooltip: context.t('miniPlayer.enterTooltip'),
                semanticLabel: context.t('miniPlayer.enterTooltip'),
                onPressed: () {
                  navigator.goBack();
                  miniPlayerController?.enter();
                },
              ),
            ],
            const SizedBox(width: 12),

            // Exit full screen button
            GlassIconButton(
              key: const Key('fullscreen_exit_button'),
              icon: Icons.fullscreen_exit,
              tooltip: context.t('fullScreen.exitTooltip'),
              semanticLabel: context.t('fullScreen.exitTooltip'),
              onPressed: () => navigator.goBack(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Artwork and track metadata column in Full Screen mode.
class FullScreenArtworkColumn extends StatelessWidget {
  /// Cover cache key, if present.
  final String? coverKey;

  /// Artwork square size in logical pixels.
  final double artworkSize;

  /// Key attached to the metadata/controls subtree for double-tap exclusion.
  final Key controlsColumnKey;

  /// Whether a track is currently loaded.
  final bool hasTrack;

  /// Active track URI, if loaded.
  final String? trackUri;

  /// Track title text.
  final String title;

  /// Localized display artist.
  final String artist;

  /// Raw artist tag for artist-detail navigation.
  final String? rawArtist;

  /// Album title text.
  final String album;

  /// Whether animations should be reduced.
  final bool reduceMotion;

  /// Application navigator.
  final AppNavigator navigator;

  /// Creates a [FullScreenArtworkColumn].
  const FullScreenArtworkColumn({
    super.key,
    required this.coverKey,
    required this.artworkSize,
    required this.controlsColumnKey,
    required this.hasTrack,
    required this.trackUri,
    required this.title,
    required this.artist,
    required this.rawArtist,
    required this.album,
    required this.reduceMotion,
    required this.navigator,
  });

  Widget _buildArtwork() {
    final hasCover = coverKey != null && CoverCache.hasCover(coverKey!);
    return Container(
      width: artworkSize,
      height: artworkSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32.0),
        border: Border.all(color: AppColors.border, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 36.0,
            offset: Offset(0, 14.0),
          ),
        ],
        color: AppColors.surface,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(31.0),
        child: hasCover
            ? Image.file(
                File(CoverCache.pathFor(coverKey!)),
                fit: BoxFit.cover,
                cacheWidth: 1024,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _placeholderIcon(),
              )
            : _placeholderIcon(),
      ),
    );
  }

  Widget _placeholderIcon() {
    return const Center(
      child: Icon(
        Icons.music_note,
        size: 80,
        color: AppColors.textMuted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildArtwork(),
        const SizedBox(height: 28),
        KeyedSubtree(
          key: controlsColumnKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textDirection: textDirectionFor(title),
                      style: AppTypography.title.copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  if (hasTrack && trackUri != null) ...[
                    const SizedBox(width: 10),
                    FullScreenFavoriteButton(path: trackUri!),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Builder(
                builder: (context) {
                  final canLink = hasTrack &&
                      rawArtist != null &&
                      rawArtist!.trim().isNotEmpty;
                  return MetadataLink(
                    text: artist,
                    style: AppTypography.title.copyWith(
                      fontSize: 20,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                    reduceMotion: reduceMotion,
                    semanticLabel: canLink
                        ? context.t(
                            'common.goToArtist',
                            args: {'name': artist},
                          )
                        : null,
                    onTap: canLink
                        ? () => MetadataNavHelper.openArtist(
                              context: context,
                              navigator: navigator,
                              rawArtist: rawArtist!,
                              leaveFullScreenFirst: true,
                            )
                        : null,
                  );
                },
              ),
              if (album.isNotEmpty) ...[
                const SizedBox(height: 4),
                Builder(
                  builder: (context) {
                    final canLink = hasTrack && album.trim().isNotEmpty;
                    return MetadataLink(
                      text: album,
                      style: AppTypography.bodyStrong.copyWith(
                        fontSize: 16,
                        color: AppColors.textMuted,
                      ),
                      textAlign: TextAlign.center,
                      reduceMotion: reduceMotion,
                      semanticLabel: canLink
                          ? context.t(
                              'common.goToAlbum',
                              args: {'name': album},
                            )
                          : null,
                      onTap: canLink
                          ? () => MetadataNavHelper.openAlbum(
                                navigator: navigator,
                                albumTitle: album,
                                leaveFullScreenFirst: true,
                              )
                          : null,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Favorite heart toggle for the active track in Full Screen mode.
class FullScreenFavoriteButton extends StatelessWidget {
  /// Track path/URI.
  final String path;

  /// Creates a [FullScreenFavoriteButton].
  const FullScreenFavoriteButton({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    final collections = UserCollectionsScope.maybeOf(context);
    if (collections == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: collections,
      builder: (context, _) {
        final isFav = collections.isFavorite(path);

        return IconButton(
          key: const Key('fullscreen_favorite_button'),
          icon: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            size: 24,
            color: isFav ? AppColors.accent : AppColors.textMuted,
          ),
          tooltip: isFav
              ? context.t('track.unfavorite')
              : context.t('track.favorite'),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => collections.toggleFavorite(path),
        );
      },
    );
  }
}
