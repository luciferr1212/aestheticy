import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/library/albums_view.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';

void main() {
  group('G2: AlbumSummary displayArtist Tests', () {
    late Directory tempDir;
    late SqliteLibraryRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('g2_test_');
      repository = SqliteLibraryRepository.inMemory();
    });

    tearDown(() async {
      await repository.close();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('listAlbums and searchAlbums compute displayArtist correctly', () async {
      final folder = await repository.addFolder('C:\\Music');
      final now = DateTime.now().toUtc();

      await repository.upsertTracks([
        // 1. No album_artist + one track artist -> displayArtist is that track artist
        Track(
          path: 'C:\\Music\\track1.mp3',
          folderId: folder.id!,
          album: 'Album Single',
          albumArtist: null,
          artist: 'Solo Singer',
          title: 'Song 1',
          durationMs: 1000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: now,
        ),
        // 2. No album_artist + two different track artists -> displayArtist is 'various'
        Track(
          path: 'C:\\Music\\track2a.mp3',
          folderId: folder.id!,
          album: 'Album Compilation',
          albumArtist: null,
          artist: 'Singer One',
          title: 'Comp 1',
          durationMs: 1000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\track2b.mp3',
          folderId: folder.id!,
          album: 'Album Compilation',
          albumArtist: null,
          artist: 'Singer Two',
          title: 'Comp 2',
          durationMs: 1000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: now,
        ),
        // 3. None -> displayArtist is null
        Track(
          path: 'C:\\Music\\track3.mp3',
          folderId: folder.id!,
          album: 'Album Empty',
          albumArtist: null,
          artist: null,
          title: 'Song Empty',
          durationMs: 1000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: now,
        ),
        // 4. Album with albumArtist unchanged
        Track(
          path: 'C:\\Music\\track4.mp3',
          folderId: folder.id!,
          album: 'Album Tagged',
          albumArtist: 'Band X',
          artist: 'Singer Y',
          title: 'Song Tagged',
          durationMs: 1000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: now,
        ),
      ]);

      final albums = await repository.listAlbums();
      final albumSingle = albums.firstWhere((a) => a.album == 'Album Single');
      final albumComp = albums.firstWhere((a) => a.album == 'Album Compilation');
      final albumEmpty = albums.firstWhere((a) => a.album == 'Album Empty');
      final albumTagged = albums.firstWhere((a) => a.album == 'Album Tagged');

      // Assertions
      expect(albumSingle.displayArtist, equals('Solo Singer'));
      expect(albumComp.displayArtist, equals('various'));
      expect(albumEmpty.displayArtist, isNull);
      expect(albumTagged.albumArtist, equals('Band X'));
      expect(albumTagged.displayArtist, equals('Band X'));

      // Verify searchAlbums computes identically
      final searchRes = await repository.searchAlbums('Album');
      final sSingle = searchRes.firstWhere((a) => a.album == 'Album Single');
      final sComp = searchRes.firstWhere((a) => a.album == 'Album Compilation');
      final sEmpty = searchRes.firstWhere((a) => a.album == 'Album Empty');
      final sTagged = searchRes.firstWhere((a) => a.album == 'Album Tagged');

      expect(sSingle.displayArtist, equals('Solo Singer'));
      expect(sComp.displayArtist, equals('various'));
      expect(sEmpty.displayArtist, isNull);
      expect(sTagged.displayArtist, equals('Band X'));

      // Verify tracksOfAlbum remains unchanged and finds tracks
      final tSingle = await repository.tracksOfAlbum('Album Single');
      expect(tSingle.length, equals(1));
      final tComp = await repository.tracksOfAlbum('Album Compilation');
      expect(tComp.length, equals(2));
      final tTagged = await repository.tracksOfAlbum('Album Tagged', albumArtist: 'Band X');
      expect(tTagged.length, equals(1));
    });

    testWidgets('AlbumsView and context.displayArtist render correct English and Arabic labels', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final folder = await repository.addFolder('C:\\Music');
      final now = DateTime.now().toUtc();

      await repository.upsertTracks([
        Track(
          path: 'C:\\Music\\t1.mp3',
          folderId: folder.id!,
          album: 'Album Single',
          artist: 'Solo Singer',
          title: 'Song 1',
          durationMs: 1000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\t2a.mp3',
          folderId: folder.id!,
          album: 'Album Compilation',
          artist: 'Singer One',
          title: 'Comp 1',
          durationMs: 1000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\t2b.mp3',
          folderId: folder.id!,
          album: 'Album Compilation',
          artist: 'Singer Two',
          title: 'Comp 2',
          durationMs: 1000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\t3.mp3',
          folderId: folder.id!,
          album: 'Album Empty',
          title: 'Empty',
          durationMs: 1000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\t4.mp3',
          folderId: folder.id!,
          album: 'Album Tagged',
          albumArtist: 'Band X',
          artist: 'Singer Y',
          title: 'Tagged',
          durationMs: 1000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: now,
        ),
      ]);

      final settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();
      final artistNameStore = ArtistNameStore(directory: tempDir);
      await artistNameStore.init();
      final navigator = AppNavigator();

      Widget buildApp({required String language}) {
        return MaterialApp(
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
        );
      }

      // 1. English
      settingsStore.update((s) => s.copyWith(language: 'en'));
      await tester.pumpWidget(buildApp(language: 'en'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Solo Singer'), findsOneWidget);
      expect(find.text('Various artists'), findsOneWidget);
      expect(find.text('Unknown Artist'), findsOneWidget);
      expect(find.text('Band X'), findsOneWidget);

      // 2. Arabic localization
      settingsStore.update((s) => s.copyWith(language: 'ar'));
      await tester.pumpWidget(buildApp(language: 'ar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Solo Singer'), findsOneWidget);
      expect(find.text('فنانون متعددون'), findsOneWidget);
      expect(find.text('فنان غير معروف'), findsOneWidget);
      expect(find.text('Band X'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      settingsStore.dispose();
      artistNameStore.dispose();
    });
  });
}
