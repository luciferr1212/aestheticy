import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/volume_hud.dart';
import 'package:aestheticy/ui/shell/volume_wheel_region.dart';

void main() {
  group('VolumeWheelRegion (S6)', () {
    late FakeAudioEngine engine;
    late SettingsStore settingsStore;
    late VolumeHudController hudController;

    setUp(() async {
      engine = FakeAudioEngine();
      await engine.init();
      settingsStore = SettingsStore(
        initialSettings: const AppSettings(volume: 0.5),
      );
      hudController = VolumeHudController();
    });

    tearDown(() async {
      settingsStore.dispose();
      await engine.dispose();
      hudController.dispose();
    });

    Widget buildApp({
      required Widget child,
    }) {
      return MaterialApp(
        home: SettingsScope(
          store: settingsStore,
          child: VolumeHudScope(
            controller: hudController,
            child: Scaffold(
              body: VolumeHudOverlay(
                controller: hudController,
                engine: engine,
                settingsStore: settingsStore,
                child: Center(
                  child: VolumeWheelRegion(
                    engine: engine,
                    settingsStore: settingsStore,
                    hudController: hudController,
                    behavior: HitTestBehavior.opaque,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'Discrete wheel notch increases volume by +0.05 (up) and decreases by -0.05 (down)',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            child: const SizedBox(
              width: 100,
              height: 100,
              child: Text('Volume Target'),
            ),
          ),
        );

        final target = tester.getCenter(find.text('Volume Target'));
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        pointer.hover(target);

        // Scroll up: discrete notch dy = -120 (Flutter PointerScrollEvent dy < 0 is scroll up)
        await tester.sendEventToBinding(
          pointer.scroll(const Offset(0, -120)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(settingsStore.settings.volume, closeTo(0.55, 0.001));
        expect(engine.currentVolume, closeTo(0.55, 0.001));
        expect(hudController.isVisible, isTrue);

        // Scroll down: discrete notch dy = 120
        await tester.sendEventToBinding(
          pointer.scroll(const Offset(0, 120)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(settingsStore.settings.volume, closeTo(0.50, 0.001));
        expect(engine.currentVolume, closeTo(0.50, 0.001));

        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'Continuous trackpad scrolls accumulate to 40 logical pixels before stepping',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            child: const SizedBox(
              width: 100,
              height: 100,
              child: Text('Volume Target'),
            ),
          ),
        );

        final target = tester.getCenter(find.text('Volume Target'));
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        pointer.hover(target);

        // Send two continuous scrolls of dy = -15 (total -30 px, under threshold)
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -15)));
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.50, 0.001));

        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -15)));
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.50, 0.001));

        // Third scroll of -15 (total -45 px >= 40 threshold): steps +0.05
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -15)));
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.55, 0.001));

        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'Direction flip and pause reset the accumulator',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            child: const SizedBox(
              width: 100,
              height: 100,
              child: Text('Volume Target'),
            ),
          ),
        );

        final target = tester.getCenter(find.text('Volume Target'));
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        pointer.hover(target);

        // Send -30 px scroll up
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -30)));
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.50, 0.001));

        // Flip direction: send +20 px scroll down -> resets accumulator to 0, does not step
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.50, 0.001));

        // Send another +10 px (total +30 from flip) -> still under 40
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 10)));
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.50, 0.001));

        // Pause for 350 ms -> resets accumulator
        await tester.pump(const Duration(milliseconds: 350));

        // Now send +20 px -> fresh accumulator, does not reach 40
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.50, 0.001));

        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'Volume strictly clamps at 0.0 and 1.0',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        settingsStore.update((s) => s.copyWith(volume: 0.98));
        await engine.setVolume(0.98);

        await tester.pumpWidget(
          buildApp(
            child: const SizedBox(
              width: 100,
              height: 100,
              child: Text('Volume Target'),
            ),
          ),
        );

        final target = tester.getCenter(find.text('Volume Target'));
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        pointer.hover(target);

        // Scroll up steps +0.05: 0.98 + 0.05 = 1.03 -> clamped to 1.0
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(1.0, 0.001));

        // Set volume near bottom
        settingsStore.update((s) => s.copyWith(volume: 0.02));
        await engine.setVolume(0.02);

        // Scroll down steps -0.05: 0.02 - 0.05 = -0.03 -> clamped to 0.0
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
        await tester.pump();
        expect(settingsStore.settings.volume, closeTo(0.0, 0.001));

        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'Child taps and gestures continue without conflict',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        var clicked = 0;
        await tester.pumpWidget(
          buildApp(
            child: ElevatedButton(
              onPressed: () => clicked++,
              child: const Text('Button Inside Wheel Region'),
            ),
          ),
        );

        await tester.tap(find.text('Button Inside Wheel Region'));
        await tester.pump();
        expect(clicked, equals(1));
      },
    );
  });
}
