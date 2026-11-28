import 'dart:async';

import 'package:flutter/material.dart';

import 'package:aestheticy/app/app_services.dart';
import 'package:aestheticy/app/window_lifecycle.dart';
import 'package:aestheticy/audio/audio_engine.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/features/history/play_recorder.dart';
import 'package:aestheticy/features/integration/app_shutdown.dart';
import 'package:aestheticy/features/integration/media_session_controller.dart';
import 'package:aestheticy/features/integration/sleep_controller.dart';
import 'package:aestheticy/features/integration/tray_window_controller.dart';
import 'package:aestheticy/features/lyrics/lyrics_controller.dart';
import 'package:aestheticy/features/lyrics/lyrics_offset_store.dart';
import 'package:aestheticy/features/lyrics/lyrics_repository.dart';
import 'package:aestheticy/features/session/session_saver.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite/userdata_backup_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/startup_identity_reconciler.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';
import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/platform/media_session_service.dart';
import 'package:aestheticy/platform/platform_services.dart';
import 'package:aestheticy/platform/sleep_inhibitor.dart';
import 'package:aestheticy/platform/tray_service.dart';
import 'package:aestheticy/platform/window_service.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/audio_panels/eq_controller.dart';
import 'package:aestheticy/ui/audio_panels/eq_scope.dart';
import 'package:aestheticy/ui/audio_panels/eq_store.dart';
import 'package:aestheticy/ui/gallery/design_gallery_screen.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/l10n/locale_controller.dart';
import 'package:aestheticy/ui/library/library_data_cache.dart';
import 'package:aestheticy/ui/mini_player/mini_player_controller.dart';
import 'package:aestheticy/ui/mini_player/mini_player_view.dart';
import 'package:aestheticy/ui/quick_search/quick_search_overlay.dart';
import 'package:aestheticy/ui/settings/app_shortcuts.dart';
import 'package:aestheticy/ui/settings/audio_settings_applier.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/shell/volume_hud.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

/// Root widget for the Aestheticy music player.
class AestheticyApp extends StatefulWidget {
  final AudioEngine? engine;
  final PlaybackController? controller;
  final LibraryRepository? repository;
  final ScanService? scanService;
  final Future<String?> Function()? directoryPicker;
  final SettingsStore? settingsStore;
  final GlassController? glassController;
  final LocaleController? localeController;
  final AudioSettingsApplier? audioSettingsApplier;
  final ArtistNameStore? artistNameStore;
  final EqController? eqController;
  final UserCollections? userCollections;
  final PlayRecorder? playRecorder;
  final SessionStore? sessionStore;
  final SessionSaver? sessionSaver;
  final MediaSessionService? mediaSessionService;
  final SleepInhibitor? sleepInhibitor;
  final TrayService? trayService;
  final WindowService? windowService;
  final AppShutdownCoordinator? shutdownCoordinator;
  final MediaSessionController? mediaSessionController;
  final SleepController? sleepController;
  final TrayWindowController? trayWindowController;
  final LyricsController? lyricsController;
  final MiniPlayerController? miniPlayerController;
  final DatabaseStartupReport? startupReport;
  final UserDataBackupService? userDataBackupService;
  final VoidCallback? onOpenLogsFolder;
  final VoidCallback? onOpenBackupsFolder;
  final Future<void> Function(String path)? onOpenFolder;

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
    this.userCollections,
    this.sessionStore,
    this.sessionSaver,
    this.playRecorder,
    this.mediaSessionService,
    this.sleepInhibitor,
    this.trayService,
    this.windowService,
    this.shutdownCoordinator,
    this.mediaSessionController,
    this.sleepController,
    this.trayWindowController,
    this.lyricsController,
    this.miniPlayerController,
    this.startupReport,
    this.userDataBackupService,
    this.onOpenLogsFolder,
    this.onOpenBackupsFolder,
    this.onOpenFolder,
  });

  /// Creates an [AestheticyApp] populated from a bootstrapped [AppServices] container.
  factory AestheticyApp.fromServices(AppServices services, {Key? key}) {
    return AestheticyApp(
      key: key,
      engine: services.engine,
      controller: services.controller,
      repository: services.repository,
      scanService: services.scanService,
      settingsStore: services.settingsStore,
      glassController: services.glassController,
      localeController: services.localeController,
      audioSettingsApplier: services.audioSettingsApplier,
      artistNameStore: services.artistNameStore,
      eqController: services.eqController,
      userCollections: services.userCollections,
      sessionStore: services.sessionStore,
      sessionSaver: services.sessionSaver,
      playRecorder: services.playRecorder,
      mediaSessionService: services.mediaSessionService,
      sleepInhibitor: services.sleepInhibitor,
      trayService: services.trayService,
      windowService: services.windowService,
      shutdownCoordinator: services.shutdownCoordinator,
      mediaSessionController: services.mediaSessionController,
      sleepController: services.sleepController,
      trayWindowController: services.trayWindowController,
      startupReport: services.startupReport,
      userDataBackupService: services.userDataBackupService,
      onOpenLogsFolder: services.onOpenLogsFolder,
      onOpenBackupsFolder: services.onOpenBackupsFolder,
      onOpenFolder: services.onOpenFolder,
    );
  }

  @override
  State<AestheticyApp> createState() => _AestheticyAppState();
}

