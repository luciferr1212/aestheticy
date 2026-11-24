import 'package:flutter/material.dart';

import '../../../features/collections/user_collections.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../shell/app_navigator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../metadata_link.dart';

/// Metadata area isolated from seek ticks.
class NowPlayingMetadataArea extends StatelessWidget {
  /// Track title text.
  final String title;

  /// Localized artist display name.
  final String artist;

  /// Album title text.
  final String album;

  /// Raw artist tag for navigation linking.
  final String? rawArtist;

  /// Application navigation coordinator.
  final AppNavigator navigator;

  /// Whether animations should be reduced.
  final bool reduceMotion;

  /// Active track file path/URI for favorite and rating controls.
  final String? trackPath;

  /// Optional test hook invoked during build.
  final VoidCallback? onBuild;

  /// Creates a [NowPlayingMetadataArea].
  const NowPlayingMetadataArea({
    super.key,
    required this.title,
    required this.artist,
    required this.album,
    this.rawArtist,
    required this.navigator,
    this.reduceMotion = false,
    this.trackPath,
    this.onBuild,
  });

  @override
  Widget build(BuildContext context) {
    onBuild?.call();

    final canLinkArtist = rawArtist != null && rawArtist!.trim().isNotEmpty;
    final canLinkAlbum = album.trim().isNotEmpty;

    return Column(
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
                style: AppTypography.title
                    .copyWith(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            if (trackPath != null) ...[
              const SizedBox(width: 8),
              NowPlayingFavoriteButton(path: trackPath!),
            ],
          ],
        ),
        const SizedBox(height: 4),
        MetadataLink(
          text: artist,
          style: AppTypography.bodyStrong.copyWith(
            color: AppColors.textSecondary,
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
          reduceMotion: reduceMotion,
          semanticLabel: canLinkArtist
              ? context.t('common.goToArtist', args: {'name': artist})
              : null,
          onTap: canLinkArtist
              ? () => MetadataNavHelper.openArtist(
                    context: context,
                    navigator: navigator,
                    rawArtist: rawArtist!,
                  )
              : null,
        ),
        if (album.isNotEmpty) ...[
          const SizedBox(height: 2),
          MetadataLink(
            text: album,
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
            reduceMotion: reduceMotion,
            semanticLabel: canLinkAlbum
                ? context.t('common.goToAlbum', args: {'name': album})
                : null,
            onTap: canLinkAlbum
                ? () => MetadataNavHelper.openAlbum(
                      navigator: navigator,
                      albumTitle: album,
                    )
                : null,
          ),
        ],
        if (trackPath != null) ...[
          const SizedBox(height: 10),
          TrackStarRatingControl(trackPath: trackPath!),
        ],
      ],
    );
  }
}

/// Favorite heart toggle for the active Now Playing track.
class NowPlayingFavoriteButton extends StatelessWidget {
  /// Track path/URI.
  final String path;

  /// Creates a [NowPlayingFavoriteButton].
  const NowPlayingFavoriteButton({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    final collections = UserCollectionsScope.maybeOf(context);
    if (collections == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: collections,
      builder: (context, _) {
        final isFav = collections.isFavorite(path);

        return IconButton(
          key: const Key('now_playing_favorite_button'),
          icon: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            size: 22,
            color: isFav ? AppColors.accent : AppColors.textMuted,
          ),
          tooltip: isFav
              ? context.t('track.unfavorite')
              : context.t('track.favorite'),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () => collections.toggleFavorite(path),
        );
      },
    );
  }
}

/// Five-star rating bar for the active track.
class TrackStarRatingControl extends StatelessWidget {
  /// Track path/URI.
  final String trackPath;

  /// Creates a [TrackStarRatingControl].
  const TrackStarRatingControl({super.key, required this.trackPath});

  @override
  Widget build(BuildContext context) {
    final collections = UserCollectionsScope.maybeOf(context);
    if (collections == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: collections,
      builder: (context, _) {
        final currentRating = collections.ratingOf(trackPath);

        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var s = 1; s <= 5; s++)
              IconButton(
                key: Key('rating_star_$s'),
                icon: Icon(
                  currentRating >= s ? Icons.star : Icons.star_border,
                  size: 20,
                  color: currentRating >= s
                      ? AppColors.accent
                      : AppColors.textMuted,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: currentRating == s
                    ? context.t('track.clearRating')
                    : context.t('track.rateStars', args: {
                        'stars': context.localizeDigitsText('$s'),
                      }),
                onPressed: () {
                  if (currentRating == s) {
                    collections.setRating(trackPath, 0);
                  } else {
                    collections.setRating(trackPath, s);
                  }
                },
              ),
          ],
        );
      },
    );
  }
}
