import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'saved_session.dart';
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
  final survivingItems = <SavedSessionItem>[];
  var droppedCount = 0;
  int? survivingCurrentIndex;
  var savedCurrentSurvived = false;

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
          survivingCurrentIndex = survivingItems.length;
          savedCurrentSurvived = true;
        } else if (originalIndex > saved.currentIndex &&
            survivingCurrentIndex == null) {
          // If the current item was dropped, start at the next surviving item with position 0
          survivingCurrentIndex = survivingItems.length;
        }
        survivingItems.add(batch[j]);
      } else {
        droppedCount++;
      }
    }
    await Future<void>.delayed(Duration.zero);
  }

  if (survivingItems.isEmpty) {
    return SessionRestoreResult(
      restoredCount: 0,
      droppedCount: droppedCount,
      restoredIndex: -1,
      armedPositionMs: 0,
    );
  }

  final restoredEntries = <QueueEntry>[];
  final usedEntryIds = <int>{};
  for (final item in survivingItems) {
    final savedId = item.entryId;
    if (savedId != null && usedEntryIds.add(savedId)) {
      restoredEntries.add(
        QueueEntry(
          id: savedId,
          source: item.toAudioSource(),
          isUserQueued: item.isUserQueued,
        ),
      );
    } else {
      final created = controller.queue.createEntry(
        item.toAudioSource(),
        isUserQueued: item.isUserQueued,
      );
      usedEntryIds.add(created.id);
      restoredEntries.add(created);
    }
  }

  int targetIndex = -1;
  bool originalItemSurvived = false;

  if (saved.currentEntryId != null) {
    final byId = restoredEntries.indexWhere((e) => e.id == saved.currentEntryId);
    if (byId >= 0) {
      targetIndex = byId;
      originalItemSurvived = true;
    } else {
      targetIndex = survivingCurrentIndex ?? 0;
      originalItemSurvived = false;
    }
  } else if (savedCurrentSurvived && survivingCurrentIndex != null) {
    targetIndex = survivingCurrentIndex;
    originalItemSurvived = saved.currentUri == null ||
        saved.currentUri!.isEmpty ||
        restoredEntries[targetIndex].source.uri == saved.currentUri;
  } else {
    if (saved.currentUri != null && saved.currentUri!.isNotEmpty) {
      targetIndex =
          restoredEntries.indexWhere((e) => e.source.uri == saved.currentUri);
    }
    if (targetIndex < 0) {
      targetIndex = survivingCurrentIndex ?? 0;
    }
    originalItemSurvived = targetIndex >= 0 &&
        targetIndex < restoredEntries.length &&
        saved.currentUri != null &&
        restoredEntries[targetIndex].source.uri == saved.currentUri;
  }

  final targetPositionMs = originalItemSurvived ? saved.positionMs : 0;

  // Restore exact saved order, entry identities, shuffle flag, and repeat mode without re-shuffling.
  controller.restoreQueueSnapshot(
    entries: restoredEntries,
    currentIndex: targetIndex,
    shuffled: saved.shuffle,
    repeatMode: saved.repeatModeEnum,
  );

  if (targetPositionMs > 0) {
    controller.armResume(Duration(milliseconds: targetPositionMs));
  }

  return SessionRestoreResult(
    restoredCount: restoredEntries.length,
    droppedCount: droppedCount,
    restoredIndex: targetIndex,
    armedPositionMs: targetPositionMs,
  );
}
