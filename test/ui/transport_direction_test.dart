import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:aestheticy/ui/glass/glass_blur_budget.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/mini_player/mini_player_controller.dart';
import 'package:aestheticy/ui/mini_player/mini_player_view.dart';
import 'package:aestheticy/ui/now_playing/now_playing_view.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/bottom_now_playing_bar.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

void main() {
  group('Direction-Neutral Transport and Seek (S3)', () {
    late Directory tempDir;
    late SettingsStore settingsStore;
    late FakeWindowService fakeWindow;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late MiniPlayerController miniController;
    late ArtistNameStore artistNameStore;
    late UserCollections userCollections;
    late GlassController glassController;
    late AppNavigator navigator;

    const testTrack = AudioSource(
      'file:///test/song.mp3',
      extras: {
        'title': 'أغنية جميلة',
        'artist': 'فنان رائع',
        'album': 'ألبوم ممتاز',
        'durationMs': '240000',
      },
    );

    setUp(() async {
      GlassBlurBudget.instance.resetForTesting();
      glassController = GlassController();
      tempDir = await Directory.systemTemp.createTemp('aestheticy_dir_test_');
      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();

      fakeWindow = FakeWindowService();
      miniController = MiniPlayerController(
        windowService: fakeWindow,
        settingsStore: settingsStore,
      );

      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();

      navigator = AppNavigator();
      artistNameStore = ArtistNameStore(directory: tempDir);
      await artistNameStore.init();

      userCollections = UserCollections(
        repository: SqliteLibraryRepository.inMemory(),
      );
      await userCollections.init();

      await controller.playQueue([testTrack], startIndex: 0);
    });

    tearDown(() async {
      miniController.dispose();
      await controller.dispose();
      await fakeWindow.dispose();
      await engine.dispose();
      userCollections.dispose();
      settingsStore.dispose();
      artistNameStore.dispose();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    testWidgets(
      'MiniPlayerView wide layout keeps prev.dx < play.dx < next.dx under RTL',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(480, 180);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: GlassScope(
                controller: glassController,
                child: SettingsScope(
                  store: settingsStore,
                  child: ArtistNameScope(
                    store: artistNameStore,
                    child: UserCollectionsScope(
                      collections: userCollections,
                      child: MiniPlayerView(
                        controller: miniController,
                        playbackController: controller,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final prev = tester.getCenter(find.byKey(const Key('mini_player_prev_button')));
        final play = tester.getCenter(find.byKey(const Key('mini_player_play_pause_button')));
        final next = tester.getCenter(find.byKey(const Key('mini_player_next_button')));

        expect(prev.dx, lessThan(play.dx), reason: 'Previous must be on the left of Play');
        expect(play.dx, lessThan(next.dx), reason: 'Play must be on the left of Next');
      },
    );

    testWidgets(
      'MiniPlayerView square layout keeps prev.dx < play.dx < next.dx under RTL',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(340, 440);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: GlassScope(
                controller: glassController,
                child: SettingsScope(
                  store: settingsStore,
                  child: ArtistNameScope(
                    store: artistNameStore,
                    child: UserCollectionsScope(
                      collections: userCollections,
                      child: MiniPlayerView(
                        controller: miniController,
                        playbackController: controller,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final prev = tester.getCenter(find.byKey(const Key('mini_player_prev_button')));
        final play = tester.getCenter(find.byKey(const Key('mini_player_play_pause_button')));
        final next = tester.getCenter(find.byKey(const Key('mini_player_next_button')));

        expect(prev.dx, lessThan(play.dx), reason: 'Previous must be on the left of Play');
        expect(play.dx, lessThan(next.dx), reason: 'Play must be on the left of Next');
      },
    );

    testWidgets(
      'BottomNowPlayingBar keeps prev.dx < play.dx < next.dx under RTL',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: Scaffold(
              bottomNavigationBar: Directionality(
                textDirection: TextDirection.rtl,
                child: GlassScope(
                  controller: glassController,
                  child: SettingsScope(
                    store: settingsStore,
                    child: ArtistNameScope(
                      store: artistNameStore,
                      child: UserCollectionsScope(
                        collections: userCollections,
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
        );
        await tester.pumpAndSettle();

        final prev = tester.getCenter(find.byKey(const Key('bottom_bar_prev_button')));
        final play = tester.getCenter(find.byKey(const Key('bottom_bar_play_pause_button')));
        final next = tester.getCenter(find.byKey(const Key('bottom_bar_next_button')));

        expect(prev.dx, lessThan(play.dx), reason: 'Bottom bar previous must be on the left of Play');
        expect(play.dx, lessThan(next.dx), reason: 'Bottom bar play must be on the left of Next');
      },
    );

    testWidgets(
      'NowPlayingView keeps prev.dx < play.dx < next.dx under RTL',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: GlassScope(
                controller: glassController,
                child: SettingsScope(
                  store: settingsStore,
                  child: ArtistNameScope(
                    store: artistNameStore,
                    child: UserCollectionsScope(
                      collections: userCollections,
                      child: NowPlayingView(
                        controller: controller,
                        engine: engine,
                        navigator: navigator,
                        settingsStore: settingsStore,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final prev = tester.getCenter(find.byKey(const Key('now_playing_prev_button')));
        final play = tester.getCenter(find.byKey(const Key('now_playing_play_pause_button')));
        final next = tester.getCenter(find.byKey(const Key('now_playing_next_button')));

        expect(prev.dx, lessThan(play.dx), reason: 'NowPlaying previous must be on the left of Play');
        expect(play.dx, lessThan(next.dx), reason: 'NowPlaying play must be on the left of Next');
      },
    );
  });
}
