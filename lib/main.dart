import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:aestheticy/audio/audio_engine.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/mpv_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/library/library_screen.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AudioEngine engine;
  final PlaybackController controller;
  try {
    engine = MpvAudioEngine();
    await engine.init();
    final queue = PlaybackQueue();
    controller = PlaybackController(engine: engine, queue: queue);
    await controller.init();
  } catch (error, stackTrace) {
    runApp(AudioInitErrorApp(
      error: error.toString(),
      stackTrace: stackTrace.toString(),
    ));
    return;
  }

  final SqliteLibraryRepository repository;
  final ScanService scanService;
  try {
    repository = await SqliteLibraryRepository.openDefault();
    scanService = ScanService(repository: repository);
  } catch (error, stackTrace) {
    runApp(LibraryInitErrorApp(
      error: error.toString(),
      stackTrace: stackTrace.toString(),
    ));
    return;
  }

  runApp(AestheticyApp(
    engine: engine,
    controller: controller,
    repository: repository,
    scanService: scanService,
  ));
}

/// Fallback screen shown when the audio engine fails to initialize.
class AudioInitErrorApp extends StatelessWidget {
  /// The error description.
  final String error;

  /// The stack trace, if available.
  final String stackTrace;

  /// Creates an [AudioInitErrorApp].
  const AudioInitErrorApp({
    super.key,
    required this.error,
    this.stackTrace = '',
  });

  @override
  Widget build(BuildContext context) {
    final fullError = stackTrace.isNotEmpty ? '$error\n\n$stackTrace' : error;

    return MaterialApp(
      title: 'Aestheticy — Audio Error',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Aestheticy / by mido'),
          backgroundColor: const Color(0xFF1E1E1E),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Audio Engine Initialization Failed',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The audio engine (libmpv) could not be loaded or initialized on this device. '
                    'Please copy the error log below and report it:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        fullError,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.amberAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (ctx) => ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: fullError));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Error copied to clipboard!')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy Error Log'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fallback screen shown when the library database fails to open.
class LibraryInitErrorApp extends StatelessWidget {
  /// The error description.
  final String error;

  /// The stack trace, if available.
  final String stackTrace;

  /// Creates a [LibraryInitErrorApp].
  const LibraryInitErrorApp({
    super.key,
    required this.error,
    this.stackTrace = '',
  });

  @override
  Widget build(BuildContext context) {
    final fullError = stackTrace.isNotEmpty ? '$error\n\n$stackTrace' : error;

    return MaterialApp(
      title: 'Aestheticy — Database Error',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Aestheticy / by mido'),
          backgroundColor: const Color(0xFF1E1E1E),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.folder_off, color: Colors.redAccent, size: 36),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Library database failed to open',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The local library database could not be opened or migrated on this device. '
                    'Please copy the error log below and report it:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        fullError,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.amberAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (ctx) => ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: fullError));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Error copied to clipboard!')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy Error Log'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Root widget for the Aestheticy music player.
class AestheticyApp extends StatelessWidget {
  /// The audio engine instance (injected or defaults to [FakeAudioEngine]).
  final AudioEngine? engine;

  /// The playback controller instance.
  final PlaybackController? controller;

  /// The library storage repository.
  final LibraryRepository? repository;

  /// The library scanner service.
  final ScanService? scanService;

  /// Optional injected directory picker for tests.
  final Future<String?> Function()? directoryPicker;

  /// Creates an [AestheticyApp].
  const AestheticyApp({
    super.key,
    this.engine,
    this.controller,
    this.repository,
    this.scanService,
    this.directoryPicker,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveEngine = engine ?? FakeAudioEngine();
    final effectiveController = controller ??
        PlaybackController(
          engine: effectiveEngine,
          queue: PlaybackQueue(),
        );
    final effectiveRepo = repository ?? SqliteLibraryRepository.inMemory();
    final effectiveScanService =
        scanService ?? ScanService(repository: effectiveRepo);

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
      home: LibraryScreen(
        engine: effectiveEngine,
        controller: effectiveController,
        repository: effectiveRepo,
        scanService: effectiveScanService,
        directoryPicker: directoryPicker,
      ),
    );
  }
}
