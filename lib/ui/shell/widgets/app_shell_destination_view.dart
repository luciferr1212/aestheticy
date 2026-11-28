import 'package:flutter/material.dart';

import '../../../audio/audio_engine.dart';
import '../../../audio/playback_controller.dart';
import '../../../features/audio_lab/audio_lab_screen.dart';
import '../../../features/collections/user_collections.dart';
import '../../../features/integration/tray_window_controller.dart';
import '../../../features/session/session_store.dart';
import '../../../features/wrapped/recap.dart';
import '../../../library/album_identity.dart';
import '../../../library/library_repository.dart';
import '../../../library/models.dart';
import '../../artist_names/artist_name_store.dart';
import '../../audio_panels/audio_panels_view.dart';
import '../../audio_panels/eq_controller.dart';
import '../../home/home_view.dart';
import '../../library/album_detail_view.dart';
import '../../library/albums_view.dart';
import '../../library/artist_detail_view.dart';
import '../../library/artists_view.dart';
import '../../library/favorites_view.dart';
import '../../library/library_data_cache.dart';
import '../../library/playlist_detail_view.dart';
import '../../library/playlists_view.dart';
import '../../library/recently_played_view.dart';
import '../../library/tracks_view.dart';
import '../../library/welcome_view.dart';
import '../../queue/queue_view.dart';
import '../../settings/audio_settings_applier.dart';
import '../../settings/settings_store.dart';
import '../../settings/settings_view.dart';
import '../../stats/stats_view.dart';
import '../../wrapped/wrapped_view.dart';
import '../app_navigator.dart';

/// Resolves and builds the active content destination inside [AppShell].
class AppShellDestinationView extends StatelessWidget {
  /// Target destination.
  final AppDestination destination;

  /// Whether any library folders are configured.
  final bool hasFolders;

  /// Audio engine instance.
  final AudioEngine engine;

  /// Playback controller.
  final PlaybackController controller;

  /// Library repository.
  final LibraryRepository repository;

  /// Settings store.
  final SettingsStore settingsStore;

  /// Navigation coordinator.
  final AppNavigator navigator;

  /// Shared library data cache.
  final LibraryDataCache dataCache;

  /// Shared user collections coordinator.
  final UserCollections userCollections;

  /// Optional audio settings applier.
  final AudioSettingsApplier? audioSettingsApplier;

  /// Optional artist display names store.
  final ArtistNameStore? artistNameStore;

  /// Optional equalizer controller.
  final EqController? eqController;

  /// Optional tray & window close controller.
  final TrayWindowController? trayWindowController;

  /// Optional session store used by the Home screen.
  final SessionStore? sessionStore;

  /// Optional clock override for the Home screen.
  final DateTime Function()? homeClock;

  /// Optional clock override for the Stats screen.
  final DateTime Function()? statsClock;

  /// Optional directory picker override for folder selection and exports.
  final Future<String?> Function()? directoryPicker;

  /// Optional folder opener callback for export success notifications.
  final Future<void> Function(String path)? onOpenFolder;

  /// Callback to add a music folder from the welcome state.
  final VoidCallback onAddFolder;

  /// Callback to open folder management sheet.
  final VoidCallback onOpenFolders;

