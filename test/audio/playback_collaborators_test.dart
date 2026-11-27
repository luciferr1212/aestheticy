import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback/playback_fade_handler.dart';
import 'package:aestheticy/audio/playback/playback_gapless_preloader.dart';
import 'package:aestheticy/audio/playback/playback_play_source_tracker.dart';
import 'package:aestheticy/audio/playback/playback_resume_state.dart';
import 'package:aestheticy/audio/playback_queue.dart';

class _ThrowingPreloadEngine extends FakeAudioEngine {
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        exclusiveMode: false,
        gapless: true,
        equalizer: true,
        replayGain: true,
      );

  @override
  Future<void> preloadNext(AudioSource? source) async {
    throw StateError('Simulated preload error');
  }
}

void main() {
  group('Playback collaborators (S2)', () {
    test('PlaybackPlaySourceTracker normalizes known and unknown play sources', () {
      final tracker = PlaybackPlaySourceTracker();
      expect(tracker.currentPlaySource, equals('unknown'));

      tracker.setSource('album');
      expect(tracker.currentPlaySource, equals('album'));

      tracker.setSource('invalid_source');
      expect(tracker.currentPlaySource, equals('unknown'));

      tracker.setSource('favorites');
      tracker.reset();
      expect(tracker.currentPlaySource, equals('unknown'));
    });

    test('PlaybackResumeState arms, clears on different URI, and fires lazy seek once', () async {
      final resume = PlaybackResumeState();
      resume.armResume(const Duration(seconds: 30), currentUri: 'file:///a.mp3');
      expect(resume.armedResumePosition, equals(const Duration(seconds: 30)));

      // Same URI does not clear
      resume.clearIfDifferentUri('file:///a.mp3');
      expect(resume.armedResumePosition, equals(const Duration(seconds: 30)));

      final seeks = <Duration>[];
      resume.checkArmedResume(
        dur: const Duration(minutes: 3),
        engineDuration: const Duration(minutes: 3),
        openedUri: 'file:///a.mp3',
        currentQueueUri: 'file:///a.mp3',
        seekEngine: (pos) async => seeks.add(pos),
      );
      expect(seeks, equals([const Duration(seconds: 30)]));
      expect(resume.armedResumePosition, isNull);

      // Different URI clears armed resume
      resume.armResume(const Duration(seconds: 15), currentUri: 'file:///a.mp3');
      resume.clearIfDifferentUri('file:///b.mp3');
      expect(resume.armedResumePosition, isNull);
    });

    test('PlaybackGaplessPreloader reports non-fatal error without throwing on engine failure', () async {
      final engine = _ThrowingPreloadEngine();
      final queue = PlaybackQueue()
        ..replaceAll([
          const AudioSource('file:///a.mp3'),
          const AudioSource('file:///b.mp3'),
        ]);
      final errors = <AudioError>[];
      final preloader = PlaybackGaplessPreloader(
        engine: engine,
        queue: queue,
        isDisposed: () => false,
        emitError: errors.add,
      );

      await preloader.preloadNext();
      expect(errors, hasLength(1));
      expect(errors.single.isFatal, isFalse);
      await engine.dispose();
    });

    test('PlaybackFadeHandler serializes transitions and restores unity gain when disabling smoothTransitions', () async {
      final engine = FakeAudioEngine();
      await engine.init();
      final handler = PlaybackFadeHandler(
        engine: engine,
        fadeTickInterval: const Duration(milliseconds: 5),
        isDisposed: () => false,
        initialProfile: FadeProfile.soft,
      );

      final gen = handler.beginTransition();
      await handler.setFadeGain(0.2);
      expect(handler.currentFadeGain, closeTo(0.2, 1e-6));

      handler.smoothTransitions = false;
      expect(handler.fadeProfile, equals(FadeProfile.off));
      expect(handler.currentFadeGain, closeTo(1.0, 1e-6));
      expect(handler.isStale(gen), isFalse);

      handler.dispose();
      expect(handler.isStale(gen), isTrue);
      await engine.dispose();
    });
  });
}
