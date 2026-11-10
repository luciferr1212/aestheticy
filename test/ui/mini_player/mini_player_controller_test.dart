import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/platform/window_service.dart';
import 'package:aestheticy/ui/mini_player/mini_player_controller.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  group('MiniPlayerController Tests', () {
    late FakeWindowService fakeWindow;
    late SettingsStore settingsStore;
    late Directory tempDir;
    late MiniPlayerController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_mini_test_');
      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();

      fakeWindow = FakeWindowService(
        initialGeometry: const WindowGeometry(
          position: Offset(100, 80),
          size: Size(1280, 800),
          isMaximized: false,
          isFullScreen: false,
        ),
        displaySizeProvider: () => const Size(1920, 1080),
      );

      controller = MiniPlayerController(
        windowService: fakeWindow,
        settingsStore: settingsStore,
      );
    });

    tearDown(() async {
      controller.dispose();
      settingsStore.dispose();
      await fakeWindow.dispose();
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('initial mode is normal', () {
      expect(controller.mode, equals(MiniPlayerMode.normal));
      expect(controller.isMini, isFalse);
    });

    test('enter then exit restores exact geometry and call order', () async {
      fakeWindow.calls.clear();

      await controller.enter();

      expect(controller.mode, equals(MiniPlayerMode.mini));
      expect(controller.isMini, isTrue);

      // bottomRight for 480x170 on 1920x1080:
      // x = 1920 - 480 - 16 = 1424
      // y = 1080 - 170 - 64 = 846
      expect(fakeWindow.calls, [
        'getGeometry',
        'setResizable(false)',
        'getDisplaySize',
        'applyGeometry(pos: Offset(1424.0, 846.0), size: Size(480.0, 170.0))',
        'setAlwaysOnTop(true)',
      ]);

      fakeWindow.calls.clear();
      await controller.exit();

      expect(controller.mode, equals(MiniPlayerMode.normal));
      expect(controller.isMini, isFalse);
      expect(fakeWindow.calls, [
        'setAlwaysOnTop(false)',
        'setResizable(true)',
        'applyGeometry(pos: Offset(100.0, 80.0), size: Size(1280.0, 800.0))',
      ]);
      expect(fakeWindow.currentGeometry.position, equals(const Offset(100, 80)));
      expect(fakeWindow.currentGeometry.size, equals(const Size(1280, 800)));
    });

    test('enter from maximized unmaximizes and exit restores maximized', () async {
      fakeWindow.currentGeometry = const WindowGeometry(
        position: Offset(0, 0),
        size: Size(1920, 1080),
        isMaximized: true,
        isFullScreen: false,
      );
      fakeWindow.calls.clear();

      await controller.enter();
      expect(fakeWindow.calls, contains('unmaximize'));

      fakeWindow.calls.clear();
      await controller.exit();

      expect(fakeWindow.calls, contains('maximize'));
      expect(fakeWindow.currentGeometry.isMaximized, isTrue);
    });

    test('enter from fullScreen leaves fullScreen first', () async {
      fakeWindow.currentGeometry = const WindowGeometry(
        position: Offset(0, 0),
        size: Size(1920, 1080),
        isMaximized: false,
        isFullScreen: true,
      );
      fakeWindow.calls.clear();

      await controller.enter();

      expect(fakeWindow.calls.first, equals('getGeometry'));
      expect(fakeWindow.calls[1], equals('setFullScreen(false)'));
      expect(fakeWindow.calls, contains('setResizable(false)'));
    });

    test('enter twice and exit twice are idempotent', () async {
      await controller.enter();
      expect(controller.isMini, isTrue);

      final callCountBeforeSecondEnter = fakeWindow.calls.length;
      await controller.enter();
      expect(fakeWindow.calls.length, equals(callCountBeforeSecondEnter));

      await controller.exit();
      expect(controller.isMini, isFalse);

      final callCountBeforeSecondExit = fakeWindow.calls.length;
      await controller.exit();
      expect(fakeWindow.calls.length, equals(callCountBeforeSecondExit));
    });

    test('position presets compute expected coordinates', () {
      const displaySize = Size(1920, 1080);
      const wide = Size(480, 170);

      // bottomRight: 1920-480-16 = 1424, 1080-170-64 = 846
      final br = MiniPlayerController.computePosition(
        preset: 'bottomRight',
        targetSize: wide,
        displaySize: displaySize,
      );
      expect(br, const Offset(1424, 846));

      // topCenter: (1920-480)/2 = 720, y = 16
      final tc = MiniPlayerController.computePosition(
        preset: 'topCenter',
        targetSize: wide,
        displaySize: displaySize,
      );
      expect(tc, const Offset(720, 16));
    });

    test('remember saves and reuses coordinates and falls back when offscreen', () async {
      settingsStore.update((s) => s.copyWith(miniPlayerPosition: 'remember'));
      await controller.enter();

      // Simulate user moving window to (300, 400)
      fakeWindow.currentGeometry = fakeWindow.currentGeometry.copyWith(
        position: const Offset(300, 400),
      );

      await controller.exit();
      expect(settingsStore.settings.miniPlayerLastX, equals(300.0));
      expect(settingsStore.settings.miniPlayerLastY, equals(400.0));

      // Enter again reuses remembered coordinates
      fakeWindow.calls.clear();
      await controller.enter();
      expect(
        fakeWindow.calls,
        contains('applyGeometry(pos: Offset(300.0, 400.0), size: Size(480.0, 170.0))'),
      );
      await controller.exit();

      // If coordinates are off-screen, falls back to bottomRight
      settingsStore.update((s) => s.copyWith(
            miniPlayerLastX: 3000.0,
            miniPlayerLastY: 2000.0,
          ));
      fakeWindow.calls.clear();
      await controller.enter();
      expect(
        fakeWindow.calls,
        contains('applyGeometry(pos: Offset(1424.0, 846.0), size: Size(480.0, 170.0))'),
      );
    });

    test('live shape and always-on-top changes apply immediately while in mini mode', () async {
      await controller.enter();
      fakeWindow.calls.clear();

      // Toggle shape to square
      await controller.toggleShape();
      expect(
        fakeWindow.calls,
        contains('applyGeometry(pos: Offset(1424.0, 640.0), size: Size(340.0, 440.0))'),
      );

      fakeWindow.calls.clear();
      // Toggle always-on-top
      await controller.toggleAlwaysOnTop();
      expect(fakeWindow.calls, contains('setAlwaysOnTop(false)'));
      expect(settingsStore.settings.miniPlayerAlwaysOnTop, isFalse);
    });
  });
}
