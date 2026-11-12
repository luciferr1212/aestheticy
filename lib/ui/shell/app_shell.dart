import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../audio/audio_engine.dart';
import '../../audio/playback_controller.dart';
import '../../features/audio_lab/audio_lab_screen.dart';
import '../../features/library/folder_management_sheet.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../features/collections/user_collections.dart';
import '../../library/scan_service.dart';
import '../../platform/window_service.dart';
import '../mini_player/mini_player_controller.dart';
import '../library/album_detail_view.dart';
import '../library/albums_view.dart';
import '../library/artist_detail_view.dart';
import '../library/artists_view.dart';
import '../library/favorites_view.dart';
import '../library/playlist_detail_view.dart';
import '../library/playlists_view.dart';
import '../library/recently_played_view.dart';
import '../library/tracks_view.dart';
import '../library/welcome_view.dart';
import '../now_playing/full_screen_view.dart';
import '../now_playing/now_playing_view.dart';
import '../artist_names/artist_name_store.dart';
import '../audio_panels/audio_panels_view.dart';
import '../audio_panels/eq_controller.dart';
import '../../features/lyrics/lyrics_controller.dart';
import '../../features/lyrics/lyrics_repository.dart';
import '../lyrics/lyrics_view.dart';
import '../queue/queue_view.dart';
import '../quick_search/quick_search_overlay.dart';
import '../settings/app_shortcuts.dart';
import '../settings/audio_settings_applier.dart';
import '../settings/settings_store.dart';
import '../settings/settings_view.dart';
import '../settings/shortcuts_cheat_sheet_dialog.dart';
import 'ambient_background.dart';
import 'app_navigator.dart';
import 'bottom_now_playing_bar.dart';
import 'global_playback_keys.dart';
import 'scanning_panel.dart';
import 'sidebar.dart';
import 'volume_hud.dart';

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
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late final UserCollections _userCollections;
  late final LyricsController _lyricsController;
  bool _createdLyricsControllerLocally = false;
  List<LibraryFolder> _folders = [];
  bool _isLoadingFolders = true;

  late final GlobalPlaybackKeysHandler _playbackKeysHandler;
  bool _shortcutsDialogOpen = false;
  bool _wasFullScreen = false;
  bool _wasMaximizedBeforeFullScreen = false;
  bool _needsMaximizeRestore = false;
  bool _isSyncingFullScreen = false;
  bool _fullScreenSyncRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playbackKeysHandler = _createPlaybackKeysHandler();
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
    _userCollections = widget.userCollections ??
        UserCollections(repository: widget.repository);
    if (!_userCollections.isLoaded) {
      _userCollections.init();
    }
    _loadFolders();
    widget.navigator.addListener(_onNavigatorChange);
    widget.scanService.addListener(_onScanChange);
    widget.settingsStore.addListener(_onSettingsChange);
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
    );
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

  void _onScanChange() {
    if (!widget.scanService.isScanning) {
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
    }
  }

  Future<void> _onAddFolder() async {
    final String? path;
    if (widget.directoryPicker != null) {
      path = await widget.directoryPicker!();
    } else {
      path = await FilePicker.getDirectoryPath();
    }

    if (path != null && path.isNotEmpty) {
      await widget.scanService.addFolder(path);
      await _loadFolders();
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

  Widget _buildContent(AppDestination destination) {
    if (_folders.isEmpty) {
      return WelcomeView(
        settingsStore: widget.settingsStore,
        onAddFolder: _onAddFolder,
      );
    }

    switch (destination) {
      case AppDestination.albums:
        return AlbumsView(
          key: const ValueKey('view_albums'),
          repository: widget.repository,
          settingsStore: widget.settingsStore,
          navigator: widget.navigator,
        );
      case AppDestination.artists:
        return ArtistsView(
          key: const ValueKey('view_artists'),
          repository: widget.repository,
          settingsStore: widget.settingsStore,
          navigator: widget.navigator,
        );
      case AppDestination.tracks:
        return TracksView(
          key: const ValueKey('view_tracks'),
          repository: widget.repository,
          controller: widget.controller,
          settingsStore: widget.settingsStore,
        );
      case AppDestination.albumDetail:
        final album = widget.navigator.selectedAlbum ??
            AlbumSummary(
              album: widget.navigator.selectedAlbumId ?? '',
              trackCount: 0,
            );
        return AlbumDetailView(
          key: ValueKey('view_album_detail_${album.album}'),
          album: album,
          repository: widget.repository,
          controller: widget.controller,
          settingsStore: widget.settingsStore,
          navigator: widget.navigator,
        );
      case AppDestination.artistDetail:
        final artist = widget.navigator.selectedArtist ??
            ArtistSummary(
              name: widget.navigator.selectedArtistId ?? '',
              albumCount: 0,
              trackCount: 0,
            );
        return ArtistDetailView(
          key: ValueKey('view_artist_detail_${artist.name}'),
          artist: artist,
          repository: widget.repository,
          controller: widget.controller,
          settingsStore: widget.settingsStore,
          navigator: widget.navigator,
        );
      case AppDestination.audioLab:
        return AudioLabScreen(
          key: const ValueKey('view_audio_lab'),
          engine: widget.engine,
          controller: widget.controller,
        );
      case AppDestination.settings:
        return SettingsView(
          key: const ValueKey('view_settings'),
          engine: widget.engine,
          repository: widget.repository,
          settingsStore: widget.settingsStore,
          navigator: widget.navigator,
          audioSettingsApplier: widget.audioSettingsApplier,
          artistNameStore: widget.artistNameStore,
          onOpenFolders: _openFolders,
        );
      case AppDestination.audioPanels:
        return AudioPanelsView(
          key: const ValueKey('view_audio_panels'),
          engine: widget.engine,
          eqController: widget.eqController,
          audioSettingsApplier: widget.audioSettingsApplier,
          settingsStore: widget.settingsStore,
          navigator: widget.navigator,
        );
      case AppDestination.playlists:
        return PlaylistsView(
          key: const ValueKey('view_playlists'),
          collections: _userCollections,
          repository: widget.repository,
          controller: widget.controller,
          settingsStore: widget.settingsStore,
          navigator: widget.navigator,
        );
      case AppDestination.playlistDetail:
        final playlistId = widget.navigator.selectedPlaylistId ?? 0;
        final playlist = widget.navigator.selectedPlaylist;
        return PlaylistDetailView(
          key: ValueKey('view_playlist_detail_$playlistId'),
          playlistId: playlistId,
          initialPlaylist: playlist,
          repository: widget.repository,
          collections: _userCollections,
          controller: widget.controller,
          settingsStore: widget.settingsStore,
          navigator: widget.navigator,
        );
      case AppDestination.favorites:
        return FavoritesView(
          key: const ValueKey('view_favorites'),
          repository: widget.repository,
          collections: _userCollections,
          controller: widget.controller,
          settingsStore: widget.settingsStore,
        );
      case AppDestination.recentlyPlayed:
        return RecentlyPlayedView(
          key: const ValueKey('view_recently_played'),
          repository: widget.repository,
          controller: widget.controller,
          settingsStore: widget.settingsStore,
          collections: _userCollections,
        );
      case AppDestination.queue:
        return QueueView(
          key: const ValueKey('view_queue'),
          controller: widget.controller,
          navigator: widget.navigator,
          settingsStore: widget.settingsStore,
          userCollections: _userCollections,
        );
      case AppDestination.folders:
        // Revert to albums and open modal
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.navigator.navigateTo(AppDestination.albums);
          _openFolders();
        });
        return const SizedBox.shrink();
      case AppDestination.lyrics:
      case AppDestination.nowPlaying:
      case AppDestination.fullScreen:
        return const SizedBox.shrink();
    }
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
            const Positioned.fill(child: AmbientBackground()),
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
            const Positioned.fill(
              child: AmbientBackground(),
            ),

            // 2. Main structure: Sidebar + Content Column
            Positioned.fill(
              child: Row(
                children: [
                  // Start side: Sidebar (blur slot 1)
                  Sidebar(
                    navigator: widget.navigator,
                    settingsStore: widget.settingsStore,
                    onOpenFolders: _openFolders,
                  ),

                  // Content area & floating now-playing bar
                  Expanded(
                    child: Stack(
                      children: [
                        // Scrollable content area with padding above bottom bar
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 104),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Top scanning panel
                                ScanningPanel(scanService: widget.scanService),

                                // Active destination view (no blur)
                                Expanded(
                                  child: AnimatedSwitcher(
                                    duration: reduceMotion
                                        ? Duration.zero
                                        : const Duration(milliseconds: 100),
                                    child: _buildContent(currentDestination),
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
                            miniPlayerController: widget.miniPlayerController,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return CallbackShortcuts(
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
          child: rootScaffold,
        ),
      ),
    );
  }
}
