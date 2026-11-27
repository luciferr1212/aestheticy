import 'dart:async';
import 'dart:math' as math;

import '../audio_engine.dart';
import '../audio_models.dart';

/// Internal fade envelope and serialized transition coordinator for
/// [PlaybackController]. Preserves exact gain ramping, gap timing, and
/// transition generation cancellation semantics.
class PlaybackFadeHandler {
  final AudioEngine engine;
  final Duration fadeTickInterval;
  final bool Function() isDisposed;

  FadeProfile _fadeProfile;
  double _currentFadeGain = 1.0;
  int _transitionGen = 0;
  Future<void>? _activeTransition;
  Timer? _fadeTimer;
  Timer? _delayTimer;
  Timer? _deadlineTimer;
  Completer<void>? _activeWaitCompleter;

  PlaybackFadeHandler({
    required this.engine,
    required this.fadeTickInterval,
    required this.isDisposed,
    required FadeProfile initialProfile,
  }) : _fadeProfile = initialProfile;

  FadeProfile get fadeProfile => _fadeProfile;

  set fadeProfile(FadeProfile value) {
    if (_fadeProfile == value) return;
    _fadeProfile = value;
  }

  bool get smoothTransitions => !_fadeProfile.isOff;

  set smoothTransitions(bool value) {
    if (value) {
      fadeProfile = FadeProfile.soft;
    } else {
      fadeProfile = FadeProfile.off;
      abortPendingWaiters();
      unawaited(setFadeGain(1.0));
    }
  }

  double get currentFadeGain => _currentFadeGain;

  int beginTransition() {
    _transitionGen++;
    abortPendingWaiters();
    return _transitionGen;
  }

  bool isStale(int gen) => isDisposed() || gen != _transitionGen;

  Future<void> enqueueTransition(Future<void> Function() task) {
    final prev = _activeTransition;
    final next = prev == null
        ? task()
        : prev.catchError((Object _) {}).then((_) => task());
    late final Future<void> tracked;
    tracked = next.whenComplete(() {
      if (identical(_activeTransition, tracked)) {
        _activeTransition = null;
      }
    });
    _activeTransition = tracked;
    return tracked;
  }

  void abortPendingWaiters() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _delayTimer?.cancel();
    _delayTimer = null;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    final completer = _activeWaitCompleter;
    _activeWaitCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void dispose() {
    _transitionGen++;
    abortPendingWaiters();
  }

  Future<void> setFadeGain(double gain) async {
    final clamped = gain.clamp(0.0, 1.0);
    _currentFadeGain = clamped;
    if (isDisposed()) return;
    await engine.setFadeGain(clamped);
  }

  Future<void> ensureUnityFadeGain() async {
    if ((_currentFadeGain - 1.0).abs() > 1e-6) {
      await setFadeGain(1.0);
    }
  }

  static double _smoothStep(double t) => 0.5 * (1.0 - math.cos(math.pi * t));

  double _fadeProgress(int step, int totalDurationUs, int swElapsedUs) {
    final tickUs = step * fadeTickInterval.inMicroseconds;
    final elapsedUs = math.max(tickUs, swElapsedUs);
    return (elapsedUs / totalDurationUs).clamp(0.0, 1.0);
  }

  Future<void> rampOut(
    Duration duration,
    int gen, {
    Duration? maxDuration,
  }) async {
    if (isStale(gen)) return;
    final startGain = _currentFadeGain.clamp(0.0, 1.0);
    if (startGain <= 0.0 || duration <= Duration.zero) {
      await setFadeGain(0.0);
      return;
    }

    final scaledMs = (duration.inMilliseconds * startGain).round();
    final effectiveMs = maxDuration != null
        ? math.min(scaledMs, maxDuration.inMilliseconds)
        : scaledMs;
    if (effectiveMs <= 0) {
      await setFadeGain(0.0);
      return;
    }

    final totalDurationUs = effectiveMs * 1000;
    final sw = Stopwatch()..start();
    var step = 0;
    final completer = Completer<void>();
    _activeWaitCompleter = completer;

    void finish() {
      _fadeTimer?.cancel();
      _fadeTimer = null;
      _deadlineTimer?.cancel();
      _deadlineTimer = null;
      if (identical(_activeWaitCompleter, completer)) {
        _activeWaitCompleter = null;
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    if (maxDuration != null) {
      _deadlineTimer = Timer(maxDuration, () {
        if (!isStale(gen)) {
          unawaited(setFadeGain(0.0));
        }
        finish();
      });
    }

    _fadeTimer = Timer.periodic(fadeTickInterval, (_) {
      if (isStale(gen)) {
        finish();
        return;
      }
      step++;
      final t = _fadeProgress(step, totalDurationUs, sw.elapsedMicroseconds);
      final gain = startGain * (1.0 - _smoothStep(t));
      unawaited(setFadeGain(gain));
      if (t >= 1.0) {
        finish();
      }
    });

    await completer.future;
    if (!isStale(gen)) {
      await setFadeGain(0.0);
    }
  }

  Future<void> waitGap(Duration duration, int gen) async {
    if (isStale(gen) || duration <= Duration.zero) return;
    final completer = Completer<void>();
    _activeWaitCompleter = completer;
    _delayTimer = Timer(duration, () {
      _delayTimer = null;
      if (identical(_activeWaitCompleter, completer)) {
        _activeWaitCompleter = null;
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    await completer.future;
  }

  void startFadeIn(Duration duration, int gen, FadeProfile profile) {
    if (isStale(gen)) return;
    _fadeTimer?.cancel();
    _fadeTimer = null;

    if (profile.isOff || duration <= Duration.zero) {
      if ((_currentFadeGain - 1.0).abs() > 1e-6) {
        unawaited(setFadeGain(1.0));
      }
      return;
    }

    final startGain = _currentFadeGain.clamp(0.0, 1.0);
    if (startGain >= 1.0) {
      return;
    }

    final remainingFraction = 1.0 - startGain;
    final totalDurationUs = (duration.inMilliseconds * remainingFraction * 1000)
        .round()
        .clamp(1, 10000000);
    final sw = Stopwatch()..start();
    var step = 0;

    _fadeTimer = Timer.periodic(fadeTickInterval, (timer) {
      if (isStale(gen)) {
        timer.cancel();
        if (identical(_fadeTimer, timer)) {
          _fadeTimer = null;
        }
        return;
      }
      step++;
      final t = _fadeProgress(step, totalDurationUs, sw.elapsedMicroseconds);
      final gain = startGain + (1.0 - startGain) * _smoothStep(t);
      unawaited(setFadeGain(gain));
      if (t >= 1.0) {
        timer.cancel();
        if (identical(_fadeTimer, timer)) {
          _fadeTimer = null;
        }
      }
    });
  }

  Future<void> prepareForTrackSwitch({
    required bool wasPlaying,
    required int gen,
    required FadeProfile profile,
  }) async {
    if (!profile.isOff) {
      if (wasPlaying) {
        if (profile.switchFadeOut > Duration.zero) {
          await rampOut(profile.switchFadeOut, gen);
          if (isStale(gen)) return;
        }
        if (profile.switchGap > Duration.zero) {
          await waitGap(profile.switchGap, gen);
          if (isStale(gen)) return;
        }
      } else {
        await setFadeGain(0.0);
        if (isStale(gen)) return;
      }
    } else if ((_currentFadeGain - 1.0).abs() > 1e-6) {
      await setFadeGain(1.0);
      if (isStale(gen)) return;
    }
  }
}
