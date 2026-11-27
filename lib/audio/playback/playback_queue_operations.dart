import 'dart:async';
import 'dart:math' as math;

import '../audio_models.dart';
import '../playback_queue.dart';
import 'playback_fade_handler.dart';
import 'playback_gapless_preloader.dart';
import 'playback_play_source_tracker.dart';
import 'playback_resume_state.dart';

/// Internal queue-mutation collaborator for [PlaybackController].
/// Preserves exact queue mutation, preload refresh, and transition order.
class PlaybackQueueOperations {
  final PlaybackQueue queue;
  final PlaybackFadeHandler fadeHandler;
  final PlaybackGaplessPreloader preloader;
  final PlaybackResumeState resumeState;
  final PlaybackPlaySourceTracker playSourceTracker;
  final void Function() resetFatalErrors;
  final void Function() notifyQueueChanged;
  final String? Function() getOpenedUri;
  final Future<void> Function(AudioSource source, int gen, FadeProfile profile)
      switchTrackInternal;
  final Future<void> Function(
    int gen, {
    bool clearResume,
    required FadeProfile profile,
  }) stopInternal;
  final Future<void> Function() stop;

  const PlaybackQueueOperations({
    required this.queue,
    required this.fadeHandler,
    required this.preloader,
    required this.resumeState,
    required this.playSourceTracker,
    required this.resetFatalErrors,
    required this.notifyQueueChanged,
    required this.getOpenedUri,
    required this.switchTrackInternal,
    required this.stopInternal,
    required this.stop,
  });

  void _replaceQueuePreservingUserQueue(
    List<AudioSource> sources, {
    required int startIndex,
  }) {
    final survivingUserEntries = <QueueEntry>[];
    if (kKeepUserQueueOnNewContext && !queue.isEmpty && queue.currentIndex >= 0) {
      for (var i = queue.currentIndex + 1; i < queue.length; i++) {
        final entry = queue.entries[i];
        if (entry.isUserQueued) {
          survivingUserEntries.add(entry);
        }
      }
    }

    if (survivingUserEntries.isEmpty) {
      queue.replaceAll(sources, startIndex: startIndex);
    } else {
      final validStartIndex = startIndex.clamp(0, sources.length - 1);
      final newEntries = <QueueEntry>[];
      for (var i = 0; i < validStartIndex; i++) {
        newEntries.add(queue.createEntry(sources[i], isUserQueued: false));
      }
      newEntries.add(
        queue.createEntry(sources[validStartIndex], isUserQueued: false),
      );
      newEntries.addAll(survivingUserEntries);
      for (var i = validStartIndex + 1; i < sources.length; i++) {
        newEntries.add(queue.createEntry(sources[i], isUserQueued: false));
      }
      queue.replaceAllEntries(newEntries, startIndex: validStartIndex);
    }
  }

  Future<void> playQueue(
    List<AudioSource> sources, {
    int startIndex = 0,
    String? source,
  }) {
    resetFatalErrors();
    resumeState.clearArmedResume();
    playSourceTracker.setSource(source);
    if (sources.isEmpty) {
      queue.clear();
      playSourceTracker.reset();
      final gen = fadeHandler.beginTransition();
      final profile = fadeHandler.fadeProfile;
      return fadeHandler.enqueueTransition(
        () => stopInternal(gen, clearResume: false, profile: profile),
      );
    }

    _replaceQueuePreservingUserQueue(sources, startIndex: startIndex);

    notifyQueueChanged();
    final currentSource = queue.current;
    final gen = fadeHandler.beginTransition();
    final profile = fadeHandler.fadeProfile;
    if (currentSource == null) {
      return fadeHandler.enqueueTransition(
        () => stopInternal(gen, clearResume: false, profile: profile),
      );
    }

    return fadeHandler.enqueueTransition(
      () => switchTrackInternal(currentSource, gen, profile),
    );
  }

  Future<void> playShuffled(
    List<AudioSource> sources, {
    math.Random? random,
    String? source,
  }) {
    resetFatalErrors();
    resumeState.clearArmedResume();
    playSourceTracker.setSource(source);
    if (sources.isEmpty) {
      return playQueue(const [], source: source);
    }

    final startIndex = sources.length > 1
        ? (random ?? math.Random()).nextInt(sources.length)
        : 0;
    _replaceQueuePreservingUserQueue(sources, startIndex: startIndex);
    queue.setShuffle(true);
    notifyQueueChanged();

    final currentSource = queue.current;
    final gen = fadeHandler.beginTransition();
    final profile = fadeHandler.fadeProfile;
    if (currentSource == null) {
      return fadeHandler.enqueueTransition(
        () => stopInternal(gen, clearResume: false, profile: profile),
      );
    }

    return fadeHandler.enqueueTransition(
      () => switchTrackInternal(currentSource, gen, profile),
    );
  }

