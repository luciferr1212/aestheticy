import 'package:flutter/material.dart';

import '../../../audio/playback_controller.dart';
import '../../artist_names/artist_name_scope.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Upcoming queue list displayed in the Now Playing "Up next" tab.
class NowPlayingUpNextList extends StatelessWidget {
  /// Active playback controller.
  final PlaybackController controller;

  /// Callback invoked when the user taps an upcoming queue index.
  final ValueChanged<int> onPlayUpcoming;

  /// Creates a [NowPlayingUpNextList].
  const NowPlayingUpNextList({
    super.key,
    required this.controller,
    required this.onPlayUpcoming,
  });

  @override
  Widget build(BuildContext context) {
    final queue = controller.queue;
    final items = queue.items;
    final currentIndex = queue.currentIndex;

    final upcomingIndices = <int>[];
    for (int i = currentIndex + 1; i < items.length; i++) {
      upcomingIndices.add(i);
    }

    if (upcomingIndices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.queue_music, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 8),
            Text(
              context.t('nowPlaying.nothingQueued'),
              style: AppTypography.body.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: upcomingIndices.length,
      itemBuilder: (context, index) {
        final queueIndex = upcomingIndices[index];
        final source = items[queueIndex];
        final trackTitle =
            source.extras?['title'] ?? context.t('library.unknownTitle');
        final rawTrackArtist = source.extras?['artist'];
        final trackArtist = rawTrackArtist != null && rawTrackArtist.isNotEmpty
            ? context.displayArtist(rawTrackArtist)
            : '—';
        final durationMsStr = source.extras?['durationMs'];
        final durationMs = int.tryParse(durationMsStr ?? '');
        final durationText = durationMs != null
            ? context.formatDurationLocalized(Duration(milliseconds: durationMs))
            : '—';

        return RepaintBoundary(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              hoverColor: const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(AppSpacing.r12),
              onTap: () => onPlayUpcoming(queueIndex),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${index + 1}',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textMuted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trackTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: textDirectionFor(trackTitle),
                            style: AppTypography.bodyStrong
                                .copyWith(color: AppColors.text),
                          ),
                          Text(
                            trackArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: textDirectionFor(trackArtist),
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      durationText,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
