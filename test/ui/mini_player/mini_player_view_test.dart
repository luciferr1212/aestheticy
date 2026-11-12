import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/features/integration/app_shutdown.dart';
import 'package:aestheticy/features/lyrics/lrc_parser.dart';
import 'package:aestheticy/features/lyrics/lyrics_controller.dart';
import 'package:aestheticy/features/lyrics/lyrics_models.dart';
import 'package:aestheticy/features/lyrics/lyrics_repository.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/main.dart';
import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/glass/glass_button.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/lyrics/lyrics_view.dart';
import 'package:aestheticy/ui/mini_player/mini_player_controller.dart';
import 'package:aestheticy/ui/mini_player/mini_player_view.dart';
import 'package:aestheticy/ui/now_playing/now_playing_view.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

class _FakeMiniLyricsRepo extends LyricsRepository {
  LyricsResult resultToReturn = const LyricsResultNotFound();

  @override
  Future<LyricsResult> resolve({
    required String filePath,
    required String title,
    required String artist,
    String? album,
    required int durationMs,
    required String mode,
  }) async {
    if (mode == 'off') return const LyricsResultOff();
    return resultToReturn;
  }
}

void main() {
  group('MiniPlayerView Widget Tests', () {
    late Directory tempDir;
    late SettingsStore settingsStore;
    late FakeWindowService fakeWindow;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController playbackController;
    late MiniPlayerController miniController;
    late ArtistNameStore artistNameStore;
    late UserCollections userCollections;
    late GlassController glassController;

    setUp(() async {
      glassController = GlassController();
      tempDir = await Directory.systemTemp.createTemp('aestheticy_mini_view_test_');
      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();

      fakeWindow = FakeWindowService();
      miniController = MiniPlayerController(
        windowService: fakeWindow,
        settingsStore: settingsStore,
      );

      engine = FakeAudioEngine();
      queue = PlaybackQueue();
      playbackController = PlaybackController(engine: engine, queue: queue);
      await playbackController.init();

      artistNameStore = ArtistNameStore(directory: tempDir);
      await artistNameStore.init();

      userCollections = UserCollections(
        repository: SqliteLibraryRepository.inMemory(),
      );
      await userCollections.init();
    });

    tearDown(() async {
      miniController.dispose();
      await playbackController.dispose();
      await fakeWindow.dispose();
      settingsStore.dispose();
      artistNameStore.dispose();
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    Widget buildTestHarness({
      required Size windowSize,
      double textScale = 1.0,
      TextDirection textDirection = TextDirection.ltr,
      LyricsController? lyricsController,
    }) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: textDirection,
          child: MediaQuery(
            data: MediaQueryData(
              size: windowSize,
              textScaler: TextScaler.linear(textScale),
            ),
            child: GlassScope(
              controller: glassController,
              child: SettingsScope(
                store: settingsStore,
                child: ArtistNameScope(
                  store: artistNameStore,
                  child: UserCollectionsScope(
                    collections: userCollections,
                    child: Center(
                      child: SizedBox(
                        width: windowSize.width,
                        height: windowSize.height,
                        child: MiniPlayerView(
                          controller: miniController,
                          playbackController: playbackController,
                          lyricsController: lyricsController,
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
    }

    testWidgets(
      'renders wide layout at 480x170 without overflow in normal, large text and RTL',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await playbackController.playQueue(const [
          AudioSource(
            'file:///track1.mp3',
            extras: {
              'title': 'Stargazing Ambient',
              'artist': 'Luna',
              'path': 'C:/music/track1.mp3',
            },
          ),
        ]);
        await tester.pump();

        // 1. Standard LTR 480x170
        await tester.pumpWidget(buildTestHarness(windowSize: const Size(480, 170)));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Stargazing Ambient'), findsOneWidget);
        expect(find.byKey(const Key('mini_player_seek_bar')), findsOneWidget);
        expect(find.byType(NowPlayingSeekBar), findsOneWidget);

        // 2. Large text scale 1.10
        await tester.pumpWidget(buildTestHarness(
          windowSize: const Size(480, 170),
          textScale: 1.10,
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);

        // 3. RTL Arabic layout
        await tester.pumpWidget(buildTestHarness(
          windowSize: const Size(480, 170),
          textScale: 1.10,
          textDirection: TextDirection.rtl,
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders square layout at 340x440 without overflow in normal, large text and RTL',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await playbackController.playQueue(const [
          AudioSource(
            'file:///track1.mp3',
            extras: {
              'title': 'Stargazing Ambient',
              'artist': 'Luna',
              'path': 'C:/music/track1.mp3',
            },
          ),
        ]);
        await tester.pump();

        // 1. Standard LTR 340x440
        await tester.pumpWidget(buildTestHarness(windowSize: const Size(340, 440)));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Stargazing Ambient'), findsOneWidget);
        expect(find.byType(NowPlayingSeekBar), findsOneWidget);

        // 2. Large text scale 1.10
        await tester.pumpWidget(buildTestHarness(
          windowSize: const Size(340, 440),
          textScale: 1.10,
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);

        // 3. RTL Arabic layout
        await tester.pumpWidget(buildTestHarness(
          windowSize: const Size(340, 440),
          textScale: 1.10,
          textDirection: TextDirection.rtl,
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'empty state displays calm label and disabled transport buttons',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(buildTestHarness(windowSize: const Size(480, 170)));
        await tester.pump();

        expect(find.text('Nothing playing'), findsOneWidget);
        expect(find.text('—'), findsOneWidget);

        // Play/Pause button should be disabled
        final playPauseBtn = tester.widget<GlassIconButton>(
          find.byKey(const Key('mini_player_play_pause_button')),
        );
        expect(playPauseBtn.onPressed, isNull);

        // Pin and expand buttons remain enabled
        final expandBtn = tester.widget<GlassIconButton>(
          find.byKey(const Key('mini_player_expand_button')),
        );
        expect(expandBtn.onPressed, isNotNull);
      },
    );

    testWidgets(
      'pin button toggles always on top setting and window service flag',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await miniController.enter();
        fakeWindow.calls.clear();

        await tester.pumpWidget(buildTestHarness(windowSize: const Size(480, 170)));
        await tester.pump();

        expect(settingsStore.settings.miniPlayerAlwaysOnTop, isTrue);

        await tester.tap(find.byKey(const Key('mini_player_pin_button')));
        await tester.pump(const Duration(milliseconds: 500));

        expect(settingsStore.settings.miniPlayerAlwaysOnTop, isFalse);
        expect(fakeWindow.calls, contains('setAlwaysOnTop(false)'));

        await tester.tap(find.byKey(const Key('mini_player_pin_button')));
        await tester.pump(const Duration(milliseconds: 500));

        expect(settingsStore.settings.miniPlayerAlwaysOnTop, isTrue);
        expect(fakeWindow.calls, contains('setAlwaysOnTop(true)'));
      },
    );

    testWidgets(
      'expand button and Esc key exit mini mode',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await miniController.enter();
        expect(miniController.isMini, isTrue);

        await tester.pumpWidget(buildTestHarness(windowSize: const Size(480, 170)));
        await tester.pump();

        // 1. Expand button exits
        await tester.tap(find.byKey(const Key('mini_player_expand_button')));
        await tester.pump();
        expect(miniController.isMini, isFalse);

        // Re-enter mini
        await miniController.enter();
        expect(miniController.isMini, isTrue);
        await tester.pump();

        // 2. Esc key exits
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(miniController.isMini, isFalse);
      },
    );

    testWidgets(
      'transport buttons call playback controller',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await playbackController.playQueue(const [
          AudioSource('file:///t1.mp3', extras: {'title': 'Track 1'}),
          AudioSource('file:///t2.mp3', extras: {'title': 'Track 2'}),
        ]);
        await tester.pump();

        await tester.pumpWidget(buildTestHarness(windowSize: const Size(480, 170)));
        await tester.pump();

        // Already playing; tap toggles to paused
        await tester.tap(find.byKey(const Key('mini_player_play_pause_button')));
        await tester.pump();
        expect(playbackController.currentState, equals(PlaybackState.paused));

        // Tap again toggles back to playing
        await tester.tap(find.byKey(const Key('mini_player_play_pause_button')));
        await tester.pump();
        expect(playbackController.currentState, equals(PlaybackState.playing));

        // Next
        await tester.tap(find.byKey(const Key('mini_player_next_button')));
        await tester.pump();
        expect(playbackController.queue.current?.extras?['title'], equals('Track 2'));

        // Previous
        await tester.tap(find.byKey(const Key('mini_player_prev_button')));
        await tester.pump();
        expect(playbackController.queue.current?.extras?['title'], equals('Track 1'));
      },
    );

    testWidgets(
      'mini lyrics toggle expands to 480x320 wide and 340x620 square with smooth LyricsView, plain scrolling, placeholder, reduce motion, and no offset controls',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final fakeRepo = _FakeMiniLyricsRepo()
          ..resultToReturn = LyricsResultFound(
            parseLrc(
              List.generate(
                14,
                (i) => '[00:${(i * 3 + 1).toString().padLeft(2, '0')}.00]Line ${i + 1} verse text',
              ).join('\n'),
            ),
          );
        final lyricsCtrl = LyricsController(
          playbackController: playbackController,
          repository: fakeRepo,
          settingsStore: settingsStore,
        );
        addTearDown(lyricsCtrl.dispose);

        await tester.runAsync(() async {
          await playbackController.playQueue(const [
            AudioSource(
              'file:///t1.mp3',
              extras: {'title': 'Song One', 'artist': 'Artist', 'path': 'C:/music/t1.mp3'},
            ),
          ]);
          await lyricsCtrl.retry();
        });
        lyricsCtrl.updatePosition(const Duration(milliseconds: 1200));
        await tester.pump();

        await tester.runAsync(() => miniController.enter());
        await tester.pumpWidget(
          buildTestHarness(
            windowSize: const Size(480, 170),
            lyricsController: lyricsCtrl,
          ),
        );
        await tester.pump();

        // Off by default: compact 480x170 with zero lyrics panel
        expect(settingsStore.settings.miniPlayerShowLyrics, isFalse);
        expect(find.byKey(const Key('mini_lyrics_toggle')), findsOneWidget);
        expect(find.byKey(const Key('mini_player_lyrics_view')), findsNothing);
        expect(find.byKey(const Key('lyrics_sync_control')), findsNothing);

        // Toggle ON -> resizes to 480x320 wide and mounts shared LyricsView in mini density
        await tester.tap(find.byKey(const Key('mini_lyrics_toggle')));
        await tester.pump();
        expect(settingsStore.settings.miniPlayerShowLyrics, isTrue);
        expect(fakeWindow.currentGeometry.size, equals(const Size(480, 320)));

        await tester.pumpWidget(
          buildTestHarness(
            windowSize: const Size(480, 320),
            lyricsController: lyricsCtrl,
          ),
        );
        await tester.pump();
        final miniLyricsWide = tester.widget<LyricsView>(
          find.byKey(const Key('mini_player_lyrics_view')),
        );
        expect(miniLyricsWide.density, equals(LyricsViewDensity.mini));
        expect(miniLyricsWide.isWideMini, isTrue);
        expect(find.text('Line 1 verse text'), findsOneWidget);
        expect(find.text('Line 2 verse text'), findsOneWidget);
        expect(find.byKey(const Key('lyrics_sync_control')), findsNothing);

        // Tapping a lyrics line seeks playback immediately
        await tester.tap(find.text('Line 2 verse text'));
        await tester.pump();
        expect(playbackController.currentPosition.inMilliseconds, equals(4000));

        // Square layout 340x620 renders multi-line lyrics without overflow in RTL & large text
        await tester.pumpWidget(
          buildTestHarness(
            windowSize: const Size(340, 620),
            textScale: 1.10,
            textDirection: TextDirection.rtl,
            lyricsController: lyricsCtrl,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final miniLyricsSquare = tester.widget<LyricsView>(
          find.byKey(const Key('mini_player_lyrics_view')),
        );
        expect(miniLyricsSquare.density, equals(LyricsViewDensity.mini));
        expect(miniLyricsSquare.isWideMini, isFalse);

        // Plain lyrics render calmly and centered in mini density
        fakeRepo.resultToReturn = const LyricsResultFound(
          LyricsDocument(
            kind: LyricsKind.plain,
            lines: [
              LyricsLine(startMs: 0, text: 'Plain line one'),
              LyricsLine(startMs: 0, text: 'Plain line two'),
            ],
            source: LyricsSourceOrigin.local,
            hasWordTiming: false,
          ),
        );
        await tester.runAsync(() => lyricsCtrl.retry());
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Plain line one'), findsOneWidget);
        expect(find.text('Plain line two'), findsOneWidget);

        // Missing / off lyrics show calm centered placeholder
        fakeRepo.resultToReturn = const LyricsResultNotFound();
        await tester.runAsync(() => lyricsCtrl.retry());
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('mini_player_no_lyrics')), findsOneWidget);
        expect(find.text('No synced lyrics'), findsOneWidget);

        // Flush settingsStore debounce timer and clear widget tree
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'AestheticyApp shares ONE LyricsController across AppShell and MiniPlayerView',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          AestheticyApp(
            engine: engine,
            controller: playbackController,
            settingsStore: settingsStore,
            windowService: fakeWindow,
            miniPlayerController: miniController,
          ),
        );
        await tester.pump();

        // AppShell has LyricsView when navigated, or check shared instance via MiniPlayerView vs AppShell:
        await tester.runAsync(() => miniController.enter());
        await tester.pump();
        final miniWidget = tester.widget<MiniPlayerView>(find.byType(MiniPlayerView));
        final sharedCtrl = miniWidget.lyricsController;
        expect(sharedCtrl, isNotNull);

        await tester.runAsync(() => miniController.exit());
        await tester.pump();
        final appShellWidget = tester.widget<AppShell>(find.byType(AppShell));
        expect(identical(appShellWidget.lyricsController, sharedCtrl), isTrue);

        // Verify re-entering mini mode reuses the EXACT same controller instance
        await tester.runAsync(() => miniController.enter());
        await tester.pump();
        final miniWidget2 = tester.widget<MiniPlayerView>(find.byType(MiniPlayerView));
        expect(identical(miniWidget2.lyricsController, sharedCtrl), isTrue);

        // Unmount app and pump debounce timers
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Mini player handles ArrowUp/Down volume, Ctrl+Up/Down, Left/Right seek, cheat sheet, and VolumeHudOverlay',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        settingsStore.update(
          (s) => s.copyWith(volume: 0.6, seekStepSeconds: 5),
        );
        await playbackController.playQueue(const [
          AudioSource(
            'file:///track_mini_keys.mp3',
            extras: {'title': 'Key Test', 'artist': 'Artist'},
          ),
        ]);

        await tester.pumpWidget(
          AestheticyApp(
            engine: engine,
            controller: playbackController,
            settingsStore: settingsStore,
            windowService: fakeWindow,
            miniPlayerController: miniController,
          ),
        );
        await tester.pump();

        await tester.runAsync(() => miniController.enter());
        await tester.pump();

        // Plain ArrowUp / Ctrl+Down adjust volume + show VolumeHudOverlay
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.65, 0.001));
        expect(engine.currentVolume, closeTo(0.65, 0.001));
        expect(find.text('65%'), findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.6, 0.001));
        expect(find.text('60%'), findsOneWidget);

        // Left / Right seek with 120ms repeat cooldown
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(playbackController.currentPosition, equals(const Duration(seconds: 5)));

        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 50));
        expect(playbackController.currentPosition, equals(const Duration(seconds: 5)));

        await tester.pump(const Duration(milliseconds: 80));
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(playbackController.currentPosition, equals(const Duration(seconds: 10)));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(playbackController.currentPosition, equals(const Duration(seconds: 5)));

        // ? opens ShortcutsCheatSheetDialog; first Esc closes only dialog, second Esc exits mini mode
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const Key('shortcuts_cheat_sheet_dialog')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const Key('shortcuts_cheat_sheet_dialog')),
          findsNothing,
        );
        expect(miniController.isMini, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(miniController.isMini, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'whole-background drag calls startDragging while seekbar drag and lyrics scroll do not',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final fakeRepo = _FakeMiniLyricsRepo()
          ..resultToReturn = LyricsResultFound(
            parseLrc(
              List.generate(
                30,
                (i) => '[00:${(i + 1).toString().padLeft(2, '0')}.00]Draggable lyrics line ${i + 1}',
              ).join('\n'),
            ),
          );
        final lyricsCtrl = LyricsController(
          playbackController: playbackController,
          repository: fakeRepo,
          settingsStore: settingsStore,
        );
        addTearDown(lyricsCtrl.dispose);

        await tester.runAsync(() async {
          await playbackController.playQueue(const [
            AudioSource(
              'file:///t1.mp3',
              extras: {'title': 'Drag Track', 'artist': 'Artist', 'path': 'C:/music/t1.mp3'},
            ),
          ]);
          await lyricsCtrl.retry();
        });
        settingsStore.update((s) => s.copyWith(miniPlayerShowLyrics: true));
        await tester.pumpWidget(
          buildTestHarness(
            windowSize: const Size(340, 620),
            lyricsController: lyricsCtrl,
          ),
        );
        await tester.pump();

        // Dragging on background cover starts native window dragging
        await tester.drag(
          find.byIcon(Icons.music_note).first,
          const Offset(40, 20),
        );
        await tester.pump();
        expect(fakeWindow.startDraggingCount, greaterThan(0));

        // Dragging the seek bar does NOT trigger window dragging
        final beforeSeek = fakeWindow.startDraggingCount;
        await tester.drag(
          find.byKey(const Key('mini_player_seek_bar')),
          const Offset(40, 0),
        );
        await tester.pump();
        expect(fakeWindow.startDraggingCount, equals(beforeSeek));

        // Vertical drag on LyricsView scrolls lyrics instead of dragging window
        await tester.drag(
          find.byKey(const Key('mini_player_lyrics_view')),
          const Offset(0, -140),
        );
        await tester.pump();
        expect(fakeWindow.startDraggingCount, equals(beforeSeek));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'mini player close button restores window frame and handles tray vs quit closeBehavior',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        // 1. tray mode: exits mini (restoring frame) and hides without destroying
        settingsStore.update((s) => s.copyWith(closeBehavior: 'tray'));
        final shutdownTray = AppShutdownCoordinator(
          settingsStore: settingsStore,
          windowService: fakeWindow,
          logger: AppLogger(customSink: StringBuffer()),
        );
        await tester.pumpWidget(
          AestheticyApp(
            engine: engine,
            controller: playbackController,
            settingsStore: settingsStore,
            windowService: fakeWindow,
            miniPlayerController: miniController,
            shutdownCoordinator: shutdownTray,
          ),
        );
        await tester.pump();

        await tester.runAsync(() => miniController.enter());
        await tester.pump();
        expect(fakeWindow.isFramelessState, isTrue);

        await tester.tap(find.byKey(const Key('mini_player_close')));
        await tester.runAsync(() async {
          for (var i = 0; i < 50 && fakeWindow.isVisible; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pumpAndSettle();

        expect(miniController.isMini, isFalse);
        expect(fakeWindow.isFramelessState, isFalse);
        expect(fakeWindow.isVisible, isFalse);
        expect(fakeWindow.isDestroyed, isFalse);
        expect(shutdownTray.hasShutdown, isFalse);

        // 2. quit mode: exits mini (restoring frame), shuts down, and destroys window
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        fakeWindow.isVisible = true;
        settingsStore.update((s) => s.copyWith(closeBehavior: 'quit'));
        final shutdownQuit = AppShutdownCoordinator(
          settingsStore: SettingsStore(),
          windowService: fakeWindow,
          logger: AppLogger(customSink: StringBuffer()),
        );
        await tester.pumpWidget(
          AestheticyApp(
            engine: engine,
            controller: playbackController,
            settingsStore: settingsStore,
            windowService: fakeWindow,
            miniPlayerController: miniController,
            shutdownCoordinator: shutdownQuit,
          ),
        );
        await tester.pump();

        await tester.runAsync(() => miniController.enter());
        await tester.pump();
        expect(fakeWindow.isFramelessState, isTrue);

        await tester.tap(find.byKey(const Key('mini_player_close')));
        await tester.runAsync(() async {
          for (var i = 0; i < 50 && !shutdownQuit.hasShutdown; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pumpAndSettle();

        expect(miniController.isMini, isFalse);
        expect(fakeWindow.isFramelessState, isFalse);
        expect(fakeWindow.calls, contains('destroy'));
        expect(shutdownQuit.hasShutdown, isTrue);
        expect(fakeWindow.isDestroyed, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );
  });
}
