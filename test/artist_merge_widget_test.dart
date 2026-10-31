import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/library/artist_detail_screen.dart';
import 'package:aestheticy/features/library/library_screen.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';

void main() {
  group('Artist Merge & Rules Widget Tests', () {
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late SqliteLibraryRepository repository;
    late ScanService scanService;

    setUp(() async {
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
    });

    Widget createTestApp() {
      return MaterialApp(
        home: LibraryScreen(
          engine: engine,
          controller: controller,
          repository: repository,
          scanService: scanService,
        ),
      );
    }

    testWidgets('Merge artist action merges two artists via UI picker', (tester) async {
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

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Switch to Artists tab
      await tester.tap(find.text('Artists'));
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

      // Tap Artist rules button in AppBar
      final rulesButton = find.byKey(const Key('artist_rules_button'));
      expect(rulesButton, findsOneWidget);
      await tester.tap(rulesButton);
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

      final artists = await repository.listArtists();
      final soloArtist = artists.firstWhere((a) => a.name == 'Solo Artist');

      await tester.pumpWidget(
        MaterialApp(
          home: ArtistDetailScreen(
            artist: soloArtist,
            repository: repository,
            controller: controller,
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
  });
}
