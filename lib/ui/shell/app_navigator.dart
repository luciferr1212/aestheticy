import 'package:flutter/foundation.dart';

import '../../library/models.dart';

/// Available top-level navigation destinations.
enum AppDestination {
  /// Albums grid or list screen.
  albums,

  /// Artists grid screen.
  artists,

  /// Tracks tabular screen.
  tracks,

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
}

/// Navigation state coordinator managing active destination and detail selection.
class AppNavigator extends ChangeNotifier {
  AppDestination _current = AppDestination.albums;
  AppDestination _previousList = AppDestination.albums;
  AppDestination _audioPanelsPrevious = AppDestination.albums;

  // Stored state for returning from nowPlaying or fullScreen
  AppDestination _savedDestination = AppDestination.albums;
  String? _savedAlbumId;
  AlbumSummary? _savedAlbum;
  String? _savedArtistId;
  ArtistSummary? _savedArtist;
  int? _savedPlaylistId;
  PlaylistSummary? _savedPlaylist;
  bool _fullScreenCameFromNowPlaying = false;

  String? _selectedAlbumId;
  AlbumSummary? _selectedAlbum;

  String? _selectedArtistId;
  ArtistSummary? _selectedArtist;

  int? _selectedPlaylistId;
  PlaylistSummary? _selectedPlaylist;

  /// Creates an [AppNavigator] defaulting to [AppDestination.albums].
  AppNavigator({AppDestination initialDestination = AppDestination.albums})
      : _current = initialDestination;

  /// Current active destination.
  AppDestination get current => _current;

  /// Current active destination alias.
  AppDestination get currentDestination => _current;

  /// Selected album ID when [current] is [AppDestination.albumDetail].
  String? get selectedAlbumId => _selectedAlbumId;

  /// Selected album model when available.
  AlbumSummary? get selectedAlbum => _selectedAlbum;

  /// Selected artist ID when [current] is [AppDestination.artistDetail].
  String? get selectedArtistId => _selectedArtistId;

  /// Selected artist model when available.
  ArtistSummary? get selectedArtist => _selectedArtist;

  /// Selected playlist ID when [current] is [AppDestination.playlistDetail].
  int? get selectedPlaylistId => _selectedPlaylistId;

  /// Selected playlist model when available.
  PlaylistSummary? get selectedPlaylist => _selectedPlaylist;

  /// Navigates to [destination].
  void navigateTo(AppDestination destination) {
    if (_current == destination) return;

    if (destination == AppDestination.audioPanels) {
      _audioPanelsPrevious = _current;
    }

    if (destination == AppDestination.nowPlaying) {
      if (_current != AppDestination.fullScreen && _current != AppDestination.lyrics) {
        _saveCurrentState();
      }
    } else if (destination == AppDestination.lyrics) {
      if (_current != AppDestination.fullScreen && _current != AppDestination.nowPlaying) {
        _saveCurrentState();
      }
    } else if (destination == AppDestination.fullScreen) {
      if (_current == AppDestination.nowPlaying) {
        _fullScreenCameFromNowPlaying = true;
      } else {
        _fullScreenCameFromNowPlaying = false;
        _saveCurrentState();
      }
    } else {
      _fullScreenCameFromNowPlaying = false;
    }

    if (_isListDestination(_current)) {
      _previousList = _current;
    }

    _current = destination;
    if (destination != AppDestination.albumDetail &&
        destination != AppDestination.nowPlaying &&
        destination != AppDestination.lyrics &&
        destination != AppDestination.fullScreen &&
        destination != AppDestination.audioPanels) {
      _selectedAlbumId = null;
      _selectedAlbum = null;
    }
    if (destination != AppDestination.artistDetail &&
        destination != AppDestination.nowPlaying &&
        destination != AppDestination.lyrics &&
        destination != AppDestination.fullScreen &&
        destination != AppDestination.audioPanels) {
      _selectedArtistId = null;
      _selectedArtist = null;
    }
    if (destination != AppDestination.playlistDetail &&
        destination != AppDestination.nowPlaying &&
        destination != AppDestination.lyrics &&
        destination != AppDestination.fullScreen &&
        destination != AppDestination.audioPanels) {
      _selectedPlaylistId = null;
      _selectedPlaylist = null;
    }
    notifyListeners();
  }

  void _saveCurrentState() {
    _savedDestination = _current;
    _savedAlbumId = _selectedAlbumId;
    _savedAlbum = _selectedAlbum;
    _savedArtistId = _selectedArtistId;
    _savedArtist = _selectedArtist;
    _savedPlaylistId = _selectedPlaylistId;
    _savedPlaylist = _selectedPlaylist;
  }

