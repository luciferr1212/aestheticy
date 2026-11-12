import '../../audio/audio_engine.dart';
import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';

/// Resolves the effective track duration for seek bars, handling idle resume state.
Duration resolveSeekBarDuration({
  required AudioEngine engine,
  required PlaybackController? controller,
  Duration? streamDuration,
}) {
  if (controller != null && controller.currentState == PlaybackState.idle) {
    return controller.currentDuration;
  }
  if (streamDuration != null && streamDuration > Duration.zero) {
    return streamDuration;
  }
  return controller?.currentDuration ?? Duration.zero;
}

/// Resolves the effective playback position for seek bars, handling idle resume state.
Duration resolveSeekBarPosition({
  required AudioEngine engine,
  required PlaybackController? controller,
  Duration? streamPosition,
}) {
  if (controller != null && controller.currentState == PlaybackState.idle) {
    return controller.currentPosition;
  }
  return streamPosition ?? controller?.currentPosition ?? Duration.zero;
}

/// Clamps [target] to [Duration.zero] .. [totalDuration] (when positive).
Duration clampSeekTarget(Duration target, Duration totalDuration) {
  if (target < Duration.zero) {
    return Duration.zero;
  }
  if (totalDuration > Duration.zero && target > totalDuration) {
    return totalDuration;
  }
  return target;
}

/// Maps a local horizontal offset [dx] in a bar of [width] to a `0..1` progress fraction.
double seekBarFractionForDx({
  required double dx,
  required double width,
  required bool isRtl,
}) {
  if (width <= 0) return 0.0;
  final raw = (dx / width).clamp(0.0, 1.0);
  return isRtl ? (1.0 - raw) : raw;
}

/// Converts a normalized `0..1` [fraction] to a clamped [Duration] within [totalDuration].
Duration seekBarDurationForFraction({
  required double fraction,
  required Duration totalDuration,
}) {
  if (totalDuration <= Duration.zero) return Duration.zero;
  final ms =
      (fraction.clamp(0.0, 1.0) * totalDuration.inMilliseconds).round();
  return clampSeekTarget(Duration(milliseconds: ms), totalDuration);
}

/// Dispatches a clamped seek to [controller] (updating armed resume when idle) or [engine].
Future<void> dispatchSeekBarSeek({
  required AudioEngine engine,
  required PlaybackController? controller,
  required Duration target,
  required Duration totalDuration,
}) {
  final clamped = clampSeekTarget(target, totalDuration);
  if (controller != null) {
    return controller.seek(clamped);
  }
  return engine.seek(clamped);
}
