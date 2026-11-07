import 'dart:async';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../platform/sleep_inhibitor.dart';
import '../../ui/settings/settings_store.dart';

/// Pure-Dart controller managing system idle sleep prevention based on playback state and user preferences.
class SleepController {
  final PlaybackController playbackController;
  final SleepInhibitor sleepInhibitor;
  final SettingsStore settingsStore;

  final List<StreamSubscription<dynamic>> _subs = [];
  bool _isAcquired = false;
  bool _disposed = false;

  /// Whether sleep inhibition is currently acquired.
  bool get isAcquired => _isAcquired;

  /// Creates a [SleepController] and starts monitoring playback and settings.
  SleepController({
    required this.playbackController,
    required this.sleepInhibitor,
    required this.settingsStore,
  }) {
    _subs.add(playbackController.stateStream.listen((_) => _evaluateState()));
    settingsStore.addListener(_evaluateState);
    _evaluateState();
  }

  void _evaluateState() {
    if (_disposed) {
      if (_isAcquired) {
        sleepInhibitor.release();
        _isAcquired = false;
      }
      return;
    }

    final shouldAcquire = playbackController.currentState == PlaybackState.playing &&
        settingsStore.settings.preventSleepWhilePlaying;

    if (shouldAcquire && !_isAcquired) {
      sleepInhibitor.acquire();
      _isAcquired = true;
    } else if (!shouldAcquire && _isAcquired) {
      sleepInhibitor.release();
      _isAcquired = false;
    }
  }

  /// Releases sleep inhibition and cancels subscriptions.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    settingsStore.removeListener(_evaluateState);
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    if (_isAcquired) {
      sleepInhibitor.release();
      _isAcquired = false;
    }
  }
}
