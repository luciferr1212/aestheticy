import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'session_store.dart';

/// Summarizes the outcome of a session restore operation.
class SessionRestoreResult {
  /// Number of tracks successfully restored into the playback queue.
  final int restoredCount;

  /// Number of missing or nonexistent tracks dropped during restore.
  final int droppedCount;

  /// The active restored queue cursor index.
  final int restoredIndex;

  /// The armed seek position in milliseconds applied lazily to the active track.
  final int armedPositionMs;

  const SessionRestoreResult({
    required this.restoredCount,
    required this.droppedCount,
    required this.restoredIndex,
    required this.armedPositionMs,
  });

  /// An empty restore result indicating no session was restored.
  static const SessionRestoreResult empty = SessionRestoreResult(
    restoredCount: 0,
    droppedCount: 0,
    restoredIndex: -1,
    armedPositionMs: 0,
  );
}

/// Restores the previous playback session into [controller] without starting playback.
Future<SessionRestoreResult> restoreSession({
  required PlaybackController controller,
  required SessionStore sessionStore,
  required SettingsStore settingsStore,
  Future<bool> Function(String path)? fileExistsChecker,
}) async {
  if (!settingsStore.settings.resumeSession) {
    return SessionRestoreResult.empty;
  }

  final saved = sessionStore.session;
  if (saved.isEmpty) {
    return SessionRestoreResult.empty;
  }

  final checker = fileExistsChecker ??
      (path) async {
        try {
          // Allow custom non-filesystem URIs (e.g. assets, stream URLs)
          if (!path.startsWith('/') &&
              !path.contains(':\\') &&
              !path.contains(':/')) {
            return true;
          }
          return File(path).existsSync();
        } catch (_) {
          return false;
        }
      };

  // Batched async existence checks (process in chunks of 50 to keep UI isolate responsive)
  const batchSize = 50;
  final survivingSources = <AudioSource>[];
  var droppedCount = 0;
  int? survivingCurrentIndex;

  for (var i = 0; i < saved.queue.length; i += batchSize) {
    final batchEnd = min(i + batchSize, saved.queue.length);
    final batch = saved.queue.sublist(i, batchEnd);

    final existenceResults = await Future.wait(
      batch.map((item) => checker(item.uri)),
    );

    for (var j = 0; j < batch.length; j++) {
      final originalIndex = i + j;
      final exists = existenceResults[j];

      if (exists) {
        if (originalIndex == saved.currentIndex) {
          survivingCurrentIndex = survivingSources.length;
        } else if (originalIndex > saved.currentIndex &&
            survivingCurrentIndex == null) {
          // If the current item was dropped, start at the next surviving item with position 0
          survivingCurrentIndex = survivingSources.length;
        }
        survivingSources.add(batch[j].toAudioSource());
      } else {
        droppedCount++;
      }
    }
    await Future<void>.delayed(Duration.zero);
  }

  if (survivingSources.isEmpty) {
    return SessionRestoreResult(
      restoredCount: 0,
      droppedCount: droppedCount,
      restoredIndex: -1,
      armedPositionMs: 0,
    );
  }

  final targetIndex = survivingCurrentIndex ?? 0;
  final originalItemSurvived = survivingCurrentIndex != null &&
      saved.currentIndex < saved.queue.length &&
      survivingSources[targetIndex].uri == saved.queue[saved.currentIndex].uri;

  final targetPositionMs = originalItemSurvived ? saved.positionMs : 0;

  // Rebuild the queue with PlaybackQueue.replaceAll(startIndex) without opening engine or playing
  controller.queue.replaceAll(survivingSources, startIndex: targetIndex);
  controller.queue.repeatMode = saved.repeatModeEnum;
  if (saved.shuffle != controller.queue.isShuffled) {
    controller.queue.setShuffle(saved.shuffle);
  }

  if (targetPositionMs > 0) {
    controller.armResume(Duration(milliseconds: targetPositionMs));
  }

  return SessionRestoreResult(
    restoredCount: survivingSources.length,
    droppedCount: droppedCount,
    restoredIndex: targetIndex,
    armedPositionMs: targetPositionMs,
  );
}
