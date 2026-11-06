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
  String? _lastPositionUri;
  DateTime? _lastPositionSaveTime;
  bool _disposed = false;

  /// Creates a [SessionSaver].
  SessionSaver({
    required this.controller,
    required this.sessionStore,
    required this.settingsStore,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    _lastPositionSaveTime = this.clock();
    final armed = controller.armedResumePosition;
    if (armed != null) {
      _lastPosition = armed;
      _lastPositionUri = controller.queue.current?.uri;
    } else if (sessionStore.session.isNotEmpty &&
        sessionStore.session.positionMs > 0) {
      _lastPosition = Duration(milliseconds: sessionStore.session.positionMs);
      _lastPositionUri = sessionStore.session.currentUri;
    }

    _subs.add(controller.currentStream.listen((source) {
      if (source != null && source.uri != _lastPositionUri) {
        if (controller.armedResumePosition != null &&
            source.uri == controller.queue.current?.uri) {
          _lastPosition = controller.armedResumePosition!;
        } else {
          _lastPosition = Duration.zero;
        }
        _lastPositionUri = source.uri;
      }
      saveSnapshot(debounce: false);
    }));

    _subs.add(controller.stateStream.listen((state) {
      if (state == PlaybackState.paused ||
          state == PlaybackState.idle ||
          state == PlaybackState.completed) {
        saveSnapshot(debounce: false);
      }
    }));

    _subs.add(controller.seekStream.listen((pos) {
      _lastPosition = pos;
      _lastPositionUri = controller.queue.current?.uri;
      saveSnapshot(debounce: false);
    }));

    _subs.add(controller.queueChangeStream.listen((_) {
      saveSnapshot(debounce: false);
    }));

    _subs.add(controller.engine.positionStream.listen(_onPosition));
  }

  void _onPosition(Duration pos) {
    if (pos == Duration.zero &&
        (controller.currentState == PlaybackState.idle ||
            controller.currentState == PlaybackState.completed)) {
      // Do not overwrite non-zero position with zero while idle or completed
      return;
    }

    _lastPosition = pos;
    _lastPositionUri = controller.queue.current?.uri;

    if (controller.currentState == PlaybackState.playing) {
      final now = clock();
      if (_lastPositionSaveTime == null ||
          now.difference(_lastPositionSaveTime!).inSeconds >= 3) {
        _lastPositionSaveTime = now;
        saveSnapshot(debounce: true);
      }
    }
  }

  SavedSession _buildSessionSnapshot() {
    final queueItems = controller.queue.items.map((src) {
      return SavedSessionItem(uri: src.uri, extras: src.extras);
    }).toList();

    int positionMs = _lastPosition.inMilliseconds;
    if (controller.armedResumePosition != null && _lastPosition == Duration.zero) {
      positionMs = controller.armedResumePosition!.inMilliseconds;
    }

    final currentTrack = controller.queue.current;
    if (currentTrack != null &&
        _lastPositionUri != null &&
        currentTrack.uri != _lastPositionUri) {
      positionMs = 0;
    }

    return SavedSession(
      queue: queueItems,
      currentIndex: controller.queue.currentIndex >= 0
          ? controller.queue.currentIndex
          : 0,
      currentUri: currentTrack?.uri,
      positionMs: positionMs,
      shuffle: controller.queue.isShuffled,
      repeatMode: controller.queue.repeatMode.name,
      savedAt: clock().toUtc(),
    );
  }

  /// Takes a snapshot of active queue, position, and modes, then persists it.
  void saveSnapshot({bool debounce = true}) {
    if (_disposed) return;
    if (!settingsStore.settings.resumeSession) return;

    final session = _buildSessionSnapshot();
    sessionStore.save(session, debounce: debounce);
  }

  /// Takes a snapshot and flushes it to disk synchronously.
  void saveSnapshotSync() {
    if (_disposed) return;
    if (!settingsStore.settings.resumeSession) return;

    final session = _buildSessionSnapshot();
    sessionStore.saveSync(session);
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
