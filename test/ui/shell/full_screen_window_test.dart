import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/platform/window_service.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/mini_player/mini_player_controller.dart';
import 'package:aestheticy/ui/now_playing/full_screen_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FullScreen and WindowService Coordination Tests', () {
    late Directory tempDir;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late SqliteLibraryRepository repository;
    late ScanService scanService;
    late SettingsStore settingsStore;
    late GlassController glassController;
    late AppNavigator navigator;
    late FakeWindowService fakeWindow;
    late MiniPlayerController miniPlayerController;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('aestheticy_fs_test_');
      engine = FakeAudioEngine();
      await engine.init();

      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();

      repository = SqliteLibraryRepository.inMemory();
      await repository.addFolder('C:\\Music');
      scanService = ScanService(repository: repository);

      settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(
          language: 'en',
          glassQuality: GlassQuality.off,
          reduceMotion: true,
        ),
      );

      glassController = GlassController(quality: GlassQuality.off);
      navigator = AppNavigator();
      fakeWindow = FakeWindowService();
      miniPlayerController = MiniPlayerController(
        windowService: fakeWindow,
        settingsStore: settingsStore,
      );
    });

    tearDown(() async {
      miniPlayerController.dispose();
      settingsStore.dispose();
      scanService.dispose();
      await repository.close();
      await controller.dispose();
      await engine.dispose();
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    Widget buildTestShell() {
      return GlassScope(
        controller: glassController,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: AppShell(
            engine: engine,
            controller: controller,
            repository: repository,
            scanService: scanService,
            settingsStore: settingsStore,
            navigator: navigator,
            windowService: fakeWindow,
            miniPlayerController: miniPlayerController,
          ),
        ),
      );
    }

    testWidgets('Entering and leaving full screen calls setFullScreen(true/false) in order', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestShell());
      await tester.pumpAndSettle();

      fakeWindow.calls.clear();

      // Enter full screen
      navigator.navigateTo(AppDestination.fullScreen);
      await tester.pumpAndSettle();

      expect(fakeWindow.calls, contains('setFullScreen(true)'));
      expect(fakeWindow.currentGeometry.isFullScreen, isTrue);

      // Leave full screen via navigator.goBack()
      fakeWindow.calls.clear();
      navigator.goBack();
      await tester.pumpAndSettle();

      expect(fakeWindow.calls, contains('setFullScreen(false)'));
      expect(fakeWindow.currentGeometry.isFullScreen, isFalse);
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Esc and F11 shortcuts toggle and exit full screen', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestShell());
      await tester.pumpAndSettle();

      expect(navigator.current, equals(AppDestination.albums));

      // Press F11 to enter full screen
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();

      expect(navigator.current, equals(AppDestination.fullScreen));
      expect(fakeWindow.calls, contains('setFullScreen(true)'));

      // Press Esc to exit full screen
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(navigator.current, equals(AppDestination.albums));
      expect(fakeWindow.calls, contains('setFullScreen(false)'));

      // Press F11 to enter full screen again
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(navigator.current, equals(AppDestination.fullScreen));

      // Press F11 again to exit full screen
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(navigator.current, equals(AppDestination.albums));
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('If window was maximized before entering full screen, it returns to maximized on exit', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      fakeWindow.currentGeometry = const WindowGeometry(
        position: Offset.zero,
        size: Size(1920, 1080),
        isMaximized: true,
        isFullScreen: false,
      );

      await tester.pumpWidget(buildTestShell());
      await tester.pumpAndSettle();

      fakeWindow.calls.clear();

      // Enter full screen
      navigator.navigateTo(AppDestination.fullScreen);
      await tester.pumpAndSettle();

      expect(fakeWindow.calls, contains('setFullScreen(true)'));

      // Exit full screen
      fakeWindow.calls.clear();
      navigator.goBack();
      await tester.pumpAndSettle();

      expect(fakeWindow.calls, contains('setFullScreen(false)'));
      expect(fakeWindow.calls, contains('maximize'));
      expect(fakeWindow.currentGeometry.isMaximized, isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Entering mini while full screen leaves full screen first', (tester) async {
      fakeWindow.currentGeometry = const WindowGeometry(
        position: Offset.zero,
        size: Size(1920, 1080),
        isMaximized: false,
        isFullScreen: true,
      );
      fakeWindow.calls.clear();

      await miniPlayerController.enter();

      expect(fakeWindow.calls.first, equals('getGeometry'));
      expect(fakeWindow.calls[1], equals('setFullScreen(false)'));
      expect(miniPlayerController.isMini, isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Bottom now-playing bar button enters mini mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestShell());
      await tester.pumpAndSettle();

      final miniBtn = find.byKey(const Key('player_mini_player_button'));
      expect(miniBtn, findsOneWidget);

      await tester.tap(miniBtn);
      await tester.pumpAndSettle();

      expect(miniPlayerController.isMini, isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Full screen view mini player button enters mini mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestShell());
      await tester.pumpAndSettle();

      // Navigate to full screen
      navigator.navigateTo(AppDestination.fullScreen);
      await tester.pumpAndSettle();

      expect(find.byType(FullScreenView), findsOneWidget);

      final fsMiniBtn = find.byKey(const Key('fullscreen_mini_player_button'));
      expect(fsMiniBtn, findsOneWidget);

      await tester.tap(fsMiniBtn);
      await tester.pumpAndSettle();

      expect(miniPlayerController.isMini, isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
