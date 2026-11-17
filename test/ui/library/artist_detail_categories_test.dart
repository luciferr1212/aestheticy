import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/library/artist_detail_view.dart';
import 'package:aestheticy/ui/library/library_view_controls.dart';
import 'package:aestheticy/ui/library/sort_direction_button.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';

void main() {
  group('ArtistDetailView Release Categories (S3)', () {
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late SqliteLibraryRepository repository;
    late Directory tempDir;
    late SettingsStore settingsStore;
    late AppNavigator navigator;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_artist_cat_');
      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
      repository = SqliteLibraryRepository.inMemory();
      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();
      navigator = AppNavigator();
    });

    tearDown(() async {
      await repository.close();
      await controller.dispose();
      await engine.dispose();
      settingsStore.dispose();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    void setupDesktopViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    Widget buildTestWidget({
      required ArtistSummary artist,
      TextDirection textDirection = TextDirection.ltr,
    }) {
      return MaterialApp(
        home: Directionality(
          textDirection: textDirection,
          child: SettingsScope(
            store: settingsStore,
            child: Scaffold(
              body: ArtistDetailView(
                artist: artist,
                repository: repository,
                controller: controller,
                settingsStore: settingsStore,
                navigator: navigator,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'Chip row hides when only one category exists (e.g. only Albums)',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setupDesktopViewport(tester);
        final folder = await repository.addFolder('/music');
        final now = DateTime.now();

        // 7 tracks in one album -> Albums category only
        final tracks = List.generate(
          7,
          (i) => Track(
            path: '/music/track$i.mp3',
            folderId: folder.id!,
            title: 'Track $i',
            artist: 'Single Cat Artist',
            albumArtist: 'Single Cat Artist',
            album: 'Full Album',
            durationMs: 180000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
        );
        await repository.upsertTracks(tracks);
        await repository.rebuildArtistLinks();

        const artist = ArtistSummary(
          name: 'Single Cat Artist',
          trackCount: 7,
          albumCount: 1,
        );

        await tester.pumpWidget(buildTestWidget(artist: artist));
        await tester.pumpAndSettle();

        // Chip row should be hidden because only 1 category exists
        expect(find.byKey(const Key('artist_category_chip_all')), findsNothing);
      },
    );

    testWidgets(
      'Chip row displays categories with counts, filters track list, and clears on All',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setupDesktopViewport(tester);
        final folder = await repository.addFolder('/music');
        final now = DateTime.now();

        // 8 tracks in Album, 1 track as Single
        final albumTracks = List.generate(
          8,
          (i) => Track(
            path: '/music/album_track$i.mp3',
            folderId: folder.id!,
            title: 'Album Song $i',
            artist: 'Multi Cat Artist',
            albumArtist: 'Multi Cat Artist',
            album: 'Big Album',
            durationMs: 180000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
        );
        final singleTrack = Track(
          path: '/music/single.mp3',
          folderId: folder.id!,
          title: 'Lone Single',
          artist: 'Multi Cat Artist',
          albumArtist: 'Multi Cat Artist',
          album: 'Lone Single - Single',
          durationMs: 180000,
          mtimeMs: 1000,
          sizeBytes: 1024,
          addedAt: now,
        );

        await repository.upsertTracks([...albumTracks, singleTrack]);
        await repository.rebuildArtistLinks();

        const artist = ArtistSummary(
          name: 'Multi Cat Artist',
          trackCount: 9,
          albumCount: 2,
        );

        await tester.pumpWidget(buildTestWidget(artist: artist));
        await tester.pumpAndSettle();

        // Chip row is visible
        expect(find.byKey(const Key('artist_category_chip_all')), findsOneWidget);
        expect(find.byKey(const Key('artist_category_chip_albums')), findsOneWidget);
        expect(find.byKey(const Key('artist_category_chip_singles')), findsOneWidget);

        // Tap Singles chip -> filters to only Lone Single
        await tester.tap(find.byKey(const Key('artist_category_chip_singles')));
        await tester.pumpAndSettle();

        expect(find.text('Lone Single'), findsOneWidget);
        expect(find.text('Album Song 0'), findsNothing);

        // Tap All chip -> restores all tracks (Album Song 0 visible)
        await tester.tap(find.byKey(const Key('artist_category_chip_all')));
        await tester.pumpAndSettle();

        expect(find.text('Album Song 0'), findsOneWidget);
      },
    );

    testWidgets(
      'Category selection resets when artist changes in didUpdateWidget',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setupDesktopViewport(tester);
        final folder = await repository.addFolder('/music');
        final now = DateTime.now();

        // Artist One has a long album (>20 mins) and a single -> 2 categories
        // Artist Two also has an album (>20 mins) and a single -> 2 categories
        await repository.upsertTracks([
          Track(
            path: '/music/a1.mp3',
            folderId: folder.id!,
            title: 'Song A1',
            artist: 'Artist One',
            albumArtist: 'Artist One',
            album: 'Album 1',
            durationMs: 1300000, // > 20 mins -> Album
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
          Track(
            path: '/music/a2.mp3',
            folderId: folder.id!,
            title: 'Single A2',
            artist: 'Artist One',
            albumArtist: 'Artist One',
            album: 'Single - Single',
            durationMs: 180000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
          Track(
            path: '/music/b1.mp3',
            folderId: folder.id!,
            title: 'Song B1',
            artist: 'Artist Two',
            albumArtist: 'Artist Two',
            album: 'Album B',
            durationMs: 1300000, // > 20 mins -> Album
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
          Track(
            path: '/music/b2.mp3',
            folderId: folder.id!,
            title: 'Single B2',
            artist: 'Artist Two',
            albumArtist: 'Artist Two',
            album: 'Single B - Single',
            durationMs: 180000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
        ]);
        await repository.rebuildArtistLinks();

        const artist1 = ArtistSummary(
          name: 'Artist One',
          trackCount: 2,
          albumCount: 2,
        );
        const artist2 = ArtistSummary(
          name: 'Artist Two',
          trackCount: 2,
          albumCount: 2,
        );

        await tester.pumpWidget(buildTestWidget(artist: artist1));
        await tester.pumpAndSettle();

        // Select singles
        await tester.tap(find.byKey(const Key('artist_category_chip_singles')));
        await tester.pumpAndSettle();
        expect(find.text('Single A2'), findsOneWidget);
        expect(find.text('Song A1'), findsNothing);

        // Update widget with artist2
        await tester.pumpWidget(buildTestWidget(artist: artist2));
        await tester.pumpAndSettle();

        // Reset to All -> both tracks of Artist Two are visible
        expect(find.text('Single B2'), findsOneWidget);
        expect(find.text('Song B1'), findsOneWidget);
      },
    );

    testWidgets(
      'RTL rendering renders without overflow',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setupDesktopViewport(tester);
        final folder = await repository.addFolder('/music');
        final now = DateTime.now();

        await repository.upsertTracks([
          Track(
            path: '/music/ar1.mp3',
            folderId: folder.id!,
            title: 'أغنية عربية',
            artist: 'فنان عربي',
            albumArtist: 'فنان عربي',
            album: 'ألبوم أول',
            durationMs: 1300000, // > 20 mins -> Album
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
          Track(
            path: '/music/ar2.mp3',
            folderId: folder.id!,
            title: 'أغنية منفردة',
            artist: 'فنان عربي',
            albumArtist: 'فنان عربي',
            album: 'منفردة - Single',
            durationMs: 180000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
        ]);
        await repository.rebuildArtistLinks();

        const artist = ArtistSummary(
          name: 'فنان عربي',
          trackCount: 2,
          albumCount: 2,
        );

        await tester.pumpWidget(
          buildTestWidget(artist: artist, textDirection: TextDirection.rtl),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('artist_category_chip_all')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Lazy list builder handles 5000 tracks smoothly without eager build',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setupDesktopViewport(tester);
        final folder = await repository.addFolder('/music');
        final now = DateTime.now();

        // Insert batches of 1000 tracks
        for (var b = 0; b < 5; b++) {
          final batch = List.generate(
            1000,
            (i) {
              final idx = b * 1000 + i;
              return Track(
                path: '/music/big_$idx.mp3',
                folderId: folder.id!,
                title: 'Massive Track $idx',
                artist: 'Huge Catalog Artist',
                albumArtist: 'Huge Catalog Artist',
                album: 'Huge Album ${idx ~/ 100}',
                durationMs: 180000,
                mtimeMs: 1000,
                sizeBytes: 1024,
                addedAt: now,
              );
            },
          );
          await repository.upsertTracks(batch);
        }
        await repository.rebuildArtistLinks();

        const artist = ArtistSummary(
          name: 'Huge Catalog Artist',
          trackCount: 5000,
          albumCount: 50,
        );

        await tester.pumpWidget(buildTestWidget(artist: artist));
        await tester.pumpAndSettle();

        // List builder builds only what fits in viewport
        expect(find.text('Massive Track 0'), findsOneWidget);
        expect(find.text('Massive Track 4999'), findsNothing);
      },
    );

    testWidgets(
      'LibraryViewControls takes natural width and aligns to start without stretching',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setupDesktopViewport(tester);
        final folder = await repository.addFolder('/music');
        final now = DateTime.now();

        await repository.upsertTracks([
          Track(
            path: '/music/w1.mp3',
            folderId: folder.id!,
            title: 'Song 1',
            artist: 'Width Test Artist',
            albumArtist: 'Width Test Artist',
            album: 'Album 1',
            durationMs: 180000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
        ]);
        await repository.rebuildArtistLinks();

        const artist = ArtistSummary(
          name: 'Width Test Artist',
          trackCount: 1,
          albumCount: 1,
        );

        await tester.pumpWidget(buildTestWidget(artist: artist));
        await tester.pumpAndSettle();

        final controlsFinder = find.byType(LibraryViewControls);
        expect(controlsFinder, findsOneWidget);

        final controlsSize = tester.getSize(controlsFinder);
        final detailSize = tester.getSize(find.byType(ArtistDetailView));

        // Natural width is significantly less than full page width
        expect(controlsSize.width, lessThan(detailSize.width * 0.6));
      },
    );

    testWidgets(
      'Category chips show track count for All and release count with track count for categories',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setupDesktopViewport(tester);
        final folder = await repository.addFolder('/music');
        final now = DateTime.now();

        // 8 tracks in Album, 1 Single -> 2 categories
        final albumTracks = List.generate(
          8,
          (i) => Track(
            path: '/music/album_track$i.mp3',
            folderId: folder.id!,
            title: 'Album Song $i',
            artist: 'Counts Artist',
            albumArtist: 'Counts Artist',
            album: 'Big Album',
            durationMs: 180000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
        );
        final singleTrack = Track(
          path: '/music/single.mp3',
          folderId: folder.id!,
          title: 'Lone Single',
          artist: 'Counts Artist',
          albumArtist: 'Counts Artist',
          album: 'Lone Single - Single',
          durationMs: 180000,
          mtimeMs: 1000,
          sizeBytes: 1024,
          addedAt: now,
        );

        await repository.upsertTracks([...albumTracks, singleTrack]);
        await repository.rebuildArtistLinks();

        const artist = ArtistSummary(
          name: 'Counts Artist',
          trackCount: 9,
          albumCount: 2,
        );

        await tester.pumpWidget(buildTestWidget(artist: artist));
        await tester.pumpAndSettle();

        // "All" chip shows track count
        expect(find.textContaining('All - 9 tracks'), findsOneWidget);

        // "Albums" chip shows 1 release and 8 tracks
        expect(find.textContaining('Albums - 1 releases'), findsOneWidget);
        expect(find.textContaining('- 8 tracks'), findsOneWidget);

        // "Singles" chip shows 1 release and 1 track
        expect(find.textContaining('Singles - 1 releases'), findsOneWidget);
        expect(find.textContaining('- 1 tracks'), findsOneWidget);
      },
    );

    testWidgets(
      'Sort defaults set natural directions on sort change',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setupDesktopViewport(tester);
        final folder = await repository.addFolder('/music');
        final now = DateTime.now();

        await repository.upsertTracks([
          Track(
            path: '/music/t1.mp3',
            folderId: folder.id!,
            title: 'Track A',
            artist: 'Sort Artist',
            album: 'Album A',
            durationMs: 180000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
        ]);
        await repository.rebuildArtistLinks();

        const artist = ArtistSummary(
          name: 'Sort Artist',
          trackCount: 1,
          albumCount: 1,
        );

        // Test SortDirection defaultReversedFor and defaultFor pure contracts
        expect(SortDirection.defaultReversedFor('mostPlayed'), isTrue);
        expect(SortDirection.defaultReversedFor('mostSongs'), isTrue);
        expect(SortDirection.defaultReversedFor('mostAlbums'), isTrue);
        expect(SortDirection.defaultReversedFor('recentlyAdded'), isTrue);
        expect(SortDirection.defaultReversedFor('year'), isTrue);

        expect(SortDirection.defaultReversedFor('title'), isFalse);
        expect(SortDirection.defaultReversedFor('album'), isFalse);
        expect(SortDirection.defaultReversedFor('name'), isFalse);
        expect(SortDirection.defaultReversedFor('duration'), isFalse);
        expect(SortDirection.defaultReversedFor('artist'), isFalse);

        expect(SortDirection.defaultFor('mostPlayed'), equals(SortDirection.descending));
        expect(SortDirection.defaultFor('title'), equals(SortDirection.ascending));

        // Test in ArtistDetailView: selecting a sort key sets its natural direction
        await tester.pumpWidget(buildTestWidget(artist: artist));
        await tester.pumpAndSettle();

        // Initial default: title ascending
        expect(settingsStore.settings.artistDetailTrackSort, equals('title'));
        expect(settingsStore.settings.artistDetailTrackSortReversed, isFalse);

        // Open sort menu and select 'Most played' -> defaults to descending (true)
        await tester.tap(find.byKey(const Key('sort_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Most played').last);
        await tester.pumpAndSettle();

        expect(settingsStore.settings.artistDetailTrackSort, equals('mostPlayed'));
        expect(settingsStore.settings.artistDetailTrackSortReversed, isTrue);

        // Open sort menu and select 'Duration' -> defaults to ascending (false)
        await tester.tap(find.byKey(const Key('sort_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Duration').last);
        await tester.pumpAndSettle();

        expect(settingsStore.settings.artistDetailTrackSort, equals('duration'));
        expect(settingsStore.settings.artistDetailTrackSortReversed, isFalse);
      },
    );
  });
}