class _AestheticyAppState extends State<AestheticyApp> {
  late final AudioEngine _engine;
  bool _createdEngineLocally = false;
  late final PlaybackController _playbackController;
  bool _createdMiniPlayerControllerLocally = false;
  bool _createdPlaybackControllerLocally = false;
  late final LyricsController _lyricsController;
  bool _createdLyricsControllerLocally = false;
  LyricsOffsetStore? _lyricsOffsetStore;
  late final LibraryRepository _repository;
  late final ScanService _scanService;
  late final SettingsStore _settingsStore;
  late final GlassController _glassController;
  late final LocaleController _localeController;
  late final ArtistNameStore _artistNameStore;
  late final EqController _eqController;
  late final UserCollections _userCollections;
  late final AudioSettingsApplier _audioSettingsApplier;
  late final AppNavigator _navigator;
  late final SessionStore _sessionStore;
  late final AppShutdownCoordinator _shutdownCoordinator;
  late final MiniPlayerController _miniPlayerController;
  late final WindowLifecycleCoordinator _windowLifecycle;
  MediaSessionController? _mediaSessionController;
  SleepController? _sleepController;
  TrayWindowController? _trayWindowController;
  PlayRecorder? _playRecorder;
  SessionSaver? _sessionSaver;
  late final LibraryDataCache _dataCache;
  late final StartupIdentityReconciler _startupIdentityReconciler;
  bool _disposed = false;
  late final VolumeHudController _volumeHudController;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _volumeHudController = VolumeHudController();
    _engine = widget.engine ?? FakeAudioEngine();
    _createdEngineLocally = widget.engine == null;
    if (widget.controller != null) {
      _playbackController = widget.controller!;
    } else {
      _playbackController = PlaybackController(
        engine: _engine,
        queue: PlaybackQueue(),
      );
      _createdPlaybackControllerLocally = true;
    }
    _repository = widget.repository ?? SqliteLibraryRepository.inMemory();
    _scanService = widget.scanService ?? ScanService(repository: _repository);
    _dataCache = LibraryDataCache(
      repository: _repository,
      scanService: _scanService,
    );
    unawaited(_dataCache.refresh());
    _startupIdentityReconciler = StartupIdentityReconciler(
      repository: _repository,
      waitForLibraryReady: _waitForLibraryCacheLoaded,
      isScanning: () => _scanService.isScanning,
      shouldAbort: () => _disposed || !mounted,
    );
    _settingsStore = widget.settingsStore ?? SettingsStore();
    _glassController = widget.glassController ?? GlassController();
    _settingsStore.bindGlassController(_glassController);
    _syncPlaybackTransitionSetting();
    _settingsStore.addListener(_syncPlaybackTransitionSetting);
    _localeController = widget.localeController ??
        LocaleController(settingsStore: _settingsStore);
    _artistNameStore = widget.artistNameStore ?? ArtistNameStore();
    _eqController = widget.eqController ??
        EqController(
          engine: _engine,
          store: EqStore(),
        );
    _userCollections = widget.userCollections ??
        UserCollections(
          repository: _repository,
        );
    _audioSettingsApplier = widget.audioSettingsApplier ??
        AudioSettingsApplier(
          engine: _engine,
          settingsStore: _settingsStore,
        );
    if (widget.lyricsController != null) {
      _lyricsController = widget.lyricsController!;
    } else {
      final offsetStore = LyricsOffsetStore();
      _lyricsOffsetStore = offsetStore;
      unawaited(offsetStore.init());
      _lyricsController = LyricsController(
        playbackController: _playbackController,
        repository: LyricsRepository(),
        settingsStore: _settingsStore,
        offsetStore: offsetStore,
      );
      _createdLyricsControllerLocally = true;
    }
    _navigator = AppNavigator();
    _sessionStore = widget.sessionStore ?? SessionStore();
    _sessionSaver = widget.sessionSaver;
    _playRecorder = widget.playRecorder;

    _createdMiniPlayerControllerLocally = widget.miniPlayerController == null;
    _miniPlayerController = widget.miniPlayerController ??
        MiniPlayerController(
          windowService:
              widget.windowService ?? PlatformServices.createWindowService(),
          settingsStore: _settingsStore,
        );

    _shutdownCoordinator = widget.shutdownCoordinator ??
        AppShutdownCoordinator(
          sessionSaver: _sessionSaver,
          playRecorder: _playRecorder,
          settingsStore: _settingsStore,
          mediaSessionService:
              widget.mediaSessionService ?? FakeMediaSessionService(),
          sleepInhibitor: widget.sleepInhibitor ?? FakeSleepInhibitor(),
          trayService: widget.trayService ?? FakeTrayService(),
        );

    _mediaSessionController = widget.mediaSessionController;
    _sleepController = widget.sleepController;
    _trayWindowController = widget.trayWindowController;

