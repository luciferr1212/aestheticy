import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/library/albums_view.dart';
import 'package:aestheticy/ui/library/artists_view.dart';
import 'package:aestheticy/ui/library/library_data_cache.dart';
import 'package:aestheticy/ui/library/library_placeholders.dart';
import 'package:aestheticy/ui/library/tracks_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

import '../../library/fake_library_repository.dart';

class _TestLibraryRepository extends FakeLibraryRepository {
  List<AlbumSummary> albumsData = [];
  List<ArtistSummary> artistsData = [];
  List<Track> tracksData = [];

  @override
  Future<List<AlbumSummary>> listAlbums({int? limit, int? offset}) async =>
      albumsData;

  @override
  Future<List<ArtistSummary>> listArtists({int? limit, int? offset}) async =>
      artistsData;

  @override
  Future<List<Track>> listTracks({
    TrackSort sort = TrackSort.titleAsc,
    int? limit,
    int? offset,
  }) async =>
      tracksData;
}

class _FakeScanService extends ScanService {
  bool _scanning = false;

  _FakeScanService({required super.repository});

  @override
  bool get isScanning => _scanning;

  void setScanning(bool value) {
    _scanning = value;
    notifyListeners();
  }
}

void main() {
  late _TestLibraryRepository repository;
  late SettingsStore settingsStore;
  late AppNavigator navigator;
  late FakeAudioEngine engine;
  late PlaybackQueue queue;
  late PlaybackController playbackController;

  setUp(() async {
    repository = _TestLibraryRepository();
    settingsStore = SettingsStore(initialSettings: const AppSettings());
    navigator = AppNavigator();
    engine = FakeAudioEngine();
    await engine.init();
    queue = PlaybackQueue();
    playbackController = PlaybackController(engine: engine, queue: queue);
    await playbackController.init();
  });

  tearDown(() async {
    await playbackController.dispose();
    await engine.dispose();
  });

  Widget buildTestHost({
    required Widget child,
    LibraryDataCache? cache,
  }) {
    final inner = SettingsScope(
      store: settingsStore,
      child: ArtistNameScope(
        store: ArtistNameStore(),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: child),
        ),
      ),
    );

    if (cache != null) {
      return LibraryDataCacheScope(
        cache: cache,
        child: inner,
      );
    }
    return inner;
  }

  group('LibraryDataCache', () {
    test('initializes and loads lists from repository',
        timeout: const Timeout(Duration(seconds: 30)), () async {
      final now = DateTime.now();
      repository.albumsData = const [
        AlbumSummary(
          album: 'Album Alpha',
          albumArtist: 'Artist Alpha',
          trackCount: 1,
        ),
      ];
      repository.artistsData = const [
        ArtistSummary(
          name: 'Artist Alpha',
          albumCount: 1,
          trackCount: 1,
        ),
      ];
      repository.tracksData = [
        Track(
          path: '/music/track1.mp3',
          folderId: 1,
          title: 'Track One',
          artist: 'Artist Alpha',
          album: 'Album Alpha',
          durationMs: 180000,
          mtimeMs: 1000,
          sizeBytes: 2000,
          addedAt: now,
        ),
      ];

      final cache = LibraryDataCache(repository: repository);
      expect(cache.hasData, isFalse);

      await cache.refresh();

      expect(cache.hasData, isTrue);
      expect(cache.albums?.length, equals(1));
      expect(cache.albums?.first.album, equals('Album Alpha'));
      expect(cache.artists?.length, equals(1));
      expect(cache.artists?.first.name, equals('Artist Alpha'));
      expect(cache.tracks?.length, equals(1));
      expect(cache.tracks?.first.title, equals('Track One'));

      cache.dispose();
    });

    test('finished scan triggers refresh automatically',
        timeout: const Timeout(Duration(seconds: 30)), () async {
      final scanService = _FakeScanService(repository: repository);
      final cache = LibraryDataCache(
        repository: repository,
        scanService: scanService,
      );

      await cache.refresh();
      expect(cache.albums, isEmpty);

      // Add a track/album to repository behind the scenes
      repository.albumsData = const [
        AlbumSummary(
          album: 'Scanned Album',
          albumArtist: 'Scanned Artist',
          trackCount: 1,
        ),
      ];

      int notifyCount = 0;
      cache.addListener(() {
        notifyCount++;
      });

      // Scan starts
      scanService.setScanning(true);
      expect(notifyCount, equals(0));

      // Scan finishes -> cache should refresh
      scanService.setScanning(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifyCount, greaterThan(0));
      expect(cache.albums?.length, equals(1));
      expect(cache.albums?.first.album, equals('Scanned Album'));

      cache.dispose();
      scanService.dispose();
    });

    testWidgets('re-entering a page paints cached data on the first frame',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cache = LibraryDataCache(repository: repository);
      cache.seed(
        albums: const [
          AlbumSummary(
            album: 'Cached Album',
            albumArtist: 'Cached Artist',
            trackCount: 5,
          ),
        ],
        artists: const [
          ArtistSummary(
            name: 'Cached Artist',
            albumCount: 1,
            trackCount: 5,
          ),
        ],
        tracks: [
          Track(
            path: '/music/cached.mp3',
            folderId: 1,
            title: 'Cached Track',
            artist: 'Cached Artist',
            album: 'Cached Album',
            durationMs: 120000,
            mtimeMs: 1000,
            sizeBytes: 2000,
            addedAt: DateTime.now(),
          ),
        ],
      );

      // Build AlbumsView with cache provided
      await tester.pumpWidget(
        buildTestHost(
          cache: cache,
          child: AlbumsView(
            repository: repository,
            settingsStore: settingsStore,
            navigator: navigator,
            dataCache: cache,
          ),
        ),
      );

      // On FIRST FRAME (0 ms / no delay pumped), the cached album must be painted!
      expect(find.text('Cached Album'), findsOneWidget);
      // No CircularProgressIndicator anywhere
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpAndSettle();
      cache.dispose();
    });

    testWidgets('first load shows placeholder with final layout when cache is empty',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Empty repository and no seeded cache: initial frame should show AlbumsViewPlaceholder, NOT CircularProgressIndicator
      await tester.pumpWidget(
        buildTestHost(
          child: AlbumsView(
            repository: repository,
            settingsStore: settingsStore,
            navigator: navigator,
          ),
        ),
      );

      // On initial pump before async loads finish:
      // It should display AlbumsViewPlaceholder with matching layout
      expect(find.byType(AlbumsViewPlaceholder), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Let async load complete
      await tester.pumpAndSettle();
      expect(find.byType(AlbumsViewPlaceholder), findsNothing);
    });

    testWidgets('TracksView paints cached tracks on first frame without spinner',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cache = LibraryDataCache(repository: repository);
      cache.seed(
        tracks: [
          Track(
            path: '/music/song1.mp3',
            folderId: 1,
            title: 'Immediate Track',
            artist: 'Immediate Artist',
            album: 'Immediate Album',
            durationMs: 150000,
            mtimeMs: 1000,
            sizeBytes: 2000,
            addedAt: DateTime.now(),
          ),
        ],
      );

      await tester.pumpWidget(
        buildTestHost(
          cache: cache,
          child: TracksView(
            repository: repository,
            controller: playbackController,
            settingsStore: settingsStore,
            dataCache: cache,
          ),
        ),
      );

      // First frame paints immediately
      expect(find.text('Immediate Track'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpAndSettle();
      cache.dispose();
    });

    testWidgets('ArtistsView first load shows ArtistsViewPlaceholder without spinner',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestHost(
          child: ArtistsView(
            repository: repository,
            settingsStore: settingsStore,
            navigator: navigator,
          ),
        ),
      );

      expect(find.byType(ArtistsViewPlaceholder), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byType(ArtistsViewPlaceholder), findsNothing);
    });

    testWidgets('TracksView first load shows TracksViewPlaceholder without spinner',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestHost(
          child: TracksView(
            repository: repository,
            controller: playbackController,
            settingsStore: settingsStore,
          ),
        ),
      );

      expect(find.byType(TracksViewPlaceholder), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byType(TracksViewPlaceholder), findsNothing);
    });

    test('disposing cache leaves no active listeners or timers',
        timeout: const Timeout(Duration(seconds: 30)), () async {
      final scanService = _FakeScanService(repository: repository);
      final cache = LibraryDataCache(
        repository: repository,
        scanService: scanService,
      );

      bool notified = false;
      cache.addListener(() => notified = true);

      cache.dispose();

      // Triggering scan finish after dispose should not throw or notify
      scanService.setScanning(true);
      scanService.setScanning(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notified, isFalse);
      scanService.dispose();
    });
  });
}
