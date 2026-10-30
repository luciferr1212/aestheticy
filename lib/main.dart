import 'package:flutter/material.dart';

import 'package:aestheticy/audio/audio_engine.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/mpv_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/audio_lab/audio_lab_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final engine = MpvAudioEngine();
  await engine.init();
  final queue = PlaybackQueue();
  final controller = PlaybackController(engine: engine, queue: queue);
  await controller.init();
  runApp(AestheticyApp(engine: engine, controller: controller));
}

/// Root widget for the Aestheticy music player.
class AestheticyApp extends StatelessWidget {
  /// The audio engine instance (injected or defaults to [FakeAudioEngine]).
  final AudioEngine? engine;

  /// The playback controller instance.
  final PlaybackController? controller;

  /// Creates an [AestheticyApp].
  const AestheticyApp({
    super.key,
    this.engine,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveEngine = engine ?? FakeAudioEngine();
    final effectiveController = controller ??
        PlaybackController(
          engine: effectiveEngine,
          queue: PlaybackQueue(),
        );

    return MaterialApp(
      title: 'Aestheticy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B5B7B),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: AudioLabScreen(
        engine: effectiveEngine,
        controller: effectiveController,
      ),
    );
  }
}
