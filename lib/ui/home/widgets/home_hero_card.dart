import 'package:flutter/material.dart';

import '../../../audio/playback_controller.dart';
import '../../artist_names/artist_name_scope.dart';
import '../../glass/glass_button.dart';
import '../../glass/glass_surface.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../library/widgets/album_tiles.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../home_models.dart';

/// Hero card at the top of the Home screen showing either the active Now
/// Playing track, a "Resume last session" prompt, or a calm empty state.
class HomeHeroCard extends StatefulWidget {
  /// Active Now Playing snapshot.
  final HomeNowPlayingSummary nowPlaying;

  /// Saved session summary when nothing is playing.
  final HomeResumeSessionSummary? resumeSession;

  /// Playback controller for play/pause actions.
  final PlaybackController playbackController;

  /// Whether animations are reduced.
  final bool reduceMotion;

  /// Called when tapping the active Now Playing hero card.
  final VoidCallback onOpenNowPlaying;

  /// Called when tapping Resume on the saved-session card.
  final VoidCallback onResumeSession;

  /// Called when tapping Browse Albums on the empty hero card.
  final VoidCallback onBrowseAlbums;

  /// Creates a [HomeHeroCard].
  const HomeHeroCard({
    super.key,
    required this.nowPlaying,
    required this.resumeSession,
    required this.playbackController,
    required this.reduceMotion,
    required this.onOpenNowPlaying,
    required this.onResumeSession,
    required this.onBrowseAlbums,
  });

  @override
  State<HomeHeroCard> createState() => _HomeHeroCardState();
}

