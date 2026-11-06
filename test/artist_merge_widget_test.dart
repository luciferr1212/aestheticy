import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/library/artist_detail_view.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';

class FailingMergeRepository implements LibraryRepository {
  final SqliteLibraryRepository _inner;
  FailingMergeRepository(this._inner);

  bool shouldThrow = false;
  String? lastSourceKey;
  String? lastTargetKey;
  String? lastTargetName;

  @override
  Future<void> mergeArtists(String sourceKey, String targetKey, {String? targetName}) async {
    lastSourceKey = sourceKey;
    lastTargetKey = targetKey;
    lastTargetName = targetName;
    if (shouldThrow) {
      throw Exception('Simulated database write error');
    }
    return _inner.mergeArtists(sourceKey, targetKey, targetName: targetName);
  }

  @override
  Future<LibraryFolder> addFolder(String path) => _inner.addFolder(path);

  @override
  Future<void> removeFolder(int folderId) => _inner.removeFolder(folderId);

  @override
  Future<List<LibraryFolder>> listFolders() => _inner.listFolders();

  @override
  Future<void> markFolderScanned(int folderId, DateTime timestamp) =>
      _inner.markFolderScanned(folderId, timestamp);

  @override
  Future<void> upsertTracks(List<Track> tracks) => _inner.upsertTracks(tracks);

  @override
  Future<Map<String, ({int mtimeMs, int sizeBytes})>> existingFiles(int folderId) =>
      _inner.existingFiles(folderId);

  @override
  Future<void> removeTracksByPath(List<String> paths) => _inner.removeTracksByPath(paths);

  @override
  Future<List<AlbumSummary>> listAlbums({int? limit, int? offset}) =>
      _inner.listAlbums(limit: limit, offset: offset);

  @override
  Future<List<ArtistSummary>> listArtists({int? limit, int? offset}) =>
      _inner.listArtists(limit: limit, offset: offset);

  @override
  Future<int> albumCount() => _inner.albumCount();

  @override
  Future<int> artistCount() => _inner.artistCount();

  @override
  Future<List<Track>> tracksOfAlbum(String album, {String? albumArtist}) =>
      _inner.tracksOfAlbum(album, albumArtist: albumArtist);

  @override
  Future<List<Track>> tracksOfArtist(String artist, {String? artistKey}) =>
      _inner.tracksOfArtist(artist, artistKey: artistKey);

  @override
  Future<void> unmergeArtist(String aliasKey) => _inner.unmergeArtist(aliasKey);

  @override
  Future<List<ArtistAlias>> listAliases() => _inner.listAliases();

  @override
  Future<void> addNoSplit(String name) => _inner.addNoSplit(name);

  @override
  Future<void> removeNoSplit(String key) => _inner.removeNoSplit(key);

  @override
  Future<List<ArtistNoSplit>> listNoSplit() => _inner.listNoSplit();

  @override
  Future<void> rebuildArtistLinks() => _inner.rebuildArtistLinks();

  @override
  Future<List<Track>> listTracks({TrackSort sort = TrackSort.titleAsc, int? limit, int? offset}) =>
      _inner.listTracks(sort: sort, limit: limit, offset: offset);

  @override
  Future<List<Track>> search(String query) => _inner.search(query);

  @override
  Future<List<AlbumSummary>> searchAlbums(String query, {int? limit}) =>
      _inner.searchAlbums(query, limit: limit);

  @override
  Future<List<ArtistSummary>> searchArtists(String query, {int? limit}) =>
      _inner.searchArtists(query, limit: limit);

  @override
  Future<int> trackCount() => _inner.trackCount();

  @override
  Future<int> insertPlayEvent(PlayEvent e) => _inner.insertPlayEvent(e);

  @override
  Future<void> updatePlayEvent(
    int id, {
    required int listenedMs,
    required bool counted,
    required bool completed,
  }) =>
      _inner.updatePlayEvent(
        id,
        listenedMs: listenedMs,
        counted: counted,
        completed: completed,
      );

  @override
  Future<List<PlayEvent>> recentPlayEvents({int limit = 50}) =>
      _inner.recentPlayEvents(limit: limit);

  @override
  Future<int> playEventCount({bool countedOnly = false}) =>
      _inner.playEventCount(countedOnly: countedOnly);

  @override
  Future<void> clearPlayEvents() => _inner.clearPlayEvents();

  @override
  Future<Set<String>> favoritePaths() => _inner.favoritePaths();

  @override
  Future<void> setFavorite(String path, bool value) =>
      _inner.setFavorite(path, value);

  @override
  Future<List<Track>> favoriteTracks() => _inner.favoriteTracks();

  @override
  Future<Map<String, int>> allRatings() => _inner.allRatings();

  @override
  Future<void> setRating(String path, int stars) =>
      _inner.setRating(path, stars);

  @override
  Future<PlaylistSummary> createPlaylist(String name) =>
      _inner.createPlaylist(name);

  @override
  Future<void> renamePlaylist(int id, String name) =>
      _inner.renamePlaylist(id, name);

  @override
  Future<void> deletePlaylist(int id) => _inner.deletePlaylist(id);

