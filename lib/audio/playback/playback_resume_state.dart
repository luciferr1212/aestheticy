import 'dart:async';

import '../audio_models.dart';
import '../playback_queue.dart';

/// Internal session snapshot restore and lazy-resume state collaborator for
/// [PlaybackController].
class PlaybackResumeState {
  Duration? _armedResumePosition;
  String? _armedResumeUri;

  Duration? get armedResumePosition => _armedResumePosition;
  String? get armedResumeUri => _armedResumeUri;

  void armResume(Duration position, {String? currentUri}) {
    _armedResumePosition = position;
    _armedResumeUri = currentUri;
  }

  void clearArmedResume() {
    _armedResumePosition = null;
    _armedResumeUri = null;
  }

  void clearIfDifferentUri(String uri) {
    if (_armedResumeUri != null && uri != _armedResumeUri) {
      _armedResumePosition = null;
      _armedResumeUri = null;
    }
  }

  void checkArmedResume({
    Duration? dur,
    required Duration engineDuration,
    required String? openedUri,
    required String? currentQueueUri,
    required Future<void> Function(Duration position) seekEngine,
  }) {
    final effectiveDur = dur ?? engineDuration;
    if (_armedResumePosition != null &&
        effectiveDur > Duration.zero &&
        (openedUri == null ||
            openedUri == _armedResumeUri ||
            currentQueueUri == _armedResumeUri)) {
      final pos = _armedResumePosition!;
      _armedResumePosition = null;
      _armedResumeUri = null;
      unawaited(seekEngine(pos));
    }
  }

  void restoreQueueSnapshot(
    PlaybackQueue queue, {
    required List<QueueEntry> entries,
    int currentIndex = 0,
    bool shuffled = false,
    RepeatMode repeatMode = RepeatMode.off,
    required void Function() notifyQueueChanged,
  }) {
    queue.restoreSnapshot(
      entries: entries,
      currentIndex: currentIndex,
      shuffled: shuffled,
      repeatMode: repeatMode,
    );
    notifyQueueChanged();
  }
}
