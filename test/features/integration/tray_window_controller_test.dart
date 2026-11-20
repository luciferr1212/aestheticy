import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/features/integration/app_shutdown.dart';
import 'package:aestheticy/features/integration/tray_window_controller.dart';
import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/platform/tray_service.dart';
import 'package:aestheticy/platform/windows/windows_tray_service.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

class _CountingShutdownCoordinator extends AppShutdownCoordinator {
  int shutdownCallCount = 0;

  _CountingShutdownCoordinator({
    required super.settingsStore,
    super.mediaSessionService,
    super.sleepInhibitor,
    super.trayService,
    super.windowService,
    super.logger,
  });

  @override
  Future<void> shutdown() {
    shutdownCallCount++;
    return super.shutdown();
  }
}

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

    test('tray created -> handleCloseRequested hides window and logs lifecycle without personal data', () async {
      final logBuffer = StringBuffer();
      final logger = AppLogger(customSink: logBuffer);
      settingsStore.update((s) => s.copyWith(closeBehavior: 'tray'));
      await settingsStore.flush();

      final controller = TrayWindowController(
        windowService: fakeWindow,
        trayService: fakeTray,
        playbackController: playbackController,
        settingsStore: settingsStore,
        shutdownCoordinator: shutdownCoordinator,
        logger: logger,
      );
      await controller.init();

      expect(fakeTray.isVisible, isTrue);
      expect(controller.isTrayUnavailable, isFalse);

      final hidden = await controller.handleCloseRequested();
      expect(hidden, isTrue);
      expect(fakeWindow.isVisible, isFalse);
      expect(fakeWindow.isDestroyed, isFalse);
      expect(shutdownCoordinator.hasShutdown, isFalse);

      final logs = logBuffer.toString();
      expect(logs, contains('Tray show result: success (isVisible=true)'));
      expect(logs, contains('Close requested'));
      expect(logs, contains('Close behavior read: tray'));
      expect(logs, contains('Final close action: hide'));

      await controller.dispose();
    });

    test('tray creation failure (returns false) marks tray unavailable and close in tray mode quits instead of hiding', () async {
      final logBuffer = StringBuffer();
      final logger = AppLogger(customSink: logBuffer);
      fakeTray.failShow = true;
      settingsStore.update((s) => s.copyWith(closeBehavior: 'tray'));
      await settingsStore.flush();

      final controller = TrayWindowController(
        windowService: fakeWindow,
        trayService: fakeTray,
        playbackController: playbackController,
        settingsStore: settingsStore,
        shutdownCoordinator: shutdownCoordinator,
        logger: logger,
      );
      await controller.init();

      expect(fakeTray.isVisible, isFalse);
      expect(controller.isTrayUnavailable, isTrue);

      fakeWindow.emitCloseRequested();
      await pumpEventQueue();
      await controller.lastCloseFuture;

      expect(shutdownCoordinator.hasShutdown, isTrue);
      expect(fakeWindow.isDestroyed, isTrue);

      final logs = logBuffer.toString();
      expect(logs, contains('Tray show result: failure'));
      expect(logs, contains('Final close action: quit'));

      await controller.dispose();
    });

    test('tray creation throwing exception logs exceptionType, marks unavailable, and close quits cleanly', () async {
      final logBuffer = StringBuffer();
      final logger = AppLogger(customSink: logBuffer);
      fakeTray.showException = StateError('Shell_NotifyIcon failed');
      settingsStore.update((s) => s.copyWith(closeBehavior: 'tray'));
      await settingsStore.flush();

      final controller = TrayWindowController(
        windowService: fakeWindow,
        trayService: fakeTray,
        playbackController: playbackController,
        settingsStore: settingsStore,
        shutdownCoordinator: shutdownCoordinator,
        logger: logger,
      );
      await controller.init();

      expect(fakeTray.isVisible, isFalse);
      expect(controller.isTrayUnavailable, isTrue);

      final hidden = await controller.handleCloseRequested();
      expect(hidden, isFalse);
      expect(shutdownCoordinator.hasShutdown, isTrue);
      expect(fakeWindow.isDestroyed, isTrue);

      final logs = logBuffer.toString();
      expect(logs, contains('exceptionType=StateError'));
      expect(logs, contains('Final close action: quit'));

      await controller.dispose();
    });

    test('switching closeBehavior at runtime: tray fail quits on close, later tray success hides on close', () async {
      fakeTray.failShow = true;
      final controller = TrayWindowController(
        windowService: fakeWindow,
        trayService: fakeTray,
        playbackController: playbackController,
        settingsStore: settingsStore,
        shutdownCoordinator: shutdownCoordinator,
      );
      await controller.init();

      settingsStore.update((s) => s.copyWith(closeBehavior: 'tray'));
      await pumpEventQueue();
      expect(controller.isTrayUnavailable, isTrue);
      expect(fakeTray.isVisible, isFalse);

      // Toggle back to quit then allow tray creation and switch to tray again
      settingsStore.update((s) => s.copyWith(closeBehavior: 'quit'));
      await pumpEventQueue();
      fakeTray.failShow = false;
      settingsStore.update((s) => s.copyWith(closeBehavior: 'tray'));
      await pumpEventQueue();

      expect(controller.isTrayUnavailable, isFalse);
      expect(fakeTray.isVisible, isTrue);

      final hidden = await controller.handleCloseRequested();
      expect(hidden, isTrue);
      expect(fakeWindow.isDestroyed, isFalse);
      expect(shutdownCoordinator.hasShutdown, isFalse);

      await controller.dispose();
    });

    test('single close handler deduplicates overlapping closes and tray Quit runs shutdown once', () async {
      final countingShutdown = _CountingShutdownCoordinator(
        settingsStore: settingsStore,
        mediaSessionService: FakeMediaSessionService(),
        sleepInhibitor: FakeSleepInhibitor(),
        trayService: fakeTray,
        windowService: fakeWindow,
        logger: AppLogger(customSink: StringBuffer()),
      );

      final controller = TrayWindowController(
        windowService: fakeWindow,
        trayService: fakeTray,
        playbackController: playbackController,
        settingsStore: settingsStore,
        shutdownCoordinator: countingShutdown,
      );
      await controller.init();

      // Overlapping close requests (e.g. window close + lifecycle exit)
      fakeWindow.emitCloseRequested();
      final secondClose = controller.handleCloseRequested();
      await pumpEventQueue();
      await controller.lastCloseFuture;
      await secondClose;

      // Subsequent Quit item from tray menu must still keep total shutdowns == 1
      await controller.handleMenuItem(TrayMenuItemId.quit);

      expect(countingShutdown.shutdownCallCount, equals(1));
      expect(fakeWindow.calls.where((c) => c == 'destroy').length, equals(1));

      await controller.dispose();
    });

    test('tray Quit menu item runs shutdown coordinator and window destroy exactly once', () async {
      settingsStore.update((s) => s.copyWith(closeBehavior: 'tray'));
      await settingsStore.flush();

      final countingShutdown = _CountingShutdownCoordinator(
        settingsStore: settingsStore,
        mediaSessionService: FakeMediaSessionService(),
        sleepInhibitor: FakeSleepInhibitor(),
        trayService: fakeTray,
        windowService: fakeWindow,
        logger: AppLogger(customSink: StringBuffer()),
      );

      final controller = TrayWindowController(
        windowService: fakeWindow,
        trayService: fakeTray,
        playbackController: playbackController,
        settingsStore: settingsStore,
        shutdownCoordinator: countingShutdown,
      );
      await controller.init();

      fakeTray.emitEvent(const TrayEvent.menuItem(TrayMenuItemId.quit));
      fakeTray.emitEvent(const TrayEvent.menuItem(TrayMenuItemId.quit));
      await pumpEventQueue();
      await controller.lastTrayEventFuture;

      expect(countingShutdown.shutdownCallCount, equals(1));
      expect(fakeWindow.calls.where((c) => c == 'destroy').length, equals(1));
      expect(fakeTray.isVisible, isFalse);

      await controller.dispose();
    });

    test('WindowsTrayService validates ICO header bytes and resolves release vs fallback icon paths', () async {
      final projectIco = File('assets/tray/app_icon.ico');
      expect(projectIco.existsSync(), isTrue);
      final realBytes = await projectIco.readAsBytes();
      expect(WindowsTrayService.isValidIcoBytes(realBytes), isTrue);

      // Invalid/truncated headers must be rejected
      expect(WindowsTrayService.isValidIcoBytes(Uint8List(0)), isFalse);
      expect(
        WindowsTrayService.isValidIcoBytes(Uint8List.fromList([0, 0, 2, 0, 1, 0, ...List.filled(16, 0)])),
        isFalse,
      );
      expect(
        WindowsTrayService.isValidIcoBytes(Uint8List.fromList([0, 0, 1, 0, 1, 0])),
        isFalse,
      );

      // Simulate release layout: <exeDir>/data/flutter_assets/assets/tray/app_icon.ico
      final releaseRoot = await Directory.systemTemp.createTemp('aestheticy_ico_rel_');
      try {
        final releaseIco = File(
          '${releaseRoot.path}${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}assets${Platform.pathSeparator}tray${Platform.pathSeparator}app_icon.ico',
        );
        await releaseIco.parent.create(recursive: true);
        await releaseIco.writeAsBytes(realBytes, flush: true);

        final resolved = await WindowsTrayService.resolveIconFilePath(
          resolvedExecutablePath: '${releaseRoot.path}${Platform.pathSeparator}aestheticy.exe',
          currentDirectoryPath: releaseRoot.path,
        );
        expect(resolved, equals(releaseIco.path));
      } finally {
        await releaseRoot.delete(recursive: true);
      }

      // Simulate missing release + cwd assets -> extracts via loadAsset to supportDir
      final fallbackRoot = await Directory.systemTemp.createTemp('aestheticy_ico_fb_');
      try {
        final resolved = await WindowsTrayService.resolveIconFilePath(
          resolvedExecutablePath: '${fallbackRoot.path}${Platform.pathSeparator}missing${Platform.pathSeparator}aestheticy.exe',
          currentDirectoryPath: '${fallbackRoot.path}${Platform.pathSeparator}nowhere',
          loadAsset: (_) async => ByteData.sublistView(realBytes),
          supportDirProvider: () async => fallbackRoot,
        );
        expect(resolved, isNotNull);
        expect(File(resolved!).existsSync(), isTrue);
      } finally {
        await fallbackRoot.delete(recursive: true);
      }
    });
  });
}
