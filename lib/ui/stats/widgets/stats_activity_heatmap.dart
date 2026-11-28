import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../library/history_models.dart';
import '../../glass/glass_button.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../stats_formatters.dart';
import '../stats_models.dart';

/// CustomPainter rendering the calm 7 x 24 weekly listening heat strip.
class StatsHeatmapPainter extends CustomPainter {
  /// Ordered ISO weekdays (7 items, matching locale week start).
  final List<int> orderedWeekdays;

  /// Lookup map keyed by `weekday * 24 + hour`.
  final Map<int, WeekdayHourListeningStat> cellLookup;

  /// Highest `totalListenedMs` across all cells for calm normalization.
  final int maxListenedMs;

  /// Currently hovered or keyboard-focused cell key (`rowIndex * 24 + hour`).
  final int? activeCellKey;

  /// Layout text direction for RTL mirroring.
  final TextDirection textDirection;

  /// Creates a [StatsHeatmapPainter].
  const StatsHeatmapPainter({
    required this.orderedWeekdays,
    required this.cellLookup,
    required this.maxListenedMs,
    required this.activeCellKey,
    required this.textDirection,
  });

  /// Maps [listenedMs] against [maxListenedMs] to a discrete 0..4 intensity
  /// level.
  static int intensityLevel(int listenedMs, int maxListenedMs) {
    if (listenedMs <= 0 || maxListenedMs <= 0) return 0;
    final ratio = listenedMs / maxListenedMs;
    if (ratio >= 0.75) return 4;
    if (ratio >= 0.50) return 3;
    if (ratio >= 0.25) return 2;
    return 1;
  }

