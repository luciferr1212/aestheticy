import 'dart:math';

import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';

/// Pure-Dart in-memory implementation of [LibraryRepository] for fast, deterministic unit testing.
class FakeLibraryRepository implements LibraryRepository {
  final List<LibraryFolder> _folders = [];
  final Map<String, Track> _tracks = {};
  final List<ArtistAlias> _aliases = [];
  final List<ArtistNoSplit> _noSplit = [];
  final List<PlayEvent> _playEvents = [];

  final Set<String> _favorites = {};
  final Map<String, int> _favTimestamps = {};
  final Map<String, int> _ratings = {};

  int _nextFolderId = 1;
  int _nextTrackId = 1;
  int _nextPlayEventId = 1;
  int _nextPlaylistId = 1;
  int _nextEntryId = 1;

  final Map<int, ({String name, int createdAt, int updatedAt})> _playlists = {};
  final List<({int id, int playlistId, int position, String path, int addedAt})>
      _playlistItems = [];

  @override
  Future<LibraryFolder> addFolder(String path) async {
    for (final f in _folders) {
      if (f.path == path) return f;
    }
    final folder = LibraryFolder(id: _nextFolderId++, path: path);
    _folders.add(folder);
    return folder;
  }

  @override
  Future<void> removeFolder(int folderId) async {
    _folders.removeWhere((f) => f.id == folderId);
    _tracks.removeWhere((k, v) => v.folderId == folderId);
  }

  @override
  Future<List<LibraryFolder>> listFolders() async => List.unmodifiable(_folders);

  @override
  Future<void> markFolderScanned(int folderId, DateTime timestamp) async {
    final idx = _folders.indexWhere((f) => f.id == folderId);
    if (idx != -1) {
      _folders[idx] = _folders[idx].copyWith(lastScanAt: timestamp);
    }
  }

  @override
  Future<void> upsertTracks(List<Track> tracks) async {
    for (final t in tracks) {
      final existing = _tracks[t.path];
      final trackToSave = t.copyWith(
        id: existing?.id ?? _nextTrackId++,
        addedAt: existing?.addedAt ?? t.addedAt,
      );
      _tracks[t.path] = trackToSave;
    }
  }

  @override
  Future<Map<String, ({int mtimeMs, int sizeBytes})>> existingFiles(int folderId) async {
    final result = <String, ({int mtimeMs, int sizeBytes})>{};
    for (final t in _tracks.values) {
      if (t.folderId == folderId) {
        result[t.path] = (mtimeMs: t.mtimeMs, sizeBytes: t.sizeBytes);
      }
    }
    return result;
  }

  @override
  Future<void> removeTracksByPath(List<String> paths) async {
    for (final p in paths) {
      _tracks.remove(p);
    }
  }

  @override
  Future<List<AlbumSummary>> listAlbums({int? limit, int? offset}) async => [];

  @override
  Future<List<ArtistSummary>> listArtists({int? limit, int? offset}) async => [];

  @override
  Future<int> albumCount() async => 0;

  @override
  Future<int> artistCount() async => 0;

  @override
  Future<List<Track>> tracksOfAlbum(String album, {String? albumArtist}) async {
    return _tracks.values.where((t) => t.album == album).toList();
  }

  @override
  Future<List<Track>> tracksOfArtist(String artist, {String? artistKey}) async {
    return _tracks.values.where((t) => t.artist == artist).toList();
  }

  @override
  Future<void> mergeArtists(String sourceKey, String targetKey, {String? targetName}) async {}

  @override
  Future<void> unmergeArtist(String aliasKey) async {}

  @override
  Future<List<ArtistAlias>> listAliases() async => List.unmodifiable(_aliases);

  @override
  Future<void> addNoSplit(String name) async {}

  @override
  Future<void> removeNoSplit(String key) async {}

  @override
  Future<List<ArtistNoSplit>> listNoSplit() async => List.unmodifiable(_noSplit);

  @override
  Future<void> rebuildArtistLinks() async {}

  @override
  Future<List<Track>> listTracks({TrackSort sort = TrackSort.titleAsc, int? limit, int? offset}) async {
    final list = _tracks.values.toList();
    list.sort((a, b) => (a.title ?? '').compareTo(b.title ?? ''));
    return list;
  }

