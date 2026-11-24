import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/library/albums_view.dart';
import 'package:aestheticy/ui/library/artists_view.dart';
import 'package:aestheticy/ui/library/tracks_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

import '../../library/fake_library_repository.dart';

class _SearchTestRepository extends FakeLibraryRepository {
  List<AlbumSummary> albumsData = [];
  List<ArtistSummary> artistsData = [];
  List<Track> tracksData = [];

  final List<String> albumQueries = [];
  final List<String> artistQueries = [];
  final List<String> trackQueries = [];

  final Map<String, Completer<List<AlbumSummary>>> albumCompleters = {};
  final Map<String, Completer<List<ArtistSummary>>> artistCompleters = {};
  final Map<String, Completer<List<Track>>> trackCompleters = {};

  Future<List<AlbumSummary>> Function(String query)? onSearchAlbums;

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

  @override
  Future<List<AlbumSummary>> searchAlbums(String query, {int? limit}) async {
    albumQueries.add(query);
    final custom = onSearchAlbums;
    if (custom != null) {
      return custom(query);
    }
    final completer = albumCompleters[query];
    if (completer != null) {
      return completer.future;
    }
    final q = query.toLowerCase();
    return albumsData
        .where((a) =>
            a.album.toLowerCase().contains(q) ||
            (a.albumArtist ?? '').toLowerCase().contains(q) ||
            (a.displayArtist ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<ArtistSummary>> searchArtists(String query, {int? limit}) async {
    artistQueries.add(query);
    final completer = artistCompleters[query];
    if (completer != null) {
      return completer.future;
    }
    final q = query.toLowerCase();
    return artistsData
        .where((a) => a.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<Track>> search(String query) async {
    trackQueries.add(query);
    final completer = trackCompleters[query];
    if (completer != null) {
      return completer.future;
    }
    final q = query.toLowerCase();
    return tracksData
        .where((t) =>
            (t.title ?? '').toLowerCase().contains(q) ||
            (t.artist ?? '').toLowerCase().contains(q) ||
            (t.album ?? '').toLowerCase().contains(q))
        .toList();
  }
}

Track _makeTrack({
  required String path,
  required String title,
  required String artist,
  String? album,
  String? albumArtist,
}) {
  return Track(
    path: path,
    folderId: 1,
    title: title,
    artist: artist,
    albumArtist: albumArtist,
    album: album,
    durationMs: 180000,
    mtimeMs: 1000,
    sizeBytes: 1024,
    addedAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('S1 Search Race Guard & Scope', () {
    testWidgets(
      'AlbumsView discards stale out-of-order search results and post-clear results',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final repo = _SearchTestRepository()
          ..albumsData = const [
            AlbumSummary(
              album: 'Initial Album',
              albumArtist: 'Artist Zero',
              trackCount: 3,
              identityKey: 'initial::zero',
            ),
          ];
        final slowCompleter = Completer<List<AlbumSummary>>();
        final fastCompleter = Completer<List<AlbumSummary>>();
        repo.albumCompleters['slow'] = slowCompleter;
        repo.albumCompleters['fast'] = fastCompleter;

        final settingsStore = SettingsStore(
          initialSettings: const AppSettings(reduceMotion: true),
        );
        final artistNameStore = ArtistNameStore();
        final navigator = AppNavigator();
        addTearDown(() {
          settingsStore.dispose();
          artistNameStore.dispose();
          navigator.dispose();
        });

        await tester.pumpWidget(
          SettingsScope(
            store: settingsStore,
            child: ArtistNameScope(
              store: artistNameStore,
              child: MaterialApp(
                locale: const Locale('en'),
                supportedLocales: const [Locale('en'), Locale('ar')],
                theme: buildAppTheme(),
                home: Scaffold(
                  body: AlbumsView(
                    repository: repo,
                    settingsStore: settingsStore,
                    navigator: navigator,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Initial Album'), findsOneWidget);

        // Query A ('slow') dispatched after 250ms debounce.
        await tester.enterText(find.byKey(const Key('library_search_field')), 'slow');
        await tester.pump(const Duration(milliseconds: 260));
        expect(repo.albumQueries, contains('slow'));

        // Query B ('fast') dispatched while 'slow' is still pending.
        await tester.enterText(find.byKey(const Key('library_search_field')), 'fast');
        await tester.pump(const Duration(milliseconds: 260));
        expect(repo.albumQueries, contains('fast'));

        // Resolve newer query B first.
        fastCompleter.complete(const [
          AlbumSummary(
            album: 'Fast Result',
            albumArtist: 'Fast Artist',
            trackCount: 2,
            identityKey: 'fast::artist',
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Fast Result'), findsOneWidget);

        // Stale query A resolves late -> must NOT overwrite UI.
        slowCompleter.complete(const [
          AlbumSummary(
            album: 'Stale Slow Result',
            albumArtist: 'Slow Artist',
            trackCount: 2,
            identityKey: 'slow::artist',
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Fast Result'), findsOneWidget);
        expect(find.text('Stale Slow Result'), findsNothing);

        // Now start another in-flight query and clear via Clear button before completion.
        final clearRaceCompleter = Completer<List<AlbumSummary>>();
        repo.albumCompleters['clearme'] = clearRaceCompleter;
        await tester.enterText(
          find.byKey(const Key('library_search_field')),
          'clearme',
        );
        await tester.pump(const Duration(milliseconds: 260));
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        clearRaceCompleter.complete(const [
          AlbumSummary(
            album: 'Zombie Clear Result',
            albumArtist: 'Ghost',
            trackCount: 1,
            identityKey: 'zombie::ghost',
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Initial Album'), findsOneWidget);
        expect(find.text('Zombie Clear Result'), findsNothing);
      },
    );

    testWidgets(
      'ArtistsView discards stale out-of-order search results',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final repo = _SearchTestRepository()
          ..artistsData = const [
            ArtistSummary(
              key: 'zero',
              name: 'Artist Zero',
              albumCount: 1,
              trackCount: 2,
            ),
          ];
        final slowCompleter = Completer<List<ArtistSummary>>();
        final fastCompleter = Completer<List<ArtistSummary>>();
        repo.artistCompleters['slow'] = slowCompleter;
        repo.artistCompleters['fast'] = fastCompleter;

        final settingsStore = SettingsStore(
          initialSettings: const AppSettings(reduceMotion: true),
        );
        final artistNameStore = ArtistNameStore();
        final navigator = AppNavigator();
        addTearDown(() {
          settingsStore.dispose();
          artistNameStore.dispose();
          navigator.dispose();
        });

        await tester.pumpWidget(
          SettingsScope(
            store: settingsStore,
            child: ArtistNameScope(
              store: artistNameStore,
              child: MaterialApp(
                locale: const Locale('en'),
                supportedLocales: const [Locale('en'), Locale('ar')],
                theme: buildAppTheme(),
                home: Scaffold(
                  body: ArtistsView(
                    repository: repo,
                    settingsStore: settingsStore,
                    navigator: navigator,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('library_search_field')), 'slow');
        await tester.pump(const Duration(milliseconds: 260));
        await tester.enterText(find.byKey(const Key('library_search_field')), 'fast');
        await tester.pump(const Duration(milliseconds: 260));

        fastCompleter.complete(const [
          ArtistSummary(
            key: 'fast_artist',
            name: 'Fast Artist Match',
            albumCount: 1,
            trackCount: 4,
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Fast Artist Match'), findsOneWidget);

        slowCompleter.complete(const [
          ArtistSummary(
            key: 'stale_artist',
            name: 'Stale Artist Match',
            albumCount: 1,
            trackCount: 1,
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Fast Artist Match'), findsOneWidget);
        expect(find.text('Stale Artist Match'), findsNothing);
      },
    );

    testWidgets(
      'TracksView discards stale out-of-order search results',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final repo = _SearchTestRepository()
          ..tracksData = [
            _makeTrack(
              path: 'C:/Music/zero.mp3',
              title: 'Zero Track',
              artist: 'Artist Zero',
              album: 'Album Zero',
            ),
          ];
        final slowCompleter = Completer<List<Track>>();
        final fastCompleter = Completer<List<Track>>();
        repo.trackCompleters['slow'] = slowCompleter;
        repo.trackCompleters['fast'] = fastCompleter;

        final engine = FakeAudioEngine();
        final controller = PlaybackController(
          engine: engine,
          queue: PlaybackQueue(),
        );
        await controller.init();
        final settingsStore = SettingsStore(
          initialSettings: const AppSettings(reduceMotion: true),
        );
        final artistNameStore = ArtistNameStore();
        addTearDown(() async {
          await controller.dispose();
          settingsStore.dispose();
          artistNameStore.dispose();
        });

        await tester.pumpWidget(
          SettingsScope(
            store: settingsStore,
            child: ArtistNameScope(
              store: artistNameStore,
              child: MaterialApp(
                locale: const Locale('en'),
                supportedLocales: const [Locale('en'), Locale('ar')],
                theme: buildAppTheme(),
                home: Scaffold(
                  body: TracksView(
                    repository: repo,
                    controller: controller,
                    settingsStore: settingsStore,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('library_search_field')), 'slow');
        await tester.pump(const Duration(milliseconds: 260));
        await tester.enterText(find.byKey(const Key('library_search_field')), 'fast');
        await tester.pump(const Duration(milliseconds: 260));

        fastCompleter.complete([
          _makeTrack(
            path: 'C:/Music/fast.mp3',
            title: 'Fast Track Match',
            artist: 'Fast Artist',
            album: 'Fast Album',
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Fast Track Match'), findsOneWidget);

        slowCompleter.complete([
          _makeTrack(
            path: 'C:/Music/stale.mp3',
            title: 'Stale Track Match',
            artist: 'Slow Artist',
            album: 'Slow Album',
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Fast Track Match'), findsOneWidget);
        expect(find.text('Stale Track Match'), findsNothing);
      },
    );

    testWidgets(
      'AlbumsView debounces rapid search typing into a single repository query',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final repo = _SearchTestRepository()
          ..albumsData = const [
            AlbumSummary(
              album: 'Midnight Echo',
              albumArtist: 'Band',
              trackCount: 5,
              identityKey: 'midnight::band',
            ),
          ];
        final settingsStore = SettingsStore(
          initialSettings: const AppSettings(reduceMotion: true),
        );
        final artistNameStore = ArtistNameStore();
        final navigator = AppNavigator();
        addTearDown(() {
          settingsStore.dispose();
          artistNameStore.dispose();
          navigator.dispose();
        });

        await tester.pumpWidget(
          SettingsScope(
            store: settingsStore,
            child: ArtistNameScope(
              store: artistNameStore,
              child: MaterialApp(
                locale: const Locale('en'),
                supportedLocales: const [Locale('en'), Locale('ar')],
                theme: buildAppTheme(),
                home: Scaffold(
                  body: AlbumsView(
                    repository: repo,
                    settingsStore: settingsStore,
                    navigator: navigator,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final searchField = find.byKey(const Key('library_search_field'));
        await tester.enterText(searchField, 'm');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(searchField, 'mi');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(searchField, 'mid');
        await tester.pump(const Duration(milliseconds: 100));

        expect(repo.albumQueries, isEmpty);

        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();

        expect(repo.albumQueries, equals(['mid']));
      },
    );

    test('SqliteLibraryRepository.searchAlbums matches track artists and merged canonical artists without corrupting trackCount', () async {
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);

      await repo.addFolder('C:/Music');
      await repo.upsertTracks([
        _makeTrack(
          path: 'C:/Music/comp1.mp3',
          title: 'Track One',
          artist: 'Featured Star',
          album: 'Compilation Hit',
          albumArtist: 'Various Artists',
        ),
        _makeTrack(
          path: 'C:/Music/comp2.mp3',
          title: 'Track Two',
          artist: 'Second Guest',
          album: 'Compilation Hit',
          albumArtist: 'Various Artists',
        ),
        _makeTrack(
          path: 'C:/Music/collab.mp3',
          title: 'Duet',
          artist: 'Alpha & Beta',
          album: 'Shared Horizons',
          albumArtist: 'Alpha',
        ),
        _makeTrack(
          path: 'C:/Music/solo_beta.mp3',
          title: 'Solo Beta',
          artist: 'Beta',
          album: 'Beta Solo',
          albumArtist: 'Beta',
        ),
        _makeTrack(
          path: 'C:/Music/alias.mp3',
          title: 'Old Name Song',
          artist: 'Old Alias',
          album: 'Alias Album',
          albumArtist: 'Old Alias',
        ),
      ]);
      await repo.rebuildArtistLinks();

      // Match by track artist on compilation album -> preserves full trackCount (2)
      final byTrackArtist = await repo.searchAlbums('Featured Star');
      expect(byTrackArtist.length, equals(1));
      expect(byTrackArtist.first.album, equals('Compilation Hit'));
      expect(byTrackArtist.first.trackCount, equals(2));

      // Combined album title + track artist query
      final byMixedTerms = await repo.searchAlbums('Compilation Second Guest');
      expect(byMixedTerms.length, equals(1));
      expect(byMixedTerms.first.album, equals('Compilation Hit'));

      // Split track artist
      final bySplitArtist = await repo.searchAlbums('Beta');
      expect(bySplitArtist.map((a) => a.album), containsAll(['Shared Horizons', 'Beta Solo']));

      // Merged canonical artist name
      await repo.mergeArtists('old alias', 'canonical_key', targetName: 'Canonical Legend');
      final byCanonical = await repo.searchAlbums('Canonical Legend');
      expect(byCanonical.map((a) => a.album), contains('Alias Album'));
    });

    testWidgets(
      'AlbumsView search matches display-only translated artist names including compilation track artists',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final sqliteRepo = SqliteLibraryRepository.inMemory();
        addTearDown(sqliteRepo.close);

        await sqliteRepo.addFolder('C:/Music');
        await sqliteRepo.upsertTracks([
          _makeTrack(
            path: 'C:/Music/el_leila.mp3',
            title: 'El Leila',
            artist: 'Amr Diab',
            album: 'El Leila Album',
            albumArtist: 'Amr Diab',
          ),
          _makeTrack(
            path: 'C:/Music/summer_mix.mp3',
            title: 'Guest Hit',
            artist: 'Amr Diab',
            album: 'Summer Mix',
            albumArtist: 'Various Artists',
          ),
          _makeTrack(
            path: 'C:/Music/sunrise.mp3',
            title: 'Sunrise',
            artist: 'Other Singer',
            album: 'Sunrise',
            albumArtist: 'Other Singer',
          ),
        ]);
        await sqliteRepo.rebuildArtistLinks();

        final artistNameStore = ArtistNameStore(
          initialEntries: {
            'amr diab': const ArtistDisplayNameEntry(
              original: 'Amr Diab',
              ar: 'عمرو دياب',
              en: 'El Hadaba',
            ),
          },
        );
        final settingsStore = SettingsStore(
          initialSettings: const AppSettings(
            language: 'ar',
            artistNameMode: 'followLanguage',
            reduceMotion: true,
          ),
        );
        final navigator = AppNavigator();
        addTearDown(() {
          artistNameStore.dispose();
          settingsStore.dispose();
          navigator.dispose();
        });

        await tester.pumpWidget(
          SettingsScope(
            store: settingsStore,
            child: ArtistNameScope(
              store: artistNameStore,
              child: MaterialApp(
                theme: buildAppTheme(),
                home: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: AlbumsView(
                      repository: sqliteRepo,
                      settingsStore: settingsStore,
                      navigator: navigator,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Searching Arabic translation matches both solo album and compilation where artist is a track artist
        await tester.enterText(
          find.byKey(const Key('library_search_field')),
          'عمرو دياب',
        );
        await tester.pump(const Duration(milliseconds: 260));
        await tester.pumpAndSettle();

        expect(find.text('El Leila Album'), findsOneWidget);
        expect(find.text('Summer Mix'), findsOneWidget);
        expect(find.text('Sunrise'), findsNothing);

        // Multi-term query mixing album title and translated artist
        await tester.enterText(
          find.byKey(const Key('library_search_field')),
          'Leila عمرو',
        );
        await tester.pump(const Duration(milliseconds: 260));
        await tester.pumpAndSettle();

        expect(find.text('El Leila Album'), findsOneWidget);
        expect(find.text('Summer Mix'), findsNothing);
      },
    );
  });
}
