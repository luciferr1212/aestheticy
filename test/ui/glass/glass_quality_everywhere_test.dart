import 'dart:io';

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
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/mini_player/mini_player_controller.dart';
import 'package:aestheticy/ui/mini_player/mini_player_view.dart';
import 'package:aestheticy/ui/now_playing/full_screen_view.dart';
import 'package:aestheticy/ui/now_playing/now_playing_view.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/ambient_background.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/bottom_now_playing_bar.dart';
import 'package:aestheticy/ui/theme/app_colors.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import 'package:aestheticy/ui/theme/dither_noise.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Glass Quality Everywhere (S8)', () {
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

    const sampleTrack = AudioSource(
      'file:///test/ambient_song.mp3',
      extras: {
        'title': 'Test Song',
        'artist': 'Test Artist',
        'album': 'Test Album',
        'durationMs': '200000',
      },
    );

    setUp(() async {
      GlassBlurBudget.instance.resetForTesting();
      glassController = GlassController();
      tempDir = await Directory.systemTemp.createTemp('glass_quality_test_');
      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();
      settingsStore.bindGlassController(glassController);

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

      await controller.playQueue([sampleTrack], startIndex: 0);
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

    Widget wrapSurface({
      required Widget child,
      required GlassQuality quality,
    }) {
      glassController.quality = quality;
      settingsStore.update((s) => s.copyWith(glassQuality: quality));
      return MaterialApp(
        theme: buildAppTheme(),
        home: GlassScope(
          controller: glassController,
          child: SettingsScope(
            store: settingsStore,
            child: ArtistNameScope(
              store: artistNameStore,
              child: Scaffold(
                body: child,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'AmbientBackground: full and light have dither, off is flat base color without dither',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        // 1. Full quality
        await tester.pumpWidget(
          wrapSurface(
            child: AmbientBackground(settingsStore: settingsStore),
            quality: GlassQuality.full,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(DitherOverlay), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is CustomPaint &&
                w.painter.runtimeType.toString() == '_AmbientBackgroundPainter',
          ),
          findsOneWidget,
        );
        expect(find.byType(BackdropFilter), findsNothing);

        // 2. Light quality
        settingsStore.update((s) => s.copyWith(glassQuality: GlassQuality.light));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(DitherOverlay), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is CustomPaint &&
                w.painter.runtimeType.toString() == '_AmbientBackgroundPainter',
          ),
          findsOneWidget,
        );
        expect(find.byType(BackdropFilter), findsNothing);

        // 3. Off quality
        settingsStore.update((s) => s.copyWith(glassQuality: GlassQuality.off));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(DitherOverlay), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is CustomPaint &&
                w.painter.runtimeType.toString() == '_AmbientBackgroundPainter',
          ),
          findsNothing,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == AppColors.base,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'FullScreenView: blobs animate at full, static at light, absent at off, updates live',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Full quality
        await tester.pumpWidget(
          wrapSurface(
            child: FullScreenView(
              controller: controller,
              engine: engine,
              navigator: navigator,
              settingsStore: settingsStore,
              miniPlayerController: miniController,
            ),
            quality: GlassQuality.full,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // BackdropFilter within budget
        final blurCountFull = find.byType(BackdropFilter).evaluate().length;
        expect(blurCountFull <= 6, isTrue);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is CustomPaint &&
                w.painter.runtimeType.toString() == '_BlobPainter',
          ),
          findsOneWidget,
        );

        // 2. Light quality
        settingsStore.update((s) => s.copyWith(glassQuality: GlassQuality.light));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final blurCountLight = find.byType(BackdropFilter).evaluate().length;
        expect(blurCountLight, equals(0));
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is CustomPaint &&
                w.painter.runtimeType.toString() == '_StaticBlobPainter',
          ),
          findsOneWidget,
        );

        // 3. Off quality
        settingsStore.update((s) => s.copyWith(glassQuality: GlassQuality.off));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final blurCountOff = find.byType(BackdropFilter).evaluate().length;
        expect(blurCountOff, equals(0));
        expect(find.byType(DitherOverlay), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is CustomPaint &&
                (w.painter.runtimeType.toString() == '_BlobPainter' ||
                    w.painter.runtimeType.toString() == '_StaticBlobPainter'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'NowPlayingView: BackdropFilter <= 6 at full, 0 at light and off',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Full quality
        await tester.pumpWidget(
          wrapSurface(
            child: NowPlayingView(
              controller: controller,
              engine: engine,
              navigator: navigator,
              settingsStore: settingsStore,
            ),
            quality: GlassQuality.full,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final fullBlurs = find.byType(BackdropFilter).evaluate().length;
        expect(fullBlurs <= 6, isTrue);

        // 2. Light quality -> 0 BackdropFilter
        settingsStore.update((s) => s.copyWith(glassQuality: GlassQuality.light));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final lightBlurs = find.byType(BackdropFilter).evaluate().length;
        expect(lightBlurs, equals(0));

        // 3. Off quality -> 0 BackdropFilter, no dither
        settingsStore.update((s) => s.copyWith(glassQuality: GlassQuality.off));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        final offBlurs = find.byType(BackdropFilter).evaluate().length;
        expect(offBlurs, equals(0));
        expect(find.byType(DitherOverlay), findsNothing);
      },
    );

    testWidgets(
      'MiniPlayerView: 0 BackdropFilter at light and off, flat opaque at off',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(480, 200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Full quality
        await tester.pumpWidget(
          wrapSurface(
            child: MiniPlayerView(
              controller: miniController,
              playbackController: controller,
            ),
            quality: GlassQuality.full,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final fullBlurs = find.byType(BackdropFilter).evaluate().length;
        expect(fullBlurs <= 6, isTrue);

        // 2. Light quality
        settingsStore.update((s) => s.copyWith(glassQuality: GlassQuality.light));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(BackdropFilter).evaluate().length, equals(0));

        // 3. Off quality
        settingsStore.update((s) => s.copyWith(glassQuality: GlassQuality.off));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(BackdropFilter).evaluate().length, equals(0));
        expect(find.byType(DitherOverlay), findsNothing);
      },
    );

    testWidgets(
      'BottomNowPlayingBar: 0 BackdropFilter at light and off, updates live',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Full quality
        await tester.pumpWidget(
          wrapSurface(
            child: BottomNowPlayingBar(
              controller: controller,
              navigator: navigator,
              miniPlayerController: miniController,
              settingsStore: settingsStore,
            ),
            quality: GlassQuality.full,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final fullBlurs = find.byType(BackdropFilter).evaluate().length;
        expect(fullBlurs <= 6, isTrue);

        // 2. Light quality
        settingsStore.update((s) => s.copyWith(glassQuality: GlassQuality.light));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(BackdropFilter).evaluate().length, equals(0));

        // 3. Off quality
        settingsStore.update((s) => s.copyWith(glassQuality: GlassQuality.off));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(BackdropFilter).evaluate().length, equals(0));
      },
    );
  });
}