  Future<void> clearQueue() async {
    queue.clear();
    playSourceTracker.reset();
    resetFatalErrors();
    resumeState.clearArmedResume();
    notifyQueueChanged();
    final gen = fadeHandler.beginTransition();
    final profile = fadeHandler.fadeProfile;
    await fadeHandler.enqueueTransition(
      () => stopInternal(gen, clearResume: false, profile: profile),
    );
    await preloader.preloadNext();
  }

  Future<void> clearUpcoming() async {
    if (getOpenedUri() == null || queue.current == null) {
      queue.clear();
      notifyQueueChanged();
      await stop();
      return;
    }

    queue.clearUpcoming();
    notifyQueueChanged();
    await preloader.preloadNext();
  }

  Future<void> playNext(List<AudioSource> sources) async {
    if (sources.isEmpty) return;
    if (queue.isEmpty || queue.current == null) {
      await playQueue(sources, startIndex: 0, source: 'queue');
      return;
    }

    queue.playNext(sources);
    notifyQueueChanged();
    unawaited(preloader.preloadNext());
  }

  Future<void> addToQueue(List<AudioSource> sources) async {
    if (sources.isEmpty) return;
    if (queue.isEmpty || queue.current == null) {
      await playQueue(sources, startIndex: 0, source: 'queue');
      return;
    }

    queue.addToQueue(sources);
    notifyQueueChanged();
    unawaited(preloader.preloadNext());
  }

  Future<void> moveInQueue(int from, int to) async {
    if (from < 0 || from >= queue.length) return;
    if (to < 0 || to >= queue.length) return;
    if (from == to) return;

    queue.move(from, to);
    notifyQueueChanged();
    await preloader.preloadNext();
  }

  Future<void> setShuffle(bool enabled) async {
    queue.setShuffle(enabled);
    notifyQueueChanged();
    await preloader.preloadNext();
  }

  Future<void> cycleRepeatMode() async {
    final next = switch (queue.repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    queue.repeatMode = next;
    notifyQueueChanged();
    await preloader.preloadNext();
  }

  Future<void> removeEntryFromQueue(int entryId) {
    return removeEntriesFromQueue([entryId]);
  }

  Future<void> removeEntriesFromQueue(Iterable<int> entryIds) async {
    final idSet = entryIds.toSet();
    if (idSet.isEmpty || queue.isEmpty) return;

    final existingIds = queue.entries.map((e) => e.id).toSet();
    final matchingIds = idSet.intersection(existingIds);
    if (matchingIds.isEmpty) return;

    final wasCurrent =
        queue.currentEntry != null && matchingIds.contains(queue.currentEntry!.id);

    queue.removeByIds(matchingIds);

    if (queue.isEmpty) {
      resetFatalErrors();
      resumeState.clearArmedResume();
      notifyQueueChanged();
      final gen = fadeHandler.beginTransition();
      final profile = fadeHandler.fadeProfile;
      await fadeHandler.enqueueTransition(
        () => stopInternal(gen, clearResume: false, profile: profile),
      );
      await preloader.preloadNext();
      return;
    }

    if (!wasCurrent) {
      notifyQueueChanged();
      await preloader.preloadNext();
      return;
    }

    notifyQueueChanged();
    resetFatalErrors();
    resumeState.clearArmedResume();
    final nextSource = queue.current;
    final gen = fadeHandler.beginTransition();
    final profile = fadeHandler.fadeProfile;
    await fadeHandler.enqueueTransition(() async {
      if (nextSource != null) {
        await switchTrackInternal(nextSource, gen, profile);
      } else {
        await stopInternal(gen, clearResume: false, profile: profile);
      }
    });
    await preloader.preloadNext();
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= queue.length) return;
    await removeEntryFromQueue(queue.entries[index].id);
  }

  Future<void> playNextFromQueue(int index) async {
    if (index < 0 || index >= queue.length) return;
    final cur = queue.currentIndex;
    if (cur < 0 || index == cur || index == cur + 1) return;
    final target = index > cur ? cur + 1 : cur;
    await moveInQueue(index, target);
  }
}
