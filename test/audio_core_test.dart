import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/audio/playback_controller.dart';

// ── Helpers ─────────────────────────────────────────────────────────────

AudioSource _src(String name) => AudioSource('file:///$name.flac');

/// A seeded Random that produces a known shuffle sequence.
Random _seededRandom() => Random(42);

// ═══════════════════════════════════════════════════════════════════════
// PlaybackQueue tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  group('PlaybackQueue', () {
    group('basic order', () {
      test('items are returned in insertion order', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        expect(q.items.map((s) => s.uri), ['file:///a.flac', 'file:///b.flac', 'file:///c.flac']);
      });

      test('insert places item at correct index', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('c'));
        q.insert(1, _src('b'));
        expect(q.items.map((s) => s.uri), ['file:///a.flac', 'file:///b.flac', 'file:///c.flac']);
      });

      test('remove removes the correct item', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        q.remove(1);
        expect(q.items.map((s) => s.uri), ['file:///a.flac', 'file:///c.flac']);
      });

      test('move reorders correctly', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        q.move(0, 2);
        expect(q.items.map((s) => s.uri), ['file:///b.flac', 'file:///c.flac', 'file:///a.flac']);
      });

      test('clear empties the queue', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.clear();
        expect(q.isEmpty, isTrue);
        expect(q.currentIndex, -1);
      });
    });

    group('navigation', () {
      test('next advances through the queue', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        // Cursor starts at 0 after first add.
        expect(q.current?.uri, 'file:///a.flac');
        expect(q.next()?.uri, 'file:///b.flac');
        expect(q.next()?.uri, 'file:///c.flac');
        expect(q.next(), isNull); // end, repeat off
      });

      test('previous goes back', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        q.next(); // b
        q.next(); // c
        expect(q.previous()?.uri, 'file:///b.flac');
        expect(q.previous()?.uri, 'file:///a.flac');
        expect(q.previous(), isNull); // start, repeat off
      });

      test('peekNext returns next without moving cursor', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        expect(q.peekNext()?.uri, 'file:///b.flac');
        expect(q.current?.uri, 'file:///a.flac'); // unchanged
      });
    });

    group('shuffle', () {
      test('shuffle keeps every item exactly once', () {
        final q = PlaybackQueue(random: _seededRandom());
        for (var i = 0; i < 20; i++) {
          q.add(_src('track$i'));
        }
        q.setShuffle(true);

        // Collect all items via navigation.
        final visited = <String>{q.current!.uri};
        while (true) {
          final n = q.next();
          if (n == null) break;
          visited.add(n.uri);
        }

        // Every item visited exactly once.
        expect(visited.length, 20);
        for (var i = 0; i < 20; i++) {
          expect(visited, contains('file:///track$i.flac'));
        }
      });

      test('shuffle keeps current item first', () {
        final q = PlaybackQueue(random: _seededRandom());
        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        q.add(_src('d'));
        // Advance to 'b'.
        q.next();
        expect(q.current?.uri, 'file:///b.flac');

        q.setShuffle(true);
        // Current item should still be 'b'.
        expect(q.current?.uri, 'file:///b.flac');
      });
    });

    group('repeat modes', () {
      test('repeat off stops at end', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.repeatMode = RepeatMode.off;
        q.next(); // b
        expect(q.next(), isNull);
      });

      test('repeat all wraps around', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.repeatMode = RepeatMode.all;
        q.next(); // b
        expect(q.next()?.uri, 'file:///a.flac'); // wrap
      });

      test('repeat one stays on same item', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.repeatMode = RepeatMode.one;
        expect(q.next()?.uri, 'file:///a.flac'); // same
        expect(q.next()?.uri, 'file:///a.flac'); // same
      });

      test('repeat all wraps previous at start', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.repeatMode = RepeatMode.all;
        expect(q.previous()?.uri, 'file:///b.flac'); // wrap to end
      });

      test('peekNext with repeat all wraps around', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.repeatMode = RepeatMode.all;
        q.next(); // b
        expect(q.peekNext()?.uri, 'file:///a.flac'); // wrap peek
      });

      test('peekNext with repeat one returns current', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.repeatMode = RepeatMode.one;
        expect(q.peekNext()?.uri, 'file:///a.flac');
      });
    });

    group('empty queue', () {
      test('next on empty queue returns null', () {
        final q = PlaybackQueue();
        expect(q.next(), isNull);
      });

      test('previous on empty queue returns null', () {
        final q = PlaybackQueue();
        expect(q.previous(), isNull);
      });

      test('peekNext on empty queue returns null', () {
        final q = PlaybackQueue();
        expect(q.peekNext(), isNull);
      });

      test('current on empty queue returns null', () {
        final q = PlaybackQueue();
        expect(q.current, isNull);
      });

      test('clear then navigate does not crash', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.clear();
        expect(q.next(), isNull);
        expect(q.previous(), isNull);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // FakeAudioEngine / AudioEngine tests
  // ═══════════════════════════════════════════════════════════════════════

  group('FakeAudioEngine', () {
    late FakeAudioEngine engine;

    setUp(() async {
      engine = FakeAudioEngine();
      await engine.init();
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('EQ gains are clamped to -12..+12', () async {
      await engine.setEqGains(
        [20, -20, 5, -5, 0, 100, -100, 3, -3, 0],
      );
      expect(engine.eqGains, [12, -12, 5, -5, 0, 12, -12, 3, -3, 0]);
    });

    test('setEqGains rejects non-10 list', () async {
      expect(
        () => engine.setEqGains([1, 2, 3]),
        throwsArgumentError,
      );
    });

    test('preamp is clamped', () async {
      await engine.setPreamp(50);
      expect(engine.preamp, 12.0);
      await engine.setPreamp(-50);
      expect(engine.preamp, -12.0);
    });

    test('volume is clamped to 0..1', () async {
      await engine.setVolume(2.0);
      // Check via stream.
      final values = <double>[];
      final sub = engine.volumeStream.listen(values.add);
      await engine.setVolume(1.5);
      await engine.setVolume(-0.5);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      for (final v in values) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });

    test('open and simulateCompletion cycle', () async {
      final states = <PlaybackState>[];
      final sub = engine.playbackStateStream.listen(states.add);

      await engine.open(_src('test'), autoPlay: true);
      engine.simulateCompletion();

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(states, contains(PlaybackState.playing));
      expect(states, contains(PlaybackState.completed));
    });

    test('simulateError emits on error stream', () async {
      final errors = <AudioError>[];
      final sub = engine.errorStream.listen(errors.add);

      await engine.open(_src('bad'));
      engine.simulateError(
        const AudioError(
          code: AudioErrorCode.fileNotFound,
          message: 'not found',
        ),
      );

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(errors, hasLength(1));
      expect(errors.first.code, AudioErrorCode.fileNotFound);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // PlaybackController tests
  // ═══════════════════════════════════════════════════════════════════════

  group('PlaybackController', () {
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;

    setUp(() async {
      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
    });

    tearDown(() async {
      await controller.dispose();
      await engine.dispose();
    });

    test('auto-advance plays next track on completion', () async {
      queue.add(_src('a'));
      queue.add(_src('b'));
      queue.add(_src('c'));

      final sources = <String?>[];
      final sub = controller.currentStream.listen(
        (s) => sources.add(s?.uri),
      );

      await controller.play(); // plays 'a'
      engine.simulateCompletion(); // auto-advance to 'b'
      await Future<void>.delayed(Duration.zero);
      engine.simulateCompletion(); // auto-advance to 'c'
      await Future<void>.delayed(Duration.zero);
      engine.simulateCompletion(); // end of queue
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();

      // a, b (from advance), c (from advance), null (end)
      expect(sources, [
        'file:///a.flac',
        'file:///b.flac',
        'file:///c.flac',
        null,
      ]);
    });

    test('preloadNext called with correct next item', () async {
      // Use a gapless-capable fake.
      await engine.dispose();
      final gaplessEngine = _GaplessFakeEngine();
      await gaplessEngine.init();
      final ctrl = PlaybackController(engine: gaplessEngine, queue: queue);
      await ctrl.init();

      queue.add(_src('a'));
      queue.add(_src('b'));
      queue.add(_src('c'));

      await ctrl.play();
      expect(gaplessEngine.preloadedNext?.uri, 'file:///b.flac');

      await ctrl.dispose();
      await gaplessEngine.dispose();
    });

    test('error on one track skips to next', () async {
      queue.add(_src('bad'));
      queue.add(_src('good'));

      final errors = <AudioError>[];
      final sources = <String?>[];
      final eSub = controller.errorStream.listen(errors.add);
      final sSub = controller.currentStream.listen(
        (s) => sources.add(s?.uri),
      );

      await controller.play(); // plays 'bad'
      engine.simulateError(
        const AudioError(
          code: AudioErrorCode.unsupportedFormat,
          message: 'bad codec',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await eSub.cancel();
      await sSub.cancel();

      expect(errors, hasLength(1));
      // Should have tried to open 'good' after the error.
      expect(sources.last, 'file:///good.flac');
    });

    test('empty queue does not crash on play', () async {
      // Should complete without throwing.
      await controller.play();
    });

    test('empty queue does not crash on skipNext', () async {
      await controller.skipNext();
    });

    test('empty queue does not crash on skipPrevious', () async {
      await controller.skipPrevious();
    });
  });
}

// ── Test doubles ────────────────────────────────────────────────────────

/// A fake engine that advertises gapless support so [PlaybackController]
/// calls [preloadNext].
class _GaplessFakeEngine extends FakeAudioEngine {
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        exclusiveMode: false,
        gapless: true,
        equalizer: true,
        replayGain: true,
      );
}
