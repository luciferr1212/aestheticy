import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../audio/audio_engine.dart';
import '../../audio/playback_controller.dart';
import '../../core/result.dart';
import '../../diagnostics/app_logger.dart';
import '../../features/collections/user_collections.dart';
import '../../features/integration/tray_window_controller.dart';
import '../../features/library/folder_management_sheet.dart';
import '../../features/lyrics/lyrics_controller.dart';
import '../../features/lyrics/lyrics_repository.dart';
import '../../features/session/session_store.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/scan_service.dart';
import '../../library/user_data_access_mode.dart';
import '../../platform/window_service.dart';
import '../artist_names/artist_name_store.dart';
import '../audio_panels/eq_controller.dart';
import '../common/error_presenter.dart';
import '../l10n/app_strings.dart';
import '../library/library_data_cache.dart';
import '../lyrics/lyrics_view.dart';
import '../mini_player/mini_player_controller.dart';
import '../now_playing/full_screen_view.dart';
import '../now_playing/now_playing_view.dart';
import '../quick_search/quick_search_overlay.dart';
import '../settings/app_shortcuts.dart';
import '../settings/audio_settings_applier.dart';
import '../settings/settings_store.dart';
import '../settings/shortcuts_cheat_sheet_dialog.dart';
import 'ambient_background.dart';
import 'app_navigator.dart';
import 'bottom_now_playing_bar.dart';
import 'global_playback_keys.dart';
import 'safe_read_only_banner.dart';
import 'scanning_panel.dart';
import 'side_panel.dart';
import 'side_panel_controller.dart';
import 'sidebar.dart';
import 'volume_hud.dart';
import 'widgets/app_shell_destination_view.dart';
import 'widgets/view_state_restorer.dart';

/// Flagship application shell hosting the ambient background, navigation sidebar,
/// dynamic content area, top scanning progress bar, and floating bottom player bar.
class AppShell extends StatefulWidget {
  /// The audio engine instance.
  final AudioEngine engine;

  /// The audio playback controller coordinating queue and engine.
  final PlaybackController controller;

  /// The library storage repository.
  final LibraryRepository repository;

  /// The active scanner application service.
  final ScanService scanService;

  /// The persistent settings store.
  final SettingsStore settingsStore;

  /// The navigation coordinator.
  final AppNavigator navigator;

  /// Optional injected directory picker for testing.
  final Future<String?> Function()? directoryPicker;

  /// Optional audio settings applier.
  final AudioSettingsApplier? audioSettingsApplier;

  /// Optional artist display names store.
  final ArtistNameStore? artistNameStore;

  /// Optional equalizer controller.
  final EqController? eqController;

  /// Optional user collections coordinator.
  final UserCollections? userCollections;

  /// Optional lyrics controller.
  final LyricsController? lyricsController;

  /// Optional native window lifecycle and geometry service.
  final WindowService? windowService;

  /// Optional mini player window controller.
  final MiniPlayerController? miniPlayerController;

  /// Optional tray & window close controller.
  final TrayWindowController? trayWindowController;

  /// Optional in-memory library data cache.
  final LibraryDataCache? dataCache;

  /// Optional docked right side panel controller.
  final SidePanelController? sidePanelController;

  /// Optional startup database integrity/recovery report.
  final DatabaseStartupReport? startupReport;

  /// Optional callback to open the logs folder from the safe read-only banner.
  final VoidCallback? onOpenLogsFolder;

  /// Optional callback to open the backups folder from the safe read-only banner.
  final VoidCallback? onOpenBackupsFolder;

  /// Optional session store used by the Home screen resume card.
  final SessionStore? sessionStore;

  /// Optional clock override for the Home screen greeting and daily rotation.
  final DateTime Function()? homeClock;

  /// Optional clock override for the Stats screen range calculations.
  final DateTime Function()? statsClock;

  /// Optional folder opener callback (e.g. Windows Explorer on Windows).
  final Future<void> Function(String path)? onOpenFolder;

