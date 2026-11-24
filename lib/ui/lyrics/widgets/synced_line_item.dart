import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../features/lyrics/lyrics_models.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../lyrics_view_helpers.dart';
import 'word_highlighted_line_text.dart';

/// Interactive synced lyrics line with active/distance opacity and scale animation.
class SyncedLineItem extends StatefulWidget {
  /// Line index in the lyrics document.
  final int index;

  /// Synced line model.
  final LyricsLine line;

  /// Listenable emitting the currently active line index.
  final ValueListenable<int> activeLineListenable;

  /// Listenable emitting the currently active word index.
  final ValueListenable<int> activeWordListenable;

  /// Listenable emitting normalized progress inside the active word.
  final ValueListenable<double> wordProgressListenable;

  /// Highlight mode (`'word'` or `'line'`).
  final String highlightMode;

  /// Whether the document includes word timings.
  final bool hasWordTiming;

  /// Character ranges mapped onto [line.text], if available.
  final List<WordCharRange>? mappedRanges;

  /// Whether animations should be reduced to zero duration.
  final bool reduceMotion;

  /// Whether rendered inside full screen mode.
  final bool isFullScreen;

  /// Layout density mode.
  final LyricsViewDensity density;

  /// Whether mini density uses the wide horizontal layout.
  final bool isWideMini;

  /// Whether active words may use gradient sweep.
  final bool canSweep;

  /// Optional test hook invoked when building this line item.
  final void Function(int index)? onBuildProbe;

  /// Callback when the user taps the line to seek.
  final VoidCallback onTap;

  /// Resolves physical alignment for a line's [TextDirection].
  final Alignment Function(TextDirection direction) resolveDirectionAlignment;

  /// Creates a [SyncedLineItem].
  const SyncedLineItem({
    super.key,
    required this.index,
    required this.line,
    required this.activeLineListenable,
    required this.activeWordListenable,
    required this.wordProgressListenable,
    required this.highlightMode,
    required this.hasWordTiming,
    required this.mappedRanges,
    required this.reduceMotion,
    required this.isFullScreen,
    required this.density,
    required this.resolveDirectionAlignment,
    this.isWideMini = false,
    this.canSweep = true,
    this.onBuildProbe,
    required this.onTap,
  });

  @override
  State<SyncedLineItem> createState() => _SyncedLineItemState();
}

class _SyncedLineItemState extends State<SyncedLineItem> {
  bool _isHovered = false;
  late bool _cachedIsCurrent;
  late double _cachedOpacity;
  late double _cachedScale;
  late bool _cachedIsWordHighlightActive;

  @override
  void initState() {
    super.initState();
    _syncCachedBucket(widget.activeLineListenable.value);
    widget.activeLineListenable.addListener(_onActiveLineChanged);
  }

  @override
  void didUpdateWidget(SyncedLineItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeLineListenable != widget.activeLineListenable) {
      oldWidget.activeLineListenable.removeListener(_onActiveLineChanged);
      widget.activeLineListenable.addListener(_onActiveLineChanged);
    }
    _syncCachedBucket(widget.activeLineListenable.value);
  }

  @override
  void dispose() {
    widget.activeLineListenable.removeListener(_onActiveLineChanged);
    super.dispose();
  }

  void _syncCachedBucket(int activeIndex) {
    _cachedIsCurrent = widget.index == activeIndex;
    _cachedOpacity = computeLineOpacity(
      index: widget.index,
      activeIndex: activeIndex,
      isHovered: _isHovered,
    );
    _cachedScale =
        widget.reduceMotion ? 1.0 : (_cachedIsCurrent ? 1.0 : 0.92);
    _cachedIsWordHighlightActive = _cachedIsCurrent &&
        widget.highlightMode == 'word' &&
        widget.hasWordTiming &&
        widget.mappedRanges != null;
  }

  void _onActiveLineChanged() {
    if (!mounted) return;
    final activeIndex = widget.activeLineListenable.value;
    final nextIsCurrent = widget.index == activeIndex;
    final nextOpacity = computeLineOpacity(
      index: widget.index,
      activeIndex: activeIndex,
      isHovered: _isHovered,
    );
    final nextScale = widget.reduceMotion ? 1.0 : (nextIsCurrent ? 1.0 : 0.92);
    final nextWordActive = nextIsCurrent &&
        widget.highlightMode == 'word' &&
        widget.hasWordTiming &&
        widget.mappedRanges != null;

    if (nextIsCurrent == _cachedIsCurrent &&
        nextOpacity == _cachedOpacity &&
        nextScale == _cachedScale &&
        nextWordActive == _cachedIsWordHighlightActive) {
      return;
    }

    setState(() {
      _cachedIsCurrent = nextIsCurrent;
      _cachedOpacity = nextOpacity;
      _cachedScale = nextScale;
      _cachedIsWordHighlightActive = nextWordActive;
    });
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuildProbe?.call(widget.index);

    final lineDirection = textDirectionFor(widget.line.text);
    final startAlign = widget.resolveDirectionAlignment(lineDirection);
    final endAlign = widget.resolveDirectionAlignment(
      lineDirection == TextDirection.rtl
          ? TextDirection.ltr
          : TextDirection.rtl,
    );

    final double constantFontSize = switch (widget.density) {
      LyricsViewDensity.mini => widget.isWideMini ? 18.0 : 20.0,
      LyricsViewDensity.sidePanel => 20.0,
      LyricsViewDensity.fullScreen => 42.0,
      LyricsViewDensity.page => 32.0,
    };
    final baseStyle = AppTypography.title.copyWith(
      fontSize: constantFontSize,
      fontWeight: FontWeight.w700,
      color: AppColors.text,
      height: 1.3,
    );

    final Duration animDuration = widget.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 400);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() {
          _isHovered = true;
          _syncCachedBucket(widget.activeLineListenable.value);
        });
      },
      onExit: (_) {
        setState(() {
          _isHovered = false;
          _syncCachedBucket(widget.activeLineListenable.value);
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedOpacity(
          opacity: _cachedOpacity,
          duration: animDuration,
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: _cachedScale,
            alignment: startAlign,
            duration: animDuration,
            curve: Curves.easeOutCubic,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: (widget.density == LyricsViewDensity.mini ||
                        widget.density == LyricsViewDensity.sidePanel)
                    ? 8
                    : 16,
                vertical: widget.density == LyricsViewDensity.mini
                    ? 5
                    : (widget.density == LyricsViewDensity.sidePanel ? 6 : 8),
              ),
              child: Align(
                alignment: startAlign,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: widget.density == LyricsViewDensity.fullScreen
                        ? 760.0
                        : double.infinity,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: _cachedIsWordHighlightActive
                        ? WordHighlightedLineText(
                            lineText: widget.line.text,
                            ranges: widget.mappedRanges!,
                            lineDirection: lineDirection,
                            baseStyle: baseStyle,
                            reduceMotion: widget.reduceMotion,
                            activeWordListenable: widget.activeWordListenable,
                            wordProgressListenable:
                                widget.wordProgressListenable,
                            sweepBegin: startAlign,
                            sweepEnd: endAlign,
                            canSweep: widget.canSweep,
                          )
                        : Text(
                            widget.line.text,
                            textAlign: TextAlign.start,
                            textDirection: lineDirection,
                            style: baseStyle,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
