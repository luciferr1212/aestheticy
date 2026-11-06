import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aestheticy/features/collections/m3u.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../library/fake_library_repository.dart';

void main() {
  group('M3U Pure Functions', () {
    test('Pure Parser handles UTF-8 BOM, CRLF, comments, and relative paths', () {
      const content =
          '\uFEFF#EXTM3U\r\n'
          '#PLAYLIST:My Favorites\r\n'
          '#EXTINF:180,Artist One - Song One\r\n'
          'song1.mp3\r\n'
          '# A random comment\r\n'
          '#EXTINF:240,Artist Two - Song Two\r\n'
          'subfolder/song2.flac\r\n'
          '#EXTINF:-1,Web Stream\r\n'
          'http://stream.example.com/live.mp3\r\n'
          'https://secure.stream.com/radio\r\n'
          'C:\\Music\\absolute.mp3\r\n';

      final result = M3u.parseM3u(content, baseDirectory: 'D:/Playlists');

      expect(result.playlistName, equals('My Favorites'));
      expect(result.skippedWebLinks, equals(2));
      expect(result.paths.length, equals(3));
      // First relative path
      expect(result.paths[0], contains('song1.mp3'));
      // Second relative path
      expect(result.paths[1], contains('subfolder'));
      expect(result.paths[1], contains('song2.flac'));
      // Third absolute path
      expect(result.paths[2], equals('C:/Music/absolute.mp3'));
    });

    test('Pure Parser handles empty file, spaces, and Arabic text', () {
      final emptyResult = M3u.parseM3u('', baseDirectory: 'C:/Music');
      expect(emptyResult.paths, isEmpty);
      expect(emptyResult.playlistName, isNull);
      expect(emptyResult.skippedWebLinks, equals(0));

      const arabicContent =
          '#EXTM3U\n'
          '#PLAYLIST:أغاني مختارة\n'
          '#EXTINF:210,فيروز - نسم علينا الهوا\n'
          'فيروز/نسم علينا الهوا.mp3\n';

      final result = M3u.parseM3u(arabicContent, baseDirectory: 'C:/Music');
      expect(result.playlistName, equals('أغاني مختارة'));
      expect(result.paths.length, equals(1));
      expect(result.paths.first, contains('نسم علينا الهوا.mp3'));
    });

    test('Pure Serializer roundtrips entries and handles missing tracks with -1 duration', () {
      final track1 = Track(
        id: 1,
        folderId: 1,
        path: 'C:/Music/song1.mp3',
        durationMs: 180000,
        title: 'Song One',
        artist: 'Artist One',
        album: 'Album One',
        mtimeMs: 0,
        sizeBytes: 1000,
        addedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

      final entries = [
        PlaylistEntry(
          entryId: 1,
          position: 1,
          path: track1.path,
          track: track1,
        ),
        const PlaylistEntry(
          entryId: 2,
          position: 2,
          path: 'C:/Music/missing_track.mp3',
          track: null,
        ),
      ];

      final serialized = M3u.buildM3u(entries, playlistName: 'Road Trip');

      expect(serialized, startsWith('#EXTM3U\n#PLAYLIST:Road Trip\n'));
      expect(serialized, contains('#EXTINF:180,Artist One - Song One\nC:/Music/song1.mp3'));
      expect(serialized, contains('#EXTINF:-1,missing_track\nC:/Music/missing_track.mp3'));

      // Roundtrip parser
      final parsed = M3u.parseM3u(serialized, baseDirectory: 'C:/Music');
      expect(parsed.playlistName, equals('Road Trip'));
      expect(parsed.paths, equals(['C:/Music/song1.mp3', 'C:/Music/missing_track.mp3']));
    });
  });

  group('M3U Service Helpers (Import & Export)', () {
    late Directory tempDir;
    late FakeLibraryRepository repo;
    late UserCollections collections;

    final track1 = Track(
      id: 1,
      folderId: 1,
      path: 'C:/Music/song1.mp3',
      durationMs: 180000,
      title: 'Song One',
      artist: 'Artist One',
      album: 'Album One',
      mtimeMs: 0,
      sizeBytes: 1000,
      addedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('m3u_service_test_');
      repo = FakeLibraryRepository();
      await repo.addFolder('C:/Music');
      await repo.upsertTracks([track1]);

      collections = UserCollections(repository: repo);
      await collections.init();
    });

    tearDown(() {
      collections.dispose();
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets(
      'M3u.exportPlaylist writes UTF-8 BOM file and displays success snackbar',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final pl = await collections.createPlaylist('Export Playlist');
        await collections.addToPlaylist(pl.id, [track1.path]);

        Uint8List? exportedBytes;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            supportedLocales: const [Locale('en'), Locale('ar')],
            theme: buildAppTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    key: const Key('trigger_export_button'),
                    onPressed: () async {
                      await M3u.exportPlaylist(
                        context,
                        repository: repo,
                        playlist: pl,
                        saveFilePicker: ({
                          required String fileName,
                          required Uint8List bytes,
                          String? dialogTitle,
                        }) async {
                          exportedBytes = bytes;
                          return 'C:/Export/$fileName';
                        },
                      );
                    },
                    child: const Text('Export'),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('trigger_export_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Playlist exported successfully'), findsOneWidget);
        expect(exportedBytes, isNotNull);

        // Starts with UTF-8 BOM: 0xEF, 0xBB, 0xBF
        expect(exportedBytes![0], equals(0xEF));
        expect(exportedBytes![1], equals(0xBB));
        expect(exportedBytes![2], equals(0xBF));

        final stringContent = utf8.decode(exportedBytes!);
        expect(stringContent, contains('#PLAYLIST:Export Playlist'));
        expect(stringContent, contains(track1.path));

        // Advance past snackbar dismiss timer
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'M3u.importPlaylist imports file, deduplicates name, and reports result',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        // Pre-create playlist with name 'Chill' to test deduplication
        await collections.createPlaylist('Chill');

        const m3uContent =
            '#EXTM3U\n'
            '#PLAYLIST:Chill\n'
            '#EXTINF:180,Artist One - Song One\n'
            'C:/Music/song1.mp3\n'
            '#EXTINF:-1,Missing File\n'
            'C:/Music/missing_song.mp3\n'
            'http://radio.example.com/stream\n';

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            supportedLocales: const [Locale('en'), Locale('ar')],
            theme: buildAppTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    key: const Key('trigger_import_button'),
                    onPressed: () async {
                      await M3u.importPlaylist(
                        context,
                        repository: repo,
                        collections: collections,
                        pickFilesPicker: ({
                          String? dialogTitle,
                          List<String>? allowedExtensions,
                          bool allowMultiple = false,
                        }) async {
                          return const ['C:/Music/chill.m3u8'];
                        },
                        fileContentReader: (path) async => m3uContent,
                      );
                    },
                    child: const Text('Import'),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('trigger_import_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Expect deduplicated playlist name 'Chill (2)'
        final importedPl =
            collections.playlists.firstWhere((p) => p.name == 'Chill (2)');
        expect(importedPl, isNotNull);

        final entries = await repo.playlistEntries(importedPl.id);
        expect(entries.length, 2);
        // Track 1 found in library
        expect(entries[0].track, isNotNull);
        // Track 2 missing from library
        expect(entries[1].track, isNull);

        // Snackbar reports: 2 tracks added, 1 not in library, 1 web link skipped
        expect(
          find.text('Added 2 tracks (1 not in library, 1 web links skipped)'),
          findsOneWidget,
        );

        // Advance past snackbar dismiss timer
        await tester.pump(const Duration(seconds: 5));
      },
    );
  });
}
