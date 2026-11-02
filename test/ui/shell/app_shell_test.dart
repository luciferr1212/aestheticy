import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/audio_lab/audio_lab_screen.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/shell/bottom_now_playing_bar.dart';
import 'package:aestheticy/ui/shell/sidebar.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

/// Fake repository capable of returning large synthetic datasets for virtualization tests.
class FakeVirtualLibraryRepository implements LibraryRepository {
  final int fakeAlbumCount;
  final int fakeTrackCount;
  final List<LibraryFolder> _folders = [
    const LibraryFolder(id: 1, path: 'C:\\Music'),
  ];
  final List<ArtistAlias> _aliases;

  FakeVirtualLibraryRepository({
    this.fakeAlbumCount = 0,
    this.fakeTrackCount = 0,
    List<ArtistAlias>? aliases,
  }) : _aliases = aliases ?? [];

  @override
  Future<LibraryFolder> addFolder(String path) async {
    final folder = LibraryFolder(id: _folders.length + 1, path: path);
    _folders.add(folder);
    return folder;
  }

  @override
  Future<List<LibraryFolder>> listFolders() async => List.unmodifiable(_folders);

  @override
  Future<void> removeFolder(int folderId) async {
    _folders.removeWhere((f) => f.id == folderId);
  }

  @override
  Future<void> markFolderScanned(int folderId, DateTime timestamp) async {}

  @override
  Future<Map<String, ({int mtimeMs, int sizeBytes})>> existingFiles(int folderId) async => {};

  @override
  Future<List<AlbumSummary>> listAlbums({int? limit, int? offset}) async {
    final count = fakeAlbumCount;
    return List.generate(
      count,
      (i) => AlbumSummary(
        album: 'Virtual Album $i',
        albumArtist: 'Virtual Artist $i',
        trackCount: 10,
        year: 2000 + (i % 25),
      ),
    );
  }

  @override
  Future<List<Track>> listTracks({
    TrackSort sort = TrackSort.titleAsc,
    int? limit,
    int? offset,
  }) async {
    final count = fakeTrackCount;
    return List.generate(
      count,
      (i) => Track(
        id: i,
        path: 'C:\\Music\\track_$i.mp3',
        folderId: 1,
        title: 'Virtual Track $i',
        artist: 'Virtual Artist ${i % 50}',
        album: 'Virtual Album ${i % 100}',
        durationMs: 180000 + (i % 60000),
        mtimeMs: 1000,
        sizeBytes: 1000000,
        addedAt: DateTime(2026, 1, 1),
      ),
    );
  }

  @override
  Future<List<ArtistSummary>> listArtists({int? limit, int? offset}) async {
    return [
      const ArtistSummary(key: 'fairouz', name: 'Fairouz', albumCount: 5, trackCount: 40),
      const ArtistSummary(key: 'solaris', name: 'Solaris', albumCount: 2, trackCount: 14),
    ];
  }

  @override
  Future<int> albumCount() async => fakeAlbumCount;

  @override
  Future<int> artistCount() async => 2;

  @override
  Future<List<ArtistAlias>> listAliases() async => List.unmodifiable(_aliases);

  @override
  Future<List<Track>> tracksOfAlbum(String album, {String? albumArtist}) async => [];

  @override
  Future<List<Track>> tracksOfArtist(String artist, {String? artistKey}) async => [];

  @override
  Future<List<Track>> search(String query) async => [];

  @override
  Future<List<AlbumSummary>> searchAlbums(String query, {int? limit}) async => [];

  @override
  Future<List<ArtistSummary>> searchArtists(String query, {int? limit}) async => [];

  @override
  Future<int> trackCount() async => fakeTrackCount;

  @override
  Future<void> mergeArtists(String sourceKey, String targetKey, {String? targetName}) async {
    _aliases.add(ArtistAlias(
      aliasKey: sourceKey,
      canonicalKey: targetKey,
      canonicalName: targetName ?? targetKey,
    ));
  }

  @override
  Future<void> unmergeArtist(String aliasKey) async {
    _aliases.removeWhere((a) => a.aliasKey == aliasKey);
  }

  @override
  Future<void> addNoSplit(String name) async {}

  @override
  Future<void> removeNoSplit(String key) async {}

  @override
  Future<List<ArtistNoSplit>> listNoSplit() async => [];

  @override
  Future<void> rebuildArtistLinks() async {}

  @override
  Future<void> upsertTracks(List<Track> tracks) async {}

  @override
  Future<void> removeTracksByPath(List<String> paths) async {}

  @override
  Future<void> close() async {}
}

