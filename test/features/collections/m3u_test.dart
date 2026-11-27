import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aestheticy/core/result.dart';
import 'package:aestheticy/features/collections/m3u.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/library/file_path_utils.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
      // Third absolute path (preserves valid Windows backslashes)
      expect(result.paths[2], equals(r'C:\Music\absolute.mp3'));
    });

    test('Pure Parser preserves Windows backslash paths, resolves relative against playlist folder, decodes file:// URIs, and extracts #EXTINF', () {
      const content =
          '\uFEFF#EXTM3U\r\n'
          '#PLAYLIST:Windows Mix\r\n'
          '#EXTINF:205,Fairuz - El Bosta\r\n'
          'subfolder\\track1.mp3\r\n'
          '#EXTINF:150,Absolute Track\r\n'
          'D:\\Library\\Jazz\\track2.flac\r\n'
          '#EXTINF:180,URI Song\r\n'
          'file:///C:/Music/Artist%20One/My%20Song.mp3\r\n'
          '#EXTINF:210,UNC Song\r\n'
          'file://nas-server/Audio/share_song.wav\r\n'
          '#EXTINF:95,POSIX URI\r\n'
          'file:///home/user/audio/track%20posix.ogg\r\n';

      final result = M3u.parseM3u(content, baseDirectory: r'C:\Playlists\Mixed');

      expect(result.playlistName, equals('Windows Mix'));
      expect(result.paths.length, equals(5));
      expect(result.paths[0], equals(r'C:\Playlists\Mixed\subfolder\track1.mp3'));
      expect(result.paths[1], equals(r'D:\Library\Jazz\track2.flac'));
      expect(result.paths[2], equals(r'C:\Music\Artist One\My Song.mp3'));
      expect(result.paths[3], equals(r'\\nas-server\Audio\share_song.wav'));
      expect(result.paths[4], equals('/home/user/audio/track posix.ogg'));

      expect(result.extinfTitles[result.paths[0]], equals('Fairuz - El Bosta'));
      expect(result.extinfTitles[result.paths[1]], equals('Absolute Track'));
      expect(result.extinfTitles[result.paths[2]], equals('URI Song'));
      expect(result.extinfTitles[result.paths[3]], equals('UNC Song'));
      expect(result.extinfTitles[result.paths[4]], equals('POSIX URI'));

      expect(
        FilePathUtils.canonicalKey('file:///C:/Music/Artist%20One/My%20Song.mp3'),
        equals(FilePathUtils.canonicalKey(r'C:\Music\Artist One\My Song.mp3')),
      );
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
                          return p.join(tempDir.path, fileName);
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

    testWidgets(
      'M3u.importPlaylistWithSummary resolves relative Windows paths, file:// URIs, and reports missing paths',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final plRepoTrack = Track(
          id: 9,
          folderId: 1,
          path: r'C:\Playlists\Folder\found song.mp3',
          durationMs: 120000,
          title: 'Found Song',
          artist: 'Tester',
          mtimeMs: 0,
          sizeBytes: 100,
          addedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
        await repo.upsertTracks([plRepoTrack]);

        const m3uContent =
            '\uFEFF#EXTM3U\r\n'
            '#PLAYLIST:Summary Mix\r\n'
            '#EXTINF:120,Tester - Found Song\r\n'
            'file:///C:/Playlists/Folder/found%20song.mp3\r\n'
            '#EXTINF:-1,Missing Relative\r\n'
            'nested\\absent_song.flac\r\n';

        M3uImportSummary? summary;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            supportedLocales: const [Locale('en'), Locale('ar')],
            theme: buildAppTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    key: const Key('trigger_summary_import'),
                    onPressed: () async {
                      summary = await M3u.importPlaylistWithSummary(
                        context,
                        repository: repo,
                        collections: collections,
                        pickFilesPicker: ({
                          String? dialogTitle,
                          List<String>? allowedExtensions,
                          bool allowMultiple = false,
                        }) async {
                          return const [r'C:\Playlists\Folder\mix.m3u8'];
                        },
                        fileContentReader: (path) async => m3uContent,
                      );
                    },
                    child: const Text('Import Summary'),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('trigger_summary_import')));
        await tester.pumpAndSettle();

        expect(summary, isNotNull);
        expect(summary!.playlist?.name, equals('Summary Mix'));
        expect(summary!.addedCount, equals(2));
        expect(summary!.missingCount, equals(1));
        expect(
          summary!.missingPaths,
          equals([r'C:\Playlists\Folder\nested\absent_song.flac']),
        );
        expect(summary!.skippedWebLinks, equals(0));
        expect(
          find.text('Added 2 tracks (1 not in library, 0 web links skipped)'),
          findsOneWidget,
        );
      },
    );

    test('M3u.validateExportTarget forces .m3u8 and refuses all known audio extensions and existing non-playlist files', () {
      const audioExts = [
        '.mp3', '.flac', '.m4a', '.wav', '.ogg', '.opus', '.wma',
        '.aac', '.alac', '.ape', '.wv', '.aiff', '.dsf', '.dff',
      ];
      for (final ext in audioExts) {
        final resUpper = M3u.validateExportTarget(
          p.join(tempDir.path, 'track${ext.toUpperCase()}'),
          fileExists: (_) => false,
        );
        expect(resUpper.isAllowed, isFalse, reason: 'Should refuse $ext');
        expect(resUpper.refusalReason, equals(M3uExportRefusalReason.audioExtension));
        expect(resUpper.extension, equals(ext));
      }

      // Existing non-playlist file must be refused
      final existingTxt = File(p.join(tempDir.path, 'notes.txt'))
        ..writeAsStringSync('keep me');
      final nonPlaylistRes = M3u.validateExportTarget(existingTxt.path);
      expect(nonPlaylistRes.isAllowed, isFalse);
      expect(
        nonPlaylistRes.refusalReason,
        equals(M3uExportRefusalReason.existingNonPlaylistFile),
      );
      expect(nonPlaylistRes.fileName, equals('notes.txt'));

      // Target without extension forces .m3u8
      final noExtRes = M3u.validateExportTarget(
        p.join(tempDir.path, 'NoExtPlaylist'),
        fileExists: (_) => false,
      );
      expect(noExtRes.isAllowed, isTrue);
      expect(
        noExtRes.targetPath,
        equals(p.join(tempDir.path, 'NoExtPlaylist.m3u8')),
      );
      expect(noExtRes.requiresOverwriteConfirmation, isFalse);
    });

    testWidgets(
      'M3u.exportPlaylist refuses audio extensions & existing non-playlist files with localized message',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final pl = await collections.createPlaylist('Safe List');
        await collections.addToPlaylist(pl.id, [track1.path]);

        final existingOther = File(p.join(tempDir.path, 'readme.txt'))
          ..writeAsStringSync('original text');
        final existingAudio = File(p.join(tempDir.path, 'song.flac'))
          ..writeAsBytesSync(const [1, 2, 3, 4]);

        final settingsStore = SettingsStore(
          initialSettings: const AppSettings(language: 'en'),
        );
        addTearDown(settingsStore.dispose);

        String nextTarget = '';
        bool? lastExportResult;

        await tester.pumpWidget(
          SettingsScope(
            store: settingsStore,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      key: const Key('export_refuse_btn'),
                      onPressed: () async {
                        lastExportResult = await M3u.exportPlaylist(
                          context,
                          repository: repo,
                          playlist: pl,
                          saveFilePicker: ({
                            required String fileName,
                            required Uint8List bytes,
                            String? dialogTitle,
                          }) async =>
                              nextTarget,
                        );
                      },
                      child: const Text('Export'),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Refuse existing audio file (.flac)
        nextTarget = existingAudio.path;
        await tester.tap(find.byKey(const Key('export_refuse_btn')));
        await tester.pumpAndSettle();
        expect(lastExportResult, isFalse);
        expect(existingAudio.readAsBytesSync(), equals([1, 2, 3, 4]));
        expect(
          find.textContaining('Cannot export playlist over an audio file (.flac)'),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 5));

        // 2. Refuse existing non-playlist file (.txt)
        nextTarget = existingOther.path;
        await tester.tap(find.byKey(const Key('export_refuse_btn')));
        await tester.pumpAndSettle();
        expect(lastExportResult, isFalse);
        expect(existingOther.readAsStringSync(), equals('original text'));
        expect(
          find.textContaining('Cannot overwrite existing non-playlist file (readme.txt)'),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 5));

        // 3. Forced .m3u8 when no extension given
        nextTarget = p.join(tempDir.path, 'ForcedExtension');
        await tester.tap(find.byKey(const Key('export_refuse_btn')));
        await tester.pumpAndSettle();
        expect(lastExportResult, isTrue);
        final forcedFile = File(p.join(tempDir.path, 'ForcedExtension.m3u8'));
        expect(forcedFile.existsSync(), isTrue);
        expect(File(nextTarget).existsSync(), isFalse);
      },
    );

    testWidgets(
      'M3u.exportPlaylist prompts localized overwrite confirmation for existing .m3u/.m3u8 and writes atomically',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final pl = await collections.createPlaylist('Atomic List');
        await collections.addToPlaylist(pl.id, [track1.path]);

        final targetM3u = File(p.join(tempDir.path, 'existing.m3u'))
          ..writeAsStringSync('#OLD PLAYLIST CONTENT\n');

        final settingsStore = SettingsStore(
          initialSettings: const AppSettings(language: 'en'),
        );
        addTearDown(settingsStore.dispose);

        bool? exportResult;

        await tester.pumpWidget(
          SettingsScope(
            store: settingsStore,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      key: const Key('export_overwrite_btn'),
                      onPressed: () async {
                        exportResult = await M3u.exportPlaylist(
                          context,
                          repository: repo,
                          playlist: pl,
                          saveFilePicker: ({
                            required String fileName,
                            required Uint8List bytes,
                            String? dialogTitle,
                          }) async =>
                              targetM3u.path,
                        );
                      },
                      child: const Text('Overwrite Export'),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // First attempt: click Cancel on localized overwrite confirmation dialog
        await tester.tap(find.byKey(const Key('export_overwrite_btn')));
        await tester.pumpAndSettle();
        expect(find.text('Overwrite playlist file?'), findsOneWidget);
        expect(
          find.text('"existing.m3u" already exists. Do you want to replace it?'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(exportResult, isFalse);
        expect(targetM3u.readAsStringSync(), equals('#OLD PLAYLIST CONTENT\n'));

        // Second attempt: click Overwrite -> atomically replaces content without leaving .tmp files
        await tester.tap(find.byKey(const Key('export_overwrite_btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Overwrite'));
        await tester.pumpAndSettle();

        expect(exportResult, isTrue);
        final updatedBytes = targetM3u.readAsBytesSync();
        expect(updatedBytes[0], equals(0xEF));
        expect(updatedBytes[1], equals(0xBB));
        expect(updatedBytes[2], equals(0xBF));
        expect(utf8.decode(updatedBytes), contains('#PLAYLIST:Atomic List'));
        expect(utf8.decode(updatedBytes), contains(track1.path));

        final leftoverTmps = tempDir
            .listSync()
            .where((e) => p.extension(e.path) == '.tmp')
            .toList();
        expect(leftoverTmps, isEmpty);
      },
    );

    testWidgets(
      'M3u.importPlaylistWithSummaryResult returns Err(IoFailure) and surfaces ErrorPresenter on read failure',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final settingsStore = SettingsStore(
          initialSettings: const AppSettings(language: 'en'),
        );
        addTearDown(settingsStore.dispose);

        Result<M3uImportSummary?>? importResult;

        await tester.pumpWidget(
          SettingsScope(
            store: settingsStore,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    key: const Key('import_fail_btn'),
                    onPressed: () async {
                      importResult = await M3u.importPlaylistWithSummaryResult(
                        context,
                        repository: repo,
                        collections: collections,
                        pickFilesPicker: ({
                          String? dialogTitle,
                          List<String>? allowedExtensions,
                          bool allowMultiple = false,
                        }) async =>
                            [p.join(tempDir.path, 'broken.m3u8')],
                        fileContentReader: (_) => Future<String>.error(
                          const FileSystemException('cannot read'),
                        ),
                      );
                    },
                    child: const Text('Import Fail'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('import_fail_btn')));
        await tester.pumpAndSettle();

        expect(importResult, isNotNull);
        expect(importResult!.isErr, isTrue);
        expect(importResult!.errorOrNull, isA<IoFailure>());
        expect(importResult!.errorOrNull?.messageKey, equals('m3u.importFailed'));
        expect(find.text('Failed to import playlist'), findsOneWidget);
      },
    );
  });
}
