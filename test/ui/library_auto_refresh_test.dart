import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/library/album_identity.dart';
import 'package:aestheticy/library/library_scanner.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/library/album_detail_view.dart';
import 'package:aestheticy/ui/library/albums_view.dart';
import 'package:aestheticy/ui/library/artist_detail_view.dart';
import 'package:aestheticy/ui/library/artists_view.dart';
import 'package:aestheticy/ui/library/favorites_view.dart';
import 'package:aestheticy/ui/library/library_data_cache.dart';
import 'package:aestheticy/ui/library/library_placeholders.dart';
import 'package:aestheticy/ui/library/playlist_detail_view.dart';
import 'package:aestheticy/ui/library/playlists_view.dart';
import 'package:aestheticy/ui/library/recently_played_view.dart';
import 'package:aestheticy/ui/library/tracks_view.dart';
import 'package:aestheticy/ui/library/welcome_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

import '../library/fake_library_repository.dart';

class _AutoRefreshFakeRepository extends FakeLibraryRepository {
  final List<LibraryFolder> fakeFolders = [];
  List<AlbumSummary> fakeAlbums = [];
  List<ArtistSummary> fakeArtists = [];
  List<Track> fakeTracks = [];
  List<Track> fakeRecentTracks = [];
  List<Track> fakeFavorites = [];
  List<PlaylistSummary> fakePlaylists = [];
  final Map<int, List<PlaylistEntry>> fakePlaylistEntries = {};
  int _nextId = 1;

  Completer<void>? pendingGate;

  Future<void> _maybeDelay() async {
    final gate = pendingGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
  }

  @override
  Future<LibraryFolder> addFolder(String path) async {
    final existing = fakeFolders.where((f) => f.path == path).firstOrNull;
    if (existing != null) return existing;
    final folder = LibraryFolder(id: _nextId++, path: path);
    fakeFolders.add(folder);
    return folder;
  }

  @override
  Future<void> removeFolder(int folderId) async {
    fakeFolders.removeWhere((f) => f.id == folderId);
    fakeTracks = fakeTracks.where((t) => t.folderId != folderId).toList();
    fakeAlbums = [];
    fakeArtists = [];
    fakeRecentTracks = [];
    fakeFavorites = fakeFavorites.where((t) => t.folderId != folderId).toList();
  }

  @override
  Future<List<LibraryFolder>> listFolders() async => List.of(fakeFolders);

  @override
  Future<List<AlbumSummary>> listAlbums({int? limit, int? offset}) async {
    await _maybeDelay();
    return List.of(fakeAlbums);
  }