  @override
  Future<List<PlaylistSummary>> listPlaylists() => _inner.listPlaylists();

  @override
  Future<List<PlaylistEntry>> playlistEntries(int id) =>
      _inner.playlistEntries(id);

  @override
  Future<int> addToPlaylist(int id, List<String> paths) =>
      _inner.addToPlaylist(id, paths);

  @override
  Future<void> removePlaylistEntries(int id, List<int> entryIds) =>
      _inner.removePlaylistEntries(id, entryIds);

  @override
  Future<void> movePlaylistEntry(int id, int entryId, int newPosition) =>
      _inner.movePlaylistEntry(id, entryId, newPosition);

  @override
  Future<List<Track>> recentlyPlayedTracks({int limit = 200}) =>
      _inner.recentlyPlayedTracks(limit: limit);

  @override
  Future<void> close() => _inner.close();
}

void main() {
  group('Artist Merge & Rules Widget Tests', () {
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late SqliteLibraryRepository repository;
    late ScanService scanService;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_artist_test_');
      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
      repository = SqliteLibraryRepository.inMemory();
      scanService = ScanService(repository: repository);
    });

    tearDown(() async {
      scanService.dispose();
      await repository.close();
      await controller.dispose();
      await engine.dispose();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Widget createTestApp({LibraryRepository? repo}) {
      final nav = AppNavigator(initialDestination: AppDestination.artists);
      final store = SettingsStore(directory: tempDir);
      return MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0F1115),
        ),
        home: AppShell(
          engine: engine,
          controller: controller,
          repository: repo ?? repository,
          scanService: scanService,
          settingsStore: store,
          navigator: nav,
        ),
      );
    }

    testWidgets('Merge artist action merges two artists via UI picker', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final folder = await repository.addFolder('C:\\Music');
      final now = DateTime.now();

      await repository.upsertTracks([
        Track(
          path: 'C:\\Music\\track1.mp3',
          folderId: folder.id!,
          title: 'Track 1',
          artist: 'Fairouz',
          album: 'Album 1',
          durationMs: 180000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\track2.mp3',
          folderId: folder.id!,
          title: 'Track 2',
          artist: 'Fayrouz',
          album: 'Album 2',
          durationMs: 200000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
      ]);
      await repository.rebuildArtistLinks();

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Fairouz'), findsOneWidget);
      expect(find.text('Fayrouz'), findsOneWidget);

      // Open menu on Fayrouz
      final fayrouzMenu = find.byKey(const Key('artist_menu_fayrouz'));
      expect(fayrouzMenu, findsOneWidget);
      await tester.tap(fayrouzMenu);
      await tester.pumpAndSettle();

      // Tap 'Merge into…'
      await tester.tap(find.text('Merge into…'));
      await tester.pumpAndSettle();

      // Verify merge dialog is open
      expect(find.text('Merge "Fayrouz" into…'), findsOneWidget);

      // Select Fairouz from list
      final targetTile = find.byKey(const Key('merge_target_fairouz'));
      expect(targetTile, findsOneWidget);
      await tester.tap(targetTile);
      await tester.pumpAndSettle();

      // Confirm dialog appears
      expect(find.text('Confirm merge'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm_merge_button')));
      await tester.pumpAndSettle();

      // Verify merged into single entry in Artists tab
      expect(find.text('Fairouz'), findsOneWidget);
      expect(find.text('Fayrouz'), findsNothing);
    });

    testWidgets('Artist rules sheet lists merges and allows unmerging', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final folder = await repository.addFolder('C:\\Music');
      final now = DateTime.now();

      await repository.upsertTracks([
        Track(
          path: 'C:\\Music\\a1.mp3',
          folderId: folder.id!,
          title: 'Song A',
          artist: 'Artist A',
          durationMs: 100,
          mtimeMs: 1,
          sizeBytes: 1,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\b1.mp3',
          folderId: folder.id!,
          title: 'Song B',
          artist: 'Artist B',
          durationMs: 100,
          mtimeMs: 1,
          sizeBytes: 1,
          addedAt: now,
        ),
      ]);

      // Merge B into A
      await repository.mergeArtists('artist b', 'artist a');

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Open menu on Artist A and choose rules
      final menuA = find.byKey(const Key('artist_menu_artist a'));
      expect(menuA, findsOneWidget);
      await tester.tap(menuA);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Artist rules...'));
      await tester.pumpAndSettle();

      expect(find.text('Artist Rules'), findsOneWidget);
      expect(find.text('artist b'), findsOneWidget);
      expect(find.text('Merged into Artist A'), findsOneWidget);

      // Tap remove merge button
      final removeButton = find.byKey(const Key('remove_merge_artist b'));
      expect(removeButton, findsOneWidget);
      await tester.tap(removeButton);
      await tester.pumpAndSettle();

      expect(find.text('No merged artists.'), findsOneWidget);
    });

    testWidgets('ArtistDetailScreen track menu can treat artist as one artist', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final folder = await repository.addFolder('C:\\Music');
      final now = DateTime.now();

      await repository.upsertTracks([
        Track(
          id: 1,
          path: 'C:\\Music\\solo.mp3',
          folderId: folder.id!,
          title: 'Solo',
          artist: 'Solo Artist',
          durationMs: 100,
          mtimeMs: 1,
          sizeBytes: 1,
          addedAt: now,
        ),
        Track(
          id: 2,
          path: 'C:\\Music\\band.mp3',
          folderId: folder.id!,
          title: 'Band Song',
          artist: 'Solo Artist and Other Band',
          durationMs: 100,
          mtimeMs: 1,
          sizeBytes: 1,
          addedAt: now,
        ),
      ]);
      await repository.rebuildArtistLinks();

      final artists = await repository.listArtists();
      final soloArtist = artists.firstWhere((a) => a.name == 'Solo Artist');

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            body: ArtistDetailView(
              artist: soloArtist,
              repository: repository,
              controller: controller,
              settingsStore: SettingsStore(directory: tempDir),
              navigator: AppNavigator(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find track menu for track id 2
      final trackMenu = find.byKey(const Key('track_menu_2'));
      expect(trackMenu, findsOneWidget);
      await tester.tap(trackMenu);
      await tester.pumpAndSettle();

      // Tap 'Treat "Solo Artist and Other Band" as one artist'
      final option = find.text('Treat "Solo Artist and Other Band" as one artist');
      expect(option, findsOneWidget);
      await tester.tap(option);
      await tester.pumpAndSettle();

      // Verify no-split was added to repository
      final noSplits = await repository.listNoSplit();
      expect(noSplits.any((n) => n.artistName == 'Solo Artist and Other Band'), isTrue);
    });

    testWidgets('F3: Merge flow with fake repository: filters target artists, cancels, handles repository exception with localized message, and shows merged badge', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final innerSqlite = SqliteLibraryRepository.inMemory();
      final fakeRepo = FailingMergeRepository(innerSqlite);
      final folder = await fakeRepo.addFolder('C:\\Music');
      final now = DateTime.now();

      await fakeRepo.upsertTracks([
        Track(
          path: 'C:\\Music\\t1.mp3',
          folderId: folder.id!,
          title: 'Song 1',
          artist: 'Fairouz',
          durationMs: 100,
          mtimeMs: 1,
          sizeBytes: 1,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\t2.mp3',
          folderId: folder.id!,
          title: 'Song 2',
          artist: 'Fayrouz',
          durationMs: 100,
          mtimeMs: 1,
          sizeBytes: 1,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\t3.mp3',
          folderId: folder.id!,
          title: 'Song 3',
          artist: 'Majida',
          durationMs: 100,
          mtimeMs: 1,
          sizeBytes: 1,
          addedAt: now,
        ),
      ]);
      await fakeRepo.rebuildArtistLinks();

      await tester.pumpWidget(createTestApp(repo: fakeRepo));
      await tester.pumpAndSettle();

      // 1. Open merge dialog for Fayrouz
      await tester.tap(find.byKey(const Key('artist_menu_fayrouz')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge into…'));
      await tester.pumpAndSettle();

      // Both other artists exist in list
      expect(find.byKey(const Key('merge_target_fairouz')), findsOneWidget);
      expect(find.byKey(const Key('merge_target_majida')), findsOneWidget);

      // Filter narrows list
      await tester.enterText(find.byKey(const Key('merge_artist_search_field')), 'Fai');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('merge_target_fairouz')), findsOneWidget);
      expect(find.byKey(const Key('merge_target_majida')), findsNothing);

      // 2. Cancel changes nothing
      await tester.tap(find.byKey(const Key('merge_target_fairouz')));
      await tester.pumpAndSettle();
      expect(find.text('Confirm merge'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(fakeRepo.lastSourceKey, isNull);

      // Dismiss target picker dialog
      await tester.tap(find.byKey(const Key('merge_dialog_cancel_button')));
      await tester.pumpAndSettle();

      // Re-open merge dialog
      await tester.tap(find.byKey(const Key('artist_menu_fayrouz')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge into…'));
      await tester.pumpAndSettle();

      // 3. Repository exception shows localized failure message
      fakeRepo.shouldThrow = true;
      await tester.tap(find.byKey(const Key('merge_target_fairouz')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_merge_button')));
      await tester.pumpAndSettle();

      expect(fakeRepo.lastSourceKey, equals('fayrouz'));
      expect(fakeRepo.lastTargetKey, equals('fairouz'));
      expect(fakeRepo.lastTargetName, equals('Fairouz'));
      expect(find.textContaining('Merge failed: Exception: Simulated database write error'), findsOneWidget);

      // Dismiss exception snackbar
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
      await tester.pumpAndSettle();

      // 4. Successful merge updates repository and displays merged badge
      fakeRepo.shouldThrow = false;
      await tester.tap(find.byKey(const Key('artist_menu_fayrouz')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge into…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('merge_target_fairouz')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_merge_button')));
      await tester.pumpAndSettle();

      // Merged badge is now visible on Fairouz
      expect(find.text('Merged'), findsOneWidget);
      expect(find.text('Fairouz'), findsOneWidget);
      expect(find.text('Fayrouz'), findsNothing);
    });
  });
}
