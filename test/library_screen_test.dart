import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/audio_lab/audio_lab_screen.dart';
import 'package:aestheticy/features/library/folder_management_sheet.dart';
import 'package:aestheticy/features/library/library_screen.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';

void main() {
  group('LibraryScreen Widget Tests', () {
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

    Future<void> seedTestData() async {
      final folder = await repository.addFolder('C:\\Music');
      final now = DateTime.now();

      await repository.upsertTracks([
        Track(
          path: 'C:\\Music\\Album1_Track1.mp3',
          folderId: folder.id!,
          title: 'Morning Sun',
          artist: 'Solaris',
          albumArtist: 'Solaris',
          album: 'Daybreak',
          trackNo: 1,
          durationMs: 180000,
          mtimeMs: 100,
          sizeBytes: 1000,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\Album1_Track2.mp3',
          folderId: folder.id!,
          title: 'Golden Horizon',
          artist: 'Solaris',
          albumArtist: 'Solaris',
          album: 'Daybreak',
          trackNo: 2,
          durationMs: 240000,
          mtimeMs: 100,
          sizeBytes: 1000,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\Album2_Track1.mp3',
          folderId: folder.id!,
          title: 'Night Sky',
          artist: 'Luna',
          albumArtist: 'Luna',
          album: 'Midnight',
          trackNo: 1,
          durationMs: 200000,
          mtimeMs: 100,
          sizeBytes: 1000,
          addedAt: now,
        ),
      ]);
      await repository.rebuildArtistLinks();
    }

    Widget createTestApp({Future<String?> Function()? directoryPicker}) {
      return MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF121212),
        ),
        home: LibraryScreen(
          engine: engine,
          controller: controller,
          repository: repository,
          scanService: scanService,
          directoryPicker: directoryPicker,
        ),
      );
    }

    testWidgets('empty-library state shows an Add folder prompt', (tester) async {
      String? pickedFolder;
      await tester.pumpWidget(
        createTestApp(
          directoryPicker: () async {
            pickedFolder = 'C:\\TestMusic';
            return pickedFolder;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Empty library prompt should be visible
      expect(find.text('Your music library is empty'), findsOneWidget);
      expect(
        find.text('Add a folder containing audio files to start listening.'),
        findsOneWidget,
      );

      final addFolderButton = find.byKey(const Key('empty_add_folder_button'));
      expect(addFolderButton, findsOneWidget);
      expect(find.text('Add folder'), findsOneWidget);

      // Tapping Add folder invokes the directory picker
      await tester.tap(addFolderButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(pickedFolder, 'C:\\TestMusic');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tabs render and can switch between Albums, Artists, Tracks', (tester) async {
      await seedTestData();
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Check all 3 tabs are present in AppBar
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Tracks'), findsOneWidget);

      // Credit "by mido" is visible
      expect(find.text('by mido'), findsWidgets);

      // Default tab: Albums. Albums should render
      expect(find.text('Daybreak'), findsOneWidget);
      expect(find.text('Midnight'), findsOneWidget);

      // Switch to Artists tab
      await tester.tap(find.text('Artists'));
      await tester.pumpAndSettle();
      expect(find.text('Solaris'), findsOneWidget);
      expect(find.text('Luna'), findsOneWidget);

      // Switch to Tracks tab
      await tester.tap(find.text('Tracks'));
      await tester.pumpAndSettle();
      expect(find.text('Morning Sun'), findsOneWidget);
      expect(find.text('Golden Horizon'), findsOneWidget);
      expect(find.text('Night Sky'), findsOneWidget);
    });

    testWidgets('search filters tracks, albums, and artists', (tester) async {
      await seedTestData();
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Initially on Albums tab, both Daybreak and Midnight are shown
      expect(find.text('Daybreak'), findsOneWidget);
      expect(find.text('Midnight'), findsOneWidget);

      // Type "Night" into the search field
      final searchField = find.byKey(const Key('library_search_field'));
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'Night');
      await tester.pumpAndSettle();

      // In Albums: only "Midnight" matches
      expect(find.text('Midnight'), findsOneWidget);
      expect(find.text('Daybreak'), findsNothing);

      // Switch to Tracks tab: only "Night Sky" matches
      await tester.tap(find.text('Tracks'));
      await tester.pumpAndSettle();
      expect(find.text('Night Sky'), findsOneWidget);
      expect(find.text('Morning Sun'), findsNothing);

      // Clear search
      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();

      // All tracks back
      expect(find.text('Morning Sun'), findsOneWidget);
      expect(find.text('Golden Horizon'), findsOneWidget);
      expect(find.text('Night Sky'), findsOneWidget);
    });

    testWidgets('search debounces 250ms before querying', (tester) async {
      await seedTestData();
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      final searchField = find.byKey(const Key('library_search_field'));
      await tester.enterText(searchField, 'Night');
      // Advance by 100ms: debounce timer has not fired yet
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Daybreak'), findsOneWidget);

      // Advance by another 200ms (total 300ms > 250ms)
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('Daybreak'), findsNothing);
      expect(find.text('Midnight'), findsOneWidget);
    });

    testWidgets('tapping a track inside Tracks tab plays the current list at right index', (tester) async {
      await seedTestData();
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Go to Tracks tab
      await tester.tap(find.text('Tracks'));
      await tester.pumpAndSettle();

      // Tap on track: "Morning Sun" (index 1 in titleAsc order)
      await tester.tap(find.text('Morning Sun'));
      await tester.pumpAndSettle();

      // Controller and engine should have opened "Morning Sun"
      expect(engine.openedSource?.uri, 'C:\\Music\\Album1_Track1.mp3');
      expect(queue.current?.uri, 'C:\\Music\\Album1_Track1.mp3');
      expect(queue.currentIndex, 1);
      // Queue replaced with the tracks list
      expect(queue.length, 3);
      expect(queue.items.map((s) => s.uri), [
        'C:\\Music\\Album1_Track2.mp3', // Golden Horizon
        'C:\\Music\\Album1_Track1.mp3', // Morning Sun
        'C:\\Music\\Album2_Track1.mp3', // Night Sky
      ]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('context rule: tapping inside an album plays that album at right index', (tester) async {
      await seedTestData();
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // On Albums tab: tap "Daybreak" album card
      await tester.tap(find.text('Daybreak'));
      await tester.pumpAndSettle();

      // We should now be in the AlbumDetailScreen
      expect(find.text('Play Album'), findsOneWidget);
      expect(find.text('Morning Sun'), findsOneWidget);
      expect(find.text('Golden Horizon'), findsOneWidget);
      // "Night Sky" is in album 2, so it shouldn't be here
      expect(find.text('Night Sky'), findsNothing);

      // Tap "Golden Horizon" (track #2 of the Daybreak album, index 1)
      await tester.tap(find.text('Golden Horizon'));
      await tester.pumpAndSettle();

      // Queue is replaced with ONLY the Daybreak album tracks!
      expect(queue.length, 2);
      expect(queue.items.map((s) => s.uri), [
        'C:\\Music\\Album1_Track1.mp3',
        'C:\\Music\\Album1_Track2.mp3',
      ]);
      expect(engine.openedSource?.uri, 'C:\\Music\\Album1_Track2.mp3');
      expect(queue.current?.uri, 'C:\\Music\\Album1_Track2.mp3');
      expect(queue.currentIndex, 1);
    });

    testWidgets('folder management sheet allows opening, adding, and rescanning', (tester) async {
      String? addedPath;
      await tester.pumpWidget(
        createTestApp(
          directoryPicker: () async {
            addedPath = 'C:\\PickedFolder';
            return addedPath;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Tap Manage Folders button in AppBar
      final manageButton = find.byKey(const Key('manage_folders_button'));
      expect(manageButton, findsOneWidget);
      await tester.tap(manageButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Folder management sheet opens
      expect(find.byType(FolderManagementSheet), findsOneWidget);
      expect(find.text('Music Folders'), findsOneWidget);
      expect(find.byKey(const Key('add_folder_button')), findsOneWidget);
      expect(find.byKey(const Key('rescan_button')), findsOneWidget);

      // Tap Add folder inside the sheet
      await tester.tap(find.byKey(const Key('add_folder_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(addedPath, 'C:\\PickedFolder');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Audio Lab Clear button clears only upcoming items while keeping playing track', (tester) async {
      queue.add(const AudioSource('file:///music/song1.mp3', extras: {'title': 'Song 1'}));
      queue.add(const AudioSource('file:///music/song2.mp3', extras: {'title': 'Song 2'}));
      queue.add(const AudioSource('file:///music/song3.mp3', extras: {'title': 'Song 3'}));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: AudioLabScreen(engine: engine, controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      // Start playing Song 1
      await tester.tap(find.text('Song 1'));
      await tester.pumpAndSettle();
      expect(engine.openedSource?.uri, 'file:///music/song1.mp3');
      expect(engine.openCallCount, 1);
      expect(queue.length, 3);

      // Tap Clear
      final clearButton = find.widgetWithText(TextButton, 'Clear');
      expect(clearButton, findsOneWidget);
      await tester.ensureVisible(clearButton);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      // Current track 'Song 1' must keep playing and was NOT reopened
      expect(engine.openCallCount, 1);
      expect(engine.openedSource?.uri, 'file:///music/song1.mp3');
      expect(queue.current?.uri, 'file:///music/song1.mp3');
      // Upcoming tracks ('Song 2' and 'Song 3') removed
      expect(queue.length, 1);
      expect(queue.items.map((s) => s.uri), ['file:///music/song1.mp3']);
    });
  });
}
