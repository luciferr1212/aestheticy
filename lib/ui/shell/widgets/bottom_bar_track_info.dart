import 'dart:io';

import 'package:flutter/material.dart';

import '../../../audio/audio_models.dart';
import '../../../audio/playback_controller.dart';
import '../../../library/cover_cache.dart';
import '../../artist_names/artist_name_scope.dart';
import '../../l10n/app_strings.dart';
import '../../now_playing/metadata_link.dart';
import '../../settings/settings_scope.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../app_navigator.dart';
import 'bottom_bar_end_controls.dart';

/// Metadata and cover artwork area on the start side of [BottomNowPlayingBar].
///
/// Isolated so seek position ticks do NOT trigger rebuilds here.
class BottomBarTrackInfo extends StatelessWidget {
  /// Active playback controller.
  final PlaybackController controller;

  /// Optional navigation coordinator.
  final AppNavigator? navigator;

  /// Optional test hook invoked when track info builds.
  final VoidCallback? onTrackInfoBuild;

  /// Whether compact layout spacing is active.
  final bool compact;

  /// Creates a [BottomBarTrackInfo].
  const BottomBarTrackInfo({
    super.key,
    required this.controller,
    this.navigator,
    this.onTrackInfoBuild,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    onTrackInfoBuild?.call();

    return StreamBuilder<AudioSource?>(
      stream: controller.currentStream,
      initialData: controller.queue.current,
      builder: (context, snapshot) {
        final current = snapshot.data;
        final hasTrack = current != null;

        final title = hasTrack
            ? (current.extras?['title'] ?? context.t('library.unknownTitle'))
            : context.t('player.noTrack');
        final rawArtist = current?.extras?['artist'];
        final artist = hasTrack ? context.displayArtist(rawArtist) : '—';
        final coverKey = current?.extras?['coverKey'];

        return Semantics(
          button: true,
          label: context.t('player.openNowPlaying'),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.r12),
            onTap: () {
              if (navigator != null) {
                navigator!.openNowPlaying();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.t('common.soon')),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 2 : 6,
                vertical: 4,
              ),
              child: Row(
                children: [
                  // Cover thumbnail
                  _buildCover(coverKey),
                  SizedBox(width: compact ? 6 : 12),

                  // Title and Artist
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: textDirectionFor(title),
                                style: AppTypography.bodyStrong.copyWith(
                                  color: hasTrack
                                      ? AppColors.text
                                      : AppColors.textMuted,
                                ),
                              ),
                            ),
                            if (hasTrack && !compact) ...[
                              const SizedBox(width: 4),
                              PlayerFavoriteButton(path: current.uri),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Builder(
                          builder: (context) {
                            final canLink = hasTrack &&
                                rawArtist != null &&
                                rawArtist.trim().isNotEmpty &&
                                navigator != null;
                            return MetadataLink(
                              text: artist,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              reduceMotion: SettingsScope.maybeOf(context)
                                      ?.settings
                                      .reduceMotion ??
                                  false,
                              semanticLabel: canLink
                                  ? context.t(
                                      'common.goToArtist',
                                      args: {'name': artist},
                                    )
                                  : null,
                              onTap: canLink
                                  ? () => MetadataNavHelper.openArtist(
                                        context: context,
                                        navigator: navigator!,
                                        rawArtist: rawArtist,
                                      )
                                  : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // Directional chevron
                  if (!compact)
                    const Icon(
                      Icons.keyboard_arrow_up,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCover(String? coverKey) {
    final dim = compact ? 36.0 : 52.0;
    Widget imageWidget;
    File? coverFile;
    if (coverKey != null && coverKey.isNotEmpty) {
      try {
        if (CoverCache.hasCover(coverKey)) {
          coverFile = File(CoverCache.pathFor(coverKey));
        }
      } on StateError {
        coverFile = null;
      }
    }
    if (coverFile != null) {
      imageWidget = Image.file(
        coverFile,
        width: dim,
        height: dim,
        fit: BoxFit.cover,
        cacheWidth: 104,
        cacheHeight: 104,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else {
      imageWidget = _buildPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.r10),
      child: SizedBox(
        width: dim,
        height: dim,
        child: imageWidget,
      ),
    );
  }

  Widget _buildPlaceholder() {
    final dim = compact ? 36.0 : 52.0;
    return Container(
      width: dim,
      height: dim,
      decoration: BoxDecoration(
        color: const Color(0xFF22212C),
        borderRadius: BorderRadius.circular(AppSpacing.r10),
      ),
      child: Center(
        child: Icon(
          Icons.music_note,
          color: Colors.white24,
          size: compact ? 18 : 24,
        ),
      ),
    );
  }
}
