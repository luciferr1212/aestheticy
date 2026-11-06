import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../diagnostics/app_logger.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';

/// State coordinator for user favorites, ratings, and playlists.
///
/// Features optimistic in-memory updates with rollback on persistence failure.
class UserCollections extends ChangeNotifier {
  /// The underlying library database repository.
  final LibraryRepository repository;

  final Set<String> _favorites = {};
  final Map<String, int> _ratings = {};
  List<PlaylistSummary> _playlists = [];
  bool _loaded = false;

  /// Creates a [UserCollections] instance wired to [repository].
  UserCollections({required this.repository});

  /// Whether collections data has finished loading from [repository].
  bool get isLoaded => _loaded;

  /// Synchronously returns whether track at [path] is a favorite.
  bool isFavorite(String path) => _favorites.contains(path);

  /// Synchronously returns star rating (1..5) for track at [path], or 0 if unrated.
  int ratingOf(String path) => _ratings[path] ?? 0;

  /// Synchronously returns all playlist summaries.
  List<PlaylistSummary> get playlists => List.unmodifiable(_playlists);

  /// Loads initial collections data from the repository.
  Future<void> init() async {
    try {
      final favs = await repository.favoritePaths();
      final rates = await repository.allRatings();
      final pls = await repository.listPlaylists();

      _favorites.clear();
      _favorites.addAll(favs);

      _ratings.clear();
      _ratings.addAll(rates);

      _playlists = pls;
      _loaded = true;
      notifyListeners();
    } catch (e, st) {
      AppLogger.instance.error(
        'Collections',
        'Failed to load user collections: $e',
        e,
        st,
      );
      rethrow;
    }
  }

  /// Optimistically toggles favorite status for [path]. Reverts on repository failure.
  Future<void> toggleFavorite(String path) async {
    final wasFavorite = _favorites.contains(path);
    final targetState = !wasFavorite;

    // Optimistic update
    if (targetState) {
      _favorites.add(path);
    } else {
      _favorites.remove(path);
    }
    notifyListeners();

    try {
      await repository.setFavorite(path, targetState);
    } catch (e, st) {
      // Revert optimistic update
      if (wasFavorite) {
        _favorites.add(path);
      } else {
        _favorites.remove(path);
      }
      notifyListeners();

      final fileName = p.basename(path);
      AppLogger.instance.warning(
        'Collections',
        'Failed to toggle favorite for $fileName: $e',
        e,
        st,
      );
      rethrow;
    }
  }

  /// Optimistically sets star rating for [path]. Reverts on repository failure.
  Future<void> setRating(String path, int stars) async {
    final oldStars = _ratings[path] ?? 0;

    // Optimistic update
    if (stars == 0) {
      _ratings.remove(path);
    } else {
      _ratings[path] = stars;
    }
    notifyListeners();

    try {
      await repository.setRating(path, stars);
    } catch (e, st) {
      // Revert optimistic update
      if (oldStars == 0) {
        _ratings.remove(path);
      } else {
        _ratings[path] = oldStars;
      }
      notifyListeners();

      final fileName = p.basename(path);
      AppLogger.instance.warning(
        'Collections',
        'Failed to set rating for $fileName: $e',
        e,
        st,
      );
      rethrow;
    }
  }

  /// Creates a new playlist with [name].
  Future<PlaylistSummary> createPlaylist(String name) async {
    try {
      final created = await repository.createPlaylist(name);
      _playlists = await repository.listPlaylists();
      notifyListeners();
      return created;
    } catch (e, st) {
      AppLogger.instance.warning(
        'Collections',
        'Failed to create playlist "$name": $e',
        e,
        st,
      );
      rethrow;
    }
  }

  /// Renames playlist [id] to [name]. Optimistically updates list and reloads.
  Future<void> renamePlaylist(int id, String name) async {
    final oldList = List<PlaylistSummary>.from(_playlists);
    final idx = _playlists.indexWhere((p) => p.id == id);
    if (idx != -1) {
      _playlists[idx] = _playlists[idx].copyWith(name: name.trim());
      notifyListeners();
    }

    try {
      await repository.renamePlaylist(id, name);
      _playlists = await repository.listPlaylists();
      notifyListeners();
    } catch (e, st) {
      _playlists = oldList;
      notifyListeners();
      AppLogger.instance.warning(
        'Collections',
        'Failed to rename playlist $id: $e',
        e,
        st,
      );
      rethrow;
    }
  }

  /// Deletes playlist [id]. Optimistically removes from list and reloads.
  Future<void> deletePlaylist(int id) async {
    final oldList = List<PlaylistSummary>.from(_playlists);
    _playlists.removeWhere((p) => p.id == id);
    notifyListeners();

    try {
      await repository.deletePlaylist(id);
      _playlists = await repository.listPlaylists();
      notifyListeners();
    } catch (e, st) {
      _playlists = oldList;
      notifyListeners();
      AppLogger.instance.warning(
        'Collections',
        'Failed to delete playlist $id: $e',
        e,
        st,
      );
      rethrow;
    }
  }

  /// Adds [paths] to playlist [id] and updates summary statistics.
  Future<int> addToPlaylist(int id, List<String> paths) async {
    try {
      final added = await repository.addToPlaylist(id, paths);
      _playlists = await repository.listPlaylists();
      notifyListeners();
      return added;
    } catch (e, st) {
      AppLogger.instance.warning(
        'Collections',
        'Failed to add ${paths.length} tracks to playlist $id: $e',
        e,
        st,
      );
      rethrow;
    }
  }

  /// Removes entries from playlist [id] and updates summary statistics.
  Future<void> removeFromPlaylist(int id, List<int> entryIds) async {
    try {
      await repository.removePlaylistEntries(id, entryIds);
      _playlists = await repository.listPlaylists();
      notifyListeners();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Collections',
        'Failed to remove entries from playlist $id: $e',
        e,
        st,
      );
      rethrow;
    }
  }

  /// Moves entry [entryId] in playlist [id] to [newPosition].
  Future<void> moveEntry(int id, int entryId, int newPosition) async {
    try {
      await repository.movePlaylistEntry(id, entryId, newPosition);
      _playlists = await repository.listPlaylists();
      notifyListeners();
    } catch (e, st) {
      AppLogger.instance.warning(
        'Collections',
        'Failed to move entry in playlist $id: $e',
        e,
        st,
      );
      rethrow;
    }
  }

  /// Refreshes playlist summaries from repository.
  Future<void> refreshPlaylists() async {
    _playlists = await repository.listPlaylists();
    notifyListeners();
  }
}

/// An inherited notifier exposing [UserCollections] to the widget tree.
class UserCollectionsScope extends InheritedNotifier<UserCollections> {
  /// Creates a [UserCollectionsScope].
  const UserCollectionsScope({
    super.key,
    required UserCollections collections,
    required super.child,
  }) : super(notifier: collections);

  /// Obtains the ambient [UserCollections] if present.
  static UserCollections? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<UserCollectionsScope>()
        ?.notifier;
  }

  /// Obtains the ambient [UserCollections] or throws.
  static UserCollections of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No UserCollectionsScope found in context');
    return scope!;
  }
}

/// Extension providing convenient access to [UserCollections] on [BuildContext].
extension UserCollectionsContext on BuildContext {
  /// Resolves the ambient [UserCollections] controller, if present.
  UserCollections? get userCollections => UserCollectionsScope.maybeOf(this);
}
