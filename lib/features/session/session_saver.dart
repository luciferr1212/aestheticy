import 'dart:async';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'saved_session.dart';
import 'session_store.dart';

/// Monitors playback queue and state, saving snapshots to [SessionStore].
class SessionSaver {
  final PlaybackController controller;
  final SessionStore sessionStore;
  final SettingsStore settingsStore;
  final DateTime Function() clock;

  final List<StreamSubscription<dynamic>> _subs = [];
  Duration _lastPosition = Duration.zero;
  DateTime? _lastPositionSaveTime;
  bool _disposed = false;

  /// Creates a [SessionSaver].
  SessionSaver({
    required this.controller,
    required this.sessionStore,
    required this.settingsStore,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    _subs.add(controller.currentStream.listen((_) {
      saveSnapshot(debounce: true);
    }));

    _subs.add(controller.stateStream.listen((state) {
      if (state == PlaybackState.paused ||
          state == PlaybackState.idle ||
          state == PlaybackState.completed) {
        saveSnapshot(debounce: false);
      }
    }));

    _subs.add(controller.engine.positionStream.listen(_onPosition));
  }

  void _onPosition(Duration pos) {
    _lastPosition = pos;
    if (controller.currentState == PlaybackState.playing) {
      final now = clock();
      if (_lastPositionSaveTime == null ||
          now.difference(_lastPositionSaveTime!).inSeconds >= 10) {
        _lastPositionSaveTime = now;
        saveSnapshot(debounce: true);
      }
    }
  }

  /// Takes a snapshot of active queue, position, and modes, then persists it.
  void saveSnapshot({bool debounce = true}) {
    if (_disposed) return;
    if (!settingsStore.settings.resumeSession) return;

    final queueItems = controller.queue.items.map((src) {
      return SavedSessionItem(uri: src.uri, extras: src.extras);
    }).toList();

    final session = SavedSession(
      queue: queueItems,
      currentIndex: controller.queue.currentIndex >= 0
          ? controller.queue.currentIndex
          : 0,
      positionMs: _lastPosition.inMilliseconds,
      shuffle: controller.queue.isShuffled,
      repeatMode: controller.queue.repeatMode.name,
      savedAt: clock().toUtc(),
    );

    sessionStore.save(session, debounce: debounce);
  }

  /// Cancels all subscriptions and writes final snapshot to disk.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    saveSnapshot(debounce: false);
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }
}
