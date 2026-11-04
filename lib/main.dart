import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:aestheticy/audio/audio_engine.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/mpv_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/gallery/design_gallery_screen.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/l10n/locale_controller.dart';
import 'package:aestheticy/ui/settings/audio_settings_applier.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

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

  final settingsStore = SettingsStore();
  await settingsStore.init();
  final glassController = GlassController();
  settingsStore.bindGlassController(glassController);
  final localeController = LocaleController(settingsStore: settingsStore);

  final audioSettingsApplier = AudioSettingsApplier(
    engine: engine,
    settingsStore: settingsStore,
  );
  await audioSettingsApplier.applyAll();

  final artistNameStore = ArtistNameStore();
  await artistNameStore.init();

  runApp(AestheticyApp(
    engine: engine,
    controller: controller,
    repository: repository,
    scanService: scanService,
    settingsStore: settingsStore,
    glassController: glassController,
    localeController: localeController,
    audioSettingsApplier: audioSettingsApplier,
    artistNameStore: artistNameStore,
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
class AestheticyApp extends StatefulWidget {
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

  /// Optional persistent settings store.
  final SettingsStore? settingsStore;

  /// Optional glass quality controller.
  final GlassController? glassController;

  /// Optional locale controller.
  final LocaleController? localeController;

  /// Optional audio settings applier.
  final AudioSettingsApplier? audioSettingsApplier;

  /// Optional artist display names store.
  final ArtistNameStore? artistNameStore;

  /// Creates an [AestheticyApp].
  const AestheticyApp({
    super.key,
    this.engine,
    this.controller,
    this.repository,
    this.scanService,
    this.directoryPicker,
    this.settingsStore,
    this.glassController,
    this.localeController,
    this.audioSettingsApplier,
    this.artistNameStore,
  });

  @override
  State<AestheticyApp> createState() => _AestheticyAppState();
}

class _AestheticyAppState extends State<AestheticyApp> {
  late final SettingsStore _settingsStore;
  late final GlassController _glassController;
  late final LocaleController _localeController;
  late final ArtistNameStore _artistNameStore;
  late final AudioSettingsApplier _audioSettingsApplier;
  late final AppNavigator _navigator;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _settingsStore = widget.settingsStore ?? SettingsStore();
    _glassController = widget.glassController ?? GlassController();
    _settingsStore.bindGlassController(_glassController);
    _localeController = widget.localeController ??
        LocaleController(settingsStore: _settingsStore);
    _artistNameStore = widget.artistNameStore ?? ArtistNameStore();
    _audioSettingsApplier = widget.audioSettingsApplier ??
        AudioSettingsApplier(
          engine: widget.engine ?? FakeAudioEngine(),
          settingsStore: _settingsStore,
        );
    _navigator = AppNavigator();
  }

  void _openDesignGallery() {
    final nav = _navigatorKey.currentState;
    if (nav != null) {
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => DesignGalleryScreen(
            glassController: _glassController,
            localeController: _localeController,
            settingsStore: _settingsStore,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveEngine = widget.engine ?? FakeAudioEngine();
    final effectiveController = widget.controller ??
        PlaybackController(
          engine: effectiveEngine,
          queue: PlaybackQueue(),
        );
    final effectiveRepo =
        widget.repository ?? SqliteLibraryRepository.inMemory();
    final effectiveScanService =
        widget.scanService ?? ScanService(repository: effectiveRepo);

    return ListenableBuilder(
      listenable: Listenable.merge([
        _settingsStore,
        _localeController,
        _glassController,
        _artistNameStore,
      ]),
      builder: (context, _) {
        final scaleFactor = switch (_settingsStore.settings.textScale) {
          'small' => 0.92,
          'large' => 1.10,
          _ => 1.0,
        };

        return GlassScope(
          controller: _glassController,
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(
                LogicalKeyboardKey.keyG,
                control: true,
                shift: true,
              ): _openDesignGallery,
            },
            child: Focus(
              autofocus: true,
              child: MaterialApp(
                navigatorKey: _navigatorKey,
                title: 'Aestheticy',
                debugShowCheckedModeBanner: false,
                locale: _localeController.locale,
                theme: buildAppTheme(uiFont: _settingsStore.settings.uiFont),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scaleFactor),
                  ),
                  child: Directionality(
                    textDirection: _localeController.textDirection,
                    child: SettingsScope(
                      store: _settingsStore,
                      child: ArtistNameScope(
                        store: _artistNameStore,
                        child: child!,
                      ),
                    ),
                  ),
                ),
                home: AppShell(
                  engine: effectiveEngine,
                  controller: effectiveController,
                  repository: effectiveRepo,
                  scanService: effectiveScanService,
                  settingsStore: _settingsStore,
                  navigator: _navigator,
                  directoryPicker: widget.directoryPicker,
                  audioSettingsApplier: _audioSettingsApplier,
                  artistNameStore: _artistNameStore,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
