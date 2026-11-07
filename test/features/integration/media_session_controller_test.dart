import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/integration/media_session_controller.dart';
import 'package:aestheticy/library/cover_cache.dart';
import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/platform/media_session_service.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/settings/app_shortcuts.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  group('MediaSessionController Tests', () {
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController playbackController;
    late FakeMediaSessionService fakeMediaService;
    late SettingsStore settingsStore;
    late ArtistNameStore artistNameStore;
    late Directory tempDir;
    late DateTime currentTime;

    DateTime testClock() => currentTime;

    setUp(() async {
      currentTime = DateTime(2026, 11, 7, 12, 0, 0);
      tempDir = await Directory.systemTemp.createTemp('aestheticy_media_test_');
      CoverCache.setCustomDirectory(tempDir.path);

      engine = FakeAudioEngine();
      queue = PlaybackQueue();
      playbackController = PlaybackController(engine: engine, queue: queue);
      await playbackController.init();

      fakeMediaService = FakeMediaSessionService();
      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();

      artistNameStore = ArtistNameStore(directory: tempDir);
      await artistNameStore.init();
      artistNameStore.setEntry('Fairuz', ar: 'فيروز', en: 'Fairuz');
    });

    tearDown(() async {
      CoverCache.resetForTesting();
      await playbackController.dispose();
      await fakeMediaService.dispose();
      settingsStore.dispose();
      artistNameStore.dispose();
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('pushes metadata and applies artist display-name resolution on track change', () async {
      // Create cover file
      final coverFile = File(p.join(tempDir.path, 'album_key_1.jpg'));
      await coverFile.writeAsBytes([1, 2, 3]);

      final controller = MediaSessionController(
        playbackController: playbackController,
        mediaSessionService: fakeMediaService,
        settingsStore: settingsStore,
        artistNameStore: artistNameStore,
        clock: testClock,
      );

      // Play track with Fairuz
      const track = AudioSource(
        'file:///music/song1.mp3',
        extras: {
          'title': 'Nassim',
          'artist': 'Fairuz',
          'album': 'Wahdon',
          'coverKey': 'album_key_1',
        },
      );

      await playbackController.playQueue([track], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeMediaService.lastTitle, equals('Nassim'));
      // English mode resolves Fairuz to Fairuz
      expect(fakeMediaService.lastArtist, equals('Fairuz'));
      expect(fakeMediaService.lastAlbum, equals('Wahdon'));
      expect(fakeMediaService.lastCoverPath, equals(coverFile.path));

      // Switch language to Arabic and play another track
      settingsStore.update((s) => s.copyWith(language: 'ar'));
      const track2 = AudioSource(
        'file:///music/song2.mp3',
        extras: {
          'title': 'Le Beirut',
          'artist': 'Fairuz',
          'album': 'Single',
        },
      );

      await playbackController.playQueue([track2], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeMediaService.lastTitle, equals('Le Beirut'));
      expect(fakeMediaService.lastArtist, equals('فيروز')); // Resolved to Arabic display name!
      expect(fakeMediaService.lastCoverPath, isNull);

      await controller.dispose();
    });

    test('pushes playback status changes (playing, paused, stopped)', () async {
      final controller = MediaSessionController(
        playbackController: playbackController,
        mediaSessionService: fakeMediaService,
        settingsStore: settingsStore,
        artistNameStore: artistNameStore,
        clock: testClock,
      );

      const track = AudioSource('file:///music/song1.mp3');
      await playbackController.playQueue([track], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeMediaService.lastStatus, equals(MediaPlaybackStatus.playing));

      await playbackController.pause();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeMediaService.lastStatus, equals(MediaPlaybackStatus.paused));

      await playbackController.stop();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeMediaService.lastStatus, equals(MediaPlaybackStatus.stopped));

      await controller.dispose();
    });

    test('throttles timeline updates to at most 1 per second, immediate on seek', () async {
      final controller = MediaSessionController(
        playbackController: playbackController,
        mediaSessionService: fakeMediaService,
        settingsStore: settingsStore,
        artistNameStore: artistNameStore,
        clock: testClock,
      );

      const track = AudioSource('file:///music/song1.mp3');
      await playbackController.playQueue([track], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      fakeMediaService.calls.clear();

      // Emit position after 200ms -> should be throttled (not sent)
      currentTime = currentTime.add(const Duration(milliseconds: 200));
      engine.simulateTick(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeMediaService.calls.where((c) => c.startsWith('setTimeline')), isEmpty);

      // Emit position after 1100ms from start -> sent
      currentTime = currentTime.add(const Duration(milliseconds: 900));
      engine.simulateTick(const Duration(milliseconds: 900));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeMediaService.calls.where((c) => c.startsWith('setTimeline')).length, equals(1));

      // Immediate seek -> sent immediately even if 50ms later
      currentTime = currentTime.add(const Duration(milliseconds: 50));
      await playbackController.seek(const Duration(seconds: 45));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeMediaService.calls.where((c) => c.startsWith('setTimeline')).length, equals(2));
      expect(fakeMediaService.lastPosition, equals(const Duration(seconds: 45)));

      await controller.dispose();
    });

    test('media button events call the corresponding PlaybackController method', () async {
      final controller = MediaSessionController(
        playbackController: playbackController,
        mediaSessionService: fakeMediaService,
        settingsStore: settingsStore,
        artistNameStore: artistNameStore,
        clock: testClock,
      );

      const track1 = AudioSource('file:///music/song1.mp3');
      const track2 = AudioSource('file:///music/song2.mp3');
      await playbackController.playQueue([track1, track2], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Button: pause
      fakeMediaService.emitButton(MediaButton.pause);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(playbackController.currentState, equals(PlaybackState.paused));

      // Button: play
      fakeMediaService.emitButton(MediaButton.play);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(playbackController.currentState, equals(PlaybackState.playing));

      // Button: next
      fakeMediaService.emitButton(MediaButton.next);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(playbackController.queue.current?.uri, equals('file:///music/song2.mp3'));

      // Button: previous
      fakeMediaService.emitButton(MediaButton.previous);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(playbackController.queue.current?.uri, equals('file:///music/song1.mp3'));

      // Button: stop
      fakeMediaService.emitButton(MediaButton.stop);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(playbackController.currentState, equals(PlaybackState.idle));

      await controller.dispose();
    });

    test('disabling mediaControls stops updates and re-enabling pushes current state', () async {
      final controller = MediaSessionController(
        playbackController: playbackController,
        mediaSessionService: fakeMediaService,
        settingsStore: settingsStore,
        artistNameStore: artistNameStore,
        clock: testClock,
      );

      const track = AudioSource('file:///music/song1.mp3', extras: {'title': 'Track 1'});
      await playbackController.playQueue([track], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeMediaService.calls, contains('initialize'));
      fakeMediaService.calls.clear();

      // Disable setting live
      settingsStore.update((s) => s.copyWith(mediaControls: false));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeMediaService.calls, contains('disable'));
      fakeMediaService.calls.clear();

      // Play next track while disabled -> no metadata or timeline pushed
      const track2 = AudioSource('file:///music/song2.mp3', extras: {'title': 'Track 2'});
      await playbackController.playQueue([track2], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeMediaService.calls.where((c) => c.startsWith('setMetadata')), isEmpty);

      // Re-enable setting live -> re-initializes and pushes track 2 state
      settingsStore.update((s) => s.copyWith(mediaControls: true));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeMediaService.calls, contains('initialize'));
      expect(fakeMediaService.lastTitle, equals('Track 2'));

      await controller.dispose();
    });

    test('plugin exceptions never break playback and mark integration unavailable', () async {
      fakeMediaService.throwOnSetMetadata = true;

      final controller = MediaSessionController(
        playbackController: playbackController,
        mediaSessionService: fakeMediaService,
        settingsStore: settingsStore,
        artistNameStore: artistNameStore,
        clock: testClock,
      );

      const track = AudioSource('file:///music/song1.mp3', extras: {'title': 'Track 1'});
      // Playing does not throw and completes normally
      await playbackController.playQueue([track], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(playbackController.currentState, equals(PlaybackState.playing));
      expect(controller.isAvailable, isFalse);

      await controller.dispose();
    });
  });

  group('Keyboard Media Key Shortcuts Tests', () {
    test('matchesShortcut matches media keys correctly', () {
      expect(
        matchesShortcut(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.mediaPlayPause,
            logicalKey: LogicalKeyboardKey.mediaPlayPause,
            timeStamp: Duration.zero,
          ),
          AppShortcutId.mediaPlayPause,
        ),
        isTrue,
      );
      expect(
        matchesShortcut(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.mediaTrackNext,
            logicalKey: LogicalKeyboardKey.mediaTrackNext,
            timeStamp: Duration.zero,
          ),
          AppShortcutId.mediaNext,
        ),
        isTrue,
      );
      expect(
        matchesShortcut(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.mediaTrackPrevious,
            logicalKey: LogicalKeyboardKey.mediaTrackPrevious,
            timeStamp: Duration.zero,
          ),
          AppShortcutId.mediaPrevious,
        ),
        isTrue,
      );
    });

    testWidgets('media key shortcuts trigger playback controls when focused', (tester) async {
      final engine = FakeAudioEngine();
      final queue = PlaybackQueue();
      final controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();

      const track1 = AudioSource('file:///music/song1.mp3');
      const track2 = AudioSource('file:///music/song2.mp3');
      await controller.playQueue([track1, track2], startIndex: 0);

      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                shortcutById(AppShortcutId.mediaPlayPause).activator: controller.togglePlayPause,
                shortcutById(AppShortcutId.mediaNext).activator: controller.skipNext,
                shortcutById(AppShortcutId.mediaPrevious).activator: controller.skipPrevious,
              },
              child: Focus(
                focusNode: focusNode,
                autofocus: true,
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      final callbackFocus = tester.widget<Focus>(
        find.descendant(of: find.byType(CallbackShortcuts), matching: find.byType(Focus)).first,
      );

      // Trigger Media Play/Pause key -> pause
      final playPauseResult = callbackFocus.onKeyEvent!(
        focusNode,
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.mediaPlayPause,
          logicalKey: LogicalKeyboardKey.mediaPlayPause,
          timeStamp: Duration.zero,
        ),
      );
      expect(playPauseResult, equals(KeyEventResult.handled));
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.currentState, equals(PlaybackState.paused));

      // Trigger Media Play/Pause key -> resume play
      final resumeResult = callbackFocus.onKeyEvent!(
        focusNode,
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.mediaPlayPause,
          logicalKey: LogicalKeyboardKey.mediaPlayPause,
          timeStamp: Duration.zero,
        ),
      );
      expect(resumeResult, equals(KeyEventResult.handled));
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.currentState, equals(PlaybackState.playing));

      // Trigger Media Next key -> skip to track 2
      final nextResult = callbackFocus.onKeyEvent!(
        focusNode,
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.mediaTrackNext,
          logicalKey: LogicalKeyboardKey.mediaTrackNext,
          timeStamp: Duration.zero,
        ),
      );
      expect(nextResult, equals(KeyEventResult.handled));
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.queue.current?.uri, equals('file:///music/song2.mp3'));

      // Trigger Media Previous key -> back to track 1
      final prevResult = callbackFocus.onKeyEvent!(
        focusNode,
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.mediaTrackPrevious,
          logicalKey: LogicalKeyboardKey.mediaTrackPrevious,
          timeStamp: Duration.zero,
        ),
      );
      expect(prevResult, equals(KeyEventResult.handled));
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.queue.current?.uri, equals('file:///music/song1.mp3'));

      await tester.pumpWidget(const SizedBox());
      focusNode.dispose();
      unawaited(controller.dispose());
      unawaited(engine.dispose());
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