  void _restoreSavedState() {
    _current = _savedDestination;
    _selectedAlbumId = _savedAlbumId;
    _selectedAlbum = _savedAlbum;
    _selectedArtistId = _savedArtistId;
    _selectedArtist = _savedArtist;
    _selectedPlaylistId = _savedPlaylistId;
    _selectedPlaylist = _savedPlaylist;
    _fullScreenCameFromNowPlaying = false;
  }

  /// Opens the synchronized lyrics view.
  void openLyrics() => navigateTo(AppDestination.lyrics);

  /// Opens the full Now Playing screen.
  void openNowPlaying() => navigateTo(AppDestination.nowPlaying);

  /// Opens the immersive Full Screen view.
  void openFullScreen() => navigateTo(AppDestination.fullScreen);

  /// Opens the Playlists view.
  void openPlaylists() => navigateTo(AppDestination.playlists);

  /// Opens the Favorites view.
  void openFavorites() => navigateTo(AppDestination.favorites);

  /// Opens the Recently Played view.
  void openRecentlyPlayed() => navigateTo(AppDestination.recentlyPlayed);

  /// Navigates to the detail screen for the given [id] and [playlist].
  void openPlaylistDetail(int id, {PlaylistSummary? playlist}) {
    if (_isListDestination(_current)) {
      _previousList = _current;
    }
    _selectedPlaylistId = id;
    _selectedPlaylist = playlist;
    _current = AppDestination.playlistDetail;
    notifyListeners();
  }

  /// Navigates to the detail screen for the given [albumId] and [album].
  void openAlbumDetail(String albumId, {AlbumSummary? album}) {
    if (_isListDestination(_current)) {
      _previousList = _current;
    }
    _selectedAlbumId = albumId;
    _selectedAlbum = album;
    _current = AppDestination.albumDetail;
    notifyListeners();
  }

  /// Navigates to the detail screen for the given [artistId] and [artist].
  void openArtistDetail(String artistId, {ArtistSummary? artist}) {
    if (_isListDestination(_current)) {
      _previousList = _current;
    }
    _selectedArtistId = artistId;
    _selectedArtist = artist;
    _current = AppDestination.artistDetail;
    notifyListeners();
  }

  /// Opens the application Settings screen.
  void openSettings() => navigateTo(AppDestination.settings);

  /// Opens the Equalizer and Signal Path panels screen.
  void openAudioPanels() => navigateTo(AppDestination.audioPanels);

  /// Navigates back from detail or immersive screens.
  ///
  /// Returns `true` if handled, `false` otherwise.
  bool goBack() {
    if (_current == AppDestination.audioPanels) {
      _current = _audioPanelsPrevious;
      notifyListeners();
      return true;
    } else if (_current == AppDestination.fullScreen) {
      if (_fullScreenCameFromNowPlaying) {
        _current = AppDestination.nowPlaying;
      } else {
        _restoreSavedState();
      }
      notifyListeners();
      return true;
    } else if (_current == AppDestination.nowPlaying) {
      _restoreSavedState();
      notifyListeners();
      return true;
    } else if (_current == AppDestination.lyrics) {
      _restoreSavedState();
      notifyListeners();
      return true;
    } else if (_current == AppDestination.playlistDetail) {
      _current = AppDestination.playlists;
      _selectedPlaylistId = null;
      _selectedPlaylist = null;
      notifyListeners();
      return true;
    } else if (_current == AppDestination.albumDetail) {
      _current = _previousList == AppDestination.artists
          ? AppDestination.artists
          : AppDestination.albums;
      _selectedAlbumId = null;
      _selectedAlbum = null;
      notifyListeners();
      return true;
    } else if (_current == AppDestination.artistDetail) {
      _current = AppDestination.artists;
      _selectedArtistId = null;
      _selectedArtist = null;
      notifyListeners();
      return true;
    } else if (_current == AppDestination.audioLab ||
        _current == AppDestination.folders ||
        _current == AppDestination.settings) {
      _current = _previousList;
      notifyListeners();
      return true;
    }
    return false;
  }

  static bool _isListDestination(AppDestination destination) {
    return destination == AppDestination.albums ||
        destination == AppDestination.artists ||
        destination == AppDestination.tracks ||
        destination == AppDestination.playlists ||
        destination == AppDestination.favorites ||
        destination == AppDestination.recentlyPlayed;
  }
}
