import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../stats_date_range.dart';
import '../stats_formatters.dart';
import '../stats_models.dart';

/// Displays up to 4 calm summary KPI tiles for the active Stats window:
/// Listening time (+ previous-period delta), Plays counted, Newly discovered,
/// and Busiest day.
class StatsSummaryGrid extends StatelessWidget {
  /// Active stats snapshot to summarize.
  final StatsSnapshot snapshot;

  /// Creates a [StatsSummaryGrid].
  const StatsSummaryGrid({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final includeYear =
        snapshot.range == StatsRange.year ||
        snapshot.range == StatsRange.allTime;
    final busiest = snapshot.busiestDay;

    final tiles = <Widget>[
      _SummaryTile(
        key: const Key('stats_tile_listening_time'),
        label: context.t('stats.summary.totalListening'),
        value: StatsFormatters.formatHoursMinutes(
          context,
          snapshot.totalListenedMs,
        ),
        subtitle: StatsFormatters.formatDelta(context, snapshot.previousDelta),
        accentSubtitle:
            snapshot.previousDelta != null &&
            (snapshot.previousDelta!.isNew ||
                (snapshot.previousDelta!.percentChange ?? 0) > 0),
      ),
      _SummaryTile(
        key: const Key('stats_tile_plays_counted'),
        label: context.t('stats.summary.playsCounted'),
        value: context.formatCountLocalized(snapshot.playsCounted),
        subtitle: context.localizeDigitsText(
          context.t(
            'stats.summary.playsSubtitle',
            args: {
              'tracks': '${snapshot.distinctTracks}',
              'artists': '${snapshot.distinctArtists}',
            },
          ),
        ),
      ),
      _SummaryTile(
        key: const Key('stats_tile_newly_discovered'),
        label: context.t('stats.summary.newlyDiscovered'),
        value: context.formatCountLocalized(snapshot.newlyDiscoveredTracks),
        subtitle: context.localizeDigitsText(
          context.t(
            'stats.summary.tracksUnit',
            args: {'count': '${snapshot.newlyDiscoveredTracks}'},
          ),
        ),
      ),
      _SummaryTile(
        key: const Key('stats_tile_busiest_day'),
        label: context.t('stats.summary.busiestDay'),
        value: busiest != null
            ? StatsFormatters.formatCalendarDay(
                context,
                busiest.date,
                includeYear: includeYear,
              )
            : context.t('stats.summary.none'),
        subtitle: busiest != null
            ? StatsFormatters.formatHoursMinutes(
                context,
                busiest.totalListenedMs,
              )
            : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 880
            ? 4
            : width >= 460
            ? 2
            : 1;
        const gap = AppSpacing.s12;
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: gap),
                tiles[i],
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += columns) {
          final slice = tiles.sublist(
            i,
            (i + columns) > tiles.length ? tiles.length : i + columns,
          );
          if (rows.isNotEmpty) {
            rows.add(const SizedBox(height: gap));
          }
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < slice.length; j++) ...[
                    if (j > 0) const SizedBox(width: gap),
                    Expanded(child: slice[j]),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final bool accentSubtitle;

  const _SummaryTile({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.accentSubtitle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.78),
        borderRadius: AppSpacing.br16,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.title.copyWith(color: AppColors.text),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            subtitle ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              color: accentSubtitle ? AppColors.success : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