  /// Creates an [AppShellDestinationView].
  const AppShellDestinationView({
    super.key,
    required this.destination,
    required this.hasFolders,
    required this.engine,
    required this.controller,
    required this.repository,
    required this.settingsStore,
    required this.navigator,
    required this.dataCache,
    required this.userCollections,
    required this.onAddFolder,
    required this.onOpenFolders,
    this.audioSettingsApplier,
    this.artistNameStore,
    this.eqController,
    this.trayWindowController,
    this.sessionStore,
    this.homeClock,
    this.statsClock,
    this.directoryPicker,
    this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasFolders) {
      return WelcomeView(
        settingsStore: settingsStore,
        onAddFolder: onAddFolder,
      );
    }

    switch (destination) {
      case AppDestination.home:
        return HomeView(
          key: const ValueKey('view_home'),
          repository: repository,
          controller: controller,
          settingsStore: settingsStore,
          navigator: navigator,
          dataCache: dataCache,
          sessionStore: sessionStore,
          clock: homeClock,
        );
      case AppDestination.albums:
        return AlbumsView(
          key: const ValueKey('view_albums'),
          repository: repository,
          settingsStore: settingsStore,
          navigator: navigator,
          dataCache: dataCache,
        );
      case AppDestination.artists:
        return ArtistsView(
          key: const ValueKey('view_artists'),
          repository: repository,
          settingsStore: settingsStore,
          navigator: navigator,
          dataCache: dataCache,
        );
      case AppDestination.tracks:
        return TracksView(
          key: const ValueKey('view_tracks'),
          repository: repository,
          controller: controller,
          settingsStore: settingsStore,
          dataCache: dataCache,
        );
      case AppDestination.stats:
        return StatsView(
          key: const ValueKey('view_stats'),
          repository: repository,
          playbackController: controller,
          settingsStore: settingsStore,
          navigator: navigator,
          dataCache: dataCache,
          clock: statsClock,
        );
      case AppDestination.wrapped:
        final entry = navigator.currentEntry;
        final kind = entry.wrappedKind ?? RecapPeriodKind.monthly;
        return WrappedView(
          key: ValueKey(
            'view_wrapped_${kind.name}_${entry.wrappedYear}_${entry.wrappedMonth}',
          ),
          repository: repository,
          settingsStore: settingsStore,
          navigator: navigator,
          dataCache: dataCache,
          initialKind: kind,
          initialYear: entry.wrappedYear,
          initialMonth: entry.wrappedMonth,
          clock: statsClock,
          directoryPicker: directoryPicker,
          onOpenFolder: onOpenFolder,
        );
      case AppDestination.albumDetail:
        final album = navigator.selectedAlbum ??
            AlbumSummary(
              album: navigator.selectedAlbumId ?? '',
              trackCount: 0,
            );
        return AlbumDetailView(
          key: ValueKey(
            'view_album_detail_${AlbumIdentity.forSummary(album)}',
          ),
          album: album,
          repository: repository,
          controller: controller,
          settingsStore: settingsStore,
          navigator: navigator,
          dataCache: dataCache,
        );
      case AppDestination.artistDetail:
        final artist = navigator.selectedArtist ??
            ArtistSummary(
              name: navigator.selectedArtistId ?? '',
              albumCount: 0,
              trackCount: 0,
            );
        return ArtistDetailView(
          key: ValueKey('view_artist_detail_${artist.name}'),
          artist: artist,
          repository: repository,
          controller: controller,
          settingsStore: settingsStore,
          navigator: navigator,
          dataCache: dataCache,
        );
      case AppDestination.audioLab:
        return AudioLabScreen(
          key: const ValueKey('view_audio_lab'),
          engine: engine,
          controller: controller,
        );
      case AppDestination.settings:
        return SettingsView(
          key: const ValueKey('view_settings'),
          engine: engine,
          repository: repository,
          settingsStore: settingsStore,
          navigator: navigator,
          audioSettingsApplier: audioSettingsApplier,
          artistNameStore: artistNameStore,
          eqController: eqController,
          onOpenFolders: onOpenFolders,
          trayWindowController: trayWindowController,
        );
      case AppDestination.audioPanels:
        return AudioPanelsView(
          key: const ValueKey('view_audio_panels'),
          engine: engine,
          eqController: eqController,
          audioSettingsApplier: audioSettingsApplier,
          settingsStore: settingsStore,
          navigator: navigator,
        );
      case AppDestination.playlists:
        return PlaylistsView(
          key: const ValueKey('view_playlists'),
          collections: userCollections,
          repository: repository,
          controller: controller,
          settingsStore: settingsStore,
          navigator: navigator,
          dataCache: dataCache,
        );
      case AppDestination.playlistDetail:
        final playlistId = navigator.selectedPlaylistId ?? 0;
        final playlist = navigator.selectedPlaylist;
        return PlaylistDetailView(
          key: ValueKey('view_playlist_detail_$playlistId'),
          playlistId: playlistId,
          initialPlaylist: playlist,
          repository: repository,
          collections: userCollections,
          controller: controller,
          settingsStore: settingsStore,
          navigator: navigator,
          dataCache: dataCache,
        );
      case AppDestination.favorites:
        return FavoritesView(
          key: const ValueKey('view_favorites'),
          repository: repository,
          collections: userCollections,
          controller: controller,
          settingsStore: settingsStore,
          dataCache: dataCache,
        );
      case AppDestination.recentlyPlayed:
        return RecentlyPlayedView(
          key: const ValueKey('view_recently_played'),
          repository: repository,
          controller: controller,
          settingsStore: settingsStore,
          collections: userCollections,
          dataCache: dataCache,
        );
      case AppDestination.queue:
        return QueueView(
          key: const ValueKey('view_queue'),
          controller: controller,
          navigator: navigator,
          settingsStore: settingsStore,
          userCollections: userCollections,
        );
      case AppDestination.folders:
        // Revert to albums and open modal
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigator.navigateTo(AppDestination.albums);
          onOpenFolders();
        });
        return const SizedBox.shrink();
      case AppDestination.lyrics:
      case AppDestination.nowPlaying:
      case AppDestination.fullScreen:
        return const SizedBox.shrink();
    }
  }
}
