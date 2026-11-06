import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:aestheticy/audio/audio_engine.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/mpv_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/features/history/play_recorder.dart';
import 'package:aestheticy/features/session/session_restorer.dart';
import 'package:aestheticy/features/session/session_saver.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/library/cover_cache.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/migrations.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/audio_panels/eq_controller.dart';
import 'package:aestheticy/ui/audio_panels/eq_scope.dart';
import 'package:aestheticy/ui/audio_panels/eq_store.dart';
import 'package:aestheticy/ui/gallery/design_gallery_screen.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/l10n/locale_controller.dart';
import 'package:aestheticy/ui/quick_search/quick_search_overlay.dart';
import 'package:aestheticy/ui/settings/app_shortcuts.dart';
import 'package:aestheticy/ui/settings/audio_settings_applier.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppLogger.instance.init();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      AppLogger.instance.error(
        'Flutter',
        'FlutterError: ${details.exceptionAsString()}',
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.instance.error(
        'Platform',
        'PlatformDispatcher error: $error',
        error,
        stack,
      );
      return true;
    };

    final AudioEngine engine;
    final PlaybackController controller;
    try {
      engine = MpvAudioEngine();
      await engine.init();
      final queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
      AppLogger.instance.info('Audio', 'Audio engine initialized');
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        'Audio',
        'Audio engine init failed: $error',
        error,
        stackTrace,
      );
      runApp(AudioInitErrorApp(
        error: error.toString(),
        stackTrace: stackTrace.toString(),
      ));
      return;
    }

    controller.errorStream.listen((err) {
      AppLogger.instance.warning('Playback', 'Playback error: $err');
    });

    final SqliteLibraryRepository repository;
    final ScanService scanService;
    try {
      await CoverCache.ensureInitialized();
      repository = await SqliteLibraryRepository.openDefault();
      scanService = ScanService(repository: repository);
      AppLogger.instance.info(
        'Library',
        'Library opened successfully at schema v$kLibrarySchemaVersion',
      );
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        'Library',
        'Library init failed: $error',
        error,
        stackTrace,
      );
      runApp(LibraryInitErrorApp(
        error: error.toString(),
        stackTrace: stackTrace.toString(),
      ));
      return;
    }

    scanService.progressStream.listen((p) {
      if (p.done) {
        AppLogger.instance.info(
          'Scan',
          'Scan finished: found ${p.found}, added ${p.added}, updated ${p.updated}',
        );
      } else if (p.errors > 0 || p.unreadableDirs > 0) {
        AppLogger.instance.warning(
          'Scan',
          'Scan errors: errors ${p.errors}, unreadable ${p.unreadableDirs}',
        );
      }
    });

    final settingsStore = SettingsStore();
    await settingsStore.init();
    final glassController = GlassController();
    settingsStore.bindGlassController(glassController);
    final localeController = LocaleController(settingsStore: settingsStore);

    final audioSettingsApplier = AudioSettingsApplier(
      engine: engine,
      settingsStore: settingsStore,
    );
    try {
      await audioSettingsApplier.applyAll();
    } catch (error, stackTrace) {
      AppLogger.instance.warning(
        'Audio',
        'AudioSettingsApplier failed: $error',
        error,
        stackTrace,
      );
    }

    final eqStore = EqStore();
    await eqStore.init();
    final eqController = EqController(engine: engine, store: eqStore);
    await eqController.applyAll();

    final artistNameStore = ArtistNameStore();
    await artistNameStore.init();

    final sessionStore = SessionStore();
    await sessionStore.init();

    if (settingsStore.settings.resumeSession) {
      final restoreResult = await restoreSession(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
      );
      AppLogger.instance.info(
        'Session',
        'Session restore: restored ${restoreResult.restoredCount}, dropped ${restoreResult.droppedCount}',
      );
    }

    final sessionSaver = SessionSaver(
      controller: controller,
      sessionStore: sessionStore,
      settingsStore: settingsStore,
    );

    final playRecorder = PlayRecorder(
      controller: controller,
      repository: repository,
    );

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
      eqController: eqController,
      sessionStore: sessionStore,
      sessionSaver: sessionSaver,
      playRecorder: playRecorder,
    ));
  }, (error, stack) {
    AppLogger.instance.error(
      'Zone',
      'Unhandled zone error: $error',
      error,
      stack,
    );
  });
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

  /// Optional equalizer controller.
  final EqController? eqController;

  /// Optional listening history recorder.
  final PlayRecorder? playRecorder;

  /// Optional session storage.
  final SessionStore? sessionStore;

  /// Optional session saver.
  final SessionSaver? sessionSaver;

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
    this.eqController,
    this.sessionStore,
    this.sessionSaver,
    this.playRecorder,
  });

  @override
  State<AestheticyApp> createState() => _AestheticyAppState();
}

class _AestheticyAppState extends State<AestheticyApp> {
  late final SettingsStore _settingsStore;
  late final GlassController _glassController;
  late final LocaleController _localeController;
  late final ArtistNameStore _artistNameStore;
  late final EqController _eqController;
  late final AudioSettingsApplier _audioSettingsApplier;
  late final AppNavigator _navigator;
  late final SessionStore _sessionStore;
  PlayRecorder? _playRecorder;
  SessionSaver? _sessionSaver;
  AppLifecycleListener? _lifecycleListener;
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
    _eqController = widget.eqController ??
        EqController(
          engine: widget.engine ?? FakeAudioEngine(),
          store: EqStore(),
        );
    _audioSettingsApplier = widget.audioSettingsApplier ??
        AudioSettingsApplier(
          engine: widget.engine ?? FakeAudioEngine(),
          settingsStore: _settingsStore,
        );
    _navigator = AppNavigator();
    _sessionStore = widget.sessionStore ?? SessionStore();
    _sessionSaver = widget.sessionSaver;
    _playRecorder = widget.playRecorder;

    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        _sessionSaver?.saveSnapshotSync();
        return AppExitResponse.exit;
      },
      onDetach: () {
        _sessionSaver?.saveSnapshotSync();
      },
      onHide: () {
        _sessionSaver?.saveSnapshotSync();
      },
      onPause: () {
        _sessionSaver?.saveSnapshotSync();
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    _playRecorder?.dispose();
    _sessionSaver?.dispose();
    _sessionStore.dispose();
    super.dispose();
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

  void _toggleQuickSearch() {
    final ctx = _navigatorKey.currentContext;
    if (ctx != null) {
      toggleQuickSearch(
        context: ctx,
        repository: widget.repository ?? SqliteLibraryRepository.inMemory(),
        controller: widget.controller ??
            PlaybackController(
              engine: widget.engine ?? FakeAudioEngine(),
              queue: PlaybackQueue(),
            ),
        navigator: _navigator,
        settingsStore: _settingsStore,
        artistNameStore: _artistNameStore,
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
        _eqController,
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
              shortcutById(AppShortcutId.gallery).activator:
                  _openDesignGallery,
              shortcutById(AppShortcutId.quickSearch).activator:
                  _toggleQuickSearch,
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
                        child: EqScope(
                          controller: _eqController,
                          child: child!,
                        ),
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
                  eqController: _eqController,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