  /// Creates an [AppShell].
  const AppShell({
    super.key,
    required this.engine,
    required this.controller,
    required this.repository,
    required this.scanService,
    required this.settingsStore,
    required this.navigator,
    this.directoryPicker,
    this.audioSettingsApplier,
    this.artistNameStore,
    this.eqController,
    this.userCollections,
    this.lyricsController,
    this.windowService,
    this.miniPlayerController,
    this.trayWindowController,
    this.dataCache,
    this.sidePanelController,
    this.startupReport,
    this.onOpenLogsFolder,
    this.onOpenBackupsFolder,
    this.sessionStore,
    this.homeClock,
    this.statsClock,
    this.onOpenFolder,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late final UserCollections _userCollections;
  late final LyricsController _lyricsController;
  late final LibraryDataCache _dataCache;
  late SidePanelController _sidePanelController;
  bool _createdLyricsControllerLocally = false;
  bool _createdDataCacheLocally = false;
  bool _createdSidePanelControllerLocally = false;
  List<LibraryFolder> _folders = [];
  bool _isLoadingFolders = true;

  late final GlobalPlaybackKeysHandler _playbackKeysHandler;
  bool _shortcutsDialogOpen = false;
  bool _wasFullScreen = false;
  bool _wasMaximizedBeforeFullScreen = false;
  bool _needsMaximizeRestore = false;
  bool _isSyncingFullScreen = false;
  bool _fullScreenSyncRequested = false;
  int _lastLibraryVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playbackKeysHandler = _createPlaybackKeysHandler();
    if (widget.dataCache != null) {
      _dataCache = widget.dataCache!;
    } else {
      _dataCache = LibraryDataCache(
        repository: widget.repository,
        scanService: widget.scanService,
      );
      _createdDataCacheLocally = true;
      unawaited(_dataCache.refresh());
    }
    _lastLibraryVersion = widget.scanService.libraryVersion;
    if (widget.lyricsController != null) {
      _lyricsController = widget.lyricsController!;
    } else {
      _lyricsController = LyricsController(
        playbackController: widget.controller,
        repository: LyricsRepository(),
        settingsStore: widget.settingsStore,
      );
      _createdLyricsControllerLocally = true;
    }
    if (widget.sidePanelController != null) {
      _sidePanelController = widget.sidePanelController!;
    } else {
      _sidePanelController = SidePanelController(
        settingsStore: widget.settingsStore,
      );
      _createdSidePanelControllerLocally = true;
    }
    _userCollections = widget.userCollections ??
        UserCollections(repository: widget.repository);
    _userCollections.onReadOnlyBlocked ??= _showReadOnlyBlockedNotice;
    if (!_userCollections.isLoaded) {
      _userCollections.init();
    }
    _dataCache.addListener(_onDataCacheChanged);
    _loadFolders();
    widget.navigator.addListener(_onNavigatorChange);
    widget.scanService.addListener(_onScanChange);
    widget.settingsStore.addListener(_onSettingsChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleStartupReport());
  }

  void _showReadOnlyBlockedNotice(String messageKey) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.t(messageKey))),
    );
  }

  void _handleStartupReport() {
    if (!mounted) return;
    final report = widget.startupReport;
    if (report == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (report.libraryRecreatedAfterCorruption) {
      messenger?.showSnackBar(
        SnackBar(content: Text(context.t('userdata.libraryCorruptNotice'))),
      );
      unawaited(widget.scanService.rescanAll());
    } else if (report.userDataRestoredFromBackup) {
      messenger?.showSnackBar(
        SnackBar(content: Text(context.t('userdata.restoredFromBackupNotice'))),
      );
    } else if (report.userDataResetEmptyAfterCorruption) {
      messenger?.showSnackBar(
        SnackBar(content: Text(context.t('userdata.resetEmptyNotice'))),
      );
    }
  }

  GlobalPlaybackKeysHandler _createPlaybackKeysHandler() {
    return GlobalPlaybackKeysHandler(
      controller: widget.controller,
      engine: widget.engine,
      settingsStore: widget.settingsStore,
      volumeHudProvider: () => VolumeHudScope.maybeOf(context),
      isInFullScreenOrMini: () =>
          widget.navigator.current == AppDestination.fullScreen,
      onEscape: () {
        if (_shortcutsDialogOpen) return false;
        final current = widget.navigator.current;
        if (current == AppDestination.fullScreen ||
            current == AppDestination.nowPlaying ||
            current == AppDestination.lyrics ||
            current == AppDestination.queue) {
          widget.navigator.goBack();
          return true;
        }
        return false;
      },
      onToggleFullScreen: widget.navigator.toggleFullScreen,
      onEnterMiniPlayer: widget.miniPlayerController?.enter,
      onShowShortcutsCheatSheet: _openShortcutsCheatSheet,
      isShortcutsCheatSheetOpen: () => _shortcutsDialogOpen,
      onNavigateBack: () {
        if (widget.navigator.canGoBack) {
          widget.navigator.goBack();
        }
      },
      onNavigateForward: () {
        if (widget.navigator.canGoForward) {
          widget.navigator.goForward();
        }
      },
      onToggleQueuePanel: () => _toggleSidePanel(SidePanelTab.queue),
      onToggleLyricsPanel: () => _toggleSidePanel(SidePanelTab.lyrics),
    );
  }

  void _toggleSidePanel(SidePanelTab tab) {
    final current = widget.navigator.current;
    if (current == AppDestination.fullScreen ||
        current == AppDestination.nowPlaying ||
        current == AppDestination.lyrics) {
      return;
    }
    _sidePanelController.toggleTab(tab);
  }

  void _openShortcutsCheatSheet() {
    if (_shortcutsDialogOpen || !mounted) return;
    _shortcutsDialogOpen = true;
    showShortcutsCheatSheetDialog(context).whenComplete(() {
      _shortcutsDialogOpen = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playbackKeysHandler.dispose();
    if (_createdLyricsControllerLocally) {
      _lyricsController.dispose();
    }
    _dataCache.removeListener(_onDataCacheChanged);
    if (_createdDataCacheLocally) {
      _dataCache.dispose();
    }
    if (_createdSidePanelControllerLocally) {
      _sidePanelController.dispose();
    }
    if (_wasFullScreen && !_isSyncingFullScreen) {
      _wasFullScreen = false;
      widget.windowService?.setFullScreen(false);
    }
    widget.navigator.removeListener(_onNavigatorChange);
    widget.scanService.removeListener(_onScanChange);
    widget.settingsStore.removeListener(_onSettingsChange);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _playbackKeysHandler.reset();
    }
  }

  void _onSettingsChange() {
    if (mounted) setState(() {});
  }

  void _onNavigatorChange() {
    if (mounted) setState(() {});
    _scheduleFullScreenSync();
  }

  void _scheduleFullScreenSync() {
    _fullScreenSyncRequested = true;
    if (_isSyncingFullScreen || widget.windowService == null) {
      return;
    }
    unawaited(_drainFullScreenTransitions());
  }

  Future<void> _drainFullScreenTransitions() async {
    if (_isSyncingFullScreen) return;
    _isSyncingFullScreen = true;
    try {
      final windowService = widget.windowService;
      if (windowService == null) return;

      while (mounted &&
          (_fullScreenSyncRequested ||
              (widget.navigator.current == AppDestination.fullScreen) !=
                  _wasFullScreen)) {
        _fullScreenSyncRequested = false;
        final wantFullScreen =
            widget.navigator.current == AppDestination.fullScreen;
        if (wantFullScreen == _wasFullScreen) {
          continue;
        }

        if (wantFullScreen) {
          final geo = await windowService.getGeometry();
          if (!mounted) break;
          if (widget.navigator.current != AppDestination.fullScreen) {
            continue;
          }
          if (!_needsMaximizeRestore) {
            _wasMaximizedBeforeFullScreen = geo.isMaximized;
          }
          _wasFullScreen = true;
          _needsMaximizeRestore = false;
          await windowService.setFullScreen(true);
        } else {
          _wasFullScreen = false;
          _needsMaximizeRestore = _wasMaximizedBeforeFullScreen;
          await windowService.setFullScreen(false);
          if (!mounted) break;
          if (widget.navigator.current == AppDestination.fullScreen) {
            continue;
          }
          if (_needsMaximizeRestore) {
            _needsMaximizeRestore = false;
            _wasMaximizedBeforeFullScreen = false;
            await windowService.maximize();
          } else {
            _wasMaximizedBeforeFullScreen = false;
          }
        }
      }
    } finally {
      _isSyncingFullScreen = false;
    }
  }

  void _onDataCacheChanged() {
    if (!mounted) return;
    unawaited(_userCollections.refresh());
  }

  void _onScanChange() {
    final currentVersion = widget.scanService.libraryVersion;
    if (!widget.scanService.isScanning ||
        currentVersion != _lastLibraryVersion) {
      _lastLibraryVersion = currentVersion;
      _loadFolders();
    }
  }

  Future<void> _loadFolders() async {
    final folders = await widget.repository.listFolders();
    if (mounted) {
      setState(() {
        _folders = folders;
        _isLoadingFolders = false;
      });
      unawaited(_dataCache.refresh());
    }
  }

  Future<void> _onAddFolder() async {
    try {
      final String? path;
      if (widget.directoryPicker != null) {
        path = await widget.directoryPicker!();
      } else {
        path = await FilePicker.getDirectoryPath();
      }

      if (path == null || path.isEmpty) return;

      final result = await widget.scanService.addFolderResult(path);
      if (!mounted) return;
      switch (result) {
        case Ok():
          await _loadFolders();
        case Err(:final error):
          ErrorPresenter.show(context, error, onRetry: _onAddFolder);
      }
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        'AppShell',
        'Directory picker failed when adding folder',
        error,
        stackTrace,
      );
      if (mounted) {
        ErrorPresenter.show(
          context,
          AppError.fromException(error, stackTrace, 'error.folderAddFailed'),
          onRetry: _onAddFolder,
        );
      }
    }
  }

  void _openFolders() {
    FolderManagementSheet.show(
      context,
      repository: widget.repository,
      scanService: widget.scanService,
      directoryPicker: widget.directoryPicker,
    ).then((_) => _loadFolders());
  }

  void _toggleQuickSearch() {
    toggleQuickSearch(
      context: context,
      repository: widget.repository,
      controller: widget.controller,
      navigator: widget.navigator,
      settingsStore: widget.settingsStore,
      artistNameStore: widget.artistNameStore ?? ArtistNameStore(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingFolders) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F1115),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final reduceMotion = widget.settingsStore.settings.reduceMotion;
    final currentDestination = widget.navigator.current;

    final Widget rootScaffold;

    // Lyrics full-screen view
    if (currentDestination == AppDestination.lyrics) {
      rootScaffold = Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: AmbientBackground(settingsStore: widget.settingsStore),
            ),
            Positioned.fill(
              child: SafeArea(
                child: LyricsView(
                  key: const ValueKey('view_lyrics'),
                  controller: _lyricsController,
                  playbackController: widget.controller,
                  settingsStore: widget.settingsStore,
                  navigator: widget.navigator,
                  showHeader: true,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (currentDestination == AppDestination.nowPlaying) {
      rootScaffold = Scaffold(
        backgroundColor: Colors.transparent,
        body: NowPlayingView(
          key: const ValueKey('view_now_playing'),
          controller: widget.controller,
          engine: widget.engine,
          navigator: widget.navigator,
          settingsStore: widget.settingsStore,
          lyricsController: _lyricsController,
        ),
      );
    } else if (currentDestination == AppDestination.fullScreen) {
      // In-app immersive Full Screen view
      rootScaffold = Scaffold(
        backgroundColor: Colors.transparent,
        body: FullScreenView(
          key: const ValueKey('view_full_screen'),
          controller: widget.controller,
          engine: widget.engine,
          navigator: widget.navigator,
          settingsStore: widget.settingsStore,
          lyricsController: _lyricsController,
          miniPlayerController: widget.miniPlayerController,
        ),
      );
    } else {
      rootScaffold = Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // 1. Ambient static background
            Positioned.fill(
              child: AmbientBackground(settingsStore: widget.settingsStore),
            ),

            // 2. Main structure: Sidebar + Content Column + Docked SidePanel
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return ListenableBuilder(
                    listenable: _sidePanelController,
                    builder: (context, _) {
                      final showSidePanel =
                          _sidePanelController.isVisibleForWidth(
                        constraints.maxWidth,
                      );

                      return Row(
                        children: [
                          // Start side: Sidebar (blur slot 1)
                          Sidebar(
                            navigator: widget.navigator,
                            settingsStore: widget.settingsStore,
                            onOpenFolders: _openFolders,
                          ),

                          // Content area & floating now-playing bar
                          Expanded(
                            key: const Key('app_shell_content_area'),
                            child: Stack(
                              children: [
                                // Scrollable content area with padding above bottom bar
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 104),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // Persistent Safe Read-Only mode banner
                                        if (widget.repository.userDataAccessMode ==
                                            UserDataAccessMode.safeReadOnly)
                                          SafeReadOnlyBanner(
                                            onOpenLogsFolder:
                                                widget.onOpenLogsFolder,
                                            onOpenBackupsFolder:
                                                widget.onOpenBackupsFolder,
                                          ),

                                        // Top scanning panel
                                        ScanningPanel(
                                          scanService: widget.scanService,
                                        ),

                                        // Active destination view (no blur)
                                        Expanded(
                                          child: AnimatedSwitcher(
                                            key: const ValueKey(
                                              'content_animated_switcher',
                                            ),
                                            duration: reduceMotion
                                                ? Duration.zero
                                                : const Duration(
                                                    milliseconds: 120,
                                                  ),
                                            switchInCurve: Curves.easeOut,
                                            switchOutCurve: Curves.easeOut,
                                            layoutBuilder: (
                                              currentChild,
                                              previousChildren,
                                            ) {
                                              return currentChild ??
                                                  const SizedBox.shrink();
                                            },
                                            transitionBuilder:
                                                (child, animation) {
                                              return FadeTransition(
                                                opacity: CurvedAnimation(
                                                  parent: animation,
                                                  curve: Curves.easeOut,
                                                ),
                                                child: child,
                                              );
                                            },
                                            child: ViewStateRestorer(
                                              key: ValueKey(
                                                'view_state_${widget.navigator.currentEntry.id}',
                                              ),
                                              entry:
                                                  widget.navigator.currentEntry,
                                              navigator: widget.navigator,
                                              child: AppShellDestinationView(
                                                destination: currentDestination,
                                                hasFolders: _folders.isNotEmpty,
                                                engine: widget.engine,
                                                controller: widget.controller,
                                                repository: widget.repository,
                                                settingsStore:
                                                    widget.settingsStore,
                                                navigator: widget.navigator,
                                                dataCache: _dataCache,
                                                userCollections:
                                                    _userCollections,
                                                audioSettingsApplier:
                                                    widget.audioSettingsApplier,
                                                artistNameStore:
                                                    widget.artistNameStore,
                                                eqController:
                                                    widget.eqController,
                                                trayWindowController:
                                                    widget.trayWindowController,
                                                sessionStore:
                                                    widget.sessionStore,
                                                homeClock: widget.homeClock,
                                                statsClock: widget.statsClock,
                                                directoryPicker:
                                                    widget.directoryPicker,
                                                onOpenFolder:
                                                    widget.onOpenFolder,
                                                onAddFolder: _onAddFolder,
                                                onOpenFolders: _openFolders,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Floating bottom player bar (blur slot 2, 16dp margins)
                                PositionedDirectional(
                                  start: 16,
                                  end: 16,
                                  bottom: 16,
                                  height: 84,
                                  child: BottomNowPlayingBar(
                                    controller: widget.controller,
                                    navigator: widget.navigator,
                                    miniPlayerController:
                                        widget.miniPlayerController,
                                    settingsStore: widget.settingsStore,
                                    sidePanelController: _sidePanelController,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // End side: Docked Queue/Lyrics SidePanel (blur slot 3 when open)
                          SidePanel(
                            key: const Key('app_shell_side_panel'),
                            isVisible: showSidePanel,
                            sidePanelController: _sidePanelController,
                            playbackController: widget.controller,
                            lyricsController: _lyricsController,
                            settingsStore: widget.settingsStore,
                            navigator: widget.navigator,
                            userCollections: _userCollections,
                            panelWidth: SidePanelController.panelWidthFor(
                              constraints.maxWidth,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return Listener(
      onPointerDown: (event) {
        if ((event.buttons & kBackMouseButton) != 0) {
          if (widget.navigator.canGoBack) {
            widget.navigator.goBack();
          }
        } else if ((event.buttons & kForwardMouseButton) != 0) {
          if (widget.navigator.canGoForward) {
            widget.navigator.goForward();
          }
        }
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          shortcutById(AppShortcutId.quickSearch).activator: _toggleQuickSearch,
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: _playbackKeysHandler.handleKeyEvent,
          onFocusChange: (hasFocus) {
            if (!hasFocus) _playbackKeysHandler.reset();
          },
          child: UserCollectionsScope(
            collections: _userCollections,
            child: LibraryDataCacheScope(
              cache: _dataCache,
              child: rootScaffold,
            ),
          ),
        ),
      ),
    );
  }
}
