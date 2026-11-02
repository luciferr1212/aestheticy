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
}

/// Navigation state coordinator managing active destination and detail selection.
class AppNavigator extends ChangeNotifier {
  AppDestination _current = AppDestination.albums;
  AppDestination _previousList = AppDestination.albums;

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

    if (_isListDestination(_current)) {
      _previousList = _current;
    }

    _current = destination;
    if (destination != AppDestination.albumDetail) {
      _selectedAlbumId = null;
      _selectedAlbum = null;
    }
    if (destination != AppDestination.artistDetail) {
      _selectedArtistId = null;
      _selectedArtist = null;
    }
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

  /// Navigates back from detail screens to the preceding list destination.
  ///
  /// Returns `true` if handled, `false` otherwise.
  bool goBack() {
    if (_current == AppDestination.albumDetail) {
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
        _current == AppDestination.folders) {
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
