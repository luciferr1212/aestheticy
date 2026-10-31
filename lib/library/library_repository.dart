/// Repository interface defining the music library data access contract.
library;

import 'package:aestheticy/library/models.dart';

/// Abstract storage repository for music library tracks and folders.
abstract class LibraryRepository {
  /// Adds a filesystem directory to the library.
  ///
  /// If the folder already exists in the database, returns the existing record.
  Future<LibraryFolder> addFolder(String path);

  /// Removes a folder and cascades deletion to all associated tracks.
  Future<void> removeFolder(int folderId);

  /// Lists all monitored library folders.
  Future<List<LibraryFolder>> listFolders();

  /// Updates the [LibraryFolder.lastScanAt] timestamp for the folder identified by [folderId].
  Future<void> markFolderScanned(int folderId, DateTime timestamp);

  /// Inserts or updates multiple tracks within a single database transaction.
  ///
  /// Existing tracks with matching paths are updated, preserving their original
  /// [Track.addedAt] timestamp.
  Future<void> upsertTracks(List<Track> tracks);

  /// Returns a map of `path -> (mtimeMs, sizeBytes)` for all existing tracks
  /// under the given [folderId].
  ///
  /// Used by directory scanners to detect added, modified, and removed files.
  Future<Map<String, ({int mtimeMs, int sizeBytes})>> existingFiles(
    int folderId,
  );

  /// Removes tracks whose paths match any of the given [paths].
  Future<void> removeTracksByPath(List<String> paths);

  /// Lists all derived albums with track counts and aggregated metadata.
  Future<List<AlbumSummary>> listAlbums({int? limit, int? offset});

  /// Lists all derived artists with album and track counts.
  Future<List<ArtistSummary>> listArtists({int? limit, int? offset});

  /// Returns the total number of unique derived albums.
  Future<int> albumCount();

  /// Returns the total number of unique derived artists.
  Future<int> artistCount();

  /// Retrieves all tracks belonging to [album], optionally scoped to [albumArtist].
  Future<List<Track>> tracksOfAlbum(String album, {String? albumArtist});

  /// Retrieves all tracks performed by [artist].
  Future<List<Track>> tracksOfArtist(String artist);

  /// Lists tracks with optional sorting and pagination.
  Future<List<Track>> listTracks({
    TrackSort sort = TrackSort.titleAsc,
    int? limit,
    int? offset,
  });

  /// Searches for tracks whose normalized title, artist, or album matches [query].
  Future<List<Track>> search(String query);

  /// Searches for derived albums matching [query] with an optional [limit].
  Future<List<AlbumSummary>> searchAlbums(String query, {int? limit});

  /// Searches for derived artists matching [query] with an optional [limit].
  Future<List<ArtistSummary>> searchArtists(String query, {int? limit});

  /// Returns the total number of tracks currently in the library.
  Future<int> trackCount();

  /// Closes the underlying database connection and releases resources.
  Future<void> close();
}
