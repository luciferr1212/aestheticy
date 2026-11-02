import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../audio/audio_engine.dart';
import '../../audio/playback_controller.dart';
import '../../features/audio_lab/audio_lab_screen.dart';
import '../../features/library/folder_management_sheet.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/scan_service.dart';
import '../library/album_detail_view.dart';
import '../library/albums_view.dart';
import '../library/artist_detail_view.dart';
import '../library/artists_view.dart';
import '../library/tracks_view.dart';
import '../library/welcome_view.dart';
import '../settings/settings_store.dart';
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
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  List<LibraryFolder> _folders = [];
  bool _isLoadingFolders = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
    widget.navigator.addListener(_onNavigatorChange);
    widget.scanService.addListener(_onScanChange);
    widget.settingsStore.addListener(_onSettingsChange);
  }

  @override
  void dispose() {
    widget.navigator.removeListener(_onNavigatorChange);
    widget.scanService.removeListener(_onScanChange);
    widget.settingsStore.removeListener(_onSettingsChange);
    super.dispose();
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
      case AppDestination.folders:
        // Revert to albums and open modal
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.navigator.navigateTo(AppDestination.albums);
          _openFolders();
        });
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

    return Scaffold(
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
}
