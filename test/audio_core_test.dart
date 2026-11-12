import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/features/session/session_saver.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

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

    group('mutation cursor preservation', () {
      test('insert before the current item keeps current item active', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        q.next(); // cursor on 'b'
        expect(q.current?.uri, 'file:///b.flac');
        expect(q.currentIndex, 1);

        q.insert(0, _src('x')); // insert before current
        expect(q.current?.uri, 'file:///b.flac');
        expect(q.currentIndex, 2);
        expect(q.items.map((s) => s.uri), [
          'file:///x.flac',
          'file:///a.flac',
          'file:///b.flac',
          'file:///c.flac',
        ]);
      });

      test('remove before the current item keeps current item active', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        q.next(); // cursor on 'b'
        expect(q.current?.uri, 'file:///b.flac');
        expect(q.currentIndex, 1);

        q.remove(0); // remove 'a' before 'b'
        expect(q.current?.uri, 'file:///b.flac');
        expect(q.currentIndex, 0);
        expect(q.items.map((s) => s.uri), [
          'file:///b.flac',
          'file:///c.flac',
        ]);
      });

      test('remove the current item moves cursor to next item at that position', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        q.next(); // cursor on 'b' at index 1
        expect(q.current?.uri, 'file:///b.flac');

        q.remove(1); // remove 'b'
        expect(q.current?.uri, 'file:///c.flac');
        expect(q.currentIndex, 1);
        expect(q.items.map((s) => s.uri), [
          'file:///a.flac',
          'file:///c.flac',
        ]);
      });

      test('remove the last item while it is current clamps cursor to new last item', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        q.next(); // b
        q.next(); // c (last item, index 2)
        expect(q.current?.uri, 'file:///c.flac');
        expect(q.currentIndex, 2);

        q.remove(2); // remove 'c'
        expect(q.current?.uri, 'file:///b.flac');
        expect(q.currentIndex, 1);
        expect(q.items.map((s) => s.uri), [
          'file:///a.flac',
          'file:///b.flac',
        ]);
      });

      test('shuffle on and off preserves the active current item', () {
        final q = PlaybackQueue(random: _seededRandom());
        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        q.add(_src('d'));
        q.next(); // b
        q.next(); // c (index 2)
        expect(q.current?.uri, 'file:///c.flac');
        expect(q.currentIndex, 2);

        q.setShuffle(true);
        expect(q.current?.uri, 'file:///c.flac');
        expect(q.currentIndex, 0); // pinned first in shuffled order

        q.setShuffle(false);
        expect(q.current?.uri, 'file:///c.flac');
        expect(q.currentIndex, 2); // restored to natural position
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

      test('repeat one stays on same item on auto advance, but next/previous move', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.repeatMode = RepeatMode.one;
        // Automatic advance repeats current track
        expect(q.advance()?.uri, 'file:///a.flac');
        expect(q.advance()?.uri, 'file:///a.flac');
        // Manual next moves to neighbouring track
        expect(q.next()?.uri, 'file:///b.flac');
        // Manual previous moves back to neighbouring track
        expect(q.previous()?.uri, 'file:///a.flac');
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

      test('clearUpcoming removes items after cursor, keeping current and history', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        q.add(_src('d'));
        q.next(); // cursor on 'b' (index 1)
        expect(q.current?.uri, 'file:///b.flac');

        q.clearUpcoming();
        expect(q.length, 2);
        expect(q.items.map((s) => s.uri), ['file:///a.flac', 'file:///b.flac']);
        expect(q.current?.uri, 'file:///b.flac');
        expect(q.currentIndex, 1);
        expect(q.peekNext(), isNull);
      });

      test('clearUpcoming clears entire queue if nothing is playing', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.clear();
        q.clearUpcoming();
        expect(q.isEmpty, isTrue);
        expect(q.current, isNull);
      });

      test('clearUpcoming does nothing when current is already the last item', () {
        final q = PlaybackQueue();
        q.add(_src('a'));
        q.add(_src('b'));
        q.next(); // cursor on 'b'
        q.clearUpcoming();
        expect(q.length, 2);
        expect(q.current?.uri, 'file:///b.flac');
      });

      test('clearUpcoming removes upcoming items correctly in shuffled mode', () {
        final q = PlaybackQueue(random: _seededRandom());
        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        q.add(_src('d'));
        q.setShuffle(true);
        final curr = q.current;
        expect(curr, isNotNull);

        q.clearUpcoming();
        expect(q.length, 1);
        expect(q.current, curr);
        expect(q.items.single, curr);
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

    test('a listener that subscribes late still gets the current device list', () async {
      engine.fakeDevices = [
        AudioDevice.auto,
        const AudioDevice(id: 'headphone', name: 'USB Headphones'),
      ];
      final received = await engine.devicesStream.first;
      expect(received, hasLength(2));
      expect(received[1].id, 'headphone');
      expect(engine.devices, hasLength(2));
    });

    test('refreshDevices emits the new list to stream listeners', () async {
      final emittedLists = <List<AudioDevice>>[];
      final sub = engine.devicesStream.listen(emittedLists.add);
      await Future<void>.delayed(Duration.zero);

      engine.fakeDevices = [
        AudioDevice.auto,
        const AudioDevice(id: 'speakers', name: 'Realtek Speakers'),
      ];
      await engine.refreshDevices();
      await Future<void>.delayed(Duration.zero);

      expect(emittedLists.last, hasLength(2));
      expect(emittedLists.last[1].id, 'speakers');
      await sub.cancel();
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

    test('gapless: engine moving on by itself does not reload the track',
        () async {
      final gEngine = _GaplessFakeEngine();
      await gEngine.init();
      final q = PlaybackQueue();
      final ctrl = PlaybackController(engine: gEngine, queue: q);
      await ctrl.init();

      q.add(_src('a'));
      q.add(_src('b'));
      q.add(_src('c'));

      final sources = <String?>[];
      final sub = ctrl.currentStream.listen((s) => sources.add(s?.uri));

      await ctrl.play();
      expect(gEngine.openCallCount, 1);
      expect(gEngine.preloadedNext?.uri, 'file:///b.flac');

      // The engine moves to the preloaded track by itself (gapless).
      gEngine.simulateGaplessAdvance();
      await Future<void>.delayed(Duration.zero);

      // The controller followed along WITHOUT reloading the file.
      expect(gEngine.openCallCount, 1);
      expect(q.current?.uri, 'file:///b.flac');
      expect(gEngine.openedSource?.uri, 'file:///b.flac');
      // ... and prepared the following track.
      expect(gEngine.preloadedNext?.uri, 'file:///c.flac');
      expect(sources, ['file:///a.flac', 'file:///b.flac']);

      await sub.cancel();
      await ctrl.dispose();
      await gEngine.dispose();
    });

    test('tapping the playing track restarts it from the beginning', () async {
      queue.add(_src('a'));
      queue.add(_src('b'));

      await controller.playTrack(0);
      expect(engine.openCallCount, 1);

      engine.simulateTick(const Duration(seconds: 10));
      expect(engine.position, const Duration(seconds: 10));

      // Manual open of the SAME track must reload it, not be ignored.
      await controller.playTrack(0);
      expect(engine.openCallCount, 2);
      expect(engine.position, Duration.zero);
    });

    test('preload failure is reported as a non-fatal error and playback goes on',
        () async {
      final bad = _ThrowingPreloadEngine();
      await bad.init();
      final q = PlaybackQueue();
      final ctrl = PlaybackController(engine: bad, queue: q);
      await ctrl.init();

      q.add(_src('a'));
      q.add(_src('b'));

      final errors = <AudioError>[];
      final sub = ctrl.errorStream.listen(errors.add);

      await ctrl.play();
      await Future<void>.delayed(Duration.zero);

      expect(errors, isNotEmpty);
      expect(errors.first.isFatal, isFalse);
      expect(errors.first.code, AudioErrorCode.engineFailure);
      expect(bad.state, PlaybackState.playing);
      expect(q.current?.uri, 'file:///a.flac');

      await sub.cancel();
      await ctrl.dispose();
      await bad.dispose();
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

    test('resuming from pause does not re-open the track', () async {
      queue.add(_src('track1'));
      await controller.play();
      expect(engine.openCallCount, 1);
      expect(engine.state, PlaybackState.playing);

      await controller.pause();
      expect(engine.state, PlaybackState.paused);

      // Resume via play()
      await controller.play();
      expect(engine.state, PlaybackState.playing);
      expect(engine.openCallCount, 1);

      // Pause and resume via togglePlayPause()
      await controller.togglePlayPause();
      expect(engine.state, PlaybackState.paused);
      await controller.togglePlayPause();
      expect(engine.state, PlaybackState.playing);
      expect(engine.openCallCount, 1);
    });

    test(
      'previous seeks to 00:00 when position > 3s, and goes to previous when <= 3s',
      () async {
        queue.add(_src('song1'));
        queue.add(_src('song2'));

        // Start song 2
        await controller.playTrack(1);
        expect(controller.queue.current?.uri, 'file:///song2.flac');

        // Simulate playing past 3 seconds (5s)
        engine.simulateTick(const Duration(seconds: 5));
        await Future<void>.delayed(Duration.zero);
        expect(engine.position, const Duration(seconds: 5));

        // When > 3s: seek to 00:00, staying on song 2
        await controller.skipPrevious();
        expect(engine.position, Duration.zero);
        expect(controller.queue.current?.uri, 'file:///song2.flac');

        // When <= 3s: skipPrevious goes to song 1
        await controller.skipPrevious();
        expect(controller.queue.current?.uri, 'file:///song1.flac');
      },
    );

    test('non-fatal lyrics error is emitted without skipping track', () async {
      queue.add(_src('song1'));
      queue.add(_src('song2'));

      final errors = <AudioError>[];
      final currentTracks = <String?>[];
      final eSub = controller.errorStream.listen(errors.add);
      final cSub = controller.currentStream.listen(
        (s) => currentTracks.add(s?.uri),
      );

      await controller.play();
      expect(controller.queue.current?.uri, 'file:///song1.flac');

      // Emit non-fatal lyrics error
      engine.simulateError(
        const AudioError(
          code: AudioErrorCode.engineFailure,
          message:
              'Lyrics file failed to load: Can not open external file song1.lrc',
          isFatal: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Error emitted on error stream
      expect(errors, hasLength(1));
      expect(errors.first.isFatal, isFalse);
      expect(errors.first.message, contains('song1.lrc'));

      // Playing track should NOT have skipped
      expect(controller.queue.current?.uri, 'file:///song1.flac');
      expect(engine.openedSource?.uri, 'file:///song1.flac');

      await eSub.cancel();
      await cSub.cancel();
    });

    test('error loop protection stops on failing track under RepeatMode.one', () async {
      queue.add(_src('failing_track'));
      queue.repeatMode = RepeatMode.one;

      final errors = <AudioError>[];
      final eSub = controller.errorStream.listen(errors.add);

      await controller.play();

      // Simulate fatal error on track 1
      engine.simulateError(
        const AudioError(
          code: AudioErrorCode.fileNotFound,
          message: 'File not found',
          isFatal: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // In RepeatMode.one with 1 item, second attempt fails too
      engine.simulateError(
        const AudioError(
          code: AudioErrorCode.fileNotFound,
          message: 'File not found',
          isFatal: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Consecutive fatal errors exceeded queue length (2 > 1) -> stops and emits final error
      expect(
        errors.any((e) => e.message.contains('consecutive fatal errors')),
        isTrue,
      );
      expect(controller.currentState, PlaybackState.idle);

      await eSub.cancel();
    });

    test('error loop protection stops on failing tracks under RepeatMode.all', () async {
      queue.add(_src('fail1'));
      queue.add(_src('fail2'));
      queue.repeatMode = RepeatMode.all;

      final errors = <AudioError>[];
      final eSub = controller.errorStream.listen(errors.add);

      await controller.play();

      // fail1 fatal error
      engine.simulateError(
        const AudioError(
          code: AudioErrorCode.fileNotFound,
          message: 'fail1 error',
          isFatal: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // fail2 fatal error
      engine.simulateError(
        const AudioError(
          code: AudioErrorCode.fileNotFound,
          message: 'fail2 error',
          isFatal: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // 3rd attempt (wrap around to fail1) fails -> stops after 3 fatal errors in a row
      engine.simulateError(
        const AudioError(
          code: AudioErrorCode.fileNotFound,
          message: 'fail1 error again',
          isFatal: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        errors.any((e) => e.message.contains('consecutive fatal errors')),
        isTrue,
      );
      expect(controller.currentState, PlaybackState.idle);

      await eSub.cancel();
    });

    test('manual next and previous move to neighbouring track in RepeatMode.one', () async {
      queue.add(_src('song1'));
      queue.add(_src('song2'));
      queue.repeatMode = RepeatMode.one;

      await controller.play();
      expect(controller.queue.current?.uri, 'file:///song1.flac');

      // Manual skipNext must move to neighbouring track (song2) even in RepeatMode.one
      await controller.skipNext();
      expect(controller.queue.current?.uri, 'file:///song2.flac');

      // Manual skipPrevious must move back to neighbouring track (song1)
      await controller.skipPrevious();
      expect(controller.queue.current?.uri, 'file:///song1.flac');
    });

    group('clearUpcoming', () {
      test('current track is not reopened, upcoming items removed, preload refreshed', () async {
        final gapless = _GaplessFakeEngine();
        await gapless.init();
        final q = PlaybackQueue();
        final ctrl = PlaybackController(engine: gapless, queue: q);
        await ctrl.init();

        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));

        await ctrl.play(); // opens 'a'
        expect(gapless.openCallCount, 1);
        expect(gapless.openedSource?.uri, 'file:///a.flac');
        expect(gapless.preloadedNext?.uri, 'file:///b.flac');

        // Clear upcoming
        await ctrl.clearUpcoming();

        // Current track 'a' must NOT be reopened
        expect(gapless.openCallCount, 1);
        expect(gapless.openedSource?.uri, 'file:///a.flac');
        // Queue now only contains 'a'
        expect(q.items.map((s) => s.uri), ['file:///a.flac']);
        expect(q.current?.uri, 'file:///a.flac');
        // Gapless preload is refreshed to null
        expect(gapless.preloadedNext, isNull);

        await ctrl.dispose();
        await gapless.dispose();
      });

      test('refreshes gapless preload to wrap-around track under RepeatMode.all', () async {
        final gapless = _GaplessFakeEngine();
        await gapless.init();
        final q = PlaybackQueue();
        final ctrl = PlaybackController(engine: gapless, queue: q);
        await ctrl.init();

        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));
        q.repeatMode = RepeatMode.all;

        await ctrl.play(); // 'a'
        await ctrl.skipNext(); // 'b'
        expect(gapless.openedSource?.uri, 'file:///b.flac');
        expect(gapless.preloadedNext?.uri, 'file:///c.flac');

        await ctrl.clearUpcoming();
        expect(q.items.map((s) => s.uri), ['file:///a.flac', 'file:///b.flac']);
        expect(gapless.preloadedNext?.uri, 'file:///a.flac');

        await ctrl.dispose();
        await gapless.dispose();
      });

      test('clears entire queue and stops engine when nothing is playing', () async {
        queue.add(_src('a'));
        queue.add(_src('b'));

        await controller.clearUpcoming();

        expect(queue.isEmpty, isTrue);
        expect(engine.state, PlaybackState.idle);
      });

      test('queue [a,b,c], play a, clearUpcoming, simulate completion => engine ends idle, nothing else opens', () async {
        final gapless = _GaplessFakeEngine();
        await gapless.init();
        final q = PlaybackQueue();
        final ctrl = PlaybackController(engine: gapless, queue: q);
        await ctrl.init();

        q.add(_src('a'));
        q.add(_src('b'));
        q.add(_src('c'));

        await ctrl.play(); // plays 'a'
        expect(gapless.openCallCount, 1);
        expect(gapless.openedSource?.uri, 'file:///a.flac');
        expect(gapless.preloadedNext?.uri, 'file:///b.flac');

        await ctrl.clearUpcoming();
        expect(gapless.preloadedNext, isNull);

        gapless.simulateCompletion();
        await Future<void>.delayed(Duration.zero);

        expect(gapless.state, PlaybackState.idle);
        expect(gapless.openCallCount, 1);
        expect(ctrl.currentState, PlaybackState.idle);

        await ctrl.dispose();
        await gapless.dispose();
      });
    });

    group('playQueue', () {
      test('replaces queue, starts at startIndex, resets preload, keeps gapless working', () async {
        final gapless = _GaplessFakeEngine();
        await gapless.init();
        final q = PlaybackQueue();
        final ctrl = PlaybackController(engine: gapless, queue: q);
        await ctrl.init();

        q.add(_src('old1'));
        q.add(_src('old2'));
        await ctrl.play();
        expect(gapless.openedSource?.uri, 'file:///old1.flac');

        final newSources = [_src('newA'), _src('newB'), _src('newC')];
        await ctrl.playQueue(newSources, startIndex: 1);

        expect(q.current?.uri, 'file:///newB.flac');
        expect(q.currentIndex, 1);
        expect(q.items.map((s) => s.uri), [
          'file:///newA.flac',
          'file:///newB.flac',
          'file:///newC.flac',
        ]);
        expect(gapless.openedSource?.uri, 'file:///newB.flac');
        expect(gapless.preloadedNext?.uri, 'file:///newC.flac');

        await ctrl.dispose();
        await gapless.dispose();
      });

      test('starts at startIndex 0 by default', () async {
        final gapless = _GaplessFakeEngine();
        await gapless.init();
        final q = PlaybackQueue();
        final ctrl = PlaybackController(engine: gapless, queue: q);
        await ctrl.init();

        final sources = [_src('track1'), _src('track2')];
        await ctrl.playQueue(sources);

        expect(q.current?.uri, 'file:///track1.flac');
        expect(gapless.openedSource?.uri, 'file:///track1.flac');
        expect(gapless.preloadedNext?.uri, 'file:///track2.flac');

        await ctrl.dispose();
        await gapless.dispose();
      });

      test('empty list stops playback and empties queue', () async {
        queue.add(_src('a'));
        await controller.play();

        await controller.playQueue([]);
        expect(queue.isEmpty, isTrue);
        expect(engine.state, PlaybackState.idle);
      });
    });

    group('playNext and addToQueue', () {
      test('playNext with an empty queue starts playback at index 0', () async {
        var queueChanged = false;
        controller.queueChangeStream.listen((_) => queueChanged = true);

        await controller.playNext([_src('first'), _src('second')]);

        expect(queue.length, 2);
        expect(queue.current?.uri, 'file:///first.flac');
        expect(engine.state, PlaybackState.playing);
        expect(queueChanged, isTrue);
      });

      test('playNext in the middle inserts items directly after the current track', () async {
        queue.add(_src('a'));
        queue.add(_src('b'));
        queue.add(_src('c'));

        await controller.playTrack(1); // 'b'
        expect(queue.current?.uri, 'file:///b.flac');

        var queueChanged = false;
        controller.queueChangeStream.listen((_) => queueChanged = true);

        await controller.playNext([_src('x'), _src('y')]);

        expect(queueChanged, isTrue);
        expect(queue.current?.uri, 'file:///b.flac');
        expect(queue.items.map((s) => s.uri).toList(), [
          'file:///a.flac',
          'file:///b.flac',
          'file:///x.flac',
          'file:///y.flac',
          'file:///c.flac',
        ]);

        await controller.skipNext();
        expect(queue.current?.uri, 'file:///x.flac');
      });

      test('playNext at the end of the queue inserts after current and allows advancing to it', () async {
        queue.add(_src('a'));
        queue.add(_src('b'));

        await controller.playTrack(1); // 'b' (last track)
        expect(queue.current?.uri, 'file:///b.flac');

        await controller.playNext([_src('z')]);

        expect(queue.items.map((s) => s.uri).toList(), [
          'file:///a.flac',
          'file:///b.flac',
          'file:///z.flac',
        ]);

        await controller.skipNext();
        expect(queue.current?.uri, 'file:///z.flac');
      });

      test('playNext with shuffle on inserts right after current in active playback order', () async {
        queue.add(_src('a'));
        queue.add(_src('b'));
        queue.add(_src('c'));
        queue.add(_src('d'));

        await controller.play();
        queue.setShuffle(true);
        expect(queue.isShuffled, isTrue);
        final currentBefore = queue.current;
        expect(currentBefore, isNotNull);

        await controller.playNext([_src('next_1'), _src('next_2')]);

        expect(queue.isShuffled, isTrue);
        expect(queue.current, currentBefore);

        final items = queue.items;
        final currIdx = queue.currentIndex;
        expect(items[currIdx], currentBefore);
        expect(items[currIdx + 1].uri, 'file:///next_1.flac');
        expect(items[currIdx + 2].uri, 'file:///next_2.flac');

        await controller.skipNext();
        expect(queue.current?.uri, 'file:///next_1.flac');
      });

      test('addToQueue with empty queue behaves like playQueue', () async {
        await controller.addToQueue([_src('one'), _src('two')]);

        expect(queue.length, 2);
        expect(queue.current?.uri, 'file:///one.flac');
        expect(engine.state, PlaybackState.playing);
      });

      test('addToQueue appends to the end of the queue', () async {
        queue.add(_src('a'));
        queue.add(_src('b'));
        await controller.play();

        var queueChanged = false;
        controller.queueChangeStream.listen((_) => queueChanged = true);

        await controller.addToQueue([_src('end1'), _src('end2')]);

        expect(queueChanged, isTrue);
        expect(queue.items.map((s) => s.uri).toList(), [
          'file:///a.flac',
          'file:///b.flac',
          'file:///end1.flac',
          'file:///end2.flac',
        ]);
      });
    });

    group('PlaybackController S1 queue operations (moveInQueue, removeFromQueue, playNextFromQueue)', () {
      test('move before, after, and around current item keeps current item and updates index math', () async {
        await controller.playQueue([_src('a'), _src('b'), _src('c'), _src('d'), _src('e')], startIndex: 2);
        expect(queue.current?.uri, 'file:///c.flac');
        expect(queue.currentIndex, 2);

        // Move before current (0 -> 1)
        await controller.moveInQueue(0, 1);
        expect(queue.current?.uri, 'file:///c.flac');
        expect(queue.currentIndex, 2);
        expect(queue.items.map((s) => s.uri), [
          'file:///b.flac',
          'file:///a.flac',
          'file:///c.flac',
          'file:///d.flac',
          'file:///e.flac',
        ]);

        // Move after current (4 -> 3)
        await controller.moveInQueue(4, 3);
        expect(queue.current?.uri, 'file:///c.flac');
        expect(queue.currentIndex, 2);
        expect(queue.items.map((s) => s.uri), [
          'file:///b.flac',
          'file:///a.flac',
          'file:///c.flac',
          'file:///e.flac',
          'file:///d.flac',
        ]);

        // Move around current: from before (0) to after (4)
        await controller.moveInQueue(0, 4);
        expect(queue.current?.uri, 'file:///c.flac');
        expect(queue.currentIndex, 1);
        expect(queue.items.map((s) => s.uri), [
          'file:///a.flac',
          'file:///c.flac',
          'file:///e.flac',
          'file:///d.flac',
          'file:///b.flac',
        ]);

        // Move around current: from after (4) to before (0)
        await controller.moveInQueue(4, 0);
        expect(queue.current?.uri, 'file:///c.flac');
        expect(queue.currentIndex, 2);
        expect(queue.items.map((s) => s.uri), [
          'file:///b.flac',
          'file:///a.flac',
          'file:///c.flac',
          'file:///e.flac',
          'file:///d.flac',
        ]);
      });

      test('move with shuffle on keeps active playback order and cursor index math', () async {
        await controller.playQueue([_src('a'), _src('b'), _src('c'), _src('d'), _src('e')], startIndex: 0);
        queue.setShuffle(true);
        expect(queue.isShuffled, isTrue);
        expect(queue.currentIndex, 0);
        expect(queue.current?.uri, 'file:///a.flac');

        final activeItems = List<AudioSource>.from(queue.items);
        final item2 = activeItems[2];
        final item3 = activeItems[3];

        await controller.moveInQueue(2, 3);
        expect(queue.current?.uri, 'file:///a.flac');
        expect(queue.currentIndex, 0);
        expect(queue.items[2].uri, item3.uri);
        expect(queue.items[3].uri, item2.uri);
      });

      test('moving the current item does not call engine.open', () async {
        await controller.playQueue([_src('a'), _src('b'), _src('c')], startIndex: 1);
        expect(engine.openCallCount, 1);
        expect(queue.current?.uri, 'file:///b.flac');

        await controller.moveInQueue(1, 0);
        expect(queue.current?.uri, 'file:///b.flac');
        expect(queue.currentIndex, 0);
        expect(engine.openCallCount, 1); // Not reopened
      });

      test('remove a non-current item (before and after cursor) keeps playing without engine.open', () async {
        await controller.playQueue([_src('a'), _src('b'), _src('c'), _src('d')], startIndex: 2);
        expect(engine.openCallCount, 1);
        expect(queue.current?.uri, 'file:///c.flac');
        expect(queue.currentIndex, 2);

        // Remove before cursor (index 0)
        await controller.removeFromQueue(0);
        expect(engine.openCallCount, 1);
        expect(queue.current?.uri, 'file:///c.flac');
        expect(queue.currentIndex, 1);
        expect(queue.items.map((s) => s.uri), ['file:///b.flac', 'file:///c.flac', 'file:///d.flac']);

        // Remove after cursor (index 2)
        await controller.removeFromQueue(2);
        expect(engine.openCallCount, 1);
        expect(queue.current?.uri, 'file:///c.flac');
        expect(queue.currentIndex, 1);
        expect(queue.items.map((s) => s.uri), ['file:///b.flac', 'file:///c.flac']);
      });

      test('remove the current item opens the new current exactly once', () async {
        await controller.playQueue([_src('a'), _src('b'), _src('c')], startIndex: 1);
        expect(engine.openCallCount, 1);
        expect(queue.current?.uri, 'file:///b.flac');

        await controller.removeFromQueue(1);
        expect(engine.openCallCount, 2);
        expect(queue.current?.uri, 'file:///c.flac');
        expect(queue.currentIndex, 1);
        expect(queue.items.map((s) => s.uri), ['file:///a.flac', 'file:///c.flac']);
      });

      test('remove the last item while current moves cursor to last valid one and opens it', () async {
        await controller.playQueue([_src('a'), _src('b'), _src('c')], startIndex: 2);
        expect(engine.openCallCount, 1);
        expect(queue.current?.uri, 'file:///c.flac');

        await controller.removeFromQueue(2);
        expect(engine.openCallCount, 2);
        expect(queue.current?.uri, 'file:///b.flac');
        expect(queue.currentIndex, 1);
        expect(queue.items.map((s) => s.uri), ['file:///a.flac', 'file:///b.flac']);
      });

      test('remove the only item stops engine and clears current track', () async {
        await controller.playQueue([_src('only')]);
        expect(queue.length, 1);
        expect(queue.current?.uri, 'file:///only.flac');

        AudioSource? lastEmitted;
        final sub = controller.currentStream.listen((s) => lastEmitted = s);

        await controller.removeFromQueue(0);
        expect(queue.isEmpty, isTrue);
        expect(queue.current, isNull);
        expect(engine.state, PlaybackState.idle);
        expect(lastEmitted, isNull);

        await sub.cancel();
      });

      test('invalid indexes are ignored by move, remove, and playNextFromQueue', () async {
        await controller.playQueue([_src('a'), _src('b')], startIndex: 0);

        await controller.removeFromQueue(-1);
        await controller.removeFromQueue(5);
        expect(queue.length, 2);

        await controller.moveInQueue(-1, 0);
        await controller.moveInQueue(0, -1);
        await controller.moveInQueue(0, 5);
        await controller.moveInQueue(5, 0);
        expect(queue.items.map((s) => s.uri), ['file:///a.flac', 'file:///b.flac']);

        await controller.playNextFromQueue(-1);
        await controller.playNextFromQueue(5);
        expect(queue.items.map((s) => s.uri), ['file:///a.flac', 'file:///b.flac']);
      });

      test('playNextFromQueue moves item to directly after current (no-op if current or already next)', () async {
        await controller.playQueue([_src('a'), _src('b'), _src('c'), _src('d')], startIndex: 1);
        expect(queue.current?.uri, 'file:///b.flac');
        expect(queue.currentIndex, 1);

        // Move d (index 3) to after b -> should be placed at index 2
        await controller.playNextFromQueue(3);
        expect(queue.current?.uri, 'file:///b.flac');
        expect(queue.currentIndex, 1);
        expect(queue.items.map((s) => s.uri), [
          'file:///a.flac',
          'file:///b.flac',
          'file:///d.flac',
          'file:///c.flac',
        ]);

        // Move a (index 0) to after b -> should be placed at index 1 (b shifts to 0)
        await controller.playNextFromQueue(0);
        expect(queue.current?.uri, 'file:///b.flac');
        expect(queue.currentIndex, 0);
        expect(queue.items.map((s) => s.uri), [
          'file:///b.flac',
          'file:///a.flac',
          'file:///d.flac',
          'file:///c.flac',
        ]);

        // Already current (0) -> no-op
        await controller.playNextFromQueue(0);
        expect(queue.items.map((s) => s.uri), [
          'file:///b.flac',
          'file:///a.flac',
          'file:///d.flac',
          'file:///c.flac',
        ]);

        // Already next (1) -> no-op
        await controller.playNextFromQueue(1);
        expect(queue.items.map((s) => s.uri), [
          'file:///b.flac',
          'file:///a.flac',
          'file:///d.flac',
          'file:///c.flac',
        ]);
      });

      test('preload is refreshed after each queue operation', () async {
        await engine.dispose();
        final gaplessEngine = _GaplessFakeEngine();
        await gaplessEngine.init();
        final ctrl = PlaybackController(engine: gaplessEngine, queue: queue);
        await ctrl.init();

        await ctrl.playQueue([_src('a'), _src('b'), _src('c'), _src('d')], startIndex: 0);
        expect(gaplessEngine.preloadedNext?.uri, 'file:///b.flac');

        // Move c (index 2) to 1 -> new next is c
        await ctrl.moveInQueue(2, 1);
        expect(gaplessEngine.preloadedNext?.uri, 'file:///c.flac');

        // Remove c (index 1) -> new next is b
        await ctrl.removeFromQueue(1);
        expect(gaplessEngine.preloadedNext?.uri, 'file:///b.flac');

        // playNextFromQueue on d (index 2) -> new next is d
        await ctrl.playNextFromQueue(2);
        expect(gaplessEngine.preloadedNext?.uri, 'file:///d.flac');

        // clearUpcoming -> new next is null
        await ctrl.clearUpcoming();
        expect(gaplessEngine.preloadedNext, isNull);

        await ctrl.dispose();
        await gaplessEngine.dispose();
      });

      test('queueChangeStream emits once per operation', () async {
        await controller.playQueue([_src('a'), _src('b'), _src('c'), _src('d')], startIndex: 0);

        var emissions = 0;
        final sub = controller.queueChangeStream.listen((_) => emissions++);

        await controller.moveInQueue(2, 1);
        expect(emissions, 1);

        await controller.playNextFromQueue(3);
        expect(emissions, 2);

        await controller.removeFromQueue(1);
        expect(emissions, 3);

        await controller.clearUpcoming();
        expect(emissions, 4);

        await sub.cancel();
      });

      test('session snapshot reflects a reorder', () async {
        final tempDir = Directory.systemTemp.createTempSync('session_reorder_test_');
        addTearDown(() {
          try {
            if (tempDir.existsSync()) {
              tempDir.deleteSync(recursive: true);
            }
          } catch (_) {}
        });

        final settingsStore = SettingsStore(directory: tempDir);
        await settingsStore.init();
        final sessionStore = SessionStore(directory: tempDir);
        await sessionStore.init();

        final saver = SessionSaver(
          controller: controller,
          sessionStore: sessionStore,
          settingsStore: settingsStore,
        );

        await controller.playQueue([_src('a'), _src('b'), _src('c')], startIndex: 0);
        expect(sessionStore.session.queue.map((i) => i.uri), [
          'file:///a.flac',
          'file:///b.flac',
          'file:///c.flac',
        ]);

        await controller.moveInQueue(2, 1);
        expect(sessionStore.session.queue.map((i) => i.uri), [
          'file:///a.flac',
          'file:///c.flac',
          'file:///b.flac',
        ]);

        await saver.dispose();
        sessionStore.dispose();
        settingsStore.dispose();
      });
    });

    group('S6c Paused jump & serialization', () {
      test('rapid paused jump to B then C leaves C opened, not superseded B or resumed A', () async {
        final slowEngine = _DelayedJumpFakeEngine(
          openDelays: const {
            'file:///b.flac': Duration(milliseconds: 60),
            'file:///c.flac': Duration(milliseconds: 5),
          },
          playDelay: const Duration(milliseconds: 40),
        );
        await slowEngine.init();
        final q = PlaybackQueue()..add(_src('a'))..add(_src('b'))..add(_src('c'));
        final ctrl = PlaybackController(engine: slowEngine, queue: q);
        await ctrl.init();

        await ctrl.playTrack(0);
        await ctrl.pause();
        await Future<void>.delayed(Duration.zero);
        expect(slowEngine.state, PlaybackState.paused);

        slowEngine.events.clear();
        unawaited(ctrl.play());
        unawaited(ctrl.playTrack(1));
        await ctrl.playTrack(2);
        await Future<void>.delayed(const Duration(milliseconds: 90));

        expect(ctrl.queue.current?.uri, 'file:///c.flac');
        expect(slowEngine.openedSource?.uri, 'file:///c.flac');
        expect(
          slowEngine.events.where((e) => e == 'play:file:///a.flac'),
          isEmpty,
        );

        await ctrl.dispose();
        await slowEngine.dispose();
      });
    });

    group('S6c Smooth transitions & fadeGain', () {
      test('fadeGain multiplies userVolume without mutating currentVolume or volumeStream, and mid-fade setVolume applies cleanly', () async {
        final spy = _TimingSpyFakeEngine();
        await spy.init();
        await spy.setVolume(0.8);

        final volumeEmissions = <double>[];
        final vSub = spy.volumeStream.listen(volumeEmissions.add);

        final q = PlaybackQueue()..add(_src('a'));
        final ctrl = PlaybackController(
          engine: spy,
          queue: q,
          smoothTransitions: true,
        );
        await ctrl.init();

        await ctrl.play();
        expect(spy.currentVolume, closeTo(0.8, 1e-6));
        expect(spy.fadeGain, closeTo(0.0, 1e-6));
        expect(spy.effectiveVolume, closeTo(0.0, 1e-6));

        // Change user volume halfway through the 250ms fade-in.
        await Future<void>.delayed(const Duration(milliseconds: 90));
        final midGain = spy.fadeGain;
        expect(midGain, greaterThan(0.0));
        expect(midGain, lessThan(1.0));

        await spy.setVolume(0.5);
        expect(spy.effectiveVolume, closeTo(0.5 * midGain, 1e-6));

        await Future<void>.delayed(const Duration(milliseconds: 220));
        expect(spy.fadeGain, closeTo(1.0, 1e-6));
        expect(spy.currentVolume, closeTo(0.5, 1e-6));
        expect(spy.effectiveVolume, closeTo(0.5, 1e-6));
        expect(volumeEmissions, [0.5]);

        await vSub.cancel();
        await ctrl.dispose();
        await spy.dispose();
      });

      test('stopped -> play ramps fadeGain from 0 to 1 over ~250ms, and paused -> resume over ~120ms', () async {
        final spy = _TimingSpyFakeEngine();
        await spy.init();
        final q = PlaybackQueue()..add(_src('a'));
        final ctrl = PlaybackController(
          engine: spy,
          queue: q,
          smoothTransitions: true,
        );
        await ctrl.init();

        // 1. Stopped -> play (~250ms fade-in)
        await ctrl.play();
        expect(spy.fadeGain, closeTo(0.0, 1e-6));
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(spy.fadeGain, greaterThan(0.05));
        expect(spy.fadeGain, lessThan(0.95));

        await Future<void>.delayed(const Duration(milliseconds: 220));
        expect(spy.fadeGain, closeTo(1.0, 1e-6));
        // Should be monotonically non-decreasing.
        for (var i = 1; i < spy.fadeGainHistory.length; i++) {
          expect(
            spy.fadeGainHistory[i],
            greaterThanOrEqualTo(spy.fadeGainHistory[i - 1] - 1e-9),
          );
        }

        // 2. Pause while playing: 100ms fade-out -> pause -> restore 1.0
        spy.events.clear();
        spy.fadeGainHistory.clear();
        final swPause = Stopwatch()..start();
        await ctrl.pause();
        swPause.stop();

        expect(swPause.elapsedMilliseconds, greaterThanOrEqualTo(75));
        expect(spy.state, PlaybackState.paused);
        expect(spy.fadeGain, closeTo(1.0, 1e-6));
        // Second-to-last fadeGain before restoring 1.0 must have reached 0.0 before pause.
        final pauseIdx = spy.events.indexWhere((e) => e.startsWith('pause:'));
        final zeroBeforePause = spy.events.sublist(0, pauseIdx).where((e) => e == 'gain:0.000');
        expect(zeroBeforePause, isNotEmpty);

        // 3. Paused -> resume (~120ms fade-in, no re-open)
        final openBefore = spy.openCallCount;
        spy.fadeGainHistory.clear();
        await ctrl.play();
        expect(spy.openCallCount, openBefore);
        expect(spy.fadeGain, closeTo(0.0, 1e-6));
        await Future<void>.delayed(const Duration(milliseconds: 160));
        expect(spy.fadeGain, closeTo(1.0, 1e-6));

        await ctrl.dispose();
        await spy.dispose();
      });

      test('manual jump while playing does 120ms fade-out + 60ms silent gap + 250ms fade-in', () async {
        final spy = _TimingSpyFakeEngine();
        await spy.init();
        final q = PlaybackQueue()..add(_src('a'))..add(_src('b'));
        final ctrl = PlaybackController(
          engine: spy,
          queue: q,
          smoothTransitions: true,
        );
        await ctrl.init();

        await ctrl.playTrack(0);
        await Future<void>.delayed(const Duration(milliseconds: 280));
        expect(spy.fadeGain, closeTo(1.0, 1e-6));

        spy.events.clear();
        spy.stopwatch.reset();
        spy.stopwatch.start();
        spy.zeroGainTimestampMs = null;
        spy.lastOpenTimestampMs = null;

        await ctrl.skipNext();
        expect(spy.openedSource?.uri, 'file:///b.flac');
        // Open of B must wait for ~120ms fade-out + ~60ms gap (~180ms total),
        // with at least ~50ms spent silent at 0.0 before B opens.
        expect(spy.zeroGainTimestampMs, isNotNull);
        expect(spy.lastOpenTimestampMs, isNotNull);
        expect(spy.zeroGainTimestampMs!, greaterThanOrEqualTo(90));
        expect(
          spy.lastOpenTimestampMs! - spy.zeroGainTimestampMs!,
          greaterThanOrEqualTo(45),
        );
        expect(spy.fadeGain, closeTo(0.0, 1e-6));

        await Future<void>.delayed(const Duration(milliseconds: 280));
        expect(spy.fadeGain, closeTo(1.0, 1e-6));

        await ctrl.dispose();
        await spy.dispose();
      });

      test('manual jump while paused does not fade out paused track or unpause it', () async {
        final spy = _TimingSpyFakeEngine();
        await spy.init();
        final q = PlaybackQueue()..add(_src('a'))..add(_src('b'));
        final ctrl = PlaybackController(
          engine: spy,
          queue: q,
          smoothTransitions: true,
        );
        await ctrl.init();

        await ctrl.playTrack(0);
        await Future<void>.delayed(const Duration(milliseconds: 280));
        await ctrl.pause();
        await Future<void>.delayed(Duration.zero);

        spy.events.clear();
        final sw = Stopwatch()..start();
        await ctrl.playTrack(1);
        sw.stop();

        // Paused jump should open B promptly (< 100ms, no 120ms+60ms fade-out/gap)
        // and never call engine.play() on paused A.
        expect(sw.elapsedMilliseconds, lessThan(100));
        expect(spy.openedSource?.uri, 'file:///b.flac');
        expect(spy.events.where((e) => e.startsWith('play:')), isEmpty);
        expect(spy.fadeGain, closeTo(0.0, 1e-6));

        await Future<void>.delayed(const Duration(milliseconds: 280));
        expect(spy.fadeGain, closeTo(1.0, 1e-6));

        await ctrl.dispose();
        await spy.dispose();
      });

      test('stop/shutdown fade-out completes within <= 150ms and restores fadeGain to 1.0', () async {
        final spy = _TimingSpyFakeEngine();
        await spy.init();
        final q = PlaybackQueue()..add(_src('a'));
        final ctrl = PlaybackController(
          engine: spy,
          queue: q,
          smoothTransitions: true,
        );
        await ctrl.init();

        await ctrl.play();
        await Future<void>.delayed(const Duration(milliseconds: 280));

        final sw = Stopwatch()..start();
        await ctrl.stop();
        sw.stop();

        expect(sw.elapsedMilliseconds, lessThanOrEqualTo(150));
        expect(spy.state, PlaybackState.idle);
        expect(spy.fadeGain, closeTo(1.0, 1e-6));

        await ctrl.dispose();
        await spy.dispose();
      });

      test('seek, gapless next, and smoothTransitions=false skip fades', () async {
        final gaplessSpy = _GaplessTimingSpyFakeEngine();
        await gaplessSpy.init();
        final q = PlaybackQueue()..add(_src('a'))..add(_src('b'))..add(_src('c'));
        final ctrl = PlaybackController(
          engine: gaplessSpy,
          queue: q,
          smoothTransitions: true,
        );
        await ctrl.init();

        await ctrl.play();
        await Future<void>.delayed(const Duration(milliseconds: 280));
        expect(gaplessSpy.fadeGain, closeTo(1.0, 1e-6));

        // 1. Seek does not drop fadeGain
        gaplessSpy.fadeGainHistory.clear();
        await ctrl.seek(const Duration(seconds: 40));
        expect(gaplessSpy.fadeGainHistory, isEmpty);
        expect(gaplessSpy.fadeGain, closeTo(1.0, 1e-6));

        // 2. Gapless completion skips fade and stays at 1.0
        gaplessSpy.fadeGainHistory.clear();
        gaplessSpy.simulateCompletion();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(q.current?.uri, 'file:///b.flac');
        expect(gaplessSpy.fadeGainHistory, isEmpty);
        expect(gaplessSpy.fadeGain, closeTo(1.0, 1e-6));

        // 3. smoothTransitions = false skips fade on manual jump and restores mid-fade
        ctrl.smoothTransitions = false;
        final sw = Stopwatch()..start();
        await ctrl.skipNext();
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(50));
        expect(gaplessSpy.openedSource?.uri, 'file:///c.flac');
        expect(gaplessSpy.fadeGain, closeTo(1.0, 1e-6));

        // 4. Toggling smoothTransitions off mid-fade cancels fade-in and restores 1.0
        ctrl.smoothTransitions = true;
        await ctrl.playTrack(0);
        expect(gaplessSpy.fadeGain, closeTo(0.0, 1e-6));
        ctrl.smoothTransitions = false;
        await Future<void>.delayed(Duration.zero);
        expect(gaplessSpy.fadeGain, closeTo(1.0, 1e-6));

        await ctrl.dispose();
        await gaplessSpy.dispose();
      });

      test('rapid interruption mid-fade switches cleanly without snapping up and dispose cancels timers', () async {
        final spy = _TimingSpyFakeEngine();
        await spy.init();
        final q = PlaybackQueue()..add(_src('a'))..add(_src('b'))..add(_src('c'));
        final ctrl = PlaybackController(
          engine: spy,
          queue: q,
          smoothTransitions: true,
        );
        await ctrl.init();

        await ctrl.playTrack(0);
        await Future<void>.delayed(const Duration(milliseconds: 280));

        // Start skipNext (enters 120ms fade-out), interrupt mid-way with skipNext to C.
        final first = ctrl.skipNext();
        await Future<void>.delayed(const Duration(milliseconds: 45));
        final gainBeforeInterrupt = spy.fadeGain;
        expect(gainBeforeInterrupt, lessThan(1.0));
        spy.fadeGainHistory.clear();
        await ctrl.skipNext();
        await first;

        // First fadeGain step after interrupt must not jump up toward 1.0.
        for (final g in spy.fadeGainHistory) {
          expect(g, lessThanOrEqualTo(gainBeforeInterrupt + 1e-6));
        }
        expect(spy.openedSource?.uri, 'file:///c.flac');

        // Dispose immediately mid-fade-in and ensure no timer errors occur.
        await ctrl.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await spy.dispose();
      });
    });
  });
}

// ── Test doubles ────────────────────────────────────────────────────────

/// A fake engine with configurable async delays on [open] and [play] to expose
/// out-of-order transition races.
class _DelayedJumpFakeEngine extends FakeAudioEngine {
  final Map<String, Duration> openDelays;
  final Duration? playDelay;
  final List<String> events = [];

  _DelayedJumpFakeEngine({
    this.openDelays = const {},
    this.playDelay,
  });

  @override
  Future<void> open(
    AudioSource source, {
    bool autoPlay = false,
    bool continuingGapless = false,
  }) async {
    final delay = openDelays[source.uri];
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    events.add('open:${source.uri}:$autoPlay');
    await super.open(
      source,
      autoPlay: autoPlay,
      continuingGapless: continuingGapless,
    );
  }

  @override
  Future<void> play() async {
    final uri = openedSource?.uri;
    if (playDelay != null) {
      await Future<void>.delayed(playDelay!);
    }
    events.add('play:$uri');
    await super.play();
  }
}

/// Records [setFadeGain], [open], [play], and [pause] sequencing with elapsed timing.
class _TimingSpyFakeEngine extends FakeAudioEngine {
  final Stopwatch stopwatch = Stopwatch()..start();
  final List<String> events = [];
  int? zeroGainTimestampMs;
  int? lastOpenTimestampMs;

  @override
  Future<void> setFadeGain(double gain) async {
    await super.setFadeGain(gain);
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
    events.add('pause:${openedSource?.uri}');
    await super.pause();
  }
}

/// Gapless-capable variant of [_TimingSpyFakeEngine].
class _GaplessTimingSpyFakeEngine extends _TimingSpyFakeEngine {
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        exclusiveMode: false,
        gapless: true,
        equalizer: true,
        replayGain: true,
      );
}

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

/// A gapless-capable fake whose preload always fails.
class _ThrowingPreloadEngine extends _GaplessFakeEngine {
  @override
  Future<void> preloadNext(AudioSource? next) async {
    throw StateError('preload failed');
  }
}
