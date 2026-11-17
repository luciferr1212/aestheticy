import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/bottom_now_playing_bar.dart';

void main() {
  group('BottomNowPlayingBar Equalizer Button (S4)', () {
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late AppNavigator navigator;

    setUp(() async {
      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
      navigator = AppNavigator();
    });

    tearDown(() async {
      await controller.dispose();
      await engine.dispose();
    });

    testWidgets(
      'tapping equalizer button in bottom bar navigates to audio panels',
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
            home: Scaffold(
              body: GlassScope(
                controller: GlassController(quality: GlassQuality.light),
                child: BottomNowPlayingBar(
                  controller: controller,
                  navigator: navigator,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final eqButtonFinder = find.byKey(const Key('player_equalizer_button'));
        expect(eqButtonFinder, findsOneWidget);

        // Verify initial destination is not audioPanels
        expect(navigator.currentDestination, isNot(equals(AppDestination.audioPanels)));

        // Tap the equalizer button
        await tester.tap(eqButtonFinder);
        await tester.pumpAndSettle();

        // Verify navigator navigated to audioPanels destination
        expect(navigator.currentDestination, equals(AppDestination.audioPanels));
      },
    );

    testWidgets(
      'equalizer button keeps tooltip and semantics',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GlassScope(
                controller: GlassController(quality: GlassQuality.light),
                child: BottomNowPlayingBar(
                  controller: controller,
                  navigator: navigator,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final eqButton = find.byKey(const Key('player_equalizer_button'));
        expect(eqButton, findsOneWidget);

        final semantics = tester.getSemantics(eqButton);
        expect(semantics.label, equals('Equalizer'));
        expect(semantics.tooltip, equals('Equalizer'));
      },
    );
  });
}
