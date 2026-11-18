import 'dart:async';
import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:flutter_test/flutter_test.dart';

AudioSource _src(String name) => AudioSource('file:///$name.flac');

class _ProfileTimingSpyEngine extends FakeAudioEngine {
  final Stopwatch stopwatch = Stopwatch()..start();
  final List<String> events = [];
  final List<double> gainRecord = [];
  int? zeroGainTimestampMs;
  int? lastOpenTimestampMs;

  @override
  Future<void> setFadeGain(double gain) async {
    await super.setFadeGain(gain);
    gainRecord.add(gain);
    events.add('gain:${gain.toStringAsFixed(3)}');
    if (gain <= 1e-6 && zeroGainTimestampMs == null) {
      zeroGainTimestampMs = stopwatch.elapsedMilliseconds;
    }
  }

  @override
  Future<void> open(
    AudioSource source, {
    bool autoPlay = false,
    bool continuingGapless = false,
  }) async {
    lastOpenTimestampMs = stopwatch.elapsedMilliseconds;
    events.add('open:${source.uri}:$autoPlay');
    await super.open(
      source,
      autoPlay: autoPlay,
      continuingGapless: continuingGapless,
    );
  }

  @override
  Future<void> play() async {
    events.add('play:${openedSource?.uri}');
    await super.play();
  }

  @override
  Future<void> pause() async {
    events.add('pause');
    await super.pause();
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    await super.stop();
  }
}

