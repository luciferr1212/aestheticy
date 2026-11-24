import 'dart:async';

import 'package:flutter/material.dart';

import '../../../audio/audio_engine.dart';
import '../../../audio/audio_models.dart';
import '../../../audio/playback_controller.dart';
import '../../l10n/number_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../seek_bar_helper.dart';

/// Isolated seekbar leaf listening to position and duration streams.
class NowPlayingSeekBar extends StatefulWidget {
  /// Underlying audio engine.
  final AudioEngine engine;

  /// Optional playback controller coordinating seeks.
  final PlaybackController? controller;

  /// Creates a [NowPlayingSeekBar].
  const NowPlayingSeekBar({super.key, required this.engine, this.controller});

  @override
  State<NowPlayingSeekBar> createState() => _NowPlayingSeekBarState();
}

class _NowPlayingSeekBarState extends State<NowPlayingSeekBar> {
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
  void didUpdateWidget(covariant NowPlayingSeekBar oldWidget) {
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
    final controller = widget.controller;
    final engine = widget.engine;

    return StreamBuilder<Duration>(
      stream: engine.durationStream,
      initialData: controller?.currentDuration ?? engine.currentDuration,
      builder: (context, durSnapshot) {
        final totalDuration = resolveSeekBarDuration(
          engine: engine,
          controller: controller,
          streamDuration: durSnapshot.data,
        );

        return StreamBuilder<Duration>(
          stream: engine.positionStream,
          initialData: controller?.currentPosition ?? engine.currentPosition,
          builder: (context, posSnapshot) {
            final position = resolveSeekBarPosition(
              engine: engine,
              controller: controller,
              streamPosition: posSnapshot.data,
            );
            final maxMs = totalDuration.inMilliseconds.toDouble();
            final currentMs = position.inMilliseconds
                .toDouble()
                .clamp(0.0, maxMs > 0 ? maxMs : 1.0);

            return Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox(
                height: 24,
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        context.formatDurationLocalized(position),
                        textAlign: TextAlign.end,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5.0,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 10.0,
                          ),
                          trackHeight: 3.5,
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
                            dispatchSeekBarSeek(
                              engine: engine,
                              controller: controller,
                              target: target,
                              totalDuration: totalDuration,
                            );
                            if (controller?.currentState == PlaybackState.idle) {
                              setState(() {});
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 36,
                      child: Text(
                        context.formatDurationLocalized(totalDuration),
                        textAlign: TextAlign.start,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