  @override
  Future<List<AlbumSummary>> searchAlbums(String query, {int? limit}) async {
    await _maybeDelay();
    final q = query.toLowerCase();
    return fakeAlbums
        .where((a) =>
            a.album.toLowerCase().contains(q) ||
            (a.displayArtist ?? a.albumArtist ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<ArtistSummary>> listArtists({int? limit, int? offset}) async {
    await _maybeDelay();
    return List.of(fakeArtists);
  }

  @override
  Future<List<Track>> listTracks({
    TrackSort sort = TrackSort.titleAsc,
    int? limit,
    int? offset,
  }) async {
    await _maybeDelay();
    return List.of(fakeTracks);
  }

  @override
  Future<List<Track>> recentlyPlayedTracks({int limit = 200}) async {
    await _maybeDelay();
    return List.of(fakeRecentTracks);
  }

  @override
  Future<List<Track>> tracksOfAlbum(
    String album, {
    String? albumArtist,
    String? albumKey,
  }) async {
    await _maybeDelay();
    final targetKey = (albumKey != null && albumKey.trim().isNotEmpty)
        ? albumKey
        : AlbumIdentity.key(
            album: album == AlbumIdentity.unknownAlbumTitle ? null : album,
            albumArtist: albumArtist,
          );
    return fakeTracks.where((t) => AlbumIdentity.forTrack(t) == targetKey).toList();
  }

  @override
  Future<List<Track>> tracksOfArtist(String artist, {String? artistKey}) async {
    await _maybeDelay();
    return fakeTracks.where((t) => t.artist == artist).toList();
  }

  @override
  Future<List<AlbumSummary>> listAlbumsByArtistKey(String artistKey) async {
    await _maybeDelay();
    return fakeAlbums
        .where((a) =>
            (a.albumArtist ?? a.displayArtist ?? '').toLowerCase() ==
            artistKey.toLowerCase())
        .toList();
  }

  @override
  Future<List<Track>> favoriteTracks() async {
    await _maybeDelay();
    return List.of(fakeFavorites);
  }

  @override
  Future<Set<String>> favoritePaths() async {
    return fakeFavorites.map((t) => t.path).toSet();
  }

  @override
  Future<List<PlaylistSummary>> listPlaylists() async {
    await _maybeDelay();
    return List.of(fakePlaylists);
  }

  @override
  Future<List<PlaylistEntry>> playlistEntries(int id) async {
    await _maybeDelay();
    return List.of(fakePlaylistEntries[id] ?? const []);
  }
}

class _FakeEventScanService extends ScanService {
  final StreamController<ScanProgress> _ctrl =
      StreamController<ScanProgress>.broadcast();
  bool _scanning = false;
  int _version = 0;
  ScanProgress _progress = const ScanProgress();

  _FakeEventScanService({required super.repository});

  @override
  bool get isScanning => _scanning;

  @override
  int get libraryVersion => _version;

  @override
  ScanProgress get currentProgress => _progress;

  @override
  Stream<ScanProgress> get progressStream => _ctrl.stream;

  void emitScanCompleted({int added = 1}) {
    _scanning = true;
    _progress = ScanProgress(found: added, processed: added, added: added);
    notifyListeners();

    _scanning = false;
    _version++;
    _progress = ScanProgress(
      found: added,
      processed: added,
      added: added,
      done: true,
    );
    _ctrl.add(_progress);
    notifyListeners();
  }

  void emitDoneProgressEventOnly({int added = 1}) {
    _progress = ScanProgress(
      found: added,
      processed: added,
      added: added,
      done: true,
    );
    _ctrl.add(_progress);
  }

  @override
  Future<LibraryFolder> addFolder(String path) async {
    final folder = await repository.addFolder(path);
    emitScanCompleted();
    return folder;
  }

  @override
  Future<void> removeFolder(int folderId) async {
    await repository.removeFolder(folderId);
    _version++;
    notifyListeners();
  }

  @override
  void dispose() {
    _ctrl.close();
    super.dispose();
  }
}

Track _track({
  required String path,
  required String title,
  String artist = 'Artist One',
  String? album = 'Album One',
  String? albumArtist,
  int folderId = 1,
}) {
  return Track(
    path: path,
    folderId: folderId,
    title: title,
    artist: artist,
    albumArtist: albumArtist ?? artist,
    album: album,
    durationMs: 180000,
    mtimeMs: 1000,
    sizeBytes: 2048,
    addedAt: DateTime.utc(2026, 3, 1),
  );
}

void main() {
  late _AutoRefreshFakeRepository repo;
  late _FakeEventScanService scanService;
  late LibraryDataCache cache;
  late UserCollections collections;
  late SettingsStore settingsStore;
  late ArtistNameStore artistNameStore;
  late AppNavigator navigator;
  late FakeAudioEngine engine;
  late PlaybackController controller;
  late GlassController glassController;

  setUp(() async {
    repo = _AutoRefreshFakeRepository();
    scanService = _FakeEventScanService(repository: repo);
    cache = LibraryDataCache(repository: repo, scanService: scanService);
    collections = UserCollections(repository: repo);
    settingsStore = SettingsStore(
      initialSettings: const AppSettings(
        language: 'en',
        reduceMotion: true,
        libraryViewMode: 'list',
        albumSort: 'title',
        albumsSortReversed: false,
      ),
    );
    artistNameStore = ArtistNameStore();
    navigator = AppNavigator();
    engine = FakeAudioEngine();
    await engine.init();
    controller = PlaybackController(engine: engine, queue: PlaybackQueue());
    await controller.init();
    glassController = GlassController();
    settingsStore.bindGlassController(glassController);
  });

  tearDown(() async {
    cache.dispose();
    scanService.dispose();
    collections.dispose();
    settingsStore.dispose();
    artistNameStore.dispose();
    navigator.dispose();
    glassController.dispose();
    await controller.dispose();
    await engine.dispose();
  });

  Widget wrapHost(Widget child) {
    return GlassScope(
      controller: glassController,
      child: LibraryDataCacheScope(
        cache: cache,
        child: SettingsScope(
          store: settingsStore,
          child: ArtistNameScope(
            store: artistNameStore,
            child: UserCollectionsScope(
              collections: collections,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildAppTheme(),
                home: Scaffold(body: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('Library auto-refresh on scan & folder change without flicker (S3)', () {
    test(
      'LibraryDataCache refreshes on progressStream done event and scanService.removeFolder',
      () async {
        final t1 = _track(
          path: 'C:\\Music\\unit1.mp3',
          title: 'Unit Song 1',
          artist: 'Unit Artist',
          album: 'Unit Album',
        );
        repo.fakeTracks = [t1];
        repo.fakeAlbums = [
          AlbumSummary(
            album: 'Unit Album',
            albumArtist: 'Unit Artist',
            trackCount: 1,
            identityKey: AlbumIdentity.forTrack(t1),
          ),
        ];
        await repo.addFolder('C:\\Music');
        await cache.refresh();
        expect(cache.albums?.length, equals(1));

        // 1. progressStream done event triggers refresh
        final t2 = _track(
          path: 'C:\\Music\\unit2.mp3',
          title: 'Unit Song 2',
          artist: 'Unit Artist 2',
          album: 'Unit Album 2',
        );
        repo.fakeTracks = [t1, t2];
        repo.fakeAlbums = [
          ...repo.fakeAlbums,
          AlbumSummary(
            album: 'Unit Album 2',
            albumArtist: 'Unit Artist 2',
            trackCount: 1,
            identityKey: AlbumIdentity.forTrack(t2),
          ),
        ];
        scanService.emitDoneProgressEventOnly();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(cache.albums?.length, equals(2));

        // 2. removeFolder triggers refresh and clears removed folder data
        await scanService.removeFolder(repo.fakeFolders.first.id!);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(cache.albums, isEmpty);
      },
    );

    testWidgets(
      'AlbumsView, ArtistsView, TracksView, and RecentlyPlayedView refresh on scan-complete event without flashing placeholders',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final localScanService = _FakeEventScanService(repository: repo);
        final localCache =
            LibraryDataCache(repository: repo, scanService: localScanService);
        addTearDown(() {
          localCache.dispose();
          localScanService.dispose();
        });

        final t1 = _track(
          path: 'C:\\Music\\one.mp3',
          title: 'Initial Track',
          artist: 'Initial Artist',
          album: 'Initial Album',
        );
        repo.fakeTracks = [t1];
        repo.fakeAlbums = [
          AlbumSummary(
            album: 'Initial Album',
            albumArtist: 'Initial Artist',
            trackCount: 1,
            identityKey: AlbumIdentity.forTrack(t1),
          ),
        ];
        repo.fakeArtists = [
          const ArtistSummary(
            key: 'initial artist',
            name: 'Initial Artist',
            albumCount: 1,
            trackCount: 1,
          ),
        ];
        repo.fakeRecentTracks = [t1];
        await localCache.refresh();

        // 1. AlbumsView
        await tester.pumpWidget(
          GlassScope(
            controller: glassController,
            child: LibraryDataCacheScope(
              cache: localCache,
              child: SettingsScope(
                store: settingsStore,
                child: ArtistNameScope(
                  store: artistNameStore,
                  child: UserCollectionsScope(
                    collections: collections,
                    child: MaterialApp(
                      debugShowCheckedModeBanner: false,
                      theme: buildAppTheme(),
                      home: Scaffold(
                        body: AlbumsView(
                          repository: repo,
                          settingsStore: settingsStore,
                          navigator: navigator,
                          dataCache: localCache,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Initial Album'), findsOneWidget);

        final albumGate = Completer<void>();
        repo.pendingGate = albumGate;
        final t2 = _track(
          path: 'C:\\Music\\two.mp3',
          title: 'Scanned Track',
          artist: 'Scanned Artist',
          album: 'Scanned Album',
        );
        repo.fakeTracks = [t1, t2];
        repo.fakeAlbums = [
          ...repo.fakeAlbums,
          AlbumSummary(
            album: 'Scanned Album',
            albumArtist: 'Scanned Artist',
            trackCount: 1,
            identityKey: AlbumIdentity.forTrack(t2),
          ),
        ];
        repo.fakeArtists = [
          ...repo.fakeArtists,
          const ArtistSummary(
            key: 'scanned artist',
            name: 'Scanned Artist',
            albumCount: 1,
            trackCount: 1,
          ),
        ];
        repo.fakeRecentTracks = [t2, t1];

        localScanService.emitDoneProgressEventOnly();
        await tester.pump();
        // Mid-refresh: old item stays visible, zero placeholder flicker!
        expect(find.text('Initial Album'), findsOneWidget);
        expect(find.byType(AlbumsViewPlaceholder), findsNothing);
        repo.pendingGate = null;
        albumGate.complete();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Scanned Album'), findsOneWidget);

        // 2. ArtistsView
        await tester.pumpWidget(
          GlassScope(
            controller: glassController,
            child: LibraryDataCacheScope(
              cache: localCache,
              child: SettingsScope(
                store: settingsStore,
                child: ArtistNameScope(
                  store: artistNameStore,
                  child: UserCollectionsScope(
                    collections: collections,
                    child: MaterialApp(
                      debugShowCheckedModeBanner: false,
                      theme: buildAppTheme(),
                      home: Scaffold(
                        body: ArtistsView(
                          repository: repo,
                          settingsStore: settingsStore,
                          navigator: navigator,
                          dataCache: localCache,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Scanned Artist'), findsOneWidget);

        final artistsGate = Completer<void>();
        repo.pendingGate = artistsGate;
        repo.fakeArtists = [
          ...repo.fakeArtists,
          const ArtistSummary(
            key: 'third artist',
            name: 'Third Artist',
            albumCount: 1,
            trackCount: 1,
          ),
        ];
        localScanService.emitScanCompleted();
        await tester.pump();
        expect(find.text('Initial Artist'), findsOneWidget);
        expect(find.byType(ArtistsViewPlaceholder), findsNothing);
        repo.pendingGate = null;
        artistsGate.complete();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Third Artist'), findsOneWidget);

        // 3. TracksView
        await tester.pumpWidget(
          GlassScope(
            controller: glassController,
            child: LibraryDataCacheScope(
              cache: localCache,
              child: SettingsScope(
                store: settingsStore,
                child: ArtistNameScope(
                  store: artistNameStore,
                  child: UserCollectionsScope(
                    collections: collections,
                    child: MaterialApp(
                      debugShowCheckedModeBanner: false,
                      theme: buildAppTheme(),
                      home: Scaffold(
                        body: TracksView(
                          repository: repo,
                          controller: controller,
                          settingsStore: settingsStore,
                          dataCache: localCache,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Scanned Track'), findsOneWidget);

        final tracksGate = Completer<void>();
        repo.pendingGate = tracksGate;
        final t3 = _track(
          path: 'C:\\Music\\three.mp3',
          title: 'Newest Scanned Track',
          artist: 'Third Artist',
          album: 'Third Album',
        );
        repo.fakeTracks = [t1, t2, t3];
        repo.fakeRecentTracks = [t3, t2, t1];
        localScanService.emitScanCompleted();
        await tester.pump();
        expect(find.text('Initial Track'), findsOneWidget);
        expect(find.byType(TracksViewPlaceholder), findsNothing);
        repo.pendingGate = null;
        tracksGate.complete();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Newest Scanned Track'), findsOneWidget);

        // 4. RecentlyPlayedView
        await tester.pumpWidget(
          GlassScope(
            controller: glassController,
            child: LibraryDataCacheScope(
              cache: localCache,
              child: SettingsScope(
                store: settingsStore,
                child: ArtistNameScope(
                  store: artistNameStore,
                  child: UserCollectionsScope(
                    collections: collections,
                    child: MaterialApp(
                      debugShowCheckedModeBanner: false,
                      theme: buildAppTheme(),
                      home: Scaffold(
                        body: RecentlyPlayedView(
                          repository: repo,
                          controller: controller,
                          settingsStore: settingsStore,
                          collections: collections,
                          dataCache: localCache,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Newest Scanned Track'), findsOneWidget);

        final recentGate = Completer<void>();
        repo.pendingGate = recentGate;
        final t4 = _track(
          path: 'C:\\Music\\four.mp3',
          title: 'Fourth Recent Track',
          artist: 'Fourth Artist',
          album: 'Fourth Album',
        );
        repo.fakeRecentTracks = [t4, t3];
        localScanService.emitScanCompleted();
        await tester.pump();
        expect(find.text('Newest Scanned Track'), findsOneWidget);
        expect(find.byType(RecentlyPlayedViewPlaceholder), findsNothing);
        repo.pendingGate = null;
        recentGate.complete();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Fourth Recent Track'), findsOneWidget);
      },
    );

    testWidgets(
      'AlbumDetailView, ArtistDetailView, PlaylistDetailView, PlaylistsView, and FavoritesView refresh after scan complete without flicker',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final t1 = _track(
          path: 'C:\\Music\\alb1.mp3',
          title: 'Album Song One',
          artist: 'Detail Artist',
          album: 'Detail Album',
        );
        final summary1 = AlbumSummary(
          album: 'Detail Album',
          albumArtist: 'Detail Artist',
          trackCount: 1,
          identityKey: AlbumIdentity.forTrack(t1),
        );
        repo.fakeTracks = [t1];
        repo.fakeAlbums = [summary1];
        repo.fakeArtists = [
          const ArtistSummary(
            key: 'detail artist',
            name: 'Detail Artist',
            albumCount: 1,
            trackCount: 1,
          ),
        ];
        repo.fakeFavorites = [t1];
        repo.fakePlaylists = [
          PlaylistSummary(
            id: 1,
            name: 'Roadtrip',
            trackCount: 1,
            totalDurationMs: 180000,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ];
        repo.fakePlaylistEntries[1] = [
          PlaylistEntry(entryId: 1, position: 0, path: t1.path, track: t1),
          const PlaylistEntry(
            entryId: 2,
            position: 1,
            path: 'C:\\Music\\alb2.mp3',
            track: null,
          ),
        ];

        await cache.refresh();
        await collections.init();

        // 1. AlbumDetailView
        await tester.pumpWidget(
          wrapHost(
            AlbumDetailView(
              album: summary1,
              repository: repo,
              controller: controller,
              settingsStore: settingsStore,
              navigator: navigator,
              dataCache: cache,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Album Song One'), findsOneWidget);
        expect(find.text('Album Song Two'), findsNothing);

        final albDetailGate = Completer<void>();
        repo.pendingGate = albDetailGate;
        final t2 = _track(
          path: 'C:\\Music\\alb2.mp3',
          title: 'Album Song Two',
          artist: 'Detail Artist',
          album: 'Detail Album',
        );
        repo.fakeTracks = [t1, t2];
        repo.fakeAlbums = [
          AlbumSummary(
            album: 'Detail Album',
            albumArtist: 'Detail Artist',
            trackCount: 2,
            identityKey: AlbumIdentity.forTrack(t1),
          ),
        ];
        scanService.emitScanCompleted();
        await tester.pump();
        // Stale-while-revalidate: old track visible, no loading spinner
        expect(find.text('Album Song One'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        repo.pendingGate = null;
        albDetailGate.complete();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Album Song Two'), findsOneWidget);

        // 2. ArtistDetailView
        await tester.pumpWidget(
          wrapHost(
            ArtistDetailView(
              artist: const ArtistSummary(
                key: 'detail artist',
                name: 'Detail Artist',
                albumCount: 1,
                trackCount: 2,
              ),
              repository: repo,
              controller: controller,
              settingsStore: settingsStore,
              navigator: navigator,
              dataCache: cache,
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Album Song Two'), findsOneWidget);

        final artistDetailGate = Completer<void>();
        repo.pendingGate = artistDetailGate;
        final t3 = _track(
          path: 'C:\\Music\\single_new.mp3',
          title: 'Brand New Artist Track',
          artist: 'Detail Artist',
          album: 'Brand New Release',
        );
        repo.fakeTracks = [t1, t2, t3];
        repo.fakeAlbums = [
          ...repo.fakeAlbums,
          AlbumSummary(
            album: 'Brand New Release',
            albumArtist: 'Detail Artist',
            trackCount: 1,
            identityKey: AlbumIdentity.forTrack(t3),
          ),
        ];
        scanService.emitScanCompleted();
        await tester.pump();
        expect(find.text('Album Song Two'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        repo.pendingGate = null;
        artistDetailGate.complete();
        await tester.pump();
        await tester.pumpAndSettle();
        // Appears both in Singles & EPs card section and Track table album column
        expect(find.text('Brand New Release'), findsNWidgets(2));
        expect(find.text('Brand New Artist Track'), findsOneWidget);

        // 3. PlaylistDetailView: previously missing entry becomes resolved on scan complete
        await tester.pumpWidget(
          wrapHost(
            PlaylistDetailView(
              playlistId: 1,
              repository: repo,
              collections: collections,
              controller: controller,
              settingsStore: settingsStore,
              navigator: navigator,
              dataCache: cache,
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Album Song Two'), findsNothing);

        final plDetailGate = Completer<void>();
        repo.pendingGate = plDetailGate;
        repo.fakePlaylistEntries[1] = [
          PlaylistEntry(entryId: 1, position: 0, path: t1.path, track: t1),
          PlaylistEntry(entryId: 2, position: 1, path: t2.path, track: t2),
        ];
        scanService.emitScanCompleted();
        await tester.pump();
        expect(find.text('Album Song One'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        repo.pendingGate = null;
        plDetailGate.complete();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Album Song Two'), findsOneWidget);

        // 4. PlaylistsView
        await tester.pumpWidget(
          wrapHost(
            PlaylistsView(
              collections: collections,
              repository: repo,
              controller: controller,
              settingsStore: settingsStore,
              navigator: navigator,
              dataCache: cache,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Roadtrip'), findsOneWidget);

        repo.fakePlaylists = [
          ...repo.fakePlaylists,
          PlaylistSummary(
            id: 2,
            name: 'Post Scan Playlist',
            trackCount: 3,
            totalDurationMs: 540000,
            createdAt: DateTime.utc(2026, 2, 1),
            updatedAt: DateTime.utc(2026, 2, 1),
          ),
        ];
        scanService.emitScanCompleted();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Post Scan Playlist'), findsOneWidget);

        // 5. FavoritesView
        await tester.pumpWidget(
          wrapHost(
            FavoritesView(
              repository: repo,
              collections: collections,
              controller: controller,
              settingsStore: settingsStore,
              dataCache: cache,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Album Song One'), findsOneWidget);
        expect(find.text('Album Song Two'), findsNothing);

        repo.fakeFavorites = [t1, t2];
        scanService.emitScanCompleted();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Album Song Two'), findsOneWidget);
      },
    );

    testWidgets(
      'AppShell switches from WelcomeView when folder added and refreshes Favorites/Albums/Welcome when last folder is removed',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          GlassScope(
            controller: glassController,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              home: AppShell(
                engine: engine,
                controller: controller,
                repository: repo,
                scanService: scanService,
                settingsStore: settingsStore,
                navigator: navigator,
                userCollections: collections,
                dataCache: cache,
                artistNameStore: artistNameStore,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially no folders -> WelcomeView
        expect(find.byType(WelcomeView), findsOneWidget);

        // Add folder + scan completes -> transitions to AlbumsView with scanned album
        final t1 = _track(
          path: 'C:\\Music\\added.mp3',
          title: 'Added Song',
          artist: 'Added Artist',
          album: 'Added Album',
          folderId: 1,
        );
        repo.fakeTracks = [t1];
        repo.fakeAlbums = [
          AlbumSummary(
            album: 'Added Album',
            albumArtist: 'Added Artist',
            trackCount: 1,
            identityKey: AlbumIdentity.forTrack(t1),
          ),
        ];
        repo.fakeArtists = [
          const ArtistSummary(
            key: 'added artist',
            name: 'Added Artist',
            albumCount: 1,
            trackCount: 1,
          ),
        ];
        repo.fakeFavorites = [t1];

        await scanService.addFolder('C:\\Music');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(find.byType(WelcomeView), findsNothing);
        expect(find.text('Added Album'), findsOneWidget);
        expect(collections.favoriteTracks.length, equals(1));

        // Remove folder via ScanService -> clears tracks, updates cache + collections, returns to WelcomeView
        await scanService.removeFolder(repo.fakeFolders.first.id!);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(find.byType(WelcomeView), findsOneWidget);
        expect(collections.favoriteTracks, isEmpty);
      },
    );
  });
}
