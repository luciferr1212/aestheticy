import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../stats_date_range.dart';
import '../stats_formatters.dart';
import '../stats_models.dart';

/// CustomPainter drawing calm proportional daily or monthly listening bars.
class StatsBarChartPainter extends CustomPainter {
  /// Ordered bar buckets from start to end of the chart window.
  final List<StatsBarBucket> bars;

  /// Index of the hovered or keyboard-focused bar, or `null`.
  final int? activeIndex;

  /// Layout text direction so bar slots mirror cleanly in RTL locales.
  final TextDirection textDirection;

  /// Creates a [StatsBarChartPainter].
  const StatsBarChartPainter({
    required this.bars,
    required this.activeIndex,
    required this.textDirection,
  });

  /// Computes exact proportional bar rectangles inside [size] for [bars].
  ///
  /// Exposed as a pure helper for unit verification of bar proportions and
  /// zero-value baseline handling.
  static List<Rect> computeBarRects(
    Size size,
    List<StatsBarBucket> bars, {
    TextDirection textDirection = TextDirection.ltr,
  }) {
    if (bars.isEmpty || size.width <= 0 || size.height <= 0) {
      return const <Rect>[];
    }

    const verticalTopPadding = 8.0;
    const baselineHeight = 2.0;
    final usableHeight = math.max(1.0, size.height - verticalTopPadding);
    var maxMs = 0;
    for (final bar in bars) {
      if (bar.totalListenedMs > maxMs) {
        maxMs = bar.totalListenedMs;
      }
    }

    final slotWidth = size.width / bars.length;
    final barWidth = math.max(
      3.0,
      math.min(28.0, slotWidth * (bars.length <= 12 ? 0.54 : 0.68)),
    );
    final isRtl = textDirection == TextDirection.rtl;

    return List<Rect>.generate(bars.length, (i) {
      final slotIndex = isRtl ? (bars.length - 1 - i) : i;
      final left = slotIndex * slotWidth + (slotWidth - barWidth) / 2.0;
      final ms = math.max(0, bars[i].totalListenedMs);
      final height = maxMs <= 0 || ms == 0
          ? baselineHeight
          : math.max(4.0, (ms / maxMs) * usableHeight);
      return Rect.fromLTWH(left, size.height - height, barWidth, height);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0 || size.height <= 0) return;

    final gridPaint = Paint()
      ..color = AppColors.borderSubtle
      ..strokeWidth = 1.0;

    // Quiet horizontal baseline + midpoint guide.
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      gridPaint..color = AppColors.borderSubtle.withValues(alpha: 0.45),
    );

    final rects = computeBarRects(size, bars, textDirection: textDirection);
    final radius = Radius.circular(bars.length > 20 ? 3.0 : 6.0);

    for (var i = 0; i < rects.length; i++) {
      final rect = rects[i];
      final isZero = bars[i].totalListenedMs <= 0;
      final isActive = i == activeIndex;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = isZero
            ? (isActive ? AppColors.textMuted : AppColors.border)
            : (isActive
                  ? AppColors.accent
                  : AppColors.accentSoft.withValues(alpha: 0.72));

      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant StatsBarChartPainter oldDelegate) {
    return oldDelegate.bars != bars ||
        oldDelegate.activeIndex != activeIndex ||
        oldDelegate.textDirection != textDirection;
  }
}

/// Interactive daily or monthly listening bar chart with hover tooltips and
/// keyboard focus traversal.
class StatsBarChart extends StatefulWidget {
  /// Snapshot containing ordered bar buckets and active range.
  final StatsSnapshot snapshot;

  /// Whether to suppress visual hover transitions.
  final bool reduceMotion;

  /// Creates a [StatsBarChart].
  const StatsBarChart({
    super.key,
    required this.snapshot,
    this.reduceMotion = false,
  });

  @override
  State<StatsBarChart> createState() => _StatsBarChartState();
}

class _StatsBarChartState extends State<StatsBarChart> {
  int? _activeIndex;

  @override
  void didUpdateWidget(covariant StatsBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.bars != widget.snapshot.bars) {
      _activeIndex = null;
    }
  }

  String _tooltipFor(BuildContext context, StatsBarBucket bucket) {
    final label = StatsFormatters.formatBarLabel(context, bucket);
    final duration = StatsFormatters.formatHoursMinutes(
      context,
      bucket.totalListenedMs,
    );
    final plays = context.formatCountLocalized(bucket.playCount);
    return context.localizeDigitsText(
      context.t(
        'stats.chart.barTooltip',
        args: {'label': label, 'duration': duration, 'plays': plays},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bars = widget.snapshot.bars;
    final granularity = StatsDateRange.barGranularityFor(widget.snapshot.range);
    final title = granularity == StatsBucketGranularity.month
        ? context.t('stats.chart.monthlyTitle')
        : context.t('stats.chart.dailyTitle');
    final activeBucket =
        (_activeIndex != null && _activeIndex! >= 0 && _activeIndex! < bars.length)
        ? bars[_activeIndex!]
        : null;

    return Container(
      key: const Key('stats_bar_chart_card'),
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
              Text(
                title,
                style: AppTypography.title.copyWith(color: AppColors.text),
              ),
              if (activeBucket != null)
                Text(
                  _tooltipFor(context, activeBucket),
                  key: const Key('stats_bar_active_readout'),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          SizedBox(
            height: 152,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  key: const Key('stats_bar_custom_paint'),
                  painter: StatsBarChartPainter(
                    bars: bars,
                    activeIndex: _activeIndex,
                    textDirection: Directionality.of(context),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < bars.length; i++)
                      Expanded(
                        child: Tooltip(
                          message: _tooltipFor(context, bars[i]),
                          waitDuration: widget.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          child: Semantics(
                            label: _tooltipFor(context, bars[i]),
                            focusable: true,
                            child: Focus(
                              onFocusChange: (hasFocus) {
                                if (!mounted) return;
                                setState(() {
                                  if (hasFocus) {
                                    _activeIndex = i;
                                  } else if (_activeIndex == i) {
                                    _activeIndex = null;
                                  }
                                });
                              },
                              child: MouseRegion(
                                cursor: SystemMouseCursors.basic,
                                onEnter: (_) {
                                  if (_activeIndex != i) {
                                    setState(() => _activeIndex = i);
                                  }
                                },
                                onExit: (_) {
                                  if (_activeIndex == i) {
                                    setState(() => _activeIndex = null);
                                  }
                                },
                                child: Container(
                                  decoration: _activeIndex == i
                                      ? BoxDecoration(
                                          border: Border.all(
                                            color: AppColors.borderSubtle,
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (bars.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                for (var i = 0; i < bars.length; i++)
                  Expanded(
                    child: Center(
                      child: _shouldShowAxisLabel(i, bars.length)
                          ? Text(
                              StatsFormatters.formatBarLabel(
                                context,
                                bars[i],
                                compactAxis:
                                    granularity == StatsBucketGranularity.day,
                              ),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              style: AppTypography.caption.copyWith(
                                fontSize: 11,
                                color: _activeIndex == i
                                    ? AppColors.text
                                    : AppColors.textMuted,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _shouldShowAxisLabel(int index, int count) {
    if (count <= 12) return true;
    final step = count > 24 ? 5 : 4;
    return index == 0 || index == count - 1 || index % step == 0;
  }
}
