import '../../diagnostics/app_logger.dart';
import '../audio_engine.dart';
import '../audio_models.dart';
import '../playback_queue.dart';

/// Internal gapless preload collaborator for [PlaybackController].
class PlaybackGaplessPreloader {
  final AudioEngine engine;
  final PlaybackQueue queue;
  final bool Function() isDisposed;
  final void Function(AudioError error) emitError;

  const PlaybackGaplessPreloader({
    required this.engine,
    required this.queue,
    required this.isDisposed,
    required this.emitError,
  });

  /// Asks the engine to prepare the next track. Never throws: a failure is
  /// reported as a non-fatal error and playback continues.
  Future<void> preloadNext() async {
    if (isDisposed() || !engine.capabilities.gapless) return;
    try {
      await engine.preloadNext(queue.peekNext());
    } catch (e, st) {
      AppLogger.instance.warn(
        'PlaybackController',
        'Preloading the next track failed',
        e,
        st,
      );
      if (isDisposed()) return;
      emitError(AudioError(
        code: AudioErrorCode.engineFailure,
        message: 'Preloading the next track failed: $e',
        isFatal: false,
      ));
    }
  }
}
