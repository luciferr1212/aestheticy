import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/ui/glass/glass_blur_budget.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/now_playing/full_screen_view.dart';
import 'package:aestheticy/ui/now_playing/now_playing_view.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/bottom_now_playing_bar.dart';

void main() {
  group('G1: Duration StreamBuilder initialData reproduction', () {
    late Directory tempDir;
    late SettingsStore settingsStore;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late AppNavigator navigator;

    setUp(() async {
      GlassBlurBudget.instance.resetForTesting();
      tempDir = await Directory.systemTemp.createTemp('g1_test_');
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

    testWidgets('BottomNowPlayingBar built AFTER duration event shows 3:00, not 0:00', (tester) async {
      queue.add(const AudioSource('test.mp3', extras: {'title': 'Test Song', 'artist': 'Artist'}));
      engine.fakeDuration = const Duration(minutes: 3);
      // Play and emit duration BEFORE widget is mounted
      await controller.play();

      // Now mount BottomNowPlayingBar
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.ltr,
              child: BottomNowPlayingBar(
                controller: controller,
                navigator: navigator,
              ),
            ),
          ),
        ),
      );

      // The duration text in the seekbar should display 3:00 immediately from initialData, not 0:00
      expect(find.text('3:00'), findsOneWidget);
    });

    testWidgets('BottomNowPlayingBar switches tracks while mounted and updates duration', (tester) async {
      queue.add(const AudioSource('test1.mp3', extras: {'title': 'Song 1', 'artist': 'Artist 1'}));
      queue.add(const AudioSource('test2.mp3', extras: {'title': 'Song 2', 'artist': 'Artist 2'}));
      engine.fakeDuration = const Duration(minutes: 3);
      await controller.play();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.ltr,
              child: BottomNowPlayingBar(
                controller: controller,
                navigator: navigator,
              ),
            ),
          ),
        ),
      );

      // Now switch track and change duration
      engine.fakeDuration = const Duration(minutes: 5);
      await controller.skipNext();
      await tester.pumpAndSettle();

      expect(find.text('5:00'), findsOneWidget);
    });

    testWidgets('NowPlayingView built AFTER duration event shows total duration, not 0:00', (tester) async {
      queue.add(const AudioSource('test.mp3', extras: {'title': 'Test Song', 'artist': 'Artist'}));
      engine.fakeDuration = const Duration(minutes: 3);
      await controller.play();

      await tester.pumpWidget(
        MaterialApp(
          home: GlassScope(
            controller: GlassController(quality: GlassQuality.full),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: NowPlayingView(
                controller: controller,
                engine: engine,
                navigator: navigator,
                settingsStore: settingsStore,
              ),
            ),
          ),
        ),
      );

      expect(find.text('3:00'), findsOneWidget);
    });

    testWidgets('FullScreenView built AFTER duration event shows total duration, not 0:00', (tester) async {
      queue.add(const AudioSource('test.mp3', extras: {'title': 'Test Song', 'artist': 'Artist'}));
      engine.fakeDuration = const Duration(minutes: 3);
      await controller.play();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: FullScreenView(
              controller: controller,
              engine: engine,
              navigator: navigator,
              settingsStore: settingsStore,
            ),
          ),
        ),
      );

      // Trigger hover over bottom progress bar so time labels are visible
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getRect(find.byType(FullScreenView)).bottomCenter - const Offset(0, 1));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('3:00'), findsOneWidget);
      await mouse.removePointer();
    });
  });
}
