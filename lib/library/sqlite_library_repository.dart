/// SQLite-backed implementation of [LibraryRepository].
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/sqlite_albums_store.dart';
import 'package:aestheticy/library/sqlite/sqlite_artists_store.dart';
import 'package:aestheticy/library/sqlite/sqlite_collections_store.dart';
import 'package:aestheticy/library/sqlite/sqlite_db_initializer.dart';
import 'package:aestheticy/library/sqlite/sqlite_history_store.dart';
import 'package:aestheticy/library/sqlite/sqlite_tracks_store.dart';

/// SQLite storage implementation for the music library.
class SqliteLibraryRepository implements LibraryRepository {
  final Database _db;
  final SqliteTracksStore _tracks;
  final SqliteAlbumsStore _albums;
  final SqliteArtistsStore _artists;
  final SqliteCollectionsStore _collections;
  final SqliteHistoryStore _history;

  SqliteLibraryRepository._(this._db)
      : _tracks = SqliteTracksStore(_db),
        _albums = SqliteAlbumsStore(_db),
        _artists = SqliteArtistsStore(_db),
        _collections = SqliteCollectionsStore(_db),
        _history = SqliteHistoryStore(_db);

  /// Opens an in-memory SQLite database, applying schema migrations.
  ///
  /// Primarily intended for isolated unit testing.
  factory SqliteLibraryRepository.inMemory() {
    final db = sqlite3.openInMemory();
    SqliteDbInitializer.init(db);
    return SqliteLibraryRepository._(db);
  }