class _HomeHeroCardState extends State<HomeHeroCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isNarrow = width < 720;
    final coverSize = isNarrow ? 84.0 : 112.0;
    final padding = isNarrow
        ? const EdgeInsets.all(AppSpacing.s16)
        : const EdgeInsets.all(AppSpacing.s24);

    if (widget.nowPlaying.hasTrack) {
      return _buildNowPlayingCard(context, coverSize, padding, isNarrow);
    }
    if (widget.resumeSession != null) {
      return _buildResumeCard(
        context,
        widget.resumeSession!,
        coverSize,
        padding,
        isNarrow,
      );
    }
    return _buildIdleCard(context, padding, isNarrow);
  }

  Widget _wrapInteractiveCard({
    required Key cardKey,
    required String semanticLabel,
    required VoidCallback? onTap,
    required EdgeInsetsGeometry padding,
    required Widget child,
  }) {
    final highlightBorder = _focused
        ? AppColors.accent
        : (_hovered ? const Color(0x38FFFFFF) : Colors.transparent);

    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      child: GlassSurface(
        key: cardKey,
        borderRadius: AppSpacing.r22,
        density: GlassDensity.clear,
        child: AnimatedContainer(
          duration: widget.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.r22),
            border: Border.all(
              color: highlightBorder,
              width: _focused ? 1.5 : 1.0,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.r22),
            mouseCursor:
                onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
            hoverColor: const Color(0x0EFFFFFF),
            focusColor: const Color(0x14FFFFFF),
            onHover: onTap != null ? (v) => setState(() => _hovered = v) : null,
            onFocusChange:
                onTap != null ? (v) => setState(() => _focused = v) : null,
            onTap: onTap,
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNowPlayingCard(
    BuildContext context,
    double coverSize,
    EdgeInsetsGeometry padding,
    bool isNarrow,
  ) {
    final np = widget.nowPlaying;
    final artist = context.displayArtist(np.artist);

    return _wrapInteractiveCard(
      cardKey: const Key('home_hero_now_playing'),
      semanticLabel: '${context.t('home.nowPlaying')}: ${np.title}',
      onTap: widget.onOpenNowPlaying,
      padding: padding,
      child: Row(
        children: [
          SizedBox(
            width: coverSize,
            height: coverSize,
            child: AlbumCoverImage(
              coverKey: np.coverKey,
              borderRadius: AppSpacing.r16,
              cacheSize: 160,
            ),
          ),
          SizedBox(width: isNarrow ? AppSpacing.s16 : AppSpacing.s24),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('home.nowPlaying').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.micro.copyWith(color: AppColors.accentSoft),
                ),
                const SizedBox(height: 6),
                Text(
                  np.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: textDirectionFor(np.title),
                  style: (isNarrow ? AppTypography.bodyStrong : AppTypography.title)
                      .copyWith(color: AppColors.text),
                ),
                if (artist.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDirectionFor(artist),
                    style: AppTypography.body
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          GlassIconButton(
            key: const Key('home_hero_play_pause'),
            icon: np.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            variant: GlassButtonVariant.primary,
            size: isNarrow ? GlassButtonSize.medium : GlassButtonSize.large,
            tooltip: np.isPlaying
                ? context.t('common.pause')
                : context.t('common.play'),
            semanticLabel: np.isPlaying
                ? context.t('common.pause')
                : context.t('common.play'),
            onPressed: widget.playbackController.togglePlayPause,
          ),
        ],
      ),
    );
  }

  Widget _buildResumeCard(
    BuildContext context,
    HomeResumeSessionSummary resume,
    double coverSize,
    EdgeInsetsGeometry padding,
    bool isNarrow,
  ) {
    final artist = context.displayArtist(resume.artist);
    final countLabel = context.t(
      'home.resumeTracksCount',
      args: {'count': context.formatCountLocalized(resume.trackCount)},
    );

    return _wrapInteractiveCard(
      cardKey: const Key('home_hero_resume'),
      semanticLabel: context.t('home.resumeLastSession'),
      onTap: widget.onResumeSession,
      padding: padding,
      child: Row(
        children: [
          SizedBox(
            width: coverSize,
            height: coverSize,
            child: AlbumCoverImage(
              coverKey: resume.coverKey,
              borderRadius: AppSpacing.r16,
              cacheSize: 160,
            ),
          ),
          SizedBox(width: isNarrow ? AppSpacing.s16 : AppSpacing.s24),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('home.resumeLastSession').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.micro.copyWith(color: AppColors.accentSoft),
                ),
                const SizedBox(height: 6),
                Text(
                  resume.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: textDirectionFor(resume.title),
                  style: (isNarrow ? AppTypography.bodyStrong : AppTypography.title)
                      .copyWith(color: AppColors.text),
                ),
                const SizedBox(height: 4),
                Text(
                  artist.isNotEmpty ? '$artist • $countLabel' : countLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: textDirectionFor(
                    artist.isNotEmpty ? artist : countLabel,
                  ),
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          GlassPillButton(
            key: const Key('home_hero_resume_button'),
            label: context.t('home.resumeAction'),
            leadingIcon: Icons.play_arrow_rounded,
            variant: GlassButtonVariant.primary,
            size: GlassButtonSize.medium,
            onPressed: widget.onResumeSession,
          ),
        ],
      ),
    );
  }

  Widget _buildIdleCard(
    BuildContext context,
    EdgeInsetsGeometry padding,
    bool isNarrow,
  ) {
    return _wrapInteractiveCard(
      cardKey: const Key('home_hero_idle'),
      semanticLabel: context.t('home.readyTitle'),
      onTap: null,
      padding: padding,
      child: Row(
        children: [
          Container(
            width: isNarrow ? 56 : 72,
            height: isNarrow ? 56 : 72,
            decoration: BoxDecoration(
              color: AppColors.accentFill,
              borderRadius: BorderRadius.circular(AppSpacing.r16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: AppColors.accent,
              size: 28,
            ),
          ),
          SizedBox(width: isNarrow ? AppSpacing.s16 : AppSpacing.s24),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('home.readyTitle'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (isNarrow ? AppTypography.bodyStrong : AppTypography.title)
                      .copyWith(color: AppColors.text),
                ),
                const SizedBox(height: 4),
                Text(
                  context.t('home.readySubtitle'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          GlassPillButton(
            key: const Key('home_hero_browse_button'),
            label: context.t('home.browseAlbums'),
            variant: GlassButtonVariant.normal,
            size: GlassButtonSize.medium,
            onPressed: widget.onBrowseAlbums,
          ),
        ],
      ),
    );
  }
}
