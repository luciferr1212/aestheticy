import 'dart:async';

import 'package:flutter/material.dart';

import '../../../audio/audio_engine.dart';
import '../../../audio/audio_models.dart';
import '../../../audio/playback_controller.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../seek_bar_helper.dart';

/// Represents the drag scrub state for the full-screen seek bar tooltip overlay.
class FullScreenSeekDragState {
  /// The local horizontal pointer offset.
  final double pointerDx;

  /// The targeted scrub duration.
  final Duration position;

  /// Creates a [FullScreenSeekDragState].
  const FullScreenSeekDragState({
    required this.pointerDx,
    required this.position,
  });
}

/// Interactive progress line spanning the bottom edge of the full screen view.
class FullScreenSeekBar extends StatefulWidget {
  /// Underlying audio engine.
  final AudioEngine engine;

  /// Optional playback controller coordinating seeks.
  final PlaybackController? controller;

  /// Whether animations should be reduced.
  final bool reduceMotion;

  /// Called when hover/drag interaction state changes.
  final ValueChanged<bool>? onInteractionChanged;

  /// Called when drag tooltip state changes.
  final ValueChanged<FullScreenSeekDragState?>? onDragStateChanged;

  /// Resolves physical alignment for the progress fill bar.
  final Alignment Function(bool isRtl) resolveFillAlignment;

  /// Creates a [FullScreenSeekBar].
  const FullScreenSeekBar({
    super.key,
    required this.engine,
    required this.resolveFillAlignment,
    this.controller,
    this.reduceMotion = false,
    this.onInteractionChanged,
    this.onDragStateChanged,
  });

  @override
  State<FullScreenSeekBar> createState() => _FullScreenSeekBarState();
}

class _FullScreenSeekBarState extends State<FullScreenSeekBar> {
  static const Duration _kDragSeekThrottle = Duration(milliseconds: 120);
  static const Duration _kSemanticsSeekStep = Duration(seconds: 5);

  bool _isHovered = false;
  bool _isDragging = false;
  double? _dragFraction;
  Timer? _seekThrottleTimer;
  Duration? _pendingSeekTarget;
  Duration _activeTotalDuration = Duration.zero;
  StreamSubscription<Duration>? _seekSub;

  @override
  void initState() {
    super.initState();
    _subscribeSeekStream();
  }