  /// Calm palette colors for intensity levels 0..4.
  static Color colorForLevel(int level) {
    switch (level) {
      case 1:
        return AppColors.accent.withValues(alpha: 0.20);
      case 2:
        return AppColors.accent.withValues(alpha: 0.40);
      case 3:
        return AppColors.accent.withValues(alpha: 0.62);
      case 4:
        return AppColors.accent.withValues(alpha: 0.88);
      default:
        return AppColors.fillControl;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (orderedWeekdays.length != 7 || size.width <= 0 || size.height <= 0) {
      return;
    }

    const gap = 3.0;
    final colWidth = math.max(1.0, (size.width - gap * 23) / 24);
    final rowHeight = math.max(1.0, (size.height - gap * 6) / 7);
    final isRtl = textDirection == TextDirection.rtl;
    const cellRadius = Radius.circular(3.0);

    for (var row = 0; row < 7; row++) {
      final weekday = orderedWeekdays[row];
      final top = row * (rowHeight + gap);
      for (var hour = 0; hour < 24; hour++) {
        final colIndex = isRtl ? (23 - hour) : hour;
        final left = colIndex * (colWidth + gap);
        final rect = Rect.fromLTWH(left, top, colWidth, rowHeight);
        final stat = cellLookup[weekday * 24 + hour];
        final level = intensityLevel(stat?.totalListenedMs ?? 0, maxListenedMs);
        final fill = Paint()
          ..style = PaintingStyle.fill
          ..color = colorForLevel(level);
        final rrect = RRect.fromRectAndRadius(rect, cellRadius);
        canvas.drawRRect(rrect, fill);

        final isActive = activeCellKey == (row * 24 + hour);
        if (isActive) {
          final focusPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = AppColors.text;
          canvas.drawRRect(rrect, focusPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant StatsHeatmapPainter oldDelegate) {
    return oldDelegate.orderedWeekdays != orderedWeekdays ||
        oldDelegate.cellLookup != cellLookup ||
        oldDelegate.maxListenedMs != maxListenedMs ||
        oldDelegate.activeCellKey != activeCellKey ||
        oldDelegate.textDirection != textDirection;
  }
}

/// Interactive 7 x 24 "Weekly listening activity" heat strip.
class StatsActivityHeatmap extends StatefulWidget {
  /// Stats snapshot supplying weekday order and `(weekday, hour)` cells.
  final StatsSnapshot snapshot;

  /// Whether to minimize tooltip hover delay transitions.
  final bool reduceMotion;

  /// Optional action opening the Weekly listening recap from this section.
  final VoidCallback? onOpenWeeklyRecap;

  /// Creates a [StatsActivityHeatmap].
  const StatsActivityHeatmap({
    super.key,
    required this.snapshot,
    this.reduceMotion = false,
    this.onOpenWeeklyRecap,
  });

  @override
  State<StatsActivityHeatmap> createState() => _StatsActivityHeatmapState();
}

class _StatsActivityHeatmapState extends State<StatsActivityHeatmap> {
  int? _activeCellKey;

  Map<int, WeekdayHourListeningStat> _buildLookup() {
    final map = <int, WeekdayHourListeningStat>{};
    for (final item in widget.snapshot.weekdayHourActivity) {
      map[item.weekday * 24 + item.hour] = item;
    }
    return map;
  }

  int _computeMaxMs(Map<int, WeekdayHourListeningStat> lookup) {
    var maxMs = 0;
    for (final item in lookup.values) {
      if (item.totalListenedMs > maxMs) {
        maxMs = item.totalListenedMs;
      }
    }
    return maxMs;
  }

  String _tooltipFor(
    BuildContext context,
    int weekday,
    int hour,
    WeekdayHourListeningStat? stat,
  ) {
    final dayLabel = StatsFormatters.formatWeekdayShort(context, weekday);
    final hourLabel = StatsFormatters.formatHour(context, hour);
    final duration = StatsFormatters.formatHoursMinutes(
      context,
      stat?.totalListenedMs ?? 0,
    );
    final plays = context.formatCountLocalized(stat?.playCount ?? 0);
    return context.localizeDigitsText(
      context.t(
        'stats.heatmap.cellTooltip',
        args: {
          'day': dayLabel,
          'hour': hourLabel,
          'duration': duration,
          'plays': plays,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weekdays = widget.snapshot.orderedWeekdays;
    final lookup = _buildLookup();
    final maxMs = _computeMaxMs(lookup);

    String? activeReadout;
    if (_activeCellKey != null) {
      final row = _activeCellKey! ~/ 24;
      final hour = _activeCellKey! % 24;
      if (row >= 0 && row < weekdays.length) {
        final weekday = weekdays[row];
        activeReadout = _tooltipFor(
          context,
          weekday,
          hour,
          lookup[weekday * 24 + hour],
        );
      }
    }

    return Container(
      key: const Key('stats_heatmap_card'),
      padding: const EdgeInsets.all(AppSpacing.s24),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.78),
        borderRadius: AppSpacing.br22,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.s12,
            runSpacing: AppSpacing.s8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('stats.heatmap.title'),
                    style: AppTypography.title.copyWith(color: AppColors.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.t('stats.heatmap.subtitle'),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              if (activeReadout != null)
                Text(
                  activeReadout,
                  key: const Key('stats_heatmap_active_readout'),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.accent,
                  ),
                )
              else
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.s12,
                  runSpacing: AppSpacing.s8,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.t('stats.heatmap.less'),
                          style: AppTypography.caption.copyWith(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        for (var level = 0; level <= 4; level++) ...[
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: StatsHeatmapPainter.colorForLevel(level),
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                          if (level < 4) const SizedBox(width: 3),
                        ],
                        const SizedBox(width: 6),
                        Text(
                          context.t('stats.heatmap.more'),
                          style: AppTypography.caption.copyWith(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    if (widget.onOpenWeeklyRecap != null)
                      GlassPillButton(
                        key: const Key('stats_weekly_recap_button'),
                        size: GlassButtonSize.small,
                        leadingIcon: Icons.auto_awesome_outlined,
                        label: context.t('stats.weeklyRecapButton'),
                        onPressed: widget.onOpenWeeklyRecap,
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                height: 148,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final weekday in weekdays)
                      SizedBox(
                        height: 18,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            StatsFormatters.formatWeekdayShort(
                              context,
                              weekday,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption.copyWith(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 148,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(
                            key: const Key('stats_heatmap_custom_paint'),
                            painter: StatsHeatmapPainter(
                              orderedWeekdays: weekdays,
                              cellLookup: lookup,
                              maxListenedMs: maxMs,
                              activeCellKey: _activeCellKey,
                              textDirection: Directionality.of(context),
                            ),
                          ),
                          Column(
                            children: [
                              for (var row = 0; row < 7; row++)
                                Expanded(
                                  child: Row(
                                    children: [
                                      for (var hour = 0; hour < 24; hour++)
                                        Expanded(
                                          child: _HeatmapCellHitTarget(
                                            cellKey: row * 24 + hour,
                                            tooltip: _tooltipFor(
                                              context,
                                              weekdays[row],
                                              hour,
                                              lookup[weekdays[row] * 24 + hour],
                                            ),
                                            reduceMotion: widget.reduceMotion,
                                            onActiveChanged: (key, active) {
                                              if (!mounted) return;
                                              setState(() {
                                                if (active) {
                                                  _activeCellKey = key;
                                                } else if (_activeCellKey ==
                                                    key) {
                                                  _activeCellKey = null;
                                                }
                                              });
                                            },
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final hour in const [0, 6, 12, 18, 23])
                          Text(
                            StatsFormatters.formatHour(context, hour),
                            style: AppTypography.caption.copyWith(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeatmapCellHitTarget extends StatelessWidget {
  final int cellKey;
  final String tooltip;
  final bool reduceMotion;
  final void Function(int key, bool active) onActiveChanged;

  const _HeatmapCellHitTarget({
    required this.cellKey,
    required this.tooltip,
    required this.reduceMotion,
    required this.onActiveChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      child: Semantics(
        label: tooltip,
        focusable: true,
        child: Focus(
          onFocusChange: (hasFocus) => onActiveChanged(cellKey, hasFocus),
          child: MouseRegion(
            onEnter: (_) => onActiveChanged(cellKey, true),
            onExit: (_) => onActiveChanged(cellKey, false),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
