import 'package:flutter/material.dart' hide RepeatMode;

import '../../../audio/audio_engine.dart';
import '../../../audio/audio_models.dart';
import '../../../audio/playback_controller.dart';
import '../../../audio/playback_queue.dart';
import '../../glass/glass_button.dart';
import '../../l10n/app_strings.dart';
import '../../settings/settings_scope.dart';
import '../../shell/volume_hud.dart';
import '../../shell/volume_wheel_region.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Transport controls row (shuffle, previous, play/pause, next, repeat).
class NowPlayingTransportRow extends StatelessWidget {
  /// Playback controller.
  final PlaybackController controller;

  /// Called when shuffle button is pressed.
  final VoidCallback onToggleShuffle;

  /// Called when repeat button is pressed.
  final VoidCallback onCycleRepeat;

  /// Creates a [NowPlayingTransportRow].
  const NowPlayingTransportRow({
    super.key,
    required this.controller,
    required this.onToggleShuffle,
    required this.onCycleRepeat,
  });

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
            key: const Key('now_playing_repeat_button'),
            icon: Icons.repeat_one,
            tooltip: tooltip,
            semanticLabel: tooltip,
            variant: variant,
            onPressed: onCycleRepeat,
          ),
          PositionedDirectional(
            end: 4,
            top: 4,
            child: IgnorePointer(
              child: Container(
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
      key: const Key('now_playing_repeat_button'),
      icon: Icons.repeat,
      tooltip: tooltip,
      semanticLabel: tooltip,
      variant: variant,
      onPressed: onCycleRepeat,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isShuffled = controller.queue.isShuffled;
    final repeatMode = controller.queue.repeatMode;

    return StreamBuilder<PlaybackState>(
      stream: controller.stateStream,
      initialData: controller.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? PlaybackState.idle;
        final isPlaying = state == PlaybackState.playing;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Shuffle
            GlassIconButton(
              key: const Key('now_playing_shuffle_button'),
              icon: Icons.shuffle,
              tooltip: context.t('player.shuffle'),
              semanticLabel: context.t('player.shuffle'),
              variant: isShuffled
                  ? GlassButtonVariant.selected
                  : GlassButtonVariant.normal,
              onPressed: onToggleShuffle,
            ),
            const SizedBox(width: 12),

            // Previous
            GlassIconButton(
              key: const Key('now_playing_prev_button'),
              icon: Icons.skip_previous,
              tooltip: context.t('common.previous'),
              semanticLabel: context.t('common.previous'),
              onPressed: () => controller.skipPrevious(),
            ),
            const SizedBox(width: 16),

            // Play / Pause (Large 60dp)
            SizedBox(
              width: 60,
              height: 60,
              child: GlassIconButton(
                key: const Key('now_playing_play_pause_button'),
                icon: isPlaying ? Icons.pause : Icons.play_arrow,
                tooltip: isPlaying
                    ? context.t('common.pause')
                    : context.t('common.play'),
                semanticLabel: isPlaying
                    ? context.t('common.pause')
                    : context.t('common.play'),
                variant: GlassButtonVariant.primary,
                size: GlassButtonSize.large,
                onPressed: () => controller.togglePlayPause(),
              ),
            ),
            const SizedBox(width: 16),

            // Next
            GlassIconButton(
              key: const Key('now_playing_next_button'),
              icon: Icons.skip_next,
              tooltip: context.t('common.next'),
              semanticLabel: context.t('common.next'),
              onPressed: () => controller.skipNext(),
            ),
            const SizedBox(width: 12),

            // Repeat (off -> all -> one -> off)
            _buildRepeatButton(context, repeatMode),
          ],
        );
      },
    );
  }
}

/// Isolated audio stream info pill leaf widget.
class NowPlayingStreamInfoPill extends StatelessWidget {
  /// Underlying audio engine.
  final AudioEngine engine;

  /// Creates a [NowPlayingStreamInfoPill].
  const NowPlayingStreamInfoPill({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AudioStreamInfo?>(
      stream: engine.streamInfoStream,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null ||
            ((info.codec == null || info.codec!.isEmpty) &&
                (info.sampleRate == null || info.sampleRate! <= 0) &&
                (info.bitDepth == null || info.bitDepth! <= 0) &&
                (info.channels == null || info.channels! <= 0) &&
                (info.bitrateKbps == null || info.bitrateKbps! <= 0))) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.fillControl,
              borderRadius: BorderRadius.circular(AppSpacing.r12),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Text(
              context.t('nowPlaying.standardAudio'),
              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            ),
          );
        }

        final parts = <String>[];
        if (info.codec != null && info.codec!.isNotEmpty) {
          parts.add(info.codec!.toUpperCase());
        }
        if (info.sampleRate != null && info.sampleRate! > 0) {
          final khz = (info.sampleRate! / 1000.0)
              .toStringAsFixed(1)
              .replaceAll('.0', '');
          parts.add('$khz kHz');
        }
        if (info.bitDepth != null && info.bitDepth! > 0) {
          parts.add('${info.bitDepth}-bit');
        }
        if (info.channels != null && info.channels! > 0) {
          parts.add(info.channels == 2
              ? 'Stereo'
              : (info.channels == 1 ? 'Mono' : '${info.channels} ch'));
        }
        if (info.bitrateKbps != null && info.bitrateKbps! > 0) {
          parts.add('${info.bitrateKbps!.round()} kbps');
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.fillControl,
            borderRadius: BorderRadius.circular(AppSpacing.r12),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (info.isLossless == true) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accentFill,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    context.t('nowPlaying.lossless'),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
              Text(
                parts.isEmpty
                    ? context.t('nowPlaying.standardAudio')
                    : parts.join(' · '),
                style: AppTypography.caption.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Compact volume slider control with mouse wheel support.
class NowPlayingVolumeControl extends StatelessWidget {
  /// Underlying audio engine.
  final AudioEngine engine;

  /// Creates a [NowPlayingVolumeControl].
  const NowPlayingVolumeControl({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    final settingsStore = SettingsScope.maybeOf(context);
    final hudCtrl = VolumeHudScope.maybeOf(context);

    return VolumeWheelRegion(
      engine: engine,
      settingsStore: settingsStore,
      hudController: hudCtrl,
      behavior: HitTestBehavior.opaque,
      child: StreamBuilder<double>(
        stream: engine.volumeStream,
        initialData: engine.currentVolume,
        builder: (context, snapshot) {
          final vol = (snapshot.data ?? 1.0).clamp(0.0, 1.0);
          return SizedBox(
            width: 140,
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.volume_down,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                Expanded(
                  child: SliderTheme(
                    data: const SliderThemeData(
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 4.0),
                      overlayShape: RoundSliderOverlayShape(overlayRadius: 8.0),
                      trackHeight: 2.5,
                      activeTrackColor: AppColors.accent,
                      inactiveTrackColor: AppColors.border,
                      thumbColor: AppColors.accent,
                    ),
                    child: Slider(
                      value: vol,
                      onChanged: (newVol) {
                        setVolumeDirect(
                          engine: engine,
                          volume: newVol,
                          settingsStore: settingsStore,
                          hudController: hudCtrl,
                        );
                      },
                    ),
                  ),
                ),
                const Icon(
                  Icons.volume_up,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
