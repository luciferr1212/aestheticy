import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/library/cover_cache.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/library/albums_view.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';

void main() {
  group('G6: CoverCache Cold Start and Initialization Tests', () {
    late Directory tempCoversDir;
    late Directory tempSettingsDir;
    late SettingsStore settingsStore;
    late ArtistNameStore artistNameStore;
    late SqliteLibraryRepository repository;
    late AppNavigator navigator;

    setUp(() async {
      tempCoversDir = await Directory.systemTemp.createTemp('g6_covers_');
      tempSettingsDir = await Directory.systemTemp.createTemp('g6_settings_');
      settingsStore = SettingsStore(directory: tempSettingsDir);
      await settingsStore.init();
      artistNameStore = ArtistNameStore(directory: tempSettingsDir);
      await artistNameStore.init();
      repository = SqliteLibraryRepository.inMemory();
      navigator = AppNavigator();
    });

    tearDown(() async {
      CoverCache.resetForTesting();
      await repository.close();
      settingsStore.dispose();
      artistNameStore.dispose();
      if (tempCoversDir.existsSync()) {
        try {
          await tempCoversDir.delete(recursive: true);
        } catch (_) {}
      }
      if (tempSettingsDir.existsSync()) {
        try {
          await tempSettingsDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('ensureInitialized resolves covers directory without running a scan', () async {
      final key = CoverCache.computeCoverKey(albumArtist: 'Coldplay', album: 'Parachutes');
      final coverFile = File(p.join(tempCoversDir.path, '$key.jpg'));
      await coverFile.writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));

      // Reset static state to simulate cold start
      CoverCache.resetForTesting();

      // Call ensureInitialized with the covers directory
      await CoverCache.ensureInitialized(directory: tempCoversDir.path);

      // Verify hasCover and pathFor find the file WITHOUT running any scan
      expect(CoverCache.hasCover(key), isTrue);
      expect(CoverCache.pathFor(key), equals(coverFile.path));
    });

    test('pathFor and hasCover fail loudly if CoverCache is uninitialized', () {
      CoverCache.resetForTesting();
      expect(
        () => CoverCache.pathFor('any_key'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => CoverCache.hasCover('any_key'),
        throwsA(isA<StateError>()),
      );
    });

    testWidgets('Library view shows album cover on first build after simulated cold start', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final key = CoverCache.computeCoverKey(albumArtist: 'Adele', album: '21');
      final coverFile = File(p.join(tempCoversDir.path, '$key.jpg'));

      await tester.runAsync(() async {
        await coverFile.writeAsBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])); // minimal JPEG header

        // Insert track into repository
        final folder = await repository.addFolder('C:\\Music');
        final now = DateTime.now().toUtc();
        await repository.upsertTracks([
          Track(
            path: 'C:\\Music\\track1.mp3',
            folderId: folder.id!,
            album: '21',
            albumArtist: 'Adele',
            artist: 'Adele',
            title: 'Rolling in the Deep',
            durationMs: 228000,
            mtimeMs: 1,
            sizeBytes: 100,
            addedAt: now,
            coverKey: key,
          ),
        ]);

        // Simulate cold start and initialization
        CoverCache.resetForTesting();
        await CoverCache.ensureInitialized(directory: tempCoversDir.path);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScope(
            store: settingsStore,
            child: ArtistNameScope(
              store: artistNameStore,
              child: Scaffold(
                body: AlbumsView(
                  repository: repository,
                  settingsStore: settingsStore,
                  navigator: navigator,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Image.file should be found with the cover file, not the placeholder icon
      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.image, isA<ResizeImage>());
      final resizeImage = imageWidget.image as ResizeImage;
      expect(resizeImage.imageProvider, isA<FileImage>());
      final fileImage = resizeImage.imageProvider as FileImage;
      expect(fileImage.file.path, equals(coverFile.path));
      expect(find.byIcon(Icons.album), findsNothing);

      // Clean up widget tree
      await tester.pumpWidget(const SizedBox());
    });
  });
}
