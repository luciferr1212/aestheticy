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
}

/// Navigation state coordinator managing active destination and detail selection.
class AppNavigator extends ChangeNotifier {
  AppDestination _current = AppDestination.albums;
  AppDestination _previousList = AppDestination.albums;

  // Stored state for returning from nowPlaying or fullScreen
  AppDestination _savedDestination = AppDestination.albums;
  String? _savedAlbumId;
  AlbumSummary? _savedAlbum;
  String? _savedArtistId;
  ArtistSummary? _savedArtist;
  bool _fullScreenCameFromNowPlaying = false;

  String? _selectedAlbumId;
  AlbumSummary? _selectedAlbum;

  String? _selectedArtistId;
  ArtistSummary? _selectedArtist;

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

  /// Navigates to [destination].
  void navigateTo(AppDestination destination) {
    if (_current == destination) return;

    if (destination == AppDestination.nowPlaying) {
      if (_current != AppDestination.fullScreen) {
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
        destination != AppDestination.fullScreen) {
      _selectedAlbumId = null;
      _selectedAlbum = null;
    }
    if (destination != AppDestination.artistDetail &&
        destination != AppDestination.nowPlaying &&
        destination != AppDestination.fullScreen) {
      _selectedArtistId = null;
      _selectedArtist = null;
    }
    notifyListeners();
  }

  void _saveCurrentState() {
    _savedDestination = _current;
    _savedAlbumId = _selectedAlbumId;
    _savedAlbum = _selectedAlbum;
    _savedArtistId = _selectedArtistId;
    _savedArtist = _selectedArtist;
  }

  void _restoreSavedState() {
    _current = _savedDestination;
    _selectedAlbumId = _savedAlbumId;
    _selectedAlbum = _savedAlbum;
    _selectedArtistId = _savedArtistId;
    _selectedArtist = _savedArtist;
    _fullScreenCameFromNowPlaying = false;
  }

  /// Opens the full Now Playing screen.
  void openNowPlaying() => navigateTo(AppDestination.nowPlaying);

  /// Opens the immersive Full Screen view.
  void openFullScreen() => navigateTo(AppDestination.fullScreen);

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

  /// Navigates back from detail or immersive screens.
  ///
  /// Returns `true` if handled, `false` otherwise.
  bool goBack() {
    if (_current == AppDestination.fullScreen) {
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
        destination == AppDestination.tracks;
  }
}
