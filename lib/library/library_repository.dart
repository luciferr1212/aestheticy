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

  /// Retrieves all tracks performed by [artist], optionally matching by [artistKey].
  Future<List<Track>> tracksOfArtist(String artist, {String? artistKey});

  /// Merges [sourceKey] artist into [targetKey] artist by creating or updating an alias.
  ///
  /// Merging chains (A->B, B->C) resolve to C; rejects cycles.
  /// Rebuilds artist links after the merge.
  Future<void> mergeArtists(
    String sourceKey,
    String targetKey, {
    String? targetName,
  });

  /// Removes an artist merge alias identified by [aliasKey] and rebuilds artist links.
  Future<void> unmergeArtist(String aliasKey);

  /// Lists all active artist merge aliases.
  Future<List<ArtistAlias>> listAliases();

  /// Adds an artist name string to the never-split list and rebuilds artist links.
  Future<void> addNoSplit(String name);

  /// Removes an artist key from the never-split list and rebuilds artist links.
  Future<void> removeNoSplit(String key);

  /// Lists all registered never-split artist rules.
  Future<List<ArtistNoSplit>> listNoSplit();

  /// Rebuilds all artist links in `track_artists` based on distinct track artists.
  Future<void> rebuildArtistLinks();

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

  /// Inserts a new playback event into history and returns its generated row ID.
  Future<int> insertPlayEvent(PlayEvent e);

  /// Updates an existing playback event with accumulated listening time and completion status.
  Future<void> updatePlayEvent(
    int id, {
    required int listenedMs,
    required bool counted,
    required bool completed,
  });

  /// Retrieves the most recent playback events ordered from newest to oldest.
  Future<List<PlayEvent>> recentPlayEvents({int limit = 50});

  /// Returns the total count of playback events, optionally restricted to counted plays.
  Future<int> playEventCount({bool countedOnly = false});

  /// Clears all recorded playback events from history.
  Future<void> clearPlayEvents();

  // ── Favorites ────────────────────────────────────────────────────────

  /// Returns the set of all track paths marked as favorite.
  Future<Set<String>> favoritePaths();

  /// Sets or clears favorite status for the track at [path].
  Future<void> setFavorite(String path, bool value);

  /// Retrieves all favorited tracks that exist in the library, newest favorite first.
  Future<List<Track>> favoriteTracks();

  // ── Ratings ──────────────────────────────────────────────────────────

  /// Returns a map of track path to star rating (1..5) for all rated tracks.
  Future<Map<String, int>> allRatings();

  /// Sets star rating (1..5) for the track at [path], or 0 to clear.
  /// Throws [ArgumentError] if [stars] is outside 0..5.
  Future<void> setRating(String path, int stars);

  // ── Playlists ────────────────────────────────────────────────────────

  /// Creates a new empty playlist with [name].
  ///
  /// Throws [PlaylistNameException] if name is invalid or duplicate.
  /// Throws [PlaylistLimitException] if the 500-playlist limit is reached.
  Future<PlaylistSummary> createPlaylist(String name);

  /// Renames an existing playlist identified by [id].
  ///
  /// Throws [PlaylistNameException] if name is invalid or duplicate.
  Future<void> renamePlaylist(int id, String name);

  /// Deletes a playlist and all its items.
  Future<void> deletePlaylist(int id);

  /// Lists all playlists with summary statistics.
  Future<List<PlaylistSummary>> listPlaylists();

  /// Retrieves all entries for playlist [id] in position order.
  Future<List<PlaylistEntry>> playlistEntries(int id);

  /// Appends [paths] to the end of playlist [id] in order.
  /// Duplicates are allowed. Returns the number of items added.
  /// Throws [PlaylistLimitException] if entry limit of 20000 is exceeded.
  Future<int> addToPlaylist(int id, List<String> paths);

  /// Removes entries with [entryIds] from playlist [id] and renumbers positions without gaps.
  Future<void> removePlaylistEntries(int id, List<int> entryIds);

  /// Moves entry [entryId] in playlist [id] to [newPosition] and updates order.
  Future<void> movePlaylistEntry(int id, int entryId, int newPosition);

  // ── Recently Played ──────────────────────────────────────────────────

  /// Retrieves tracks played (counted = 1) from history, distinct by track path,
  /// newest first, skipping any files not found in the library.
  Future<List<Track>> recentlyPlayedTracks({int limit = 200});

  /// Closes the underlying database connection and releases resources.
  Future<void> close();
}