void main() {
  group('FadeProfile model and constants', () {
    test('off profile has all zero durations and isOff is true', () {
      const p = FadeProfile.off;
      expect(p.isOff, isTrue);
      expect(p.startFadeIn, Duration.zero);
      expect(p.resumeFadeIn, Duration.zero);
      expect(p.switchFadeOut, Duration.zero);
      expect(p.switchGap, Duration.zero);
      expect(p.switchFadeIn, Duration.zero);
      expect(p.pauseFadeOut, Duration.zero);
      expect(p.stopFadeOut, Duration.zero);
    });

    test('soft profile matches legacy durations exactly', () {
      const p = FadeProfile.soft;
      expect(p.isOff, isFalse);
      expect(p.startFadeIn, const Duration(milliseconds: 250));
      expect(p.resumeFadeIn, const Duration(milliseconds: 120));
      expect(p.switchFadeOut, const Duration(milliseconds: 120));
      expect(p.switchGap, const Duration(milliseconds: 60));
      expect(p.switchFadeIn, const Duration(milliseconds: 250));
      expect(p.pauseFadeOut, const Duration(milliseconds: 100));
      expect(p.stopFadeOut, const Duration(milliseconds: 100));
    });

    test('smooth profile matches extended smooth specification', () {
      const p = FadeProfile.smooth;
      expect(p.isOff, isFalse);
      expect(p.startFadeIn, const Duration(milliseconds: 450));
      expect(p.resumeFadeIn, const Duration(milliseconds: 280));
      expect(p.switchFadeOut, const Duration(milliseconds: 300));
      expect(p.switchGap, const Duration(milliseconds: 90));
      expect(p.switchFadeIn, const Duration(milliseconds: 450));
      expect(p.pauseFadeOut, const Duration(milliseconds: 260));
      expect(p.stopFadeOut, const Duration(milliseconds: 260));
    });

    test('equality and hashCode behave correctly', () {
      const p1 = FadeProfile(
        startFadeIn: Duration(milliseconds: 100),
        resumeFadeIn: Duration(milliseconds: 50),
        switchFadeOut: Duration(milliseconds: 50),
        switchGap: Duration(milliseconds: 20),
        switchFadeIn: Duration(milliseconds: 100),
        pauseFadeOut: Duration(milliseconds: 40),
        stopFadeOut: Duration(milliseconds: 40),
      );
      const p2 = FadeProfile(
        startFadeIn: Duration(milliseconds: 100),
        resumeFadeIn: Duration(milliseconds: 50),
        switchFadeOut: Duration(milliseconds: 50),
        switchGap: Duration(milliseconds: 20),
        switchFadeIn: Duration(milliseconds: 100),
        pauseFadeOut: Duration(milliseconds: 40),
        stopFadeOut: Duration(milliseconds: 40),
      );
      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
    });
  });

  group('PlaybackController with FadeProfiles (S1)', () {
    test('off profile performs instant transitions with unity gain (no fades)', () async {
      final engine = _ProfileTimingSpyEngine();
      await engine.init();
      final q = PlaybackQueue()..add(_src('a'))..add(_src('b'));
      final ctrl = PlaybackController(
        engine: engine,
        queue: q,
        fadeProfile: FadeProfile.off,
      );
      await ctrl.init();

      expect(ctrl.smoothTransitions, isFalse);
      expect(ctrl.fadeProfile, equals(FadeProfile.off));

      // Stopped -> Play: instant unity gain, no fade-in timer
      final sw = Stopwatch()..start();
      await ctrl.play();
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(50));
      expect(engine.fadeGain, closeTo(1.0, 1e-6));

      // Manual switch: instant switch, no fade-out or gap
      sw.reset();
      sw.start();
      await ctrl.skipNext();
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(50));
      expect(q.current?.uri, 'file:///b.flac');
      expect(engine.fadeGain, closeTo(1.0, 1e-6));

      // Pause: instant pause
      sw.reset();
      sw.start();
      await ctrl.pause();
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(50));
      expect(engine.state, PlaybackState.paused);

      await ctrl.dispose();
      await engine.dispose();
    });

    test('soft profile uses 250ms start, 120ms resume, 120ms switch-out, 60ms gap', () async {
      final engine = _ProfileTimingSpyEngine();
      await engine.init();
      final q = PlaybackQueue()..add(_src('a'))..add(_src('b'));
      final ctrl = PlaybackController(
        engine: engine,
        queue: q,
        fadeProfile: FadeProfile.soft,
      );
      await ctrl.init();

      expect(ctrl.smoothTransitions, isTrue);
      expect(ctrl.fadeProfile, equals(FadeProfile.soft));

      // 1. Stopped -> Play (~250ms fade-in)
      await ctrl.play();
      expect(engine.fadeGain, closeTo(0.0, 1e-6));
      await Future<void>.delayed(const Duration(milliseconds: 140));
      expect(engine.fadeGain, inInclusiveRange(0.2, 0.85));
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(engine.fadeGain, closeTo(1.0, 1e-6));

      // 2. Pause (~100ms fade-out)
      final pauseStart = engine.stopwatch.elapsedMilliseconds;
      await ctrl.pause();
      final pauseElapsed = engine.stopwatch.elapsedMilliseconds - pauseStart;
      expect(pauseElapsed, inInclusiveRange(80, 220));
      expect(engine.state, PlaybackState.paused);

      // 3. Resume (~120ms fade-in)
      await ctrl.play();
      expect(engine.fadeGain, closeTo(0.0, 1e-6));
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(engine.fadeGain, inInclusiveRange(0.2, 0.85));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(engine.fadeGain, closeTo(1.0, 1e-6));

      // 4. Switch track while playing: 120ms out + 60ms gap + 250ms in
      engine.zeroGainTimestampMs = null;
      engine.lastOpenTimestampMs = null;
      await ctrl.skipNext();
      expect(engine.zeroGainTimestampMs, isNotNull);
      expect(engine.lastOpenTimestampMs, isNotNull);
      final gapMs = engine.lastOpenTimestampMs! - engine.zeroGainTimestampMs!;
      expect(gapMs, inInclusiveRange(45, 120));

      await ctrl.dispose();
      await engine.dispose();
    });

    test('smooth profile uses 450ms start, 280ms resume, 300ms switch-out, 90ms gap, 260ms pause/stop', () async {
      final engine = _ProfileTimingSpyEngine();
      await engine.init();
      final q = PlaybackQueue()..add(_src('a'))..add(_src('b'));
      final ctrl = PlaybackController(
        engine: engine,
        queue: q,
        fadeProfile: FadeProfile.smooth,
      );
      await ctrl.init();

      expect(ctrl.fadeProfile, equals(FadeProfile.smooth));

      // 1. Stopped -> Play (~450ms fade-in)
      await ctrl.play();
      expect(engine.fadeGain, closeTo(0.0, 1e-6));
      // At 200ms into a 450ms curve, gain should still be mid-range
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(engine.fadeGain, inInclusiveRange(0.2, 0.75));
      // At 480ms, should reach full gain
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(engine.fadeGain, closeTo(1.0, 1e-6));

      // 2. Pause (~260ms fade-out)
      final pauseStart = engine.stopwatch.elapsedMilliseconds;
      await ctrl.pause();
      final pauseElapsed = engine.stopwatch.elapsedMilliseconds - pauseStart;
      expect(pauseElapsed, inInclusiveRange(220, 420));
      expect(engine.state, PlaybackState.paused);

      // 3. Resume (~280ms fade-in)
      await ctrl.play();
      expect(engine.fadeGain, closeTo(0.0, 1e-6));
      await Future<void>.delayed(const Duration(milliseconds: 140));
      expect(engine.fadeGain, inInclusiveRange(0.2, 0.75));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(engine.fadeGain, closeTo(1.0, 1e-6));

      // 4. Switch track while playing: 300ms out + 90ms gap + 450ms in
      engine.zeroGainTimestampMs = null;
      engine.lastOpenTimestampMs = null;
      final switchStart = engine.stopwatch.elapsedMilliseconds;
      await ctrl.skipNext();
      expect(engine.zeroGainTimestampMs, isNotNull);
      expect(engine.lastOpenTimestampMs, isNotNull);
      final outDuration = engine.zeroGainTimestampMs! - switchStart;
      expect(outDuration, inInclusiveRange(240, 450));
      final gapMs = engine.lastOpenTimestampMs! - engine.zeroGainTimestampMs!;
      expect(gapMs, inInclusiveRange(70, 180));

      await ctrl.dispose();
      await engine.dispose();
    });

    test('rapid skipping stays latest-wins with smooth profile', () async {
      final engine = _ProfileTimingSpyEngine();
      await engine.init();
      final q = PlaybackQueue()
        ..add(_src('a'))
        ..add(_src('b'))
        ..add(_src('c'))
        ..add(_src('d'));
      final ctrl = PlaybackController(
        engine: engine,
        queue: q,
        fadeProfile: FadeProfile.smooth,
      );
      await ctrl.init();

      await ctrl.playTrack(0);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Fire rapid skips in close succession
      unawaited(ctrl.skipNext());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      unawaited(ctrl.skipNext());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await ctrl.skipNext();

      // Wait for the final transition to settle
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(q.current?.uri, 'file:///d.flac');
      expect(engine.openedSource?.uri, 'file:///d.flac');
      expect(engine.fadeGain, closeTo(1.0, 1e-6));

      await ctrl.dispose();
      await engine.dispose();
    });

    test('pause then play mid-fade catches gain smoothly and never jumps', () async {
      final engine = _ProfileTimingSpyEngine();
      await engine.init();
      final q = PlaybackQueue()..add(_src('a'));
      final ctrl = PlaybackController(
        engine: engine,
        queue: q,
        fadeProfile: FadeProfile.smooth,
      );
      await ctrl.init();

      await ctrl.play();
      // Reach full gain
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(engine.fadeGain, closeTo(1.0, 1e-6));

      // Trigger pause (260ms ramp-out)
      unawaited(ctrl.pause());
      // Wait for gain to decrease to ~0.5
      await Future<void>.delayed(const Duration(milliseconds: 130));
      final gainAtMidPause = engine.fadeGain;
      expect(gainAtMidPause, inInclusiveRange(0.1, 0.9));

      // Immediately hit play mid-fade
      unawaited(ctrl.play());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Verify gain didn't jump to 0.0 or 1.0 abruptly, but caught smoothly
      expect(engine.fadeGain, inInclusiveRange(gainAtMidPause - 0.25, 1.0));
      expect(engine.state, PlaybackState.playing);

      // Eventually ramps to 1.0
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(engine.fadeGain, closeTo(1.0, 1e-6));

      await ctrl.dispose();
      await engine.dispose();
    });

    test('profile switch applies on the next transition, never in the middle of a running fade', () async {
      final engine = _ProfileTimingSpyEngine();
      await engine.init();
      final q = PlaybackQueue()..add(_src('a'))..add(_src('b'))..add(_src('c'));
      final ctrl = PlaybackController(
        engine: engine,
        queue: q,
        fadeProfile: FadeProfile.soft,
      );
      await ctrl.init();

      await ctrl.play();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(engine.fadeGain, closeTo(1.0, 1e-6));

      // Start a track switch with soft profile (120ms out)
      unawaited(ctrl.skipNext());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Mid-fade, switch profile to smooth
      ctrl.fadeProfile = FadeProfile.smooth;

      // The running switch should finish using soft profile durations (~120ms out + ~60ms gap)
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(q.current?.uri, 'file:///b.flac');

      // The NEXT transition (pause) should now use smooth profile (~260ms out)
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final pauseStart = engine.stopwatch.elapsedMilliseconds;
      await ctrl.pause();
      final pauseDuration = engine.stopwatch.elapsedMilliseconds - pauseStart;
      expect(pauseDuration, inInclusiveRange(220, 420));

      await ctrl.dispose();
      await engine.dispose();
    });

    test('smoothTransitions adapter sets soft when true and off when false', () async {
      final engine = _ProfileTimingSpyEngine();
      await engine.init();
      final q = PlaybackQueue()..add(_src('a'));
      final ctrl = PlaybackController(
        engine: engine,
        queue: q,
        smoothTransitions: true,
      );
      await ctrl.init();

      expect(ctrl.smoothTransitions, isTrue);
      expect(ctrl.fadeProfile, equals(FadeProfile.soft));

      ctrl.smoothTransitions = false;
      expect(ctrl.smoothTransitions, isFalse);
      expect(ctrl.fadeProfile, equals(FadeProfile.off));

      ctrl.smoothTransitions = true;
      expect(ctrl.smoothTransitions, isTrue);
      expect(ctrl.fadeProfile, equals(FadeProfile.soft));

      await ctrl.dispose();
      await engine.dispose();
    });
  });
}
