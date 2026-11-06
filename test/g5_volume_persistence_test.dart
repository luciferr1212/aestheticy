import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/audio_settings_applier.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/bottom_now_playing_bar.dart';

void main() {
  group('G5: Volume Persistence and Popup Tests', () {
    late Directory tempDir;
    late SettingsStore settingsStore;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late AppNavigator navigator;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('g5_test_');
      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();

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
      settingsStore.dispose();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('AppSettings volume serialization, clamping, and tolerant fallback', () {
      // Default volume is 1.0
      const defaultSettings = AppSettings();
      expect(defaultSettings.volume, equals(1.0));

      // Clamping: < 0.0 clamps to 0.0, > 1.0 clamps to 1.0
      final clampedLow = const AppSettings().copyWith(volume: -0.5);
      expect(clampedLow.volume, equals(0.0));
      final clampedHigh = const AppSettings().copyWith(volume: 1.5);
      expect(clampedHigh.volume, equals(1.0));

      // Tolerant fromJson
      final json = {'volume': 0.7};
      final fromJson = AppSettings.fromJson(json);
      expect(fromJson.volume, equals(0.7));

      final invalidJson = {'volume': 'invalid'};
      final fallback = AppSettings.fromJson(invalidJson);
      expect(fallback.volume, equals(1.0));

      // Round trip
      final serialized = fromJson.toJson();
      expect(serialized['volume'], equals(0.7));
    });

    test('Startup applies saved volume to the audio engine', () async {
      // Save 0.3 to settings
      settingsStore.update((s) => s.copyWith(volume: 0.3));
      await settingsStore.flush();

      // AudioSettingsApplier applies volume at startup
      final applier = AudioSettingsApplier(
        engine: engine,
        settingsStore: settingsStore,
      );
      await applier.applyAll();

      expect(engine.currentVolume, equals(0.3));
    });

    testWidgets('Volume popup reads real volume, reopen shows updated volume, and volume change persists', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Set engine volume to 0.7 initially
      await engine.setVolume(0.7);

      Widget buildApp() {
        return MaterialApp(
          home: SettingsScope(
            store: settingsStore,
            child: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: BottomNowPlayingBar(
                      controller: controller,
                      navigator: navigator,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Open volume popup
      final volumeBtn = find.byKey(const Key('player_volume_button'));
      await tester.tap(volumeBtn);
      await tester.pumpAndSettle();

      // Slider should read 0.7 (not 1.0 default)
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders.any((s) => (s.value - 0.7).abs() < 0.01), isTrue);

      // Change volume via slider to 0.5
      final volumeSliderFinder = find.byWidgetPredicate((w) => w is Slider && (w.value - 0.7).abs() < 0.01);
      final volumeSlider = tester.widget<Slider>(volumeSliderFinder);
      volumeSlider.onChanged?.call(0.5);
      await tester.pump();
      await tester.runAsync(() async {
        await settingsStore.flush();
      });

      // Engine volume updated to 0.5
      expect(engine.currentVolume, closeTo(0.5, 0.01));
      // Settings updated to 0.5
      expect(settingsStore.settings.volume, closeTo(0.5, 0.01));

      // Close popup via Esc key
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Reopen popup and verify it shows 0.5
      await tester.tap(volumeBtn);
      await tester.pumpAndSettle();

      final reopenedSliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(reopenedSliders.any((s) => (s.value - 0.5).abs() < 0.01), isTrue);

      // Clean up popup
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });
  });
}
