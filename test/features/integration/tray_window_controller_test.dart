import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/integration/app_shutdown.dart';
import 'package:aestheticy/features/integration/tray_window_controller.dart';
import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/platform/tray_service.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  group('TrayWindowController Tests', () {
    late FakeWindowService fakeWindow;
    late FakeTrayService fakeTray;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController playbackController;
    late SettingsStore settingsStore;
    late AppShutdownCoordinator shutdownCoordinator;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_tray_test_');
      fakeWindow = FakeWindowService();
      fakeTray = FakeTrayService();
      engine = FakeAudioEngine();
      queue = PlaybackQueue();
      playbackController = PlaybackController(engine: engine, queue: queue);
      await playbackController.init();

      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();

      shutdownCoordinator = AppShutdownCoordinator(
        settingsStore: settingsStore,
        mediaSessionService: FakeMediaSessionService(),
        sleepInhibitor: FakeSleepInhibitor(),
        trayService: fakeTray,
      );
    });

    tearDown(() async {
      await playbackController.dispose();
      await fakeWindow.dispose();
      await fakeTray.dispose();
      settingsStore.dispose();
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('close request in quit mode runs shutdown then destroy', () async {
      final controller = TrayWindowController(
        windowService: fakeWindow,
        trayService: fakeTray,
        playbackController: playbackController,
        settingsStore: settingsStore,
        shutdownCoordinator: shutdownCoordinator,
      );
      await controller.init();

      expect(settingsStore.settings.closeBehavior, equals('quit'));
      expect(fakeWindow.isPreventClose, isTrue);

      fakeWindow.emitCloseRequested();
      await pumpEventQueue();
      await controller.lastCloseFuture;

      expect(shutdownCoordinator.hasShutdown, isTrue);
      expect(fakeWindow.isDestroyed, isTrue);

      await controller.dispose();
    });

    test('close request in tray mode hides window and does not destroy or stop playback', () async {
      settingsStore.update((s) => s.copyWith(closeBehavior: 'tray'));
      await settingsStore.flush();

      final controller = TrayWindowController(
        windowService: fakeWindow,
        trayService: fakeTray,
        playbackController: playbackController,
        settingsStore: settingsStore,
        shutdownCoordinator: shutdownCoordinator,
      );
      await controller.init();

      const track = AudioSource('file:///music/song.mp3');
      await playbackController.playQueue([track], startIndex: 0);

      fakeWindow.emitCloseRequested();
      await pumpEventQueue();
      await controller.lastCloseFuture;

      expect(fakeWindow.isVisible, isFalse);
      expect(fakeWindow.isDestroyed, isFalse);
      expect(playbackController.currentState, equals(PlaybackState.playing));
      expect(shutdownCoordinator.hasShutdown, isFalse);

      await controller.dispose();
    });

    test('tray left click toggles window between hide and show', () async {
      settingsStore.update((s) => s.copyWith(closeBehavior: 'tray'));
      await settingsStore.flush();

      final controller = TrayWindowController(
        windowService: fakeWindow,
        trayService: fakeTray,
        playbackController: playbackController,
        settingsStore: settingsStore,
        shutdownCoordinator: shutdownCoordinator,
      );
      await controller.init();

      // Window starts visible
      expect(controller.isWindowVisible, isTrue);

      // Click tray icon -> hides window
      fakeTray.emitEvent(const TrayEvent.iconClicked());
      await pumpEventQueue();
      await controller.lastTrayEventFuture;
      expect(fakeWindow.isVisible, isFalse);
      expect(controller.isWindowVisible, isFalse);

      // Click tray icon again -> shows and focuses window
      fakeTray.emitEvent(const TrayEvent.iconClicked());
      await pumpEventQueue();
      await controller.lastTrayEventFuture;
      expect(fakeWindow.isVisible, isTrue);
      expect(fakeWindow.isFocused, isTrue);
      expect(controller.isWindowVisible, isTrue);

      await controller.dispose();
    });

    test('tray menu labels follow the language and playback state', () async {
      settingsStore.update((s) => s.copyWith(closeBehavior: 'tray', language: 'en'));
      await settingsStore.flush();

      final controller = TrayWindowController(
        windowService: fakeWindow,
        trayService: fakeTray,
        playbackController: playbackController,
        settingsStore: settingsStore,
        shutdownCoordinator: shutdownCoordinator,
      );
      await controller.init();

      // Idle: label is Play
      expect(fakeTray.currentLabels?.playPause, equals('Play'));
      expect(fakeTray.currentLabels?.show, equals('Show'));

      // Play track: label changes to Pause
      const track = AudioSource('file:///music/song.mp3');
      await playbackController.playQueue([track], startIndex: 0);
      await pumpEventQueue();
      expect(fakeTray.currentLabels?.playPause, equals('Pause'));

      // Switch language to Arabic: labels update in Arabic
      settingsStore.update((s) => s.copyWith(language: 'ar'));
      await pumpEventQueue();
      expect(fakeTray.currentLabels?.playPause, equals('إيقاف مؤقت'));
      expect(fakeTray.currentLabels?.show, equals('إظهار'));
      expect(fakeTray.currentLabels?.quit, equals('إنهاء'));

      await controller.dispose();
    });

    test('each menu item triggers the right action', () async {
      settingsStore.update((s) => s.copyWith(closeBehavior: 'tray'));
      await settingsStore.flush();

      final controller = TrayWindowController(
        windowService: fakeWindow,
        trayService: fakeTray,
        playbackController: playbackController,
        settingsStore: settingsStore,
        shutdownCoordinator: shutdownCoordinator,
      );
      await controller.init();

      const track1 = AudioSource('file:///music/song1.mp3');
      const track2 = AudioSource('file:///music/song2.mp3');
      await playbackController.playQueue([track1, track2], startIndex: 0);

      // Item: PlayPause
      fakeTray.emitEvent(const TrayEvent.menuItem(TrayMenuItemId.playPause));
      await pumpEventQueue();
      await controller.lastTrayEventFuture;
      expect(playbackController.currentState, equals(PlaybackState.paused));

      // Item: Next
      fakeTray.emitEvent(const TrayEvent.menuItem(TrayMenuItemId.next));
      await pumpEventQueue();
      await controller.lastTrayEventFuture;
      expect(playbackController.queue.current?.uri, equals('file:///music/song2.mp3'));

      // Item: Previous
      fakeTray.emitEvent(const TrayEvent.menuItem(TrayMenuItemId.previous));
      await pumpEventQueue();
      await controller.lastTrayEventFuture;
      expect(playbackController.queue.current?.uri, equals('file:///music/song1.mp3'));

      // Item: Show
      fakeWindow.calls.clear();
      fakeTray.emitEvent(const TrayEvent.menuItem(TrayMenuItemId.show));
      await pumpEventQueue();
      await controller.lastTrayEventFuture;
      expect(fakeWindow.calls, contains('show'));

      // Item: Quit -> full shutdown then destroy
      fakeTray.emitEvent(const TrayEvent.menuItem(TrayMenuItemId.quit));
      await pumpEventQueue();
      await controller.lastTrayEventFuture;
      expect(shutdownCoordinator.hasShutdown, isTrue);

      await controller.dispose();
    });

    test('switching closeBehavior setting at runtime shows and hides the tray', () async {
      final controller = TrayWindowController(
        windowService: fakeWindow,
        trayService: fakeTray,
        playbackController: playbackController,
        settingsStore: settingsStore,
        shutdownCoordinator: shutdownCoordinator,
      );
      await controller.init();

      // Starts in quit mode -> tray not shown
      expect(fakeTray.isVisible, isFalse);

      // Switch to tray mode live -> tray is shown
      settingsStore.update((s) => s.copyWith(closeBehavior: 'tray'));
      await pumpEventQueue();
      expect(fakeTray.isVisible, isTrue);

      // Switch back to quit mode live -> tray is hidden
      settingsStore.update((s) => s.copyWith(closeBehavior: 'quit'));
      await pumpEventQueue();
      expect(fakeTray.isVisible, isFalse);

      await controller.dispose();
    });
  });
}
