import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/audio_lab/audio_lab_screen.dart';

void main() {
  group('AudioLabScreen Widget Tests', () {
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;

    setUp(() async {
      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
    });

    tearDown(() async {
      await controller.dispose();
      await engine.dispose();
    });

    Widget createTestWidget() {
      return MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: AudioLabScreen(
          engine: engine,
          controller: controller,
        ),
      );
    }

    testWidgets('the queue renders chosen files', (tester) async {
      // Add test items to the queue.
      queue.add(
        const AudioSource(
          'file:///music/song1.mp3',
          extras: {'title': 'First Song'},
        ),
      );
      queue.add(
        const AudioSource(
          'file:///music/song2.flac',
          extras: {'title': 'Second Song'},
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify the queue section title and items render.
      expect(find.text('Queue (2 tracks)'), findsOneWidget);
      expect(find.text('First Song'), findsOneWidget);
      expect(find.text('Second Song'), findsOneWidget);
    });

    testWidgets('tapping a track starts it', (tester) async {
      queue.add(
        const AudioSource(
          'file:///music/track_a.mp3',
          extras: {'title': 'Track Alpha'},
        ),
      );
      queue.add(
        const AudioSource(
          'file:///music/track_b.flac',
          extras: {'title': 'Track Beta'},
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap on Track Beta.
      await tester.tap(find.text('Track Beta'));
      await tester.pumpAndSettle();

      // Engine should have opened Track Beta and entered playing state.
      expect(engine.openedSource?.uri, 'file:///music/track_b.flac');
      expect(engine.state, PlaybackState.playing);
    });

    testWidgets('the EQ reset button sets all gains to 0', (tester) async {
      // Set non-zero EQ gains and preamp.
      await engine.setEqGains([6, 6, 6, 6, 6, -3, -3, -3, -3, -3]);
      await engine.setPreamp(4.5);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find the Reset button.
      final resetButton = find.byKey(const Key('eq_reset_button'));
      expect(resetButton, findsOneWidget);

      // Scroll into view if needed and tap Reset.
      await tester.ensureVisible(resetButton);
      await tester.tap(resetButton);
      await tester.pumpAndSettle();

      // Verify that engine gains and preamp are reset to 0.0.
      expect(engine.eqGains, List<double>.filled(10, 0.0));
      expect(engine.preamp, 0.0);
    });
  });
}
