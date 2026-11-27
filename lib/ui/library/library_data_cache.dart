import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../diagnostics/app_logger.dart';
import '../../library/library_repository.dart';
import '../../library/library_scanner.dart';
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
  bool _pendingRefresh = false;
  bool _pendingForceNotify = false;
  bool _disposed = false;
  bool _wasScanning = false;
  int _lastLibraryVersion = 0;
  int _revision = 0;
  StreamSubscription<ScanProgress>? _progressSubscription;

  /// Creates a [LibraryDataCache].
  LibraryDataCache({
    required this.repository,
    this.scanService,
  }) {
    if (scanService != null) {
      _wasScanning = scanService!.isScanning;
      _lastLibraryVersion = scanService!.libraryVersion;
      scanService!.addListener(_onScanChanged);
      _progressSubscription = scanService!.progressStream.listen((progress) {
        if (progress.done && !_disposed) {
          refresh(forceNotify: true);
        }
      });
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

  /// Monotonically incremented revision counter for cache invalidation and
  /// detail-view revalidation.
  int get revision => _revision;

  /// Whether a background revalidation is in progress.
  bool get isRefreshing => _isRefreshing;

  /// Whether any data is present in the cache.
  bool get hasData =>
      _albums != null || _artists != null || _tracks != null;

  /// Whether the core library lists (albums, artists, tracks) have finished loading.
  bool get isLoaded =>
      _albums != null && _artists != null && _tracks != null;

  void _onScanChanged() {
    final service = scanService;
    if (service == null) return;
    final scanning = service.isScanning;
    final version = service.libraryVersion;
    final scanFinished = _wasScanning && !scanning;
    final versionChanged = version != _lastLibraryVersion;
    _wasScanning = scanning;
    _lastLibraryVersion = version;
    if (scanFinished || versionChanged) {
      // Scan finished or folder added/removed - revalidate lists stale-while-revalidate.
      refresh(forceNotify: true);
    }
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
    _revision++;
    notifyListeners();
  }

  /// Refreshes all cached library lists in the background without clearing
  /// existing data (stale-while-revalidate).
  ///
  /// Concurrent calls are coalesced so a scan completion during an in-flight
  /// refresh still triggers one trailing revalidation.
  Future<void> refresh({bool forceNotify = false}) async {
    if (_disposed) return;
    if (_isRefreshing) {
      _pendingRefresh = true;
      if (forceNotify) {
        _pendingForceNotify = true;
      }
      return;
    }
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

      if (changed || forceNotify) {
        _revision++;
        notifyListeners();
      }
    } catch (e, st) {
      AppLogger.instance.warn(
        'LibraryDataCache',
        'Background library cache refresh failed',
        e,
        st,
      );
    } finally {
      _isRefreshing = false;
      if (_pendingRefresh && !_disposed) {
        final followUpForce = _pendingForceNotify;
        _pendingRefresh = false;
        _pendingForceNotify = false;
        await refresh(forceNotify: followUpForce);
      } else {
        _pendingRefresh = false;
        _pendingForceNotify = false;
      }
    }
  }

  /// Invalidate cache and trigger background revalidation.
  void invalidate() {
    refresh(forceNotify: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _progressSubscription?.cancel();
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