  @override
  void didUpdateWidget(FullScreenSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _seekSub?.cancel();
      _subscribeSeekStream();
    }
  }

  void _subscribeSeekStream() {
    _seekSub = widget.controller?.seekStream.listen((_) {
      if (mounted && widget.controller?.currentState == PlaybackState.idle) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _seekThrottleTimer?.cancel();
    _seekSub?.cancel();
    super.dispose();
  }

  void _setHover(bool hovered) {
    if (_isHovered == hovered) return;
    final wasActive = _isHovered || _isDragging;
    setState(() => _isHovered = hovered);
    final isActive = _isHovered || _isDragging;
    if (wasActive != isActive) {
      widget.onInteractionChanged?.call(isActive);
    }
  }

  void _dispatchSeekImmediate(Duration target, Duration total) {
    if (total <= Duration.zero) return;
    dispatchSeekBarSeek(
      engine: widget.engine,
      controller: widget.controller,
      target: target,
      totalDuration: total,
    );
    if (widget.controller?.currentState == PlaybackState.idle && mounted) {
      setState(() {});
    }
  }

  void _scheduleThrottledSeek(Duration target, Duration total) {
    _activeTotalDuration = total;
    if (total <= Duration.zero) return;
    if (_seekThrottleTimer == null) {
      _dispatchSeekImmediate(target, total);
      _seekThrottleTimer = Timer(_kDragSeekThrottle, _onThrottleElapsed);
    } else {
      _pendingSeekTarget = target;
    }
  }

  void _onThrottleElapsed() {
    _seekThrottleTimer = null;
    if (!_isDragging) {
      _pendingSeekTarget = null;
      return;
    }
    final pending = _pendingSeekTarget;
    _pendingSeekTarget = null;
    if (pending != null && _activeTotalDuration > Duration.zero) {
      _dispatchSeekImmediate(pending, _activeTotalDuration);
      _seekThrottleTimer = Timer(_kDragSeekThrottle, _onThrottleElapsed);
    }
  }

  void _handleTapUp(
    TapUpDetails details,
    double width,
    bool isRtl,
    Duration total,
  ) {
    if (total <= Duration.zero) return;
    final frac = seekBarFractionForDx(
      dx: details.localPosition.dx,
      width: width,
      isRtl: isRtl,
    );
    final target = seekBarDurationForFraction(
      fraction: frac,
      totalDuration: total,
    );
    _dispatchSeekImmediate(target, total);
  }

  void _handleDragStart(
    DragStartDetails details,
    double width,
    bool isRtl,
    Duration total,
  ) {
    final wasActive = _isHovered || _isDragging;
    final frac = seekBarFractionForDx(
      dx: details.localPosition.dx,
      width: width,
      isRtl: isRtl,
    );
    final pointerDx = details.localPosition.dx.clamp(0.0, width);
    final target = total > Duration.zero
        ? seekBarDurationForFraction(fraction: frac, totalDuration: total)
        : Duration.zero;

    setState(() {
      _isDragging = true;
      _dragFraction = total > Duration.zero ? frac : null;
    });

    if (total > Duration.zero) {
      widget.onDragStateChanged?.call(
        FullScreenSeekDragState(pointerDx: pointerDx, position: target),
      );
      _scheduleThrottledSeek(target, total);
    }

    if (!wasActive) {
      widget.onInteractionChanged?.call(true);
    }
  }

  void _handleDragUpdate(
    DragUpdateDetails details,
    double width,
    bool isRtl,
    Duration total,
  ) {
    final frac = seekBarFractionForDx(
      dx: details.localPosition.dx,
      width: width,
      isRtl: isRtl,
    );
    final pointerDx = details.localPosition.dx.clamp(0.0, width);
    final target = total > Duration.zero
        ? seekBarDurationForFraction(fraction: frac, totalDuration: total)
        : Duration.zero;

    setState(() {
      _dragFraction = total > Duration.zero ? frac : null;
    });

    if (total > Duration.zero) {
      widget.onDragStateChanged?.call(
        FullScreenSeekDragState(pointerDx: pointerDx, position: target),
      );
      _scheduleThrottledSeek(target, total);
    }
  }

  void _finishDrag(Duration total, {required bool commitSeek}) {
    _seekThrottleTimer?.cancel();
    _seekThrottleTimer = null;
    final pending = _pendingSeekTarget;
    _pendingSeekTarget = null;
    final frac = _dragFraction;
    if (commitSeek && total > Duration.zero) {
      final target = pending ??
          (frac != null
              ? seekBarDurationForFraction(fraction: frac, totalDuration: total)
              : null);
      if (target != null) {
        _dispatchSeekImmediate(target, total);
      }
    }
    final wasActive = _isHovered || _isDragging;
    setState(() {
      _isDragging = false;
      _dragFraction = null;
    });
    widget.onDragStateChanged?.call(null);
    final isActive = _isHovered || _isDragging;
    if (wasActive != isActive) {
      widget.onInteractionChanged?.call(isActive);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return StreamBuilder<Duration>(
      stream: widget.engine.durationStream,
      initialData:
          widget.controller?.currentDuration ?? widget.engine.currentDuration,
      builder: (context, durSnapshot) {
        final total = resolveSeekBarDuration(
          engine: widget.engine,
          controller: widget.controller,
          streamDuration: durSnapshot.data,
        );

        return StreamBuilder<Duration>(
          stream: widget.engine.positionStream,
          initialData: widget.controller?.currentPosition ??
              widget.engine.currentPosition,
          builder: (context, posSnapshot) {
            final pos = resolveSeekBarPosition(
              engine: widget.engine,
              controller: widget.controller,
              streamPosition: posSnapshot.data,
            );
            final displayFraction = _dragFraction ??
                (total.inMilliseconds > 0
                    ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                    : 0.0);
            final displayPos = _dragFraction != null
                ? seekBarDurationForFraction(
                    fraction: displayFraction,
                    totalDuration: total,
                  )
                : pos;

            return Semantics(
              slider: true,
              label: context.t('fullScreen.seekBarLabel'),
              value: context.formatDurationLocalized(displayPos),
              increasedValue: total > Duration.zero
                  ? context.formatDurationLocalized(
                      clampSeekTarget(displayPos + _kSemanticsSeekStep, total),
                    )
                  : null,
              decreasedValue: total > Duration.zero
                  ? context.formatDurationLocalized(
                      clampSeekTarget(displayPos - _kSemanticsSeekStep, total),
                    )
                  : null,
              onIncrease: total > Duration.zero
                  ? () => _dispatchSeekImmediate(
                        displayPos + _kSemanticsSeekStep,
                        total,
                      )
                  : null,
              onDecrease: total > Duration.zero
                  ? () => _dispatchSeekImmediate(
                        displayPos - _kSemanticsSeekStep,
                        total,
                      )
                  : null,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;

                  return SizedBox(
                    height: 28.0,
                    width: double.infinity,
                    child: MouseRegion(
                      cursor: total > Duration.zero
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      onEnter: (_) => _setHover(true),
                      onExit: (_) => _setHover(false),
                      child: GestureDetector(
                        key: const Key('fullscreen_seek_bar'),
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) =>
                            _handleTapUp(details, width, isRtl, total),
                        onHorizontalDragStart: (details) =>
                            _handleDragStart(details, width, isRtl, total),
                        onHorizontalDragUpdate: (details) =>
                            _handleDragUpdate(details, width, isRtl, total),
                        onHorizontalDragEnd: (_) =>
                            _finishDrag(total, commitSeek: true),
                        onHorizontalDragCancel: () =>
                            _finishDrag(total, commitSeek: false),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                key: const Key('fullscreen_seek_track'),
                                height: 3.0,
                                color: Colors.white.withValues(alpha: 0.24),
                                child: FractionallySizedBox(
                                  alignment: widget.resolveFillAlignment(isRtl),
                                  widthFactor: displayFraction,
                                  child: Container(
                                    key: const Key('fullscreen_seek_fill'),
                                    height: 3.0,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
