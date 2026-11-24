import 'package:flutter/material.dart';

import '../../../audio/audio_models.dart';
import '../../../features/lyrics/lyrics_controller.dart';
import '../../../features/lyrics/lyrics_models.dart';
import '../../artist_names/artist_name_scope.dart';
import '../../glass/glass_button.dart';
import '../../l10n/app_strings.dart';
import '../../shell/app_navigator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'lyrics_sync_control.dart';

/// Compact toolbar rendered at the top of the docked side-panel lyrics view.
class LyricsSidePanelToolbar extends StatelessWidget {
  /// Active track source, if any.
  final AudioSource? currentTrack;

  /// Current lyrics controller.
  final LyricsController controller;

  /// Creates a [LyricsSidePanelToolbar].
  const LyricsSidePanelToolbar({
    super.key,
    required this.currentTrack,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final doc = controller.document;
    final isSynced = doc != null && doc.kind == LyricsKind.synced;
    if (currentTrack == null && !isSynced) {
      return const SizedBox.shrink();
    }

    final title = currentTrack != null
        ? (currentTrack!.extras?['title'] ?? context.t('library.unknownTitle'))
        : context.t('player.noTrack');
    final rawArtist = currentTrack?.extras?['artist'];
    final artist = currentTrack != null
        ? (rawArtist != null && rawArtist.isNotEmpty
            ? context.displayArtist(rawArtist)
            : context.t('library.unknownArtist'))
        : '—';

    final sourceLabel = _lyricsSourceLabel(context, doc);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (currentTrack != null)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: textDirectionFor(title),
                        style: AppTypography.bodyStrong.copyWith(
                          color: AppColors.text,
                        ),
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
                if (sourceLabel.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  LyricsBadge(label: sourceLabel),
                ],
              ],
            ),
          if (isSynced) ...[
            if (currentTrack != null) const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: LyricsSyncControl(controller: controller),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full page header for the dedicated lyrics screen.
class LyricsHeader extends StatelessWidget {
  /// Active track source, if any.
  final AudioSource? currentTrack;

  /// Current lyrics controller.
  final LyricsController controller;

  /// Optional navigation coordinator for the back button.
  final AppNavigator? navigator;

  /// Creates a [LyricsHeader].
  const LyricsHeader({
    super.key,
    required this.currentTrack,
    required this.controller,
    this.navigator,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrack = currentTrack != null;

    final title = hasTrack
        ? (currentTrack!.extras?['title'] ?? context.t('library.unknownTitle'))
        : context.t('player.noTrack');

    final rawArtist = currentTrack?.extras?['artist'];
    final artist = hasTrack
        ? (rawArtist != null && rawArtist.isNotEmpty
            ? context.displayArtist(rawArtist)
            : context.t('library.unknownArtist'))
        : '—';

    final doc = controller.document;
    final sourceLabel = _lyricsSourceLabel(context, doc);

    final String timingLabel;
    if (doc != null && doc.kind == LyricsKind.synced) {
      timingLabel = doc.hasWordTiming
          ? context.t('lyrics.timing.word')
          : context.t('lyrics.timing.line');
    } else {
      timingLabel = '';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasTrailing =
              sourceLabel.isNotEmpty ||
              timingLabel.isNotEmpty ||
              (doc != null && doc.kind == LyricsKind.synced);
          final trailingMaxWidth =
              (constraints.maxWidth * 0.68).clamp(160.0, 900.0);

          return Row(
            children: [
              if (navigator != null)
                GlassPillButton(
                  leadingIcon: Icons.chevron_left,
                  matchTextDirection: true,
                  label: context.t('common.back'),
                  tooltip: context.t('common.back'),
                  semanticLabel: context.t('common.back'),
                  onPressed: () => navigator!.goBack(),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: textDirectionFor(title),
                      style: AppTypography.title.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
              if (hasTrailing) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: trailingMaxWidth),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (sourceLabel.isNotEmpty) LyricsBadge(label: sourceLabel),
                      if (timingLabel.isNotEmpty) LyricsBadge(label: timingLabel),
                      if (doc != null && doc.kind == LyricsKind.synced)
                        LyricsSyncControl(controller: controller),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Small pill badge used for lyrics source and timing labels.
class LyricsBadge extends StatelessWidget {
  /// Badge text.
  final String label;

  /// Creates a [LyricsBadge].
  const LyricsBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.fillControl,
        borderRadius: BorderRadius.circular(AppSpacing.pill),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Text(
        label,
        style: AppTypography.micro.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _lyricsSourceLabel(BuildContext context, LyricsDocument? doc) {
  if (doc == null) return '';
  return switch (doc.source) {
    LyricsSourceOrigin.local => context.t('lyrics.source.local'),
    LyricsSourceOrigin.embedded => context.t('lyrics.source.embedded'),
    LyricsSourceOrigin.lrclib => context.t('lyrics.source.lrclib'),
  };
}
