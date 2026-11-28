import 'package:flutter/foundation.dart';

import '../../diagnostics/app_logger.dart';
import '../../library/models.dart';

/// Available top-level navigation destinations.
enum AppDestination {
  /// Calm Home landing screen.
  home,

  /// Albums grid or list screen.
  albums,

  /// Artists grid screen.
  artists,

  /// Tracks tabular screen.
  tracks,

  /// Calm listening statistics screen.
  stats,

  /// Detail view for a specific album.
  albumDetail,

  /// Detail view for a specific artist.
  artistDetail,

  /// Audio engine inspection and diagnostics screen.
  audioLab,

  /// Music library folder management screen.
  folders,

  /// Full Now Playing screen.
  nowPlaying,

  /// Immersive in-app full screen view.
  fullScreen,

  /// Application settings and preferences screen.
  settings,

  /// Equalizer and Signal Path audio panels screen.
  audioPanels,

  /// User playlists library screen.
  playlists,

  /// Detail view for a specific playlist.
  playlistDetail,

  /// Favorites library screen.
  favorites,

  /// Recently played tracks screen.
  recentlyPlayed,

  /// Synchronized and plain lyrics screen.
  lyrics,

  /// Interactive playback queue screen.
  queue,
}

/// Represents a distinct entry in the navigation history stack.
class NavEntry {
  /// Unique identifier for this history entry.
  final String id;

  /// The screen destination.
  final AppDestination destination;

  /// Selected album ID when destination is [AppDestination.albumDetail].
  final String? albumId;

  /// Selected album model when available.
  final AlbumSummary? album;

  /// Selected artist ID when destination is [AppDestination.artistDetail].
  final String? artistId;

  /// Selected artist model when available.
  final ArtistSummary? artist;

  /// Selected playlist ID when destination is [AppDestination.playlistDetail].
  final int? playlistId;

  /// Selected playlist model when available.
  final PlaylistSummary? playlist;

  /// Preserved view state (e.g. scroll offset) across navigation.
  final Map<String, Object?> viewState;

  /// Creates a new [NavEntry].
  NavEntry({
    required this.id,
    required this.destination,
    this.albumId,
    this.album,
    this.artistId,
    this.artist,
    this.playlistId,
    this.playlist,
    Map<String, Object?>? viewState,
  }) : viewState = viewState ?? <String, Object?>{};

  /// Checks if this entry matches destination and all detail arguments.
  bool matches({
    required AppDestination destination,
    String? albumId,
    String? artistId,
    int? playlistId,
  }) {
    if (this.destination != destination) return false;
    if (destination == AppDestination.albumDetail && this.albumId != albumId) return false;
    if (destination == AppDestination.artistDetail && this.artistId != artistId) return false;
    if (destination == AppDestination.playlistDetail && this.playlistId != playlistId) return false;
    return true;
  }
}

/// Navigation state coordinator managing active destination and history stack.
class AppNavigator extends ChangeNotifier {
  static const int kMaxHistory = 50;

  final List<NavEntry> _history = [];
  int _historyIndex = 0;
  int _idSeq = 0;

  /// Optional callback invoked to capture active view state before navigating.
  void Function(Map<String, Object?>)? onCaptureViewState;

  /// Creates an [AppNavigator] defaulting to [AppDestination.home].
  AppNavigator({AppDestination initialDestination = AppDestination.home}) {
    _history.add(
      NavEntry(
        id: 'nav_${_idSeq++}',
        destination: initialDestination,
      ),
    );
    _historyIndex = 0;
  }

  /// Current active navigation entry.
  NavEntry get currentEntry => _history[_historyIndex];

  /// Current active destination.
  AppDestination get current => currentEntry.destination;

  /// Current active destination alias.
  AppDestination get currentDestination => current;

  /// Selected album ID when [current] is [AppDestination.albumDetail].
  String? get selectedAlbumId => currentEntry.albumId;

  /// Selected album model when available.
  AlbumSummary? get selectedAlbum => currentEntry.album;

  /// Selected artist ID when [current] is [AppDestination.artistDetail].
  String? get selectedArtistId => currentEntry.artistId;

  /// Selected artist model when available.
  ArtistSummary? get selectedArtist => currentEntry.artist;

  /// Selected playlist ID when [current] is [AppDestination.playlistDetail].
  int? get selectedPlaylistId => currentEntry.playlistId;

  /// Selected playlist model when available.
  PlaylistSummary? get selectedPlaylist => currentEntry.playlist;

  /// Whether navigating back is possible.
  bool get canGoBack => _historyIndex > 0;

  /// Whether navigating forward is possible.
  bool get canGoForward => _historyIndex < _history.length - 1;

