import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../lyrics_view_helpers.dart';

/// Renders an active lyrics line with per-word highlight sweep or fade.
class WordHighlightedLineText extends StatefulWidget {
  /// Full line text.
  final String lineText;

  /// Word character ranges mapped into [lineText].
  final List<WordCharRange> ranges;

  /// Resolved reading direction for [lineText].
  final TextDirection lineDirection;

  /// Base text style for the line.
  final TextStyle baseStyle;

  /// Whether animations should be reduced to zero duration.
  final bool reduceMotion;

  /// Listenable emitting the currently active word index.
  final ValueListenable<int> activeWordListenable;

  /// Listenable emitting normalized progress (0..1) inside the active word.
  final ValueListenable<double> wordProgressListenable;

  /// Whether gradient sweep is allowed across the active word.
  final bool canSweep;

  /// Gradient start alignment for the line's direction.
  final Alignment sweepBegin;

  /// Gradient end alignment for the line's direction.
  final Alignment sweepEnd;

  /// Creates a [WordHighlightedLineText].
  const WordHighlightedLineText({
    super.key,
    required this.lineText,
    required this.ranges,
    required this.lineDirection,
    required this.baseStyle,
    required this.reduceMotion,
    required this.activeWordListenable,
    required this.wordProgressListenable,
    required this.sweepBegin,
    required this.sweepEnd,
    this.canSweep = true,
  });

  @override
  State<WordHighlightedLineText> createState() =>
      _WordHighlightedLineTextState();
}

class _WordHighlightedLineTextState extends State<WordHighlightedLineText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  int _lastActiveWordIdx = -1;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: widget.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      value: 1.0,
    );
    _lastActiveWordIdx = widget.activeWordListenable.value;
    widget.activeWordListenable.addListener(_onActiveWordChanged);
  }

  @override
  void didUpdateWidget(WordHighlightedLineText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeWordListenable != widget.activeWordListenable) {
      oldWidget.activeWordListenable.removeListener(_onActiveWordChanged);
      widget.activeWordListenable.addListener(_onActiveWordChanged);
    }
    if (oldWidget.reduceMotion != widget.reduceMotion) {
      _fadeController.duration = widget.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200);
    }
  }

  void _onActiveWordChanged() {
    final current = widget.activeWordListenable.value;
    if (current != _lastActiveWordIdx) {
      _lastActiveWordIdx = current;
      if (!widget.canSweep && !widget.reduceMotion) {
        _fadeController.forward(from: 0.0);
      } else {
        _fadeController.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    widget.activeWordListenable.removeListener(_onActiveWordChanged);
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dimColor = AppColors.textMuted.withValues(alpha: 0.45);
    final geometryOnlyStyle = TextStyle(
      fontFamily: widget.baseStyle.fontFamily,
      fontFamilyFallback: widget.baseStyle.fontFamilyFallback,
      fontSize: widget.baseStyle.fontSize,
      fontWeight: widget.baseStyle.fontWeight,
      height: widget.baseStyle.height,
      letterSpacing: widget.baseStyle.letterSpacing,
    );
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return ListenableBuilder(
          listenable: Listenable.merge(
            [
              widget.activeWordListenable,
              widget.wordProgressListenable,
              _fadeController,
            ],
          ),
          builder: (context, _) {
            final activeWordIdx = widget.activeWordListenable.value;
            final progress = widget.wordProgressListenable.value.clamp(0.0, 1.0);

            Rect? activeWordRect;
            if (!widget.reduceMotion &&
                widget.canSweep &&
                activeWordIdx >= 0 &&
                activeWordIdx < widget.ranges.length &&
                progress > 0.0 &&
                progress < 1.0) {
              final r = widget.ranges[activeWordIdx];
              final tp = TextPainter(
                text: TextSpan(text: widget.lineText, style: geometryOnlyStyle),
                textAlign: TextAlign.start,
                textDirection: widget.lineDirection,
                textScaler: textScaler,
              )..layout(maxWidth: constraints.maxWidth);
              final boxes = tp.getBoxesForSelection(
                TextSelection(baseOffset: r.start, extentOffset: r.end),
              );
              tp.dispose();
              if (boxes.isNotEmpty) {
                var union = boxes.first.toRect();
                for (var b = 1; b < boxes.length; b++) {
                  union = union.expandToInclude(boxes[b].toRect());
                }
                if (union.width > 0 && union.height > 0) {
                  activeWordRect = union;
                }
              }
            }

            final spans = <InlineSpan>[];
            var cursor = 0;

            for (var i = 0; i < widget.ranges.length; i++) {
              final r = widget.ranges[i];
              if (r.start > cursor) {
                final gapColor = (activeWordIdx >= 0 && i <= activeWordIdx)
                    ? AppColors.text
                    : dimColor;
                spans.add(
                  TextSpan(
                    text: widget.lineText.substring(cursor, r.start),
                    style: TextStyle(color: gapColor),
                  ),
                );
              }

              final wordSlice = widget.lineText.substring(r.start, r.end);
              final TextStyle wordStyle;
              if (activeWordIdx < 0) {
                wordStyle = TextStyle(color: dimColor);
              } else if (i < activeWordIdx) {
                wordStyle = const TextStyle(color: AppColors.text);
              } else if (i == activeWordIdx) {
                if (widget.reduceMotion || progress >= 1.0) {
                  wordStyle = const TextStyle(color: AppColors.text);
                } else if (!widget.canSweep) {
                  final t = _fadeController.value;
                  wordStyle = TextStyle(
                    color: Color.lerp(dimColor, AppColors.text, t),
                  );
                } else if (progress <= 0.0 || activeWordRect == null) {
                  wordStyle = TextStyle(
                    color: progress >= 0.5 ? AppColors.text : dimColor,
                  );
                } else {
                  final featherPx = 0.6 * activeWordRect.height;
                  final featherFrac = activeWordRect.width > 0
                      ? (featherPx / activeWordRect.width)
                      : 0.05;
                  final halfFeather = featherFrac / 2.0;
                  final stop1 = (progress - halfFeather).clamp(0.0, 1.0);
                  final stop2 = math.max(
                    stop1 + 0.001,
                    (progress + halfFeather).clamp(0.0, 1.0),
                  );
                  final finalStop2 = stop2.clamp(0.0, 1.0);
                  final finalStop1 =
                      math.min(stop1, finalStop2 - 0.001).clamp(0.0, 1.0);

                  final shader = LinearGradient(
                    begin: widget.sweepBegin,
                    end: widget.sweepEnd,
                    colors: [
                      AppColors.text,
                      AppColors.text,
                      dimColor,
                      dimColor,
                    ],
                    stops: [0.0, finalStop1, finalStop2, 1.0],
                  ).createShader(activeWordRect);
                  wordStyle = TextStyle(foreground: Paint()..shader = shader);
                }
              } else {
                wordStyle = TextStyle(color: dimColor);
              }

              spans.add(TextSpan(text: wordSlice, style: wordStyle));
              cursor = r.end;
            }

            if (cursor < widget.lineText.length) {
              final tailColor = (activeWordIdx >= widget.ranges.length)
                  ? AppColors.text
                  : dimColor;
              spans.add(
                TextSpan(
                  text: widget.lineText.substring(cursor),
                  style: TextStyle(color: tailColor),
                ),
              );
            }

            return DefaultTextStyle(
              style: geometryOnlyStyle,
              child: Text.rich(
                TextSpan(children: spans),
                textAlign: TextAlign.start,
                textDirection: widget.lineDirection,
              ),
            );
          },
        );
      },
    );
  }
}
