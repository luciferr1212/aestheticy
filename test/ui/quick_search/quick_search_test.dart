import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/quick_search/quick_search_overlay.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';

class _FakeSearchRepo implements LibraryRepository {
  List<Track> tracksToReturn = [];
  List<AlbumSummary> albumsToReturn = [];
  List<ArtistSummary> artistsToReturn = [];
  Duration? searchDelay;
  int searchCallCount = 0;

  @override
  Future<List<Track>> search(String query) async {
    searchCallCount++;
    if (searchDelay != null) await Future<void>.delayed(searchDelay!);
    final q = query.toLowerCase();
    return tracksToReturn
        .where((t) =>
            (t.title?.toLowerCase().contains(q) ?? false) ||
            (t.artist?.toLowerCase().contains(q) ?? false) ||
            (t.album?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Future<List<AlbumSummary>> searchAlbums(String query, {int? limit}) async {
    if (searchDelay != null) await Future<void>.delayed(searchDelay!);
    final q = query.toLowerCase();
    final list = albumsToReturn
        .where((a) =>
            a.album.toLowerCase().contains(q) ||
            (a.albumArtist?.toLowerCase().contains(q) ?? false))
        .toList();
    return limit != null ? list.take(limit).toList() : list;
  }

  @override
  Future<List<ArtistSummary>> searchArtists(String query, {int? limit}) async {
    if (searchDelay != null) await Future<void>.delayed(searchDelay!);
    final list = artistsToReturn
        .where((a) => a.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return limit != null ? list.take(limit).toList() : list;
  }

  @override
  Future<LibraryFolder> addFolder(String path) => throw UnimplementedError();
  @override
  Future<void> removeFolder(int folderId) => throw UnimplementedError();
  @override
  Future<List<LibraryFolder>> listFolders() async => [];
  @override
  Future<void> markFolderScanned(int folderId, DateTime timestamp) => throw UnimplementedError();
  @override
  Future<void> upsertTracks(List<Track> tracks) => throw UnimplementedError();
  @override
  Future<Map<String, ({int mtimeMs, int sizeBytes})>> existingFiles(int folderId) => throw UnimplementedError();
  @override
  Future<void> removeTracksByPath(List<String> paths) => throw UnimplementedError();
  @override
  Future<List<AlbumSummary>> listAlbums({int? limit, int? offset}) async => [];
  @override
  Future<List<ArtistSummary>> listArtists({int? limit, int? offset}) async => [];
  @override
  Future<int> albumCount() async => 0;
  @override
  Future<int> artistCount() async => 0;
  @override
  Future<List<Track>> tracksOfAlbum(String album, {String? albumArtist}) async => [];
  @override
  Future<List<Track>> tracksOfArtist(String artist, {String? artistKey}) async => [];
  @override
  Future<void> mergeArtists(String aliasKey, String canonicalKey, {String? targetName}) => throw UnimplementedError();
  @override
  Future<void> unmergeArtist(String aliasKey) => throw UnimplementedError();
  @override
  Future<List<ArtistAlias>> listAliases() async => [];
  @override
  Future<void> addNoSplit(String name) => throw UnimplementedError();
  @override
  Future<void> removeNoSplit(String key) => throw UnimplementedError();
  @override
  Future<List<ArtistNoSplit>> listNoSplit() async => [];
  @override
  Future<void> rebuildArtistLinks() => throw UnimplementedError();
  @override
  Future<List<Track>> listTracks({int? limit, int? offset, TrackSort sort = TrackSort.titleAsc}) async => [];
  @override
  Future<int> trackCount() async => 0;

  @override
  Future<int> insertPlayEvent(PlayEvent e) async => 1;

  @override
  Future<void> updatePlayEvent(
    int id, {
    required int listenedMs,
    required bool counted,
    required bool completed,
  }) async {}

  @override
  Future<List<PlayEvent>> recentPlayEvents({int limit = 50}) async => [];

  @override
  Future<int> playEventCount({bool countedOnly = false}) async => 0;

  @override
  Future<void> clearPlayEvents() async {}

  @override
  Future<void> close() async {}
}

void main() {
  late Directory tempDir;
  late FakeAudioEngine engine;
  late PlaybackController controller;
  late AppNavigator navigator;
  late SettingsStore settingsStore;
  late ArtistNameStore artistNameStore;
  late _FakeSearchRepo repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('quick_search_test_');
    engine = FakeAudioEngine();
    controller = PlaybackController(engine: engine, queue: PlaybackQueue());
    await controller.init();

    navigator = AppNavigator();
    settingsStore = SettingsStore(directoryProvider: () async => tempDir);
    await settingsStore.init();

    artistNameStore = ArtistNameStore(directoryProvider: () async => tempDir);
    await artistNameStore.init();

    repo = _FakeSearchRepo();
  });

  tearDown(() async {
    closeQuickSearch();
    settingsStore.dispose();
    artistNameStore.dispose();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Widget buildHostApp({
    Locale locale = const Locale('en'),
    VoidCallback? onOpen,
  }) {
    return MaterialApp(
      locale: locale,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                key: const Key('open_search_btn'),
                onPressed: () {
                  toggleQuickSearch(
                    context: context,
                    repository: repo,
                    controller: controller,
                    navigator: navigator,
                    settingsStore: settingsStore,
                    artistNameStore: artistNameStore,
                  );
                  onOpen?.call();
                },
                child: const Text('Open Search'),
              ),
            );
          },
        ),
      ),
    );
  }

  group('QuickSearchOverlay Tests', () {
    testWidgets('Ctrl+K opens overlay, Esc or second Ctrl+K closes it',
        (tester) async {
      await tester.pumpWidget(buildHostApp());
      await tester.pumpAndSettle();

      // Open search
      await tester.tap(find.byKey(const Key('open_search_btn')));
      await tester.pumpAndSettle();

      expect(find.byType(QuickSearchOverlay), findsOneWidget);
      expect(find.byKey(const Key('quick_search_input')), findsOneWidget);

      // Send Esc -> closes
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(QuickSearchOverlay), findsNothing);

      // Re-open
      await tester.tap(find.byKey(const Key('open_search_btn')));
      await tester.pumpAndSettle();
      expect(find.byType(QuickSearchOverlay), findsOneWidget);

      // Send Ctrl+K -> closes
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      expect(find.byType(QuickSearchOverlay), findsNothing);
    });

    testWidgets('debounces queries by 120ms before hitting repository',
        (tester) async {
      repo.tracksToReturn = [
        Track(
          id: 1,
          folderId: 1,
          path: '/music/song.mp3',
          title: 'Acoustic Guitar',
          album: 'Solo',
          artist: 'John',
          mtimeMs: 0,
          sizeBytes: 1000,
          durationMs: 180000,
          addedAt: DateTime(2025),
        ),
      ];

      await tester.pumpWidget(buildHostApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_search_btn')));
      await tester.pumpAndSettle();

      // Type rapidly
      await tester.enterText(find.byKey(const Key('quick_search_input')), 'A');
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.searchCallCount, 0);

      await tester.enterText(find.byKey(const Key('quick_search_input')), 'Ac');
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.searchCallCount, 0);

      await tester.enterText(find.byKey(const Key('quick_search_input')), 'Acoustic');
      await tester.pump(const Duration(milliseconds: 130));
      await tester.pumpAndSettle();

      expect(repo.searchCallCount, 1);
      expect(find.text('Acoustic Guitar'), findsOneWidget);
    });

    testWidgets('enforces section caps: max 4 artists, max 4 albums, max 8 tracks',
        (tester) async {
      repo.artistsToReturn = List.generate(
        10,
        (i) => ArtistSummary(name: 'Artist $i', trackCount: 1, albumCount: 1),
      );
      repo.albumsToReturn = List.generate(
        10,
        (i) => AlbumSummary(album: 'Album $i', albumArtist: 'Artist $i', trackCount: 1),
      );
      repo.tracksToReturn = List.generate(
        20,
        (i) => Track(
          id: i + 1,
          folderId: 1,
          path: '/m/$i.mp3',
          title: 'Track $i',
          album: 'Album $i',
          artist: 'Artist $i',
          mtimeMs: 0,
          sizeBytes: 1000,
          durationMs: 180000,
          addedAt: DateTime(2025),
        ),
      );

      await tester.pumpWidget(buildHostApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_search_btn')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('quick_search_input')), 'a');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      // Artists section has max 4 items
      for (var i = 0; i < 4; i++) {
        expect(find.text('Artist $i'), findsWidgets);
      }
      expect(find.text('Artist 4'), findsNothing);

      // Albums section has max 4 items
      for (var i = 0; i < 4; i++) {
        expect(find.text('Album $i'), findsWidgets);
      }
      expect(find.text('Album 4'), findsNothing);

      // Tracks section has max 8 items
      for (var i = 0; i < 8; i++) {
        expect(find.text('Track $i'), findsOneWidget);
      }
      expect(find.text('Track 8'), findsNothing);
    });

    testWidgets('keyboard navigation (Down, Up, Enter) activates items correctly',
        (tester) async {
      final track = Track(
        id: 1,
        folderId: 1,
        path: '/music/track1.mp3',
        title: 'Bohemian Rhapsody',
        album: 'A Night at the Opera',
        artist: 'Queen',
        mtimeMs: 0,
        sizeBytes: 1000,
        durationMs: 354000,
        addedAt: DateTime(2025),
      );

      const album = AlbumSummary(
        album: 'A Night at the Opera',
        albumArtist: 'Queen',
        trackCount: 12,
      );

      const artist = ArtistSummary(
        name: 'Queen',
        trackCount: 50,
        albumCount: 5,
      );

      repo.artistsToReturn = [artist];
      repo.albumsToReturn = [album];
      repo.tracksToReturn = [track];

      await tester.pumpWidget(buildHostApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_search_btn')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('quick_search_input')), 'q');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      // First item is artist (index 0). Press Enter -> opens artist detail
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(navigator.current, AppDestination.artistDetail);
      expect(navigator.selectedArtist?.toString(), contains('Queen'));
      expect(find.byType(QuickSearchOverlay), findsNothing); // Closed

      // Re-open and navigate to track
      await tester.tap(find.byKey(const Key('open_search_btn')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('quick_search_input')), 'q');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      // Press Down twice: index 0 (Artist) -> index 1 (Album) -> index 2 (Track)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      // Press Enter on track -> plays track via playQueue
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controller.queue.items.length, 1);
      expect(controller.queue.items.first.uri, '/music/track1.mp3');
      expect(find.byType(QuickSearchOverlay), findsNothing); // Closed
    });

    testWidgets('translated artist name matching finds artists without altering repo queries',
        (tester) async {
      // User entered an Arabic display name for Fairuz
      artistNameStore.setEntry('Fairuz', ar: 'فيروز');

      repo.artistsToReturn = [
        const ArtistSummary(name: 'Fairuz', trackCount: 30, albumCount: 4),
      ];

      await tester.pumpWidget(buildHostApp(locale: const Locale('ar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_search_btn')));
      await tester.pumpAndSettle();

      // User types the Arabic display name
      await tester.enterText(find.byKey(const Key('quick_search_input')), 'فيروز');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      // Found the artist!
      expect(find.text('Fairuz'), findsOneWidget);
    });

    testWidgets('clicking scrim closes the overlay',
        (tester) async {
      await tester.pumpWidget(buildHostApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_search_btn')));
      await tester.pumpAndSettle();

      expect(find.byType(QuickSearchOverlay), findsOneWidget);

      // Tap outside card on scrim (top-left corner)
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(QuickSearchOverlay), findsNothing);
    });
  });
}
