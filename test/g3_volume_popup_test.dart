import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/bottom_now_playing_bar.dart';

void main() {
  group('G3: Volume popup dismissal verification', () {
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

    testWidgets('Volume popup closes on outside click and on Esc key', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: BottomNowPlayingBar(
                      controller: controller,
                      navigator: navigator,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final volumeBtn = find.byKey(const Key('player_volume_button'));
      expect(volumeBtn, findsOneWidget);

      // 1. Verify outside click dismissal
      await tester.tap(volumeBtn);
      await tester.pumpAndSettle();

      // Popup is visible (2 Sliders total: seek bar + volume slider)
      expect(find.byType(Slider), findsNWidgets(2));

      // Tap outside (top-left of the screen)
      await tester.tapAt(const Offset(50, 50));
      await tester.pumpAndSettle();

      // Popup is dismissed (only seek bar Slider remains)
      expect(find.byType(Slider), findsOneWidget);

      // 2. Verify Esc key dismissal
      await tester.tap(volumeBtn);
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNWidgets(2));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
    });
  });
}