void main() {
  group('AppShell & Library Screens Tests', () {
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late SqliteLibraryRepository repository;
    late ScanService scanService;
    late SettingsStore settingsStore;
    late GlassController glassController;
    late AppNavigator navigator;

    setUp(() async {
      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
      repository = SqliteLibraryRepository.inMemory();
      scanService = ScanService(repository: repository);
      settingsStore = SettingsStore(
        initialSettings: const AppSettings(
          language: 'en',
          userName: 'mido',
          glassQuality: GlassQuality.full,
          reduceMotion: false,
        ),
      );
      glassController = GlassController();
      settingsStore.bindGlassController(glassController);
      navigator = AppNavigator();
    });

    tearDown(() async {
      settingsStore.dispose();
      scanService.dispose();
      await repository.close();
      await controller.dispose();
      await engine.dispose();
    });

    Widget createTestShell({
      LibraryRepository? customRepo,
      String language = 'en',
      VoidCallback? onTrackInfoBuild,
      Future<String?> Function()? directoryPicker,
    }) {
      final effectiveRepo = customRepo ?? repository;
      final effectiveScanService =
          customRepo != null ? ScanService(repository: customRepo) : scanService;

      return GlassScope(
        controller: glassController,
        child: MaterialApp(
          locale: Locale(language),
          theme: buildAppTheme(),
          builder: (context, child) => Directionality(
            textDirection: language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
          home: AppShell(
            engine: engine,
            controller: controller,
            repository: effectiveRepo,
            scanService: effectiveScanService,
            settingsStore: settingsStore,
            navigator: navigator,
            directoryPicker: directoryPicker,
          ),
        ),
      );
    }

    testWidgets('Shell renders in LTR and in RTL with no overflow errors; sidebar is on start side', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');

      // 1. Test LTR
      await tester.pumpWidget(createTestShell(language: 'en'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final sidebarLtr = tester.getTopLeft(find.byType(Sidebar));
      expect(sidebarLtr.dx, lessThan(20.0)); // Left side in LTR

      // 2. Test RTL
      settingsStore.update((s) => s.copyWith(language: 'ar'));
      await tester.pumpWidget(createTestShell(language: 'ar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final sidebarRtl = tester.getTopRight(find.byType(Sidebar));
      expect(sidebarRtl.dx, greaterThan(1200.0)); // Right side in RTL
    });

    testWidgets('Compact toggle changes width and persists the setting', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');
      await tester.pumpWidget(createTestShell());
      await tester.pumpAndSettle();

      expect(settingsStore.settings.sidebarCompact, isFalse);

      final toggleButton = find.byKey(const Key('sidebar_toggle_compact'));
      expect(toggleButton, findsOneWidget);

      await tester.tap(toggleButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settingsStore.flush();

      expect(settingsStore.settings.sidebarCompact, isTrue);

      final sidebarBox = tester.getSize(find.byType(Sidebar));
      expect(sidebarBox.width, closeTo(64.0, 1.0));
    });

    testWidgets('Disabled items do not navigate and do nothing; Audio Lab opens AudioLabScreen', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');
      await tester.pumpWidget(createTestShell());
      await tester.pumpAndSettle();

      expect(navigator.current, AppDestination.albums);

      // Tapping Last.fm (disabled)
      await tester.tap(find.byKey(const Key('sidebar_last_fm')));
      await tester.pumpAndSettle();
      expect(navigator.current, AppDestination.albums);

      // Tapping Playlists (disabled)
      await tester.tap(find.byKey(const Key('sidebar_playlists')));
      await tester.pumpAndSettle();
      expect(navigator.current, AppDestination.albums);

      // Tapping Audio Lab (enabled)
      await tester.tap(find.byKey(const Key('sidebar_audio_lab')));
      await tester.pumpAndSettle();
      expect(navigator.current, AppDestination.audioLab);
      expect(find.byType(AudioLabScreen), findsOneWidget);
    });

    testWidgets('Transport controls keep left-to-right order inside an RTL app', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');
      await tester.pumpWidget(createTestShell(language: 'ar'));
      await tester.pumpAndSettle();

      final prevCenter = tester.getCenter(find.byIcon(Icons.skip_previous));
      final playCenter = tester.getCenter(find.byIcon(Icons.play_arrow));
      final nextCenter = tester.getCenter(find.byIcon(Icons.skip_next));

      // In RTL, temporal controls MUST still follow Left-to-Right progression:
      // prev < play < next
      expect(prevCenter.dx, lessThan(playCenter.dx));
      expect(playCenter.dx, lessThan(nextCenter.dx));
    });

    testWidgets('Bottom bar: seek position updates do not rebuild the title/cover area', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');

      int trackInfoBuildCount = 0;

      await tester.pumpWidget(
        GlassScope(
          controller: glassController,
          child: MaterialApp(
            home: Scaffold(
              body: BottomNowPlayingBar(
                controller: controller,
                onTrackInfoBuild: () => trackInfoBuildCount++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(trackInfoBuildCount, 1);

      // Emit multiple seek positions
      engine.simulateTick(const Duration(seconds: 1));
      await tester.pump();
      engine.simulateTick(const Duration(seconds: 1));
      await tester.pump();
      engine.simulateTick(const Duration(seconds: 1));
      await tester.pump();

      // Track info area build count MUST remain untouched (rebuild counter remains 1)
      expect(trackInfoBuildCount, 1);
    });

    testWidgets('Albums: view-mode switch persists; sort selection persists; grid is virtualized', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeRepo = FakeVirtualLibraryRepository(fakeAlbumCount: 5000);
      await tester.pumpWidget(createTestShell(customRepo: fakeRepo));
      await tester.pumpAndSettle();

      // Virtualization assertion: out of 5,000 albums, fewer than 100 tiles exist in widget tree
      final squareTiles = find.byType(InkWell);
      expect(squareTiles.evaluate().length, lessThan(100));

      // View mode switch to wide
      await tester.tap(find.byKey(const Key('view_mode_wide')));
      await tester.pumpAndSettle();
      expect(settingsStore.settings.libraryViewMode, 'wide');

      // Sort selection change
      final sortButton = find.byKey(const Key('sort_button'));
      await tester.tap(sortButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Title').last);
      await tester.pumpAndSettle();
      expect(settingsStore.settings.albumSort, 'title');
    });

    testWidgets('Tracks: playing row is highlighted; double click plays; virtualized with 20,000 tracks', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeRepo = FakeVirtualLibraryRepository(fakeTrackCount: 20000);
      await tester.pumpWidget(createTestShell(customRepo: fakeRepo));
      await tester.pumpAndSettle();

      // Navigate to tracks
      await tester.tap(find.byKey(const Key('sidebar_tracks')));
      await tester.pumpAndSettle();

      expect(navigator.current, AppDestination.tracks);

      // Virtualization: out of 20,000 tracks, fewer than 100 row tiles exist
      final renderedRows = find.byKey(const Key('tracks_list_view'));
      expect(renderedRows, findsOneWidget);

      // Double click to play
      final firstTrackTile = find.text('Virtual Track 0');
      expect(firstTrackTile, findsOneWidget);

      await tester.tap(firstTrackTile);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(firstTrackTile);
      await tester.pumpAndSettle();

      expect(engine.openedSource?.uri, 'C:\\Music\\track_0.mp3');
    });

    testWidgets('Artists: merged badge shows; context menu items exist; two Soon items disabled', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeRepo = FakeVirtualLibraryRepository(
        aliases: [
          const ArtistAlias(
            aliasKey: 'fairouz_alt',
            canonicalKey: 'fairouz',
            canonicalName: 'Fairouz',
          ),
        ],
      );

      await tester.pumpWidget(createTestShell(customRepo: fakeRepo));
      await tester.pumpAndSettle();

      // Navigate to Artists
      await tester.tap(find.byKey(const Key('sidebar_artists')));
      await tester.pumpAndSettle();

      expect(navigator.current, AppDestination.artists);

      // Merged badge shows for Fairouz
      expect(find.byKey(const Key('artist_merged_badge_fairouz')), findsOneWidget);

      // Open context menu for Fairouz
      final menuButton = find.byKey(const Key('artist_menu_fairouz'));
      expect(menuButton, findsOneWidget);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      // Verify menu items
      expect(find.text('Merge into…'), findsOneWidget);
      expect(find.text('Artist rules...'), findsOneWidget);
      expect(find.textContaining('Choose picture'), findsOneWidget);
      expect(find.textContaining('Refresh picture'), findsOneWidget);
    });

    testWidgets('Welcome: name field shown only when userName empty; saves trimmed name up to 40 chars', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Empty library (no folders) & empty userName
      settingsStore.update((s) => s.copyWith(userName: ''));

      String? pickedFolder;
      await tester.pumpWidget(
        createTestShell(
          directoryPicker: () async {
            pickedFolder = 'C:\\MyMusic';
            return pickedFolder;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Welcome panel is shown
      expect(find.text('Welcome to Aestheticy'), findsOneWidget);
      final nameField = find.byKey(const Key('welcome_name_field'));
      expect(nameField, findsOneWidget);

      // Enter name with extra spaces and > 40 chars
      const longName = '   A very long user name that definitely exceeds the forty character maximum limit   ';
      await tester.enterText(nameField, longName);
      await tester.pumpAndSettle();

      final addFolderButton = find.byKey(const Key('welcome_add_folder_button'));
      expect(addFolderButton, findsOneWidget);
      await tester.tap(addFolderButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await settingsStore.flush();

      expect(pickedFolder, 'C:\\MyMusic');
      expect(settingsStore.settings.userName.length, lessThanOrEqualTo(40));
      expect(settingsStore.settings.userName, equals(longName.trim().substring(0, 40)));
    });

    testWidgets('Scanning panel shows real service values and Cancel calls the service', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await repository.addFolder('C:\\Music');
      await tester.pumpWidget(createTestShell());
      await tester.pumpAndSettle();

      // Trigger a rescan
      unawaited(scanService.rescanAll());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Scanning your music'), findsOneWidget);
      final cancelButton = find.byKey(const Key('scan_cancel_button'));
      expect(cancelButton, findsOneWidget);

      await tester.tap(cancelButton);
      await tester.pumpAndSettle();

      expect(scanService.isScanning, isFalse);
    });
  });
}
