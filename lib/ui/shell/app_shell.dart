import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/audio_engine.dart';
import '../../audio/playback_controller.dart';
import '../../features/audio_lab/audio_lab_screen.dart';
import '../../features/library/folder_management_sheet.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../features/collections/user_collections.dart';
import '../../library/scan_service.dart';
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
import '../quick_search/quick_search_overlay.dart';
import '../settings/app_shortcuts.dart';
import '../settings/audio_settings_applier.dart';
import '../settings/settings_store.dart';
import '../settings/settings_view.dart';
import 'ambient_background.dart';
import 'app_navigator.dart';
import 'bottom_now_playing_bar.dart';
import 'scanning_panel.dart';
import 'sidebar.dart';

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

  bool _isSpaceDown = false;
  bool _spaceChordUsed = false;
  int _arrowHeldDirection = 0;
  DateTime? _lastSeekTimestamp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_createdLyricsControllerLocally) {
      _lyricsController.dispose();
    }
    widget.navigator.removeListener(_onNavigatorChange);
    widget.scanService.removeListener(_onScanChange);
    widget.settingsStore.removeListener(_onSettingsChange);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _resetKeyboardState();
    }
  }

  void _resetKeyboardState() {
    _isSpaceDown = false;
    _spaceChordUsed = false;
    _arrowHeldDirection = 0;
    _lastSeekTimestamp = null;
  }

  void _onSettingsChange() {
    if (mounted) setState(() {});
  }

  void _onNavigatorChange() {
    if (mounted) setState(() {});
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

  bool _isDeepWidgetConsumed({required bool isArrow}) {
    final focusNode = FocusManager.instance.primaryFocus;
    final focusContext = focusNode?.context;
    if (focusContext == null) return false;

    // Editable text (search, text inputs)
    if (focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null) {
      return true;
    }

    // Modal routes, popups, dialogs
    final route = ModalRoute.of(focusContext);
    if (route is PopupRoute ||
        focusContext.findAncestorWidgetOfExactType<Dialog>() != null) {
      return true;
    }

    // Sliders handle arrow keys directly
    if (isArrow && focusContext.findAncestorWidgetOfExactType<Slider>() != null) {
      return true;
    }

    // Buttons consume Space
    if (!isArrow &&
        (focusContext.findAncestorWidgetOfExactType<ButtonStyleButton>() != null ||
            focusContext.findAncestorWidgetOfExactType<IconButton>() != null)) {
      return true;
    }

    return false;
  }

  void _performSeek(Duration delta) {
    final currentPos = widget.controller.currentPosition;
    final totalDuration = widget.controller.currentDuration;

    var target = currentPos + delta;
    if (target < Duration.zero) {
      target = Duration.zero;
    } else if (totalDuration > Duration.zero && target > totalDuration) {
      target = totalDuration;
    }

    widget.controller.seek(target);
  }

  KeyEventResult _handleRootKeyEvent(FocusNode node, KeyEvent event) {
    // 1. Esc key (Back)
    if (event is KeyDownEvent && matchesShortcut(event, AppShortcutId.back)) {
      if (widget.navigator.current == AppDestination.fullScreen) {
        widget.navigator.navigateTo(AppDestination.albums);
        return KeyEventResult.handled;
      }
      if (widget.navigator.current == AppDestination.nowPlaying ||
          widget.navigator.current == AppDestination.lyrics) {
        widget.navigator.goBack();
        return KeyEventResult.handled;
      }
    }

    // 2. Volume controls (Ctrl + Up / Down)
    if (event is KeyDownEvent && matchesShortcut(event, AppShortcutId.volumeUp)) {
      final currentVol = widget.settingsStore.settings.volume;
      final newVol = (currentVol + 0.05).clamp(0.0, 1.0);
      final rounded = (newVol * 100).round() / 100.0;
      widget.engine.setVolume(rounded);
      widget.settingsStore.update((s) => s.copyWith(volume: rounded));
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent && matchesShortcut(event, AppShortcutId.volumeDown)) {
      final currentVol = widget.settingsStore.settings.volume;
      final newVol = (currentVol - 0.05).clamp(0.0, 1.0);
      final rounded = (newVol * 100).round() / 100.0;
      widget.engine.setVolume(rounded);
      widget.settingsStore.update((s) => s.copyWith(volume: rounded));
      return KeyEventResult.handled;
    }

    // 3. Media keys & Ctrl + Left / Right
    if (event is KeyDownEvent) {
      if (matchesShortcut(event, AppShortcutId.mediaPlayPause)) {
        widget.controller.togglePlayPause();
        return KeyEventResult.handled;
      }
      if (matchesShortcut(event, AppShortcutId.nextTrack) ||
          matchesShortcut(event, AppShortcutId.mediaNext)) {
        widget.controller.skipNext();
        return KeyEventResult.handled;
      }
      if (matchesShortcut(event, AppShortcutId.previousTrack) ||
          matchesShortcut(event, AppShortcutId.mediaPrevious)) {
        widget.controller.skipPrevious();
        return KeyEventResult.handled;
      }
    }

    // 4. Space key tracking
    if (isSpaceKey(event)) {
      if (_isDeepWidgetConsumed(isArrow: false)) {
        _resetKeyboardState();
        return KeyEventResult.ignored;
      }

      if (event is KeyDownEvent) {
        _isSpaceDown = true;
        _spaceChordUsed = false;
        return KeyEventResult.handled;
      } else if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        final wasDown = _isSpaceDown;
        final chordUsed = _spaceChordUsed;
        _isSpaceDown = false;
        _spaceChordUsed = false;
        if (wasDown && !chordUsed) {
          widget.controller.togglePlayPause();
          return KeyEventResult.handled;
        }
        return KeyEventResult.handled;
      }
    }

    // 5. Left and Right arrows (seek or space chord)
    if (isArrowLeftKey(event) || isArrowRightKey(event)) {
      final isRight = isArrowRightKey(event);

      // 5A. Space chord: Space + Right / Left
      if (_isSpaceDown) {
        if (event is KeyDownEvent) {
          if (isRight) {
            widget.controller.skipNext();
          } else {
            widget.controller.skipPrevious();
          }
          _spaceChordUsed = true;
          return KeyEventResult.handled;
        } else if (event is KeyRepeatEvent || event is KeyUpEvent) {
          return KeyEventResult.handled;
        }
      }

      // 5B. Normal Seek arrows: Left / Right
      if (_isDeepWidgetConsumed(isArrow: true)) {
        _arrowHeldDirection = 0;
        _lastSeekTimestamp = null;
        return KeyEventResult.ignored;
      }

      final direction = isRight ? 1 : -1;
      final stepSeconds = widget.settingsStore.settings.seekStepSeconds;
      final delta = Duration(seconds: direction * stepSeconds);

      if (event is KeyDownEvent) {
        _arrowHeldDirection = direction;
        _lastSeekTimestamp = DateTime.now();
        _performSeek(delta);
        return KeyEventResult.handled;
      } else if (event is KeyRepeatEvent) {
        final now = DateTime.now();
        if (_lastSeekTimestamp == null ||
            now.difference(_lastSeekTimestamp!).inMilliseconds >= 120) {
          _lastSeekTimestamp = now;
          _performSeek(delta);
        }
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        if (_arrowHeldDirection != 0) {
          _arrowHeldDirection = 0;
          _lastSeekTimestamp = null;
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.ignored;
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
        onKeyEvent: _handleRootKeyEvent,
        onFocusChange: (hasFocus) {
          if (!hasFocus) _resetKeyboardState();
        },
        child: UserCollectionsScope(
          collections: _userCollections,
          child: rootScaffold,
        ),
      ),
    );
  }
}
