import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;

import '../../../audio/audio_engine.dart';
import '../../../audio/audio_models.dart';
import '../../../audio/playback_controller.dart';
import '../../../audio/playback_queue.dart';
import '../../glass/glass_button.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Center transport controls and isolated seekbar for [BottomNowPlayingBar].
class BottomBarTransportArea extends StatelessWidget {
  /// Active playback controller.
  final PlaybackController controller;

  /// Creates a [BottomBarTransportArea].
  const BottomBarTransportArea({super.key, required this.controller});

  Widget _buildRepeatButton(BuildContext context, RepeatMode mode) {
    final (variant, tooltip) = switch (mode) {
      RepeatMode.off => (
          GlassButtonVariant.normal,
          context.t('player.repeatOff'),
        ),
      RepeatMode.all => (
          GlassButtonVariant.selected,
          context.t('player.repeatAll'),
        ),
      RepeatMode.one => (
          GlassButtonVariant.selected,
          context.t('player.repeatOne'),
        ),
    };

    if (mode == RepeatMode.one) {
      return Stack(
        alignment: Alignment.center,
        children: [
          GlassIconButton(
            key: const Key('bottom_bar_repeat_button'),
            icon: Icons.repeat_one,
            tooltip: tooltip,
            semanticLabel: tooltip,
            size: GlassButtonSize.small,
            variant: variant,
            onPressed: () => unawaited(controller.cycleRepeatMode()),
          ),
          PositionedDirectional(
            end: 2,
            top: 2,
            child: IgnorePointer(
              child: Container(
                key: const Key('bottom_bar_repeat_one_badge'),
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '1',
                  style: TextStyle(
                    color: AppColors.base,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return GlassIconButton(
      key: const Key('bottom_bar_repeat_button'),
      icon: Icons.repeat,
      tooltip: tooltip,
      semanticLabel: tooltip,
      size: GlassButtonSize.small,
      variant: variant,
      onPressed: () => unawaited(controller.cycleRepeatMode()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: controller.queueChangeStream,
      builder: (context, _) {
        final isShuffled = controller.queue.isShuffled;
        final repeatMode = controller.queue.repeatMode;

        return StreamBuilder<PlaybackState>(
          stream: controller.stateStream,
          initialData: controller.currentState,
          builder: (context, snapshot) {
            final state = snapshot.data ?? PlaybackState.idle;
            final isPlaying = state == PlaybackState.playing;
            final hasTrack = controller.queue.current != null;

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Transport buttons row: [shuffle] [prev] [play/pause] [next] [repeat]
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlassIconButton(
                        key: const Key('bottom_bar_shuffle_button'),
                        icon: Icons.shuffle,
                        tooltip: context.t('player.shuffle'),
                        semanticLabel: context.t('player.shuffle'),
                        size: GlassButtonSize.small,
                        variant: isShuffled
                            ? GlassButtonVariant.selected
                            : GlassButtonVariant.normal,
                        onPressed: () =>
                            unawaited(controller.setShuffle(!isShuffled)),
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        key: const Key('bottom_bar_prev_button'),
                        icon: Icons.skip_previous,
                        tooltip: context.t('common.previous'),
                        semanticLabel: context.t('common.previous'),
                        size: GlassButtonSize.small,
                        onPressed:
                            hasTrack ? () => controller.skipPrevious() : null,
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        key: const Key('bottom_bar_play_pause_button'),
                        icon: isPlaying ? Icons.pause : Icons.play_arrow,
                        tooltip: isPlaying
                            ? context.t('common.pause')
                            : context.t('common.play'),
                        semanticLabel: isPlaying
                            ? context.t('common.pause')
                            : context.t('common.play'),
                        size: GlassButtonSize.medium,
                        variant: GlassButtonVariant.primary,
                        onPressed:
                            hasTrack ? () => controller.togglePlayPause() : null,
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        key: const Key('bottom_bar_next_button'),
                        icon: Icons.skip_next,
                        tooltip: context.t('common.next'),
                        semanticLabel: context.t('common.next'),
                        size: GlassButtonSize.small,
                        onPressed:
                            hasTrack ? () => controller.skipNext() : null,
                      ),
                      const SizedBox(width: 8),
                      _buildRepeatButton(context, repeatMode),
                    ],
                  ),
                ),
                const SizedBox(height: 2),

                // Isolated Seek Bar Leaf (rebuilds on its own)
                BottomBarSeekBarLeaf(
                  engine: controller.engine,
                  hasTrack: hasTrack,
                  controller: controller,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Leaf seek bar widget that rebuilds independently on position updates.
class BottomBarSeekBarLeaf extends StatefulWidget {
  /// Underlying audio engine.
  final AudioEngine engine;

  /// Whether a track is currently loaded.
  final bool hasTrack;

  /// Optional playback controller coordinating seeks.
  final PlaybackController? controller;

  /// Creates a [BottomBarSeekBarLeaf].
  const BottomBarSeekBarLeaf({
    super.key,
    required this.engine,
    required this.hasTrack,
    this.controller,
  });

  @override
  State<BottomBarSeekBarLeaf> createState() => _BottomBarSeekBarLeafState();
}

class _BottomBarSeekBarLeafState extends State<BottomBarSeekBarLeaf> {
  StreamSubscription<Duration>? _seekSub;

  @override
  void initState() {
    super.initState();
    _seekSub = widget.controller?.seekStream.listen((_) {
      if (mounted && widget.controller?.currentState == PlaybackState.idle) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant BottomBarSeekBarLeaf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _seekSub?.cancel();
      _seekSub = widget.controller?.seekStream.listen((_) {
        if (mounted && widget.controller?.currentState == PlaybackState.idle) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _seekSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasTrack) {
      return SizedBox(
        height: 18,
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  context.formatDurationLocalized(Duration.zero),
                  style:
                      AppTypography.micro.copyWith(color: AppColors.textMuted),
                ),
              ),
            ),
            const Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 0),
                  trackHeight: 3.0,
                  activeTrackColor: AppColors.fillControl,
                  inactiveTrackColor: AppColors.fillGlass,
                ),
                child: Slider(
                  value: 0.0,
                  onChanged: null,
                ),
              ),
            ),
            SizedBox(
              width: 32,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.formatDurationLocalized(Duration.zero),
                  style:
                      AppTypography.micro.copyWith(color: AppColors.textMuted),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final controller = widget.controller;
    final engine = widget.engine;

    return StreamBuilder<Duration>(
      stream: engine.durationStream,
      initialData: controller?.currentDuration ?? engine.currentDuration,
      builder: (context, durSnapshot) {
        final totalDuration = (controller != null &&
                controller.currentState == PlaybackState.idle)
            ? controller.currentDuration
            : (durSnapshot.data != null && durSnapshot.data! > Duration.zero
                ? durSnapshot.data!
                : (controller?.currentDuration ?? Duration.zero));

        return StreamBuilder<Duration>(
          stream: engine.positionStream,
          initialData: controller?.currentPosition ?? engine.currentPosition,
          builder: (context, posSnapshot) {
            final position = (controller != null &&
                    controller.currentState == PlaybackState.idle)
                ? controller.currentPosition
                : (posSnapshot.data ??
                    controller?.currentPosition ??
                    Duration.zero);
            final maxMs = totalDuration.inMilliseconds.toDouble();
            final currentMs = position.inMilliseconds
                .toDouble()
                .clamp(0.0, maxMs > 0 ? maxMs : 1.0);

            return SizedBox(
              height: 18,
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        context.formatDurationLocalized(position),
                        textAlign: TextAlign.end,
                        style: AppTypography.micro
                            .copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 4.0,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 8.0,
                        ),
                        trackHeight: 3.0,
                        activeTrackColor: AppColors.accent,
                        inactiveTrackColor: AppColors.border,
                        thumbColor: AppColors.accent,
                        mouseCursor:
                            WidgetStateProperty.resolveWith<MouseCursor>(
                          (states) => states.contains(WidgetState.disabled)
                              ? SystemMouseCursors.basic
                              : SystemMouseCursors.click,
                        ),
                      ),
                      child: Slider(
                        value: maxMs > 0 ? currentMs : 0.0,
                        max: maxMs > 0 ? maxMs : 1.0,
                        onChanged: (val) {
                          final target = Duration(milliseconds: val.toInt());
                          if (controller != null) {
                            controller.seek(target);
                          } else {
                            engine.seek(target);
                          }
                          if (controller?.currentState == PlaybackState.idle) {
                            setState(() {});
                          }
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        context.formatDurationLocalized(totalDuration),
                        textAlign: TextAlign.start,
                        style: AppTypography.micro
                            .copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
