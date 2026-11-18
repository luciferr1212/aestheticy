import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/scan_service.dart';

/// In-memory cache holding the latest library read models (albums, artists,
/// tracks, recently played).
///
/// Implements stale-while-revalidate for library list pages so that navigating
/// between views paints immediately from memory on the first frame, without
/// flashing empty states or loading indicators.
class LibraryDataCache extends ChangeNotifier {
  /// The underlying library database repository.
  final LibraryRepository repository;

  /// Optional scan service coordinating folder scanning.
  final ScanService? scanService;

  List<AlbumSummary>? _albums;
  List<ArtistSummary>? _artists;
  List<Track>? _tracks;
  List<Track>? _recentTracks;
  Set<String>? _mergedCanonicalKeys;

  bool _isRefreshing = false;
  bool _disposed = false;
  bool _wasScanning = false;

  /// Creates a [LibraryDataCache].
  LibraryDataCache({
    required this.repository,
    this.scanService,
  }) {
    if (scanService != null) {
      _wasScanning = scanService!.isScanning;
      scanService!.addListener(_onScanChanged);
    }
  }

  /// Latest cached list of album summaries.
  List<AlbumSummary>? get albums => _albums;

  /// Latest cached list of artist summaries.
  List<ArtistSummary>? get artists => _artists;

  /// Latest cached list of all tracks.
  List<Track>? get tracks => _tracks;

  /// Latest cached list of recently played tracks.
  List<Track>? get recentTracks => _recentTracks;

  /// Latest set of canonical merged artist keys.
  Set<String>? get mergedCanonicalKeys => _mergedCanonicalKeys;

  /// Whether a background revalidation is in progress.
  bool get isRefreshing => _isRefreshing;

  /// Whether any data is present in the cache.
  bool get hasData =>
      _albums != null || _artists != null || _tracks != null;

  /// Whether the core library lists (albums, artists, tracks) have finished loading.
  bool get isLoaded =>
      _albums != null && _artists != null && _tracks != null;

  void _onScanChanged() {
    final scanning = scanService?.isScanning ?? false;
    if (_wasScanning && !scanning) {
      // Scan finished - invalidate and refresh lists
      refresh();
    }
    _wasScanning = scanning;
  }

  /// Seeds or updates the cache with explicit data (e.g. for testing).
  void seed({
    List<AlbumSummary>? albums,
    List<ArtistSummary>? artists,
    List<Track>? tracks,
    List<Track>? recentTracks,
    Set<String>? mergedCanonicalKeys,
  }) {
    if (albums != null) _albums = List.unmodifiable(albums);
    if (artists != null) _artists = List.unmodifiable(artists);
    if (tracks != null) _tracks = List.unmodifiable(tracks);
    if (recentTracks != null) _recentTracks = List.unmodifiable(recentTracks);
    if (mergedCanonicalKeys != null) {
      _mergedCanonicalKeys = Set.unmodifiable(mergedCanonicalKeys);
    }
    notifyListeners();
  }

  /// Refreshes all cached library lists in the background.
  ///
  /// Safe to call concurrently; only notifies listeners when data has changed
  /// or upon initial load.
  Future<void> refresh() async {
    if (_disposed) return;
    _isRefreshing = true;

    try {
      final albumsFuture = repository.listAlbums();
      final artistsFuture = repository.listArtists(limit: 5000);
      final tracksFuture = repository.listTracks();
      final aliasesFuture = repository.listAliases();
      final recentFuture = repository.recentlyPlayedTracks(limit: 200);

      final results = await Future.wait([
        albumsFuture,
        artistsFuture,
        tracksFuture,
        aliasesFuture,
        recentFuture,
      ]);

      if (_disposed) return;

      final newAlbums = results[0] as List<AlbumSummary>;
      final newArtists = results[1] as List<ArtistSummary>;
      final newTracks = results[2] as List<Track>;
      final aliases = results[3] as List<ArtistAlias>;
      final newRecent = results[4] as List<Track>;
      final newMergedKeys = aliases.map((a) => a.canonicalKey).toSet();

      final isFirst = _albums == null;
      final changed = isFirst ||
          !listEquals(_albums, newAlbums) ||
          !listEquals(_artists, newArtists) ||
          !listEquals(_tracks, newTracks) ||
          !listEquals(_recentTracks, newRecent) ||
          !setEquals(_mergedCanonicalKeys, newMergedKeys);

      _albums = newAlbums;
      _artists = newArtists;
      _tracks = newTracks;
      _recentTracks = newRecent;
      _mergedCanonicalKeys = newMergedKeys;

      if (changed) {
        notifyListeners();
      }
    } catch (_) {
      // Graceful error handling
    } finally {
      _isRefreshing = false;
    }
  }

  /// Invalidate cache and trigger background revalidation.
  void invalidate() {
    refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    scanService?.removeListener(_onScanChanged);
    super.dispose();
  }
}

/// Inherited widget exposing [LibraryDataCache] down the widget tree.
class LibraryDataCacheScope extends InheritedNotifier<LibraryDataCache> {
  /// Creates a [LibraryDataCacheScope].
  const LibraryDataCacheScope({
    super.key,
    required LibraryDataCache cache,
    required super.child,
  }) : super(notifier: cache);

  /// Accesses the nearest [LibraryDataCache] in the tree, or `null` if not found.
  static LibraryDataCache? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<LibraryDataCacheScope>()
        ?.notifier;
  }

  /// Accesses the nearest [LibraryDataCache] in the tree.
  static LibraryDataCache of(BuildContext context) {
    final cache = maybeOf(context);
    assert(cache != null, 'No LibraryDataCacheScope found in context');
    return cache!;
  }
}
