import 'dart:io';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/ui/glass/glass_blur_budget.dart';
import 'package:aestheticy/ui/glass/glass_button.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/now_playing/now_playing_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/bottom_now_playing_bar.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

import '../../library/fake_library_repository.dart';

class _PreloadSpyFakeEngine extends FakeAudioEngine {
  int preloadCallCount = 0;
  final List<String?> preloadedUris = [];

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        exclusiveMode: false,
        gapless: true,
        equalizer: true,
        replayGain: true,
      );

  @override
  Future<void> preloadNext(AudioSource? next) async {
    preloadCallCount++;
    preloadedUris.add(next?.uri);
    await super.preloadNext(next);
  }
}

void main() {
  group('BottomNowPlayingBar Shuffle & Repeat Tests (S2)', () {
    late Directory tempDir;
    late _PreloadSpyFakeEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late FakeLibraryRepository repository;
    late UserCollections userCollections;
    late SettingsStore settingsStore;
    late AppNavigator navigator;

    const tracks = [
      AudioSource(
        'file:///music/1.flac',
        extras: {'title': 'Track One', 'artist': 'Aria', 'durationMs': '180000'},
      ),
      AudioSource(
        'file:///music/2.flac',
        extras: {'title': 'Track Two', 'artist': 'Zed', 'durationMs': '200000'},
      ),
      AudioSource(
        'file:///music/3.flac',
        extras: {'title': 'Track Three', 'artist': 'Nova', 'durationMs': '220000'},
      ),
    ];

    setUp(() async {
      GlassBlurBudget.instance.resetForTesting();
      tempDir = await Directory.systemTemp.createTemp('aestheticy_bb_sr_');
      engine = _PreloadSpyFakeEngine();
      await engine.init();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
      repository = FakeLibraryRepository();
      userCollections = UserCollections(repository: repository);
      await userCollections.init();
      settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(
          language: 'en',
          userName: 'mido',
          glassQuality: GlassQuality.off,
          reduceMotion: true,
        ),
      );
      await settingsStore.init();
      navigator = AppNavigator();
    });

    tearDown(() async {
      settingsStore.dispose();
      userCollections.dispose();
      await controller.dispose();
      await engine.dispose();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    Widget buildBottomBarHarness({
      TextDirection textDirection = TextDirection.ltr,
    }) {
      return SettingsScope(
        store: settingsStore,
        child: GlassScope(
          controller: GlassController(quality: GlassQuality.off),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: Directionality(
              textDirection: textDirection,
              child: Scaffold(
                body: Center(
                  child: BottomNowPlayingBar(
                    controller: controller,
                    navigator: navigator,
                    settingsStore: settingsStore,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget buildBothSurfacesHarness() {
      return UserCollectionsScope(
        collections: userCollections,
        child: SettingsScope(
          store: settingsStore,
          child: GlassScope(
            controller: GlassController(quality: GlassQuality.off),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              home: Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: NowPlayingView(
                        controller: controller,
                        engine: engine,
                        navigator: navigator,
                        settingsStore: settingsStore,
                      ),
                    ),
                    BottomNowPlayingBar(
                      controller: controller,
                      navigator: navigator,
                      settingsStore: settingsStore,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'buttons appear in symmetric order [shuffle] [prev] [play/pause] [next] [repeat] in LTR and RTL without overflow',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await controller.playQueue(tracks, startIndex: 0);

        for (final dir in [TextDirection.ltr, TextDirection.rtl]) {
          settingsStore.update(
            (s) => s.copyWith(language: dir == TextDirection.rtl ? 'ar' : 'en'),
          );
          await tester.pumpWidget(buildBottomBarHarness(textDirection: dir));
          await tester.pumpAndSettle();

          final shuffleFinder = find.byKey(const Key('bottom_bar_shuffle_button'));
          final prevFinder = find.byKey(const Key('bottom_bar_prev_button'));
          final playFinder = find.byKey(const Key('bottom_bar_play_pause_button'));
          final nextFinder = find.byKey(const Key('bottom_bar_next_button'));
          final repeatFinder = find.byKey(const Key('bottom_bar_repeat_button'));

          expect(shuffleFinder, findsOneWidget);
          expect(prevFinder, findsOneWidget);
          expect(playFinder, findsOneWidget);
          expect(nextFinder, findsOneWidget);
          expect(repeatFinder, findsOneWidget);

          final shuffleDx = tester.getCenter(shuffleFinder).dx;
          final prevDx = tester.getCenter(prevFinder).dx;
          final playDx = tester.getCenter(playFinder).dx;
          final nextDx = tester.getCenter(nextFinder).dx;
          final repeatDx = tester.getCenter(repeatFinder).dx;

          expect(shuffleDx, lessThan(prevDx));
          expect(prevDx, lessThan(playDx));
          expect(playDx, lessThan(nextDx));
          expect(nextDx, lessThan(repeatDx));

          // Verify horizontal symmetry around play/pause
          expect((playDx - prevDx), closeTo(nextDx - playDx, 1.0));
          expect((playDx - shuffleDx), closeTo(repeatDx - playDx, 1.0));

          expect(tester.takeException(), isNull);
        }
        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'shuffle and repeat buttons toggle state, highlight with muted accent, show 1 badge, and trigger preloadNext refresh',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await controller.playQueue(tracks, startIndex: 0);
        engine.preloadCallCount = 0;
        engine.preloadedUris.clear();

        await tester.pumpWidget(buildBottomBarHarness());
        await tester.pumpAndSettle();

        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('bottom_bar_shuffle_button'))).variant,
          GlassButtonVariant.normal,
        );
        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('bottom_bar_repeat_button'))).variant,
          GlassButtonVariant.normal,
        );
        expect(find.byKey(const Key('bottom_bar_repeat_one_badge')), findsNothing);

        // Tap shuffle on -> selected + preload refreshed
        await tester.tap(find.byKey(const Key('bottom_bar_shuffle_button')));
        await tester.pumpAndSettle();
        expect(controller.queue.isShuffled, isTrue);
        expect(engine.preloadCallCount, 1);
        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('bottom_bar_shuffle_button'))).variant,
          GlassButtonVariant.selected,
        );

        // Tap repeat 1st time -> all (selected, no badge) + preload refreshed
        await tester.tap(find.byKey(const Key('bottom_bar_repeat_button')));
        await tester.pumpAndSettle();
        expect(controller.queue.repeatMode, RepeatMode.all);
        expect(engine.preloadCallCount, 2);
        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('bottom_bar_repeat_button'))).variant,
          GlassButtonVariant.selected,
        );
        expect(find.byKey(const Key('bottom_bar_repeat_one_badge')), findsNothing);

        // Tap repeat 2nd time -> one (selected, repeat_one icon + '1' badge)
        await tester.tap(find.byKey(const Key('bottom_bar_repeat_button')));
        await tester.pumpAndSettle();
        expect(controller.queue.repeatMode, RepeatMode.one);
        expect(engine.preloadCallCount, 3);
        final repeatOneBtn = tester.widget<GlassIconButton>(
          find.byKey(const Key('bottom_bar_repeat_button')),
        );
        expect(repeatOneBtn.variant, GlassButtonVariant.selected);
        expect(repeatOneBtn.icon, Icons.repeat_one);
        expect(find.byKey(const Key('bottom_bar_repeat_one_badge')), findsOneWidget);

        // Tap repeat 3rd time -> off (normal variant, badge gone)
        await tester.tap(find.byKey(const Key('bottom_bar_repeat_button')));
        await tester.pumpAndSettle();
        expect(controller.queue.repeatMode, RepeatMode.off);
        expect(engine.preloadCallCount, 4);
        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('bottom_bar_repeat_button'))).variant,
          GlassButtonVariant.normal,
        );
        expect(find.byKey(const Key('bottom_bar_repeat_one_badge')), findsNothing);
      },
    );

    testWidgets(
      'state stays synchronized across BottomNowPlayingBar and NowPlayingView',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await controller.playQueue(tracks, startIndex: 0);
        await tester.pumpWidget(buildBothSurfacesHarness());
        await tester.pumpAndSettle();

        // Toggle shuffle from bottom bar -> updates Now Playing
        await tester.tap(find.byKey(const Key('bottom_bar_shuffle_button')));
        await tester.pumpAndSettle();
        expect(controller.queue.isShuffled, isTrue);
        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('now_playing_shuffle_button'))).variant,
          GlassButtonVariant.selected,
        );

        // Cycle repeat from Now Playing -> updates Bottom Bar (including '1' badge)
        await tester.tap(find.byKey(const Key('now_playing_repeat_button')));
        await tester.pumpAndSettle();
        expect(controller.queue.repeatMode, RepeatMode.all);
        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('bottom_bar_repeat_button'))).variant,
          GlassButtonVariant.selected,
        );

        await tester.tap(find.byKey(const Key('now_playing_repeat_button')));
        await tester.pumpAndSettle();
        expect(controller.queue.repeatMode, RepeatMode.one);
        expect(find.byKey(const Key('bottom_bar_repeat_one_badge')), findsOneWidget);

        // Turn shuffle off via controller -> updates both surfaces
        await controller.setShuffle(false);
        await tester.pumpAndSettle();
        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('bottom_bar_shuffle_button'))).variant,
          GlassButtonVariant.normal,
        );
        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('now_playing_shuffle_button'))).variant,
          GlassButtonVariant.normal,
        );
      },
    );

    testWidgets(
      'tooltips and semantic labels are localized in English and Arabic',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await controller.playQueue(tracks, startIndex: 0);
        await tester.pumpWidget(buildBottomBarHarness());
        await tester.pumpAndSettle();

        // English tooltips & semantics
        var shuffleBtn = tester.widget<GlassIconButton>(
          find.byKey(const Key('bottom_bar_shuffle_button')),
        );
        expect(shuffleBtn.tooltip, 'Shuffle');
        expect(shuffleBtn.semanticLabel, 'Shuffle');

        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('bottom_bar_repeat_button'))).tooltip,
          'Repeat: Off',
        );
        await controller.cycleRepeatMode();
        await tester.pumpAndSettle();
        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('bottom_bar_repeat_button'))).tooltip,
          'Repeat: All',
        );
        await controller.cycleRepeatMode();
        await tester.pumpAndSettle();
        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('bottom_bar_repeat_button'))).tooltip,
          'Repeat: One',
        );

        // Switch to Arabic and verify Arabic tooltips & semantics
        await controller.cycleRepeatMode(); // back to off
        settingsStore.update((s) => s.copyWith(language: 'ar'));
        await tester.pumpWidget(buildBottomBarHarness(textDirection: TextDirection.rtl));
        await tester.pumpAndSettle();

        shuffleBtn = tester.widget<GlassIconButton>(
          find.byKey(const Key('bottom_bar_shuffle_button')),
        );
        expect(shuffleBtn.tooltip, 'عشوائي');
        expect(shuffleBtn.semanticLabel, 'عشوائي');
        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('bottom_bar_repeat_button'))).tooltip,
          'التكرار: معطل',
        );

        await controller.cycleRepeatMode();
        await tester.pumpAndSettle();
        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('bottom_bar_repeat_button'))).tooltip,
          'التكرار: الكل',
        );

        await controller.cycleRepeatMode();
        await tester.pumpAndSettle();
        expect(
          tester.widget<GlassIconButton>(find.byKey(const Key('bottom_bar_repeat_button'))).tooltip,
          'التكرار: أغنية واحدة',
        );
        expect(find.byTooltip('التكرار: أغنية واحدة'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 500));
      },
    );
  });
}
