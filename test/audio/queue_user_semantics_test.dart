import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/session/saved_session.dart';

class _GaplessFakeEngine extends FakeAudioEngine {
  AudioSource? lastPreloadedSource;

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        exclusiveMode: false,
        gapless: true,
        equalizer: true,
        replayGain: true,
      );

  @override
  Future<void> preloadNext(AudioSource? next) async {
    lastPreloadedSource = next;
    await super.preloadNext(next);
  }
}

AudioSource _src(String name) => AudioSource('file:///$name.mp3');

void main() {
  group('Queue User Semantics and Entry Identity (S1)', () {
    late _GaplessFakeEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;

    setUp(() async {
      engine = _GaplessFakeEngine();
      queue = PlaybackQueue(random: Random(1234));
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
    });

    tearDown(() async {
      await controller.dispose();
      await engine.dispose();
    });

    test('album-then-add scenario: playing album track 2 of 10, addToQueue(X) plays X right after track 2, then track 3', () async {
      final albumTracks = List.generate(10, (i) => _src('track_${i + 1}'));
      // Play album starting at track 2 (0-indexed: index 1)
      await controller.playQueue(albumTracks, startIndex: 1);
      expect(controller.queue.currentIndex, 1);
      expect(controller.queue.current?.uri, 'file:///track_2.mp3');

      // addToQueue(X)
      await controller.addToQueue([_src('X')]);

      // Active order must be: track_1, track_2, X, track_3, ..., track_10
      expect(controller.queue.items.map((s) => s.uri).toList(), [
        'file:///track_1.mp3',
        'file:///track_2.mp3',
        'file:///X.mp3',
        'file:///track_3.mp3',
        'file:///track_4.mp3',
        'file:///track_5.mp3',
        'file:///track_6.mp3',
        'file:///track_7.mp3',
        'file:///track_8.mp3',
        'file:///track_9.mp3',
        'file:///track_10.mp3',
      ]);
      expect(controller.queue.current?.uri, 'file:///track_2.mp3');

      // Advancing plays X next, then track_3
      await controller.skipNext();
      expect(controller.queue.current?.uri, 'file:///X.mp3');
      await controller.skipNext();
      expect(controller.queue.current?.uri, 'file:///track_3.mp3');
    });

    test('two addToQueue calls play in order X then Y then track 3', () async {
      final albumTracks = List.generate(5, (i) => _src('track_${i + 1}'));
      await controller.playQueue(albumTracks, startIndex: 1); // track 2
      await controller.addToQueue([_src('X')]);
      await controller.addToQueue([_src('Y')]);

      expect(controller.queue.items.map((s) => s.uri).take(5).toList(), [
        'file:///track_1.mp3',
        'file:///track_2.mp3',
        'file:///X.mp3',
        'file:///Y.mp3',
        'file:///track_3.mp3',
      ]);

      await controller.skipNext();
      expect(controller.queue.current?.uri, 'file:///X.mp3');
      await controller.skipNext();
      expect(controller.queue.current?.uri, 'file:///Y.mp3');
      await controller.skipNext();
      expect(controller.queue.current?.uri, 'file:///track_3.mp3');
    });

    test('playNext twice plays the second one first', () async {
      final albumTracks = List.generate(5, (i) => _src('track_${i + 1}'));
      await controller.playQueue(albumTracks, startIndex: 1); // track 2
      await controller.playNext([_src('firstPlayNext')]);
      await controller.playNext([_src('secondPlayNext')]);

      // Later playNext goes in front of earlier one
      expect(controller.queue.items.map((s) => s.uri).take(5).toList(), [
        'file:///track_1.mp3',
        'file:///track_2.mp3',
        'file:///secondPlayNext.mp3',
        'file:///firstPlayNext.mp3',
        'file:///track_3.mp3',
      ]);

      await controller.skipNext();
      expect(controller.queue.current?.uri, 'file:///secondPlayNext.mp3');
      await controller.skipNext();
      expect(controller.queue.current?.uri, 'file:///firstPlayNext.mp3');
      await controller.skipNext();
      expect(controller.queue.current?.uri, 'file:///track_3.mp3');
    });

    test('the same song added 3 times with shuffle off and on plays 3 times and each queue entry has a distinct id', () async {
      final song = _src('songA');
      await controller.playQueue([song], startIndex: 0);
      await controller.addToQueue([song]);
      await controller.addToQueue([song]);

      expect(controller.queue.length, 3);
      final entries = controller.queue.entries;
      expect(entries[0].id, isNot(equals(entries[1].id)));
      expect(entries[1].id, isNot(equals(entries[2].id)));
      expect(entries[0].id, isNot(equals(entries[2].id)));
      expect(entries.every((e) => e.source.uri == 'file:///songA.mp3'), isTrue);

      // Verify each plays in turn
      expect(controller.queue.current?.uri, 'file:///songA.mp3');
      final firstEntry = controller.queue.currentEntry;

      await controller.skipNext();
      expect(controller.queue.current?.uri, 'file:///songA.mp3');
      final secondEntry = controller.queue.currentEntry;
      expect(secondEntry?.id, isNot(equals(firstEntry?.id)));

      await controller.skipNext();
      expect(controller.queue.current?.uri, 'file:///songA.mp3');
      final thirdEntry = controller.queue.currentEntry;
      expect(thirdEntry?.id, isNot(equals(secondEntry?.id)));

      // Shuffle on and off with 3 copies
      controller.queue.setShuffle(true);
      expect(controller.queue.length, 3);
      controller.queue.setShuffle(false);
      expect(controller.queue.length, 3);
    });

    test('duplicates inside an album context: removing one duplicate removes only that entry', () async {
      final tracks = [_src('songA'), _src('songB'), _src('songA'), _src('songC')];
      await controller.playQueue(tracks, startIndex: 0);

      // Entries 0 and 2 have identical AudioSource but different IDs
      final id0 = controller.queue.entries[0].id;
      final id2 = controller.queue.entries[2].id;
      expect(id0, isNot(equals(id2)));

      // Remove index 2 (the second duplicate)
      await controller.removeFromQueue(2);

      expect(controller.queue.length, 3);
      expect(controller.queue.items.map((s) => s.uri).toList(), [
        'file:///songA.mp3',
        'file:///songB.mp3',
        'file:///songC.mp3',
      ]);
      expect(controller.queue.entries[0].id, id0);
      expect(controller.queue.current?.uri, 'file:///songA.mp3');
    });

    test('moving one duplicate moves only that entry and preserves current entry', () async {
      final tracks = [_src('songA'), _src('songB'), _src('songA'), _src('songC')];
      await controller.playQueue(tracks, startIndex: 0);

      final id0 = controller.queue.entries[0].id;
      final id2 = controller.queue.entries[2].id;

      // Move index 2 to index 1
      await controller.moveInQueue(2, 1);

      expect(controller.queue.items.map((s) => s.uri).toList(), [
        'file:///songA.mp3',
        'file:///songA.mp3',
        'file:///songB.mp3',
        'file:///songC.mp3',
      ]);
      expect(controller.queue.entries[0].id, id0);
      expect(controller.queue.entries[1].id, id2);
      expect(controller.queue.current?.uri, 'file:///songA.mp3');
      expect(controller.queue.currentEntry?.id, id0);
    });

    test('shuffle on and off keeps the user block in front', () async {
      final q = PlaybackQueue(random: Random(42));
      q.replaceAll([_src('c1'), _src('c2'), _src('c3'), _src('c4')], startIndex: 1); // c2 is current
      q.addToQueue([_src('u1'), _src('u2')]);

      expect(q.items.map((s) => s.uri).toList(), [
        'file:///c1.mp3',
        'file:///c2.mp3',
        'file:///u1.mp3',
        'file:///u2.mp3',
        'file:///c3.mp3',
        'file:///c4.mp3',
      ]);

      // Turn shuffle on
      q.setShuffle(true);
      expect(q.current?.uri, 'file:///c2.mp3');
      expect(q.currentIndex, 0);
      // Upcoming user block (u1, u2) MUST follow c2 immediately
      expect(q.entries[1].source.uri, 'file:///u1.mp3');
      expect(q.entries[1].isUserQueued, isTrue);
      expect(q.entries[2].source.uri, 'file:///u2.mp3');
      expect(q.entries[2].isUserQueued, isTrue);

      // Remaining context entries (c1, c3, c4) come after in shuffled order
      final remainingUris = q.items.skip(3).map((s) => s.uri).toSet();
      expect(remainingUris, {'file:///c1.mp3', 'file:///c3.mp3', 'file:///c4.mp3'});

      // Turn shuffle off
      q.setShuffle(false);
      expect(q.current?.uri, 'file:///c2.mp3');
      expect(q.currentIndex, 1);
      expect(q.items.map((s) => s.uri).toList(), [
        'file:///c1.mp3',
        'file:///c2.mp3',
        'file:///u1.mp3',
        'file:///u2.mp3',
        'file:///c3.mp3',
        'file:///c4.mp3',
      ]);
    });

    test('new context keeps upcoming user-queued entries directly after newly started track', () async {
      await controller.playQueue([_src('album1_t1'), _src('album1_t2')], startIndex: 0);
      await controller.addToQueue([_src('userX'), _src('userY')]);

      expect(controller.queue.items.map((s) => s.uri).toList(), [
        'file:///album1_t1.mp3',
        'file:///userX.mp3',
        'file:///userY.mp3',
        'file:///album1_t2.mp3',
      ]);

      // User starts playback of album 2 (tracks: album2_t1, album2_t2, album2_t3)
      await controller.playQueue([_src('album2_t1'), _src('album2_t2'), _src('album2_t3')], startIndex: 0);

      // Since kKeepUserQueueOnNewContext is true, userX and userY must survive right after album2_t1
      expect(controller.queue.items.map((s) => s.uri).toList(), [
        'file:///album2_t1.mp3',
        'file:///userX.mp3',
        'file:///userY.mp3',
        'file:///album2_t2.mp3',
        'file:///album2_t3.mp3',
      ]);
      expect(controller.queue.current?.uri, 'file:///album2_t1.mp3');
      expect(controller.queue.entries[1].isUserQueued, isTrue);
      expect(controller.queue.entries[2].isUserQueued, isTrue);
    });

    test('clearUpcoming removes upcoming user-queued entries too', () async {
      await controller.playQueue([_src('t1'), _src('t2')], startIndex: 0);
      await controller.addToQueue([_src('u1')]);
      expect(controller.queue.length, 3);

      await controller.clearUpcoming();
      expect(controller.queue.length, 1);
      expect(controller.queue.current?.uri, 'file:///t1.mp3');
    });

    test('gapless preload targets the next entry after each mutation', () async {
      await controller.playQueue([_src('t1'), _src('t2'), _src('t3')], startIndex: 0);
      expect(engine.lastPreloadedSource?.uri, 'file:///t2.mp3');

      // playNext inserts X before t2 -> preload targets X
      await controller.playNext([_src('X')]);
      expect(engine.lastPreloadedSource?.uri, 'file:///X.mp3');

      // remove X -> preload targets t2 again
      await controller.removeFromQueue(1);
      expect(engine.lastPreloadedSource?.uri, 'file:///t2.mp3');

      // move t3 to index 1 -> preload targets t3
      await controller.moveInQueue(2, 1);
      expect(engine.lastPreloadedSource?.uri, 'file:///t3.mp3');

      // clearUpcoming -> preload targets null
      await controller.clearUpcoming();
      expect(engine.lastPreloadedSource, isNull);
    });

    test('no use of source equality: two equal sources at different positions are treated distinctly', () async {
      final duplicate = _src('dup');
      await controller.playQueue([_src('head'), duplicate, _src('mid'), duplicate, _src('tail')], startIndex: 1);

      // Current is the first duplicate (index 1)
      final firstDupId = controller.queue.currentEntry?.id;
      final secondDupId = controller.queue.entries[3].id;
      expect(firstDupId, isNot(equals(secondDupId)));

      // Call playNext
      await controller.playNext([_src('insertedNext')]);
      // insertedNext must be at index 2 (directly after first duplicate)
      expect(controller.queue.entries[2].source.uri, 'file:///insertedNext.mp3');
      expect(controller.queue.currentEntry?.id, firstDupId);
      expect(controller.queue.entries[4].id, secondDupId);

      // Toggle shuffle
      controller.queue.setShuffle(true);
      expect(controller.queue.currentEntry?.id, firstDupId);
      controller.queue.setShuffle(false);
      expect(controller.queue.currentEntry?.id, firstDupId);
    });

    test('session round trip preserves isUserQueued flags', () async {
      const itemUser = SavedSessionItem(uri: 'file:///a.mp3', isUserQueued: true);
      const itemContext = SavedSessionItem(uri: 'file:///b.mp3', isUserQueued: false);

      const session = SavedSession(
        queue: [itemUser, itemContext],
        currentIndex: 0,
        currentUri: 'file:///a.mp3',
      );

      final json = session.toJson();
      final restored = SavedSession.fromJson(json);

      expect(restored.queue[0].isUserQueued, isTrue);
      expect(restored.queue[1].isUserQueued, isFalse);
    });
  });
}