  /// Opens or creates an SQLite database at [filePath], applying schema migrations.
  factory SqliteLibraryRepository.openFile(String filePath) {
    final file = File(filePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final db = sqlite3.open(filePath);
    SqliteDbInitializer.init(db);
    return SqliteLibraryRepository._(db);
  }

  /// Wraps an existing [Database] instance, applying schema migrations.
  factory SqliteLibraryRepository.fromDatabase(Database db) {
    SqliteDbInitializer.init(db);
    return SqliteLibraryRepository._(db);
  }

  /// Opens the default database file in the application support directory.
  static Future<SqliteLibraryRepository> openDefault() async {
    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(supportDir.path, 'Aestheticy'));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }
    final dbPath = p.join(dbDir.path, 'library.db');
    return SqliteLibraryRepository.openFile(dbPath);
  }

  @override
  Future<LibraryFolder> addFolder(String path) => _tracks.addFolder(path);

  @override
  Future<void> removeFolder(int folderId) => _tracks.removeFolder(folderId);

  @override
  Future<List<LibraryFolder>> listFolders() => _tracks.listFolders();

  @override
  Future<void> markFolderScanned(int folderId, DateTime timestamp) =>
      _tracks.markFolderScanned(folderId, timestamp);

  @override
  Future<void> upsertTracks(List<Track> tracks) => _tracks.upsertTracks(tracks);

  @override
  Future<Map<String, ({int mtimeMs, int sizeBytes})>> existingFiles(
    int folderId,
  ) =>
      _tracks.existingFiles(folderId);

  @override
  Future<void> removeTracksByPath(List<String> paths) =>
      _tracks.removeTracksByPath(paths);

  @override
  Future<List<AlbumSummary>> listAlbums({int? limit, int? offset}) =>
      _albums.listAlbums(limit: limit, offset: offset);

  @override
  Future<List<AlbumSummary>> listAlbumsByArtistKey(String artistKey) =>
      _albums.listAlbumsByArtistKey(artistKey);

  @override
  Future<List<AlbumSummary>> listAlbumsByArtistKeys(List<String> artistKeys) =>
      _albums.listAlbumsByArtistKeys(artistKeys);

  @override
  Future<List<ArtistSummary>> listArtists({int? limit, int? offset}) =>
      _artists.listArtists(limit: limit, offset: offset);

  @override
  Future<List<Track>> tracksOfAlbum(
    String album, {
    String? albumArtist,
    String? albumKey,
  }) =>
      _albums.tracksOfAlbum(album, albumArtist: albumArtist, albumKey: albumKey);

  @override
  Future<List<Track>> tracksOfArtist(String artist, {String? artistKey}) =>
      _artists.tracksOfArtist(artist, artistKey: artistKey);

  @override
  Future<List<Track>> listTracks({
    TrackSort sort = TrackSort.titleAsc,
    int? limit,
    int? offset,
  }) =>
      _tracks.listTracks(sort: sort, limit: limit, offset: offset);

  @override
  Future<List<Track>> search(String query) => _tracks.search(query);

  @override
  Future<List<AlbumSummary>> searchAlbums(String query, {int? limit}) =>
      _albums.searchAlbums(query, limit: limit);

  @override
  Future<List<ArtistSummary>> searchArtists(String query, {int? limit}) =>
      _artists.searchArtists(query, limit: limit);

  @override
  Future<int> albumCount() => _albums.albumCount();

  @override
  Future<int> artistCount() => _artists.artistCount();

  @override
  Future<int> trackCount() => _tracks.trackCount();

  @override
  Future<void> mergeArtists(
    String sourceKey,
    String targetKey, {
    String? targetName,
  }) =>
      _artists.mergeArtists(sourceKey, targetKey, targetName: targetName);

  @override
  Future<void> unmergeArtist(String aliasKey) =>
      _artists.unmergeArtist(aliasKey);

  @override
  Future<List<ArtistAlias>> listAliases() => _artists.listAliases();

  @override
  Future<void> addNoSplit(String name) => _artists.addNoSplit(name);

  @override
  Future<void> removeNoSplit(String key) => _artists.removeNoSplit(key);

  @override
  Future<List<ArtistNoSplit>> listNoSplit() => _artists.listNoSplit();

  @override
  Future<void> rebuildArtistLinks() => _artists.rebuildArtistLinks();

  @override
  Future<int> insertPlayEvent(PlayEvent e) => _history.insertPlayEvent(e);

  @override
  Future<void> updatePlayEvent(
    int id, {
    required int listenedMs,
    required bool counted,
    required bool completed,
  }) =>
      _history.updatePlayEvent(
        id,
        listenedMs: listenedMs,
        counted: counted,
        completed: completed,
      );

  @override
  Future<List<PlayEvent>> recentPlayEvents({int limit = 50}) =>
      _history.recentPlayEvents(limit: limit);

  @override
  Future<int> playEventCount({bool countedOnly = false}) =>
      _history.playEventCount(countedOnly: countedOnly);

  @override
  Future<void> clearPlayEvents() => _history.clearPlayEvents();

  @override
  Future<Set<String>> favoritePaths() => _collections.favoritePaths();

  @override
  Future<void> setFavorite(String path, bool value) =>
      _collections.setFavorite(path, value);

  @override
  Future<List<Track>> favoriteTracks() => _collections.favoriteTracks();

  @override
  Future<Map<String, int>> allRatings() => _collections.allRatings();

  @override
  Future<void> setRating(String path, int stars) =>
      _collections.setRating(path, stars);

  @override
  Future<PlaylistSummary> createPlaylist(String name) =>
      _collections.createPlaylist(name);

  @override
  Future<void> renamePlaylist(int id, String name) =>
      _collections.renamePlaylist(id, name);

  @override
  Future<void> deletePlaylist(int id) => _collections.deletePlaylist(id);

  @override
  Future<List<PlaylistSummary>> listPlaylists() =>
      _collections.listPlaylists();

  @override
  Future<List<PlaylistEntry>> playlistEntries(int id) =>
      _collections.playlistEntries(id);

  @override
  Future<int> addToPlaylist(int id, List<String> paths) =>
      _collections.addToPlaylist(id, paths);

  @override
  Future<void> removePlaylistEntries(int id, List<int> entryIds) =>
      _collections.removePlaylistEntries(id, entryIds);

  @override
  Future<void> movePlaylistEntry(int id, int entryId, int newPosition) =>
      _collections.movePlaylistEntry(id, entryId, newPosition);

  @override
  Future<List<Track>> recentlyPlayedTracks({int limit = 200}) =>
      _history.recentlyPlayedTracks(limit: limit);

  @override
  Future<void> close() async {
    _db.close();
  }
}