  /// Unmodifiable view of the history stack.
  List<NavEntry> get history => List.unmodifiable(_history);

  /// Current index within the history stack.
  int get historyIndex => _historyIndex;

  void _captureViewState() {
    try {
      onCaptureViewState?.call(currentEntry.viewState);
    } catch (e, st) {
      AppLogger.instance.warn(
        'AppNavigator',
        'Failed capturing view state on navigation',
        e,
        st,
      );
    }
  }

  void _pushEntry(NavEntry entry) {
    // 1. Pushing an entry equal to the current one does nothing
    if (currentEntry.matches(
      destination: entry.destination,
      albumId: entry.albumId,
      artistId: entry.artistId,
      playlistId: entry.playlistId,
    )) {
      return;
    }

    // 2. If new destination equals previous entry (toggle back), treat as goBack
    if (_historyIndex > 0) {
      final prev = _history[_historyIndex - 1];
      if (prev.matches(
        destination: entry.destination,
        albumId: entry.albumId,
        artistId: entry.artistId,
        playlistId: entry.playlistId,
      )) {
        goBack();
        return;
      }
    }

    _captureViewState();

    // Drop forward entries
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }

    _history.add(entry);
    _historyIndex = _history.length - 1;

    // Cap at 50 entries
    if (_history.length > kMaxHistory) {
      _history.removeAt(0);
      _historyIndex--;
    }

    notifyListeners();
  }

  /// Navigates to [destination].
  void navigateTo(AppDestination destination) {
    _pushEntry(
      NavEntry(
        id: 'nav_${_idSeq++}',
        destination: destination,
      ),
    );
  }

  /// Navigates to the detail screen for the given [albumId] and [album].
  void openAlbumDetail(String albumId, {AlbumSummary? album}) {
    _pushEntry(
      NavEntry(
        id: 'nav_${_idSeq++}',
        destination: AppDestination.albumDetail,
        albumId: albumId,
        album: album,
      ),
    );
  }

  /// Navigates to the detail screen for the given [artistId] and [artist].
  void openArtistDetail(String artistId, {ArtistSummary? artist}) {
    _pushEntry(
      NavEntry(
        id: 'nav_${_idSeq++}',
        destination: AppDestination.artistDetail,
        artistId: artistId,
        artist: artist,
      ),
    );
  }

  /// Navigates to the detail screen for the given [id] and [playlist].
  void openPlaylistDetail(int id, {PlaylistSummary? playlist}) {
    _pushEntry(
      NavEntry(
        id: 'nav_${_idSeq++}',
        destination: AppDestination.playlistDetail,
        playlistId: id,
        playlist: playlist,
      ),
    );
  }

  /// Opens the Home screen.
  void openHome() => navigateTo(AppDestination.home);

  /// Opens the Listening Stats screen.
  void openStats() => navigateTo(AppDestination.stats);

  /// Opens the synchronized lyrics view.
  void openLyrics() => navigateTo(AppDestination.lyrics);

  /// Opens the interactive queue view.
  void openQueue() => navigateTo(AppDestination.queue);

  /// Opens the full Now Playing screen.
  void openNowPlaying() => navigateTo(AppDestination.nowPlaying);

  /// Opens the immersive Full Screen view.
  void openFullScreen() => navigateTo(AppDestination.fullScreen);

  /// Toggles between [AppDestination.fullScreen] and the previous view.
  void toggleFullScreen() {
    if (current == AppDestination.fullScreen) {
      goBack();
    } else {
      openFullScreen();
    }
  }

  /// Opens the Playlists view.
  void openPlaylists() => navigateTo(AppDestination.playlists);

  /// Opens the Favorites view.
  void openFavorites() => navigateTo(AppDestination.favorites);

  /// Opens the Recently Played view.
  void openRecentlyPlayed() => navigateTo(AppDestination.recentlyPlayed);

  /// Opens the application Settings screen.
  void openSettings() => navigateTo(AppDestination.settings);

  /// Opens the Equalizer and Signal Path panels screen.
  void openAudioPanels() => navigateTo(AppDestination.audioPanels);

  /// Navigates back to the previous entry.
  ///
  /// Returns `true` if popped, `false` if at root.
  bool goBack() {
    if (!canGoBack) return false;
    _captureViewState();
    _historyIndex--;
    notifyListeners();
    return true;
  }

  /// Navigates forward to the next entry.
  ///
  /// Returns `true` if moved forward, `false` otherwise.
  bool goForward() {
    if (!canGoForward) return false;
    _captureViewState();
    _historyIndex++;
    notifyListeners();
    return true;
  }
}
