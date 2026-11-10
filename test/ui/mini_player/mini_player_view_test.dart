import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/glass/glass_button.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/mini_player/mini_player_controller.dart';
import 'package:aestheticy/ui/mini_player/mini_player_view.dart';
import 'package:aestheticy/ui/now_playing/now_playing_view.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

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
                    child: SizedBox(
                      width: windowSize.width,
                      height: windowSize.height,
                      child: MiniPlayerView(
                        controller: miniController,
                        playbackController: playbackController,
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
  });
}