    _windowLifecycle = WindowLifecycleCoordinator(
      miniPlayerController: _miniPlayerController,
      playbackController: _playbackController,
      settingsStore: _settingsStore,
      shutdownCoordinator: widget.shutdownCoordinator ?? _shutdownCoordinator,
      trayWindowController: _trayWindowController,
      trayService: widget.trayService,
      sessionSaver: _sessionSaver,
      isMounted: () => mounted,
    )..attach();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _disposed) return;
      unawaited(_startupIdentityReconciler.runOnce());
      final backupService = widget.userDataBackupService;
      if (backupService == null) return;
      unawaited(
        backupService
            .runDailyBackup(accessMode: _repository.userDataAccessMode)
            .catchError((Object e, StackTrace st) {
          AppLogger.instance.warning(
            'Backup',
            'Daily userdata backup failed: $e',
            e,
            st,
          );
          return null;
        }),
      );
    });
  }

  Future<void> _waitForLibraryCacheLoaded() async {
    if (_disposed || _dataCache.isLoaded) return;
    final completer = Completer<void>();
    void onCacheChanged() {
      if ((_disposed || _dataCache.isLoaded) && !completer.isCompleted) {
        completer.complete();
      }
    }

    _dataCache.addListener(onCacheChanged);
    try {
      await completer.future;
    } finally {
      _dataCache.removeListener(onCacheChanged);
    }
  }

  void _syncPlaybackTransitionSetting() {
    _playbackController.fadeProfile = _settingsStore.settings.fadeProfile;
  }

  @override
  void dispose() {
    _disposed = true;
    _dataCache.dispose();
    _settingsStore.removeListener(_syncPlaybackTransitionSetting);
    if (_createdLyricsControllerLocally) {
      _lyricsController.dispose();
    }
    _lyricsOffsetStore?.dispose();
    if (_createdPlaybackControllerLocally) {
      unawaited(_playbackController.dispose());
    }
    if (_createdEngineLocally) {
      unawaited(_engine.dispose());
    }
    if (_createdMiniPlayerControllerLocally) {
      _miniPlayerController.dispose();
    }
    _trayWindowController?.dispose();
    _windowLifecycle.dispose();
    _sleepController?.dispose();
    _mediaSessionController?.dispose();
    _playRecorder?.dispose();
    _sessionSaver?.dispose();
    _sessionStore.dispose();
    _volumeHudController.dispose();
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
        repository: _repository,
        controller: _playbackController,
        navigator: _navigator,
        settingsStore: _settingsStore,
        artistNameStore: _artistNameStore,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveEngine = _engine;
    final effectiveController = _playbackController;
    final effectiveRepo = _repository;
    final effectiveScanService = _scanService;

    return ListenableBuilder(
      listenable: Listenable.merge([
        _settingsStore,
        _localeController,
        _glassController,
        _artistNameStore,
        _eqController,
        _miniPlayerController,
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
              shortcutById(AppShortcutId.gallery).activator: _openDesignGallery,
              shortcutById(AppShortcutId.quickSearch).activator:
                  _toggleQuickSearch,
              shortcutById(AppShortcutId.mediaPlayPause).activator:
                  effectiveController.togglePlayPause,
              shortcutById(AppShortcutId.mediaNext).activator:
                  effectiveController.skipNext,
              shortcutById(AppShortcutId.mediaPrevious).activator:
                  effectiveController.skipPrevious,
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
                      child: VolumeHudScope(
                        controller: _volumeHudController,
                        child: ArtistNameScope(
                          store: _artistNameStore,
                          child: EqScope(
                            controller: _eqController,
                            child: UserCollectionsScope(
                              collections: _userCollections,
                              child: VolumeHudOverlay(
                                controller: _volumeHudController,
                                engine: effectiveEngine,
                                settingsStore: _settingsStore,
                                child: child!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                home: _miniPlayerController.isMini
                    ? MiniPlayerView(
                        controller: _miniPlayerController,
                        playbackController: effectiveController,
                        lyricsController: _lyricsController,
                        onCloseRequested:
                            _windowLifecycle.handleMiniCloseRequested,
                      )
                    : AppShell(
                        engine: effectiveEngine,
                        controller: effectiveController,
                        repository: effectiveRepo,
                        scanService: effectiveScanService,
                        dataCache: _dataCache,
                        settingsStore: _settingsStore,
                        navigator: _navigator,
                        sessionStore: _sessionStore,
                        directoryPicker: widget.directoryPicker,
                        audioSettingsApplier: _audioSettingsApplier,
                        artistNameStore: _artistNameStore,
                        eqController: _eqController,
                        userCollections: _userCollections,
                        lyricsController: _lyricsController,
                        windowService: widget.windowService,
                        miniPlayerController: _miniPlayerController,
                        trayWindowController: _trayWindowController,
                        startupReport: widget.startupReport,
                        onOpenLogsFolder: widget.onOpenLogsFolder,
                        onOpenBackupsFolder: widget.onOpenBackupsFolder,
                        onOpenFolder: widget.onOpenFolder,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