  @override
  Future<List<Track>> search(String query) async {
    final q = query.toLowerCase();
    return _tracks.values.where((t) {
      return (t.title ?? '').toLowerCase().contains(q) ||
          (t.artist ?? '').toLowerCase().contains(q) ||
          (t.album ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Future<List<AlbumSummary>> searchAlbums(String query, {int? limit}) async => [];

  @override
  Future<List<ArtistSummary>> searchArtists(String query, {int? limit}) async => [];

  @override
  Future<int> trackCount() async => _tracks.length;

  @override
  Future<int> insertPlayEvent(PlayEvent e) async {
    final id = _nextPlayEventId++;
    _playEvents.add(e.copyWith(id: id));
    return id;
  }

  @override
  Future<void> updatePlayEvent(int id, {required int listenedMs, required bool counted, required bool completed}) async {
    final idx = _playEvents.indexWhere((e) => e.id == id);
    if (idx != -1) {
      _playEvents[idx] = _playEvents[idx].copyWith(
        listenedMs: listenedMs,
        counted: counted,
        completed: completed,
      );
    }
  }

  @override
  Future<List<PlayEvent>> recentPlayEvents({int limit = 50}) async {
    final sorted = List.of(_playEvents)
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sorted.take(limit).toList();
  }

  @override
  Future<int> playEventCount({bool countedOnly = false}) async {
    if (countedOnly) {
      return _playEvents.where((e) => e.counted).length;
    }
    return _playEvents.length;
  }

  @override
  Future<void> clearPlayEvents() async {
    _playEvents.clear();
  }

  // ── Favorites ────────────────────────────────────────────────────────

  @override
  Future<Set<String>> favoritePaths() async => Set.unmodifiable(_favorites);

  @override
  Future<void> setFavorite(String path, bool value) async {
    if (value) {
      _favorites.add(path);
      _favTimestamps[path] = DateTime.now().millisecondsSinceEpoch;
    } else {
      _favorites.remove(path);
      _favTimestamps.remove(path);
    }
  }

  @override
  Future<List<Track>> favoriteTracks() async {
    final list = <Track>[];
    final favList = _favorites.toList()
      ..sort((a, b) => (_favTimestamps[b] ?? 0).compareTo(_favTimestamps[a] ?? 0));
    for (final p in favList) {
      final t = _tracks[p];
      if (t != null) list.add(t);
    }
    return list;
  }

  // ── Ratings ──────────────────────────────────────────────────────────

  @override
  Future<Map<String, int>> allRatings() async => Map.unmodifiable(_ratings);

  @override
  Future<void> setRating(String path, int stars) async {
    if (stars < 0 || stars > 5) {
      throw ArgumentError.value(stars, 'stars', 'Rating stars must be between 0 and 5');
    }
    if (stars == 0) {
      _ratings.remove(path);
    } else {
      _ratings[path] = stars;
    }
  }

  // ── Playlists ────────────────────────────────────────────────────────

  static String _validatePlaylistName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const PlaylistNameException(PlaylistNameError.empty);
    }
    if (trimmed.length > 60) {
      throw PlaylistNameException(PlaylistNameError.tooLong, name: trimmed);
    }
    return trimmed;
  }

  @override
  Future<PlaylistSummary> createPlaylist(String name) async {
    final trimmed = _validatePlaylistName(name);
    if (_playlists.length >= 500) {
      throw const PlaylistLimitException('Maximum 500 playlists limit reached');
    }
    for (final p in _playlists.values) {
      if (p.name.toLowerCase() == trimmed.toLowerCase()) {
        throw PlaylistNameException(PlaylistNameError.duplicate, name: trimmed);
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _nextPlaylistId++;
    _playlists[id] = (name: trimmed, createdAt: now, updatedAt: now);
    final nowDt = DateTime.fromMillisecondsSinceEpoch(now, isUtc: true);
    return PlaylistSummary(
      id: id,
      name: trimmed,
      trackCount: 0,
      totalDurationMs: 0,
      createdAt: nowDt,
      updatedAt: nowDt,
      coverKey: null,
    );
  }

  @override
  Future<void> renamePlaylist(int id, String name) async {
    final trimmed = _validatePlaylistName(name);
    for (final entry in _playlists.entries) {
      if (entry.key != id && entry.value.name.toLowerCase() == trimmed.toLowerCase()) {
        throw PlaylistNameException(PlaylistNameError.duplicate, name: trimmed);
      }
    }
    final existing = _playlists[id];
    if (existing != null) {
      _playlists[id] = (
        name: trimmed,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  @override
  Future<void> deletePlaylist(int id) async {
    _playlists.remove(id);
    _playlistItems.removeWhere((item) => item.playlistId == id);
  }

  @override
  Future<List<PlaylistSummary>> listPlaylists() async {
    final list = <PlaylistSummary>[];
    final sortedKeys = _playlists.keys.toList()
      ..sort((a, b) => _playlists[a]!.name.toLowerCase().compareTo(_playlists[b]!.name.toLowerCase()));

    for (final id in sortedKeys) {
      final info = _playlists[id]!;
      final items = _playlistItems.where((i) => i.playlistId == id).toList()
        ..sort((a, b) => a.position.compareTo(b.position));

      var dur = 0;
      String? cover;
      for (final it in items) {
        final t = _tracks[it.path];
        if (t != null) {
          dur += t.durationMs;
          if (cover == null && t.coverKey != null && t.coverKey!.isNotEmpty) {
            cover = t.coverKey;
          }
        }
      }

      list.add(PlaylistSummary(
        id: id,
        name: info.name,
        trackCount: items.length,
        totalDurationMs: dur,
        createdAt: DateTime.fromMillisecondsSinceEpoch(info.createdAt, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(info.updatedAt, isUtc: true),
        coverKey: cover,
      ));
    }
    return list;
  }

  @override
  Future<List<PlaylistEntry>> playlistEntries(int id) async {
    final items = _playlistItems.where((i) => i.playlistId == id).toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    return items.map((it) {
      final t = _tracks[it.path];
      return PlaylistEntry(
        entryId: it.id,
        position: it.position,
        path: it.path,
        track: t,
      );
    }).toList();
  }

  @override
  Future<int> addToPlaylist(int id, List<String> paths) async {
    if (paths.isEmpty) return 0;
    final currentItems = _playlistItems.where((i) => i.playlistId == id).toList();
    if (currentItems.length + paths.length > 20000) {
      throw const PlaylistLimitException('Playlist entry limit of 20000 exceeded');
    }
    final maxPos = currentItems.isEmpty
        ? -1
        : currentItems.map((i) => i.position).reduce(max);
    var nextPos = maxPos + 1;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final p in paths) {
      _playlistItems.add((
        id: _nextEntryId++,
        playlistId: id,
        position: nextPos++,
        path: p,
        addedAt: now,
      ));
    }

    final pInfo = _playlists[id];
    if (pInfo != null) {
      _playlists[id] = (name: pInfo.name, createdAt: pInfo.createdAt, updatedAt: now);
    }
    return paths.length;
  }

  @override
  Future<void> removePlaylistEntries(int id, List<int> entryIds) async {
    if (entryIds.isEmpty) return;
    final idSet = entryIds.toSet();
    _playlistItems.removeWhere((i) => i.playlistId == id && idSet.contains(i.id));

    final remaining = _playlistItems.where((i) => i.playlistId == id).toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    for (var i = 0; i < remaining.length; i++) {
      final item = remaining[i];
      final idx = _playlistItems.indexOf(item);
      _playlistItems[idx] = (
        id: item.id,
        playlistId: item.playlistId,
        position: i,
        path: item.path,
        addedAt: item.addedAt,
      );
    }

    final pInfo = _playlists[id];
    if (pInfo != null) {
      _playlists[id] = (
        name: pInfo.name,
        createdAt: pInfo.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  @override
  Future<void> movePlaylistEntry(int id, int entryId, int newPosition) async {
    final items = _playlistItems.where((i) => i.playlistId == id).toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    final oldIndex = items.indexWhere((i) => i.id == entryId);
    if (oldIndex == -1) return;

    final targetIndex = newPosition.clamp(0, items.length - 1);
    if (oldIndex == targetIndex) return;

    final moving = items.removeAt(oldIndex);
    items.insert(targetIndex, moving);

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final idx = _playlistItems.indexOf(item);
      _playlistItems[idx] = (
        id: item.id,
        playlistId: item.playlistId,
        position: i,
        path: item.path,
        addedAt: item.addedAt,
      );
    }

    final pInfo = _playlists[id];
    if (pInfo != null) {
      _playlists[id] = (
        name: pInfo.name,
        createdAt: pInfo.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  // ── Recently Played ──────────────────────────────────────────────────

  @override
  Future<List<Track>> recentlyPlayedTracks({int limit = 200}) async {
    final countedEvents = _playEvents.where((e) => e.counted).toList();
    final latestPlayByCleanPath = <String, DateTime>{};

    for (final e in countedEvents) {
      final clean = e.uri.startsWith('file://') ? e.uri.substring(7) : e.uri;
      final existing = latestPlayByCleanPath[clean];
      if (existing == null || e.startedAt.isAfter(existing)) {
        latestPlayByCleanPath[clean] = e.startedAt;
      }
    }

    final sortedEntries = latestPlayByCleanPath.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final result = <Track>[];
    for (final entry in sortedEntries) {
      final t = _tracks[entry.key];
      if (t != null) {
        result.add(t);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  @override
  Future<void> close() async {}
}
