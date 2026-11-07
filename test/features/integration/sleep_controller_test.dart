import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/integration/sleep_controller.dart';
import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  group('SleepController Tests', () {
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController playbackController;
    late FakeSleepInhibitor fakeInhibitor;
    late SettingsStore settingsStore;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_sleep_test_');
      engine = FakeAudioEngine();
      queue = PlaybackQueue();
      playbackController = PlaybackController(engine: engine, queue: queue);
      await playbackController.init();

      fakeInhibitor = FakeSleepInhibitor();
      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();
    });

    tearDown(() async {
      await playbackController.dispose();
      settingsStore.dispose();
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('acquires on play, releases on pause, stop, and track completion', () async {
      final controller = SleepController(
        playbackController: playbackController,
        sleepInhibitor: fakeInhibitor,
        settingsStore: settingsStore,
      );

      const track = AudioSource('file:///music/song.mp3');
      await playbackController.playQueue([track], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeInhibitor.isAcquired, isTrue);
      expect(fakeInhibitor.calls, equals(['acquire']));

      // Pause -> release
      await playbackController.pause();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeInhibitor.isAcquired, isFalse);
      expect(fakeInhibitor.calls, equals(['acquire', 'release']));

      // Resume play -> acquire
      await playbackController.play();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeInhibitor.isAcquired, isTrue);
      expect(fakeInhibitor.calls, equals(['acquire', 'release', 'acquire']));

      // Stop -> release
      await playbackController.stop();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeInhibitor.isAcquired, isFalse);

      // Play again and trigger natural completion
      await playbackController.playQueue([track], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeInhibitor.isAcquired, isTrue);

      engine.simulateCompletion();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeInhibitor.isAcquired, isFalse);

      await controller.dispose();
    });

    test('no double acquire when already acquired and receiving rapid play events', () async {
      final controller = SleepController(
        playbackController: playbackController,
        sleepInhibitor: fakeInhibitor,
        settingsStore: settingsStore,
      );

      const track = AudioSource('file:///music/song.mp3');
      await playbackController.playQueue([track], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeInhibitor.calls.where((c) => c == 'acquire').length, equals(1));

      // Emit playing state again
      await engine.play();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeInhibitor.calls.where((c) => c == 'acquire').length, equals(1));

      await controller.dispose();
    });

    test('setting toggled live acquires or releases immediately', () async {
      final controller = SleepController(
        playbackController: playbackController,
        sleepInhibitor: fakeInhibitor,
        settingsStore: settingsStore,
      );

      const track = AudioSource('file:///music/song.mp3');
      await playbackController.playQueue([track], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeInhibitor.isAcquired, isTrue);

      // Turn setting off live while playing -> release
      settingsStore.update((s) => s.copyWith(preventSleepWhilePlaying: false));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeInhibitor.isAcquired, isFalse);

      // Turn setting back on live while playing -> acquire
      settingsStore.update((s) => s.copyWith(preventSleepWhilePlaying: true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeInhibitor.isAcquired, isTrue);

      await controller.dispose();
    });

    test('releases on controller dispose / shutdown', () async {
      final controller = SleepController(
        playbackController: playbackController,
        sleepInhibitor: fakeInhibitor,
        settingsStore: settingsStore,
      );

      const track = AudioSource('file:///music/song.mp3');
      await playbackController.playQueue([track], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakeInhibitor.isAcquired, isTrue);

      await controller.dispose();
      expect(fakeInhibitor.isAcquired, isFalse);
    });
  });
}
