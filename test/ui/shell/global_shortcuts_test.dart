import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/app_shortcuts.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/shell/bottom_now_playing_bar.dart';
import 'package:aestheticy/ui/shell/volume_hud.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

void main() {
  group('Global Shortcuts Tests (I1)', () {
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late SqliteLibraryRepository repository;
    late ScanService scanService;
    late SettingsStore settingsStore;
    late GlassController glassController;
    late AppNavigator navigator;

    setUp(() async {
      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
      repository = SqliteLibraryRepository.inMemory();
      scanService = ScanService(repository: repository);
      settingsStore = SettingsStore(
        initialSettings: const AppSettings(
          language: 'en',
          userName: 'mido',
          glassQuality: GlassQuality.off,
          reduceMotion: true,
          volume: 0.8,
        ),
      );
      glassController = GlassController();
      settingsStore.bindGlassController(glassController);
      navigator = AppNavigator();
    });

    tearDown(() async {
      settingsStore.dispose();
      scanService.dispose();
      await repository.close();
      await controller.dispose();
      await engine.dispose();
    });

    Widget createTestApp() {
      return GlassScope(
        controller: glassController,
        child: MaterialApp(
          locale: const Locale('en'),
          theme: buildAppTheme(),
          home: AppShell(
            engine: engine,
            controller: controller,
            repository: repository,
            scanService: scanService,
            settingsStore: settingsStore,
            navigator: navigator,
          ),
        ),
      );
    }

    test('kAppShortcuts configuration: Space, Seek Arrows, and Space Chords are global', () {
      final playPause = shortcutById(AppShortcutId.playPause);
      expect(playPause.scope, equals(AppShortcutScope.global));

      final nextTrack = shortcutById(AppShortcutId.nextTrack);
      expect(nextTrack.scope, equals(AppShortcutScope.global));

      final prevTrack = shortcutById(AppShortcutId.previousTrack);
      expect(prevTrack.scope, equals(AppShortcutScope.global));

      final volUp = shortcutById(AppShortcutId.volumeUp);
      expect(volUp.scope, equals(AppShortcutScope.global));

      final volDown = shortcutById(AppShortcutId.volumeDown);
      expect(volDown.scope, equals(AppShortcutScope.global));

      // Arrows and Space chords are global scope in S7
      expect(shortcutById(AppShortcutId.seekBackward).scope, equals(AppShortcutScope.global));
      expect(shortcutById(AppShortcutId.seekForward).scope, equals(AppShortcutScope.global));
      expect(shortcutById(AppShortcutId.chordNext).scope, equals(AppShortcutScope.global));
      expect(shortcutById(AppShortcutId.chordPrevious).scope, equals(AppShortcutScope.global));
    });

    testWidgets('Space toggles playback across Albums, Tracks, Artists, Playlists, and Settings',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');
      const track = AudioSource('file:///music/song.mp3');
      await controller.playQueue([track], startIndex: 0);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      final destinations = [
        AppDestination.albums,
        AppDestination.tracks,
        AppDestination.artists,
        AppDestination.playlists,
        AppDestination.settings,
      ];

      for (final dest in destinations) {
        navigator.navigateTo(dest);
        await tester.pumpAndSettle();

        expect(controller.currentState, equals(PlaybackState.playing));

        // Press Space -> pause
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump(const Duration(milliseconds: 50));
        expect(controller.currentState, equals(PlaybackState.paused),
            reason: 'Space should pause on destination: $dest');

        // Press Space -> play
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump(const Duration(milliseconds: 50));
        expect(controller.currentState, equals(PlaybackState.playing),
            reason: 'Space should resume play on destination: $dest');
      }
    });

    testWidgets('Space inside an EditableText does not toggle playback',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');
      const track = AudioSource('file:///music/song.mp3');
      await controller.playQueue([track], startIndex: 0);

      // On tracks view, focus search field
      navigator.navigateTo(AppDestination.tracks);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      await tester.tap(textField);
      await tester.pumpAndSettle();

      expect(controller.currentState, equals(PlaybackState.playing));

      // Press Space while text field is focused
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 50));

      // Playback must NOT toggle
      expect(controller.currentState, equals(PlaybackState.playing));
    });

    testWidgets('Ctrl+Right, Ctrl+Left, Ctrl+Up, and Ctrl+Down act globally',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');
      const track1 = AudioSource('file:///music/song1.mp3');
      const track2 = AudioSource('file:///music/song2.mp3');
      await controller.playQueue([track1, track2], startIndex: 0);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Ctrl + Right -> next track
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.queue.current?.uri, equals('file:///music/song2.mp3'));

      // Ctrl + Left -> previous track
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.queue.current?.uri, equals('file:///music/song1.mp3'));

      // Initial volume is 0.8
      expect(settingsStore.settings.volume, closeTo(0.8, 0.001));

      // Ctrl + Up -> volume +5%
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 50));

      expect(settingsStore.settings.volume, closeTo(0.85, 0.001));

      // Ctrl + Down -> volume -5%
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 50));

      expect(settingsStore.settings.volume, closeTo(0.80, 0.001));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('Space key down does not toggle, key up toggles play/pause',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');
      const track = AudioSource('file:///music/song.mp3');
      await controller.playQueue([track], startIndex: 0);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(controller.currentState, equals(PlaybackState.playing));

      // KeyDown Space -> Still playing (not toggled yet!)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.currentState, equals(PlaybackState.playing));

      // KeyUp Space -> Now paused
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.currentState, equals(PlaybackState.paused));
    });

    testWidgets('Space + Right chord skips to next track without toggling play/pause on release',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');
      const track1 = AudioSource('file:///music/song1.mp3');
      const track2 = AudioSource('file:///music/song2.mp3');
      await controller.playQueue([track1, track2], startIndex: 0);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(controller.queue.current?.uri, equals('file:///music/song1.mp3'));
      expect(controller.currentState, equals(PlaybackState.playing));

      // 1. Hold Space down
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 20));

      // 2. Tap Right Arrow
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 50));

      // Track should advance to song2
      expect(controller.queue.current?.uri, equals('file:///music/song2.mp3'));

      // 3. Release Space -> Playback must remain playing, not pause!
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.currentState, equals(PlaybackState.playing));
    });

    testWidgets('Space + Left chord skips to previous track without toggling play/pause on release',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');
      const track1 = AudioSource('file:///music/song1.mp3');
      const track2 = AudioSource('file:///music/song2.mp3');
      await controller.playQueue([track1, track2], startIndex: 1);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(controller.queue.current?.uri, equals('file:///music/song2.mp3'));

      // 1. Hold Space down
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 20));

      // 2. Tap Left Arrow
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 50));

      // Track should skip back to song1
      expect(controller.queue.current?.uri, equals('file:///music/song1.mp3'));

      // 3. Release Space -> Playback must remain playing
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.currentState, equals(PlaybackState.playing));
    });

    testWidgets('Left and Right seek arrows seek by seekStepSeconds and clamp to bounds',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');
      const track = AudioSource('file:///music/song.mp3', extras: {'durationMs': '10000'});
      await controller.playQueue([track], startIndex: 0);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Default seekStepSeconds is 2 seconds
      expect(settingsStore.settings.seekStepSeconds, equals(2));

      // Right arrow: 0 -> 2s
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.currentPosition, equals(const Duration(seconds: 2)));

      // Right arrow: 2s -> 4s
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.currentPosition, equals(const Duration(seconds: 4)));

      // Left arrow: 4s -> 2s
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.currentPosition, equals(const Duration(seconds: 2)));

      // Left arrow 2 times: 2s -> 0s (clamps at 0, no negative time)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.currentPosition, equals(Duration.zero));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.currentPosition, equals(Duration.zero));
    });

    testWidgets('Idle state seek updates armed resume position',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');
      const track = AudioSource('file:///music/song.mp3', extras: {'durationMs': '10000'});
      queue.replaceAll([track]);
      // Engine is idle, armed position is armed
      controller.armResume(const Duration(seconds: 3));

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(controller.currentState, equals(PlaybackState.idle));
      expect(controller.currentPosition, equals(const Duration(seconds: 3)));

      // Seek Right while idle -> updates armed position to 5s
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.armedResumePosition, equals(const Duration(seconds: 5)));
      expect(controller.currentPosition, equals(const Duration(seconds: 5)));
    });

    testWidgets(
      'Volume keys throttle repeats at 60ms, seek repeats at 120ms, and plain arrows ignored outside FS/Mini',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await repository.addFolder('C:\\Music');
        const track = AudioSource(
          'file:///music/long.mp3',
          extras: {'durationMs': '60000'},
        );
        await controller.playQueue([track]);

        final hudCtrl = VolumeHudController();
        addTearDown(hudCtrl.dispose);

        await tester.pumpWidget(
          GlassScope(
            controller: glassController,
            child: SettingsScope(
              store: settingsStore,
              child: VolumeHudScope(
                controller: hudCtrl,
                child: MaterialApp(
                  locale: const Locale('en'),
                  theme: buildAppTheme(),
                  home: VolumeHudOverlay(
                    controller: hudCtrl,
                    child: AppShell(
                      engine: engine,
                      controller: controller,
                      repository: repository,
                      scanService: scanService,
                      settingsStore: settingsStore,
                      navigator: navigator,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Plain ArrowUp/Down is ignored on normal destination (home)
        expect(settingsStore.settings.volume, closeTo(0.8, 0.001));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.8, 0.001));
        expect(hudCtrl.isVisible, isFalse);

        // Ctrl + Up steps +5% and triggers 60ms repeat throttle
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.85, 0.001));
        expect(hudCtrl.isVisible, isTrue);
        expect(find.text('85%'), findsOneWidget);

        // Immediate repeat (< 60ms) is throttled
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump(const Duration(milliseconds: 20));
        expect(settingsStore.settings.volume, closeTo(0.85, 0.001));

        // After >= 60ms, repeat steps again
        await tester.pump(const Duration(milliseconds: 45));
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.9, 0.001));
        expect(find.text('90%'), findsOneWidget);

        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        // Seek repeat throttle at 120ms
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(controller.currentPosition, equals(const Duration(seconds: 2)));

        // Immediate repeat (< 120ms) is throttled
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 50));
        expect(controller.currentPosition, equals(const Duration(seconds: 2)));

        // After >= 120ms, repeat advances another step
        await tester.pump(const Duration(milliseconds: 75));
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(controller.currentPosition, equals(const Duration(seconds: 4)));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);

        await tester.pump(const Duration(seconds: 2));
        await settingsStore.flush();
      },
    );

    testWidgets(
      'Volume HUD fades after 1s hold, obeys reduceMotion zero duration, and ignores pointers',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        settingsStore.update((s) => s.copyWith(reduceMotion: false, volume: 0.8));
        final hudCtrl = VolumeHudController();
        addTearDown(hudCtrl.dispose);

        await tester.pumpWidget(
          GlassScope(
            controller: glassController,
            child: SettingsScope(
              store: settingsStore,
              child: VolumeHudScope(
                controller: hudCtrl,
                child: MaterialApp(
                  locale: const Locale('en'),
                  theme: buildAppTheme(),
                  home: VolumeHudOverlay(
                    controller: hudCtrl,
                    child: AppShell(
                      engine: engine,
                      controller: controller,
                      repository: repository,
                      scanService: scanService,
                      settingsStore: settingsStore,
                      navigator: navigator,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        expect(hudCtrl.isVisible, isTrue);
        expect(find.text('75%'), findsOneWidget);
        final opacityBefore = tester.widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byKey(const Key('volume_hud')),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(opacityBefore.opacity, equals(1.0));
        expect(opacityBefore.duration, equals(const Duration(milliseconds: 220)));
        expect(
          find.ancestor(
            of: find.byKey(const Key('volume_hud')),
            matching: find.byType(IgnorePointer),
          ),
          findsWidgets,
        );

        await tester.pump(const Duration(milliseconds: 600));
        expect(hudCtrl.isVisible, isTrue);

        await tester.pump(const Duration(milliseconds: 500));
        expect(hudCtrl.isVisible, isFalse);
        final opacityAfter = tester.widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byKey(const Key('volume_hud')),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(opacityAfter.opacity, equals(0.0));

        // Reduce motion uses zero fade duration
        settingsStore.update((s) => s.copyWith(reduceMotion: true));
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        final opacityReduced = tester.widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byKey(const Key('volume_hud')),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(opacityReduced.duration, equals(Duration.zero));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await settingsStore.flush();
      },
    );

    testWidgets(
      'Bottom bar mouse wheel adjusts volume +/-5%, updates HUD, and absorbs scroll',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final hudCtrl = VolumeHudController();
        final scrollCtrl = ScrollController();
        addTearDown(() {
          hudCtrl.dispose();
          scrollCtrl.dispose();
        });

        await tester.pumpWidget(
          GlassScope(
            controller: glassController,
            child: SettingsScope(
              store: settingsStore,
              child: VolumeHudScope(
                controller: hudCtrl,
                child: MaterialApp(
                  locale: const Locale('en'),
                  theme: buildAppTheme(),
                  home: VolumeHudOverlay(
                    controller: hudCtrl,
                    child: Scaffold(
                      body: SizedBox(
                        width: 1100,
                        height: 600,
                        child: SingleChildScrollView(
                          controller: scrollCtrl,
                          child: SizedBox(
                            height: 2000,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: 1000,
                                height: 84,
                                child: BottomNowPlayingBar(
                                  controller: controller,
                                  navigator: navigator,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final volCenter =
            tester.getCenter(find.byKey(const Key('player_volume_button')));
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.hover(volCenter));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
        await tester.pump();

        expect(settingsStore.settings.volume, closeTo(0.85, 0.001));
        expect(engine.currentVolume, closeTo(0.85, 0.001));
        expect(hudCtrl.isVisible, isTrue);
        expect(find.text('85%'), findsOneWidget);
        expect(scrollCtrl.offset, equals(0.0));

        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.8, 0.001));
        expect(find.text('80%'), findsOneWidget);
        expect(scrollCtrl.offset, equals(0.0));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await settingsStore.flush();
      },
    );

    testWidgets(
      'Cheat sheet opens with ? and Ctrl+/, closes on Esc, and ignores focused EditableText',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await repository.addFolder('C:\\Music');

        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();

        // ? (Shift + /) opens cheat sheet
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('shortcuts_cheat_sheet_dialog')),
          findsOneWidget,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('shortcuts_cheat_sheet_dialog')),
          findsNothing,
        );

        // Ctrl + / opens cheat sheet
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('shortcuts_cheat_sheet_dialog')),
          findsOneWidget,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        // Navigate to Tracks search (or focus EditableText) and verify ? / Ctrl+/ ignored
        navigator.navigateTo(AppDestination.tracks);
        await tester.pumpAndSettle();
        final textField = find.byType(TextField).first;
        await tester.tap(textField);
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(
          find.byKey(const Key('shortcuts_cheat_sheet_dialog')),
          findsNothing,
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(
          find.byKey(const Key('shortcuts_cheat_sheet_dialog')),
          findsNothing,
        );
      },
    );
  });
}
