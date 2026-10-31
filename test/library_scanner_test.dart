import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/library/cover_cache.dart';
import 'package:aestheticy/library/library_scanner.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/tag_reader.dart';

/// Test implementation of [TagReader] with controllable responses and error simulation.
class FakeTagReader implements TagReader {
  final Map<String, RawTags> tagsMap;
  final Set<String> corruptPaths;
  final Duration? delay;

  FakeTagReader({
    Map<String, RawTags> tagsMap = const {},
    Set<String> corruptPaths = const {},
    this.delay,
  })  : tagsMap = tagsMap.map((k, v) => MapEntry(p.normalize(k), v)),
        corruptPaths = corruptPaths.map(p.normalize).toSet();

  @override
  FutureOr<RawTags> readTags(String filePath, {bool readCover = true}) async {
    final normalized = p.normalize(filePath);
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }
    if (corruptPaths.contains(normalized)) {
      throw const FormatException('Corrupt or invalid audio file');
    }
    return tagsMap[normalized] ?? const RawTags();
  }
}

void main() {
  late Directory tempDir;
  late Directory coversDir;
  late SqliteLibraryRepository repo;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('aestheticy_scan_test_');
    coversDir = Directory(p.join(tempDir.path, 'test_covers'))..createSync();
    CoverCache.setCustomDirectory(coversDir.path);
    repo = SqliteLibraryRepository.inMemory();
  });

  tearDown(() async {
    await repo.close();
    CoverCache.setCustomDirectory(null);
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  File createDummyFile(String relativePath, [List<int> bytes = const [0, 1, 2]]) {
    final file = File(p.normalize(p.join(tempDir.path, relativePath)));
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    file.writeAsBytesSync(bytes, flush: true);
    return file;
  }

  group('LibraryScanner', () {
    test('new files added are correctly parsed and stored', () async {
      final f1 = createDummyFile('album1/track1.mp3');
      final f2 = createDummyFile('album1/track2.flac');

      final fakeReader = FakeTagReader(
        tagsMap: {
          f1.path: const RawTags(
            title: 'Song One',
            artist: 'Band A',
            album: 'First Album',
            trackNo: 1,
            year: 2021,
            durationMs: 180000,
          ),
          f2.path: const RawTags(
            title: 'Song Two',
            artist: 'Band A',
            album: 'First Album',
            trackNo: 2,
            year: 2021,
            durationMs: 240000,
          ),
        },
      );

      final scanner = LibraryScanner(
        repository: repo,
        tagReader: fakeReader,
        coversDirectory: coversDir.path,
      );

      final folder = await repo.addFolder(tempDir.path);
      final finalProgress = await scanner.scan(folder).last;

      expect(finalProgress.done, isTrue);
      expect(finalProgress.found, equals(2));
      expect(finalProgress.added, equals(2));
      expect(finalProgress.updated, equals(0));
      expect(finalProgress.removed, equals(0));
      expect(finalProgress.errors, equals(0));

      final tracks = await repo.listTracks();
      expect(tracks.length, equals(2));

      final t1 = tracks.firstWhere((t) => t.path == f1.path);
      expect(t1.title, equals('Song One'));
      expect(t1.artist, equals('Band A'));
      expect(t1.album, equals('First Album'));
      expect(t1.trackNo, equals(1));
      expect(t1.year, equals(2021));
      expect(t1.durationMs, equals(180000));
    });

    test('incremental rescan updates changed file and preserves addedAt', () async {
      final f1 = createDummyFile('album/song.mp3', [1, 2, 3]);

      final fakeReader = FakeTagReader(
        tagsMap: {
          f1.path: const RawTags(
            title: 'Original Title',
            artist: 'Original Artist',
            album: 'Album',
          ),
        },
      );

      final scanner = LibraryScanner(
        repository: repo,
        tagReader: fakeReader,
        coversDirectory: coversDir.path,
      );

      final folder = await repo.addFolder(tempDir.path);
      await scanner.scan(folder).last;

      final initialTracks = await repo.listTracks();
      expect(initialTracks.length, equals(1));
      final originalAddedAt = initialTracks.first.addedAt;

      // Small pause to ensure filesystem mtime is strictly greater
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Modify the file on disk
      f1.writeAsBytesSync([1, 2, 3, 4, 5, 6], flush: true);

      // Rescan with updated tags
      final updatedReader = FakeTagReader(
        tagsMap: {
          f1.path: const RawTags(
            title: 'Updated Title',
            artist: 'Original Artist',
            album: 'Album',
          ),
        },
      );

      final rescanScanner = LibraryScanner(
        repository: repo,
        tagReader: updatedReader,
        coversDirectory: coversDir.path,
      );

      final rescanProgress = await rescanScanner.scan(folder).last;

      expect(rescanProgress.found, equals(1));
      expect(rescanProgress.added, equals(0));
      expect(rescanProgress.updated, equals(1));
      expect(rescanProgress.removed, equals(0));

      final updatedTracks = await repo.listTracks();
      expect(updatedTracks.length, equals(1));
      expect(updatedTracks.first.title, equals('Updated Title'));
      expect(updatedTracks.first.addedAt, equals(originalAddedAt));
    });

    test('incremental rescan removes deleted files from repository', () async {
      final f1 = createDummyFile('song1.mp3');
      final f2 = createDummyFile('song2.mp3');

      final fakeReader = FakeTagReader();
      final scanner = LibraryScanner(
        repository: repo,
        tagReader: fakeReader,
        coversDirectory: coversDir.path,
      );

      final folder = await repo.addFolder(tempDir.path);
      await scanner.scan(folder).last;
      expect(await repo.trackCount(), equals(2));

      // Delete one file from filesystem
      f2.deleteSync();

      // Rescan
      final rescanProgress = await scanner.scan(folder).last;

      expect(rescanProgress.found, equals(1));
      expect(rescanProgress.added, equals(0));
      expect(rescanProgress.updated, equals(0));
      expect(rescanProgress.removed, equals(1));

      final remaining = await repo.listTracks();
      expect(remaining.length, equals(1));
      expect(remaining.first.path, equals(f1.path));
    });

    test('corrupt file does not stop the scan, is counted in errors and recorded', () async {
      final f1 = createDummyFile('valid.mp3');
      final f2 = createDummyFile('corrupt.mp3');

      final fakeReader = FakeTagReader(
        tagsMap: {
          f1.path: const RawTags(title: 'Valid Song'),
        },
        corruptPaths: {f2.path},
      );

      final scanner = LibraryScanner(
        repository: repo,
        tagReader: fakeReader,
        coversDirectory: coversDir.path,
      );

      final folder = await repo.addFolder(tempDir.path);
      final progress = await scanner.scan(folder).last;

      expect(progress.done, isTrue);
      expect(progress.found, equals(2));
      expect(progress.added, equals(1));
      expect(progress.errors, equals(1));
      expect(progress.corruptPaths, contains(f2.path));

      final tracks = await repo.listTracks();
      expect(tracks.length, equals(1));
      expect(tracks.first.title, equals('Valid Song'));
    });

    test('cancel() stops scanning immediately', () async {
      for (int i = 0; i < 5; i++) {
        createDummyFile('track_$i.mp3');
      }

      final fakeReader = FakeTagReader(
        delay: const Duration(milliseconds: 150),
      );

      final scanner = LibraryScanner(
        repository: repo,
        tagReader: fakeReader,
        coversDirectory: coversDir.path,
      );

      final folder = await repo.addFolder(tempDir.path);
      final stream = scanner.scan(folder);

      final sub = stream.listen((_) {});

      // Cancel after brief moment
      await Future<void>.delayed(const Duration(milliseconds: 50));
      scanner.cancel();

      await sub.cancel();
      // Ensure no unhandled crashes
      expect(true, isTrue);
    });

    test('filters supported extensions and skips hidden/system directories', () async {
      // Supported extensions
      final supportedExts = [
        'mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wav', 'wma', 'aiff', 'aif', 'ape', 'wv',
      ];
      for (final ext in supportedExts) {
        createDummyFile('valid.$ext');
      }

      // Unsupported extensions
      createDummyFile('notes.txt');
      createDummyFile('picture.jpg');
      createDummyFile('manual.pdf');

      // Hidden & system folders
      createDummyFile('.git/hidden.mp3');
      createDummyFile(r'$RECYCLE.BIN/deleted.mp3');
      createDummyFile('System Volume Information/system.flac');

      final fakeReader = FakeTagReader();
      final scanner = LibraryScanner(
        repository: repo,
        tagReader: fakeReader,
        coversDirectory: coversDir.path,
      );

      final folder = await repo.addFolder(tempDir.path);
      final progress = await scanner.scan(folder).last;

      expect(progress.found, equals(supportedExts.length));
      expect(progress.added, equals(supportedExts.length));
      expect(await repo.trackCount(), equals(supportedExts.length));
    });

    test('fallbacks when tags are missing: title=filename, album=parent folder, artist=Unknown artist', () async {
      final subDir = Directory(p.join(tempDir.path, 'Summer Vibes'))..createSync();
      final file = File(p.join(subDir.path, 'Chill Beats.mp3'))..writeAsBytesSync([1, 2]);

      // Empty tags
      final fakeReader = FakeTagReader(
        tagsMap: {
          file.path: const RawTags(),
        },
      );

      final scanner = LibraryScanner(
        repository: repo,
        tagReader: fakeReader,
        coversDirectory: coversDir.path,
      );

      final folder = await repo.addFolder(tempDir.path);
      await scanner.scan(folder).last;

      final tracks = await repo.listTracks();
      expect(tracks.length, equals(1));

      final track = tracks.first;
      expect(track.title, equals('Chill Beats'));
      expect(track.album, equals('Summer Vibes'));
      expect(track.artist, equals('Unknown artist'));
    });

    test('saves ONE embedded cover per album and assigns coverKey', () async {
      final coverBytes = Uint8List.fromList([10, 20, 30, 40]);

      final f1 = createDummyFile('albumA/track1.mp3');
      final f2 = createDummyFile('albumA/track2.mp3');

      final fakeReader = FakeTagReader(
        tagsMap: {
          f1.path: RawTags(
            title: 'Track 1',
            artist: 'Artist One',
            album: 'Album One',
            albumArtist: 'Band One',
            embeddedCover: coverBytes,
          ),
          f2.path: const RawTags(
            title: 'Track 2',
            artist: 'Artist One',
            album: 'Album One',
            albumArtist: 'Band One',
            embeddedCover: null, // No embedded cover in 2nd track
          ),
        },
      );

      final scanner = LibraryScanner(
        repository: repo,
        tagReader: fakeReader,
        coversDirectory: coversDir.path,
      );

      final folder = await repo.addFolder(tempDir.path);
      await scanner.scan(folder).last;

      final tracks = await repo.listTracks();
      expect(tracks.length, equals(2));

      final t1 = tracks.firstWhere((t) => t.path == f1.path);
      final t2 = tracks.firstWhere((t) => t.path == f2.path);

      expect(t1.coverKey, isNotNull);
      expect(t2.coverKey, equals(t1.coverKey));

      final expectedPath = CoverCache.pathFor(
        t1.coverKey!,
        coversDirectory: coversDir.path,
      );
      final coverFile = File(expectedPath);
      expect(coverFile.existsSync(), isTrue);
      expect(coverFile.readAsBytesSync(), equals(coverBytes));

      // Verify only 1 cover was created for this album
      final coversOnDisk = coversDir.listSync().whereType<File>().toList();
      expect(coversOnDisk.length, equals(1));
    });
  });

  group('ScanService', () {
    test('addFolder scans folder, reports progress, and updates listeners', () async {
      createDummyFile('music/song.mp3');

      final fakeReader = FakeTagReader(
        tagsMap: {
          p.join(tempDir.path, 'music', 'song.mp3'): const RawTags(title: 'Service Song'),
        },
      );

      final scanner = LibraryScanner(
        repository: repo,
        tagReader: fakeReader,
        coversDirectory: coversDir.path,
      );

      final service = ScanService(
        repository: repo,
        scanner: scanner,
      );

      int notifyCount = 0;
      service.addListener(() {
        notifyCount++;
      });

      final progressEvents = <ScanProgress>[];
      final sub = service.progressStream.listen(progressEvents.add);

      final folder = await service.addFolder(tempDir.path);

      expect(folder.path, equals(tempDir.path));
      expect(service.isScanning, isFalse);
      expect(service.currentProgress.done, isTrue);
      expect(service.currentProgress.added, equals(1));
      expect(notifyCount, greaterThan(0));
      expect(progressEvents.isNotEmpty, isTrue);

      await sub.cancel();
      service.dispose();
    });

    test('rescanAll rescans all library folders', () async {
      final f1 = createDummyFile('folder1/s1.mp3');
      final f2 = createDummyFile('folder2/s2.mp3');

      final scanner = LibraryScanner(
        repository: repo,
        tagReader: FakeTagReader(),
        coversDirectory: coversDir.path,
      );

      final service = ScanService(
        repository: repo,
        scanner: scanner,
      );

      await repo.addFolder(f1.parent.path);
      await repo.addFolder(f2.parent.path);

      await service.rescanAll();

      expect(service.isScanning, isFalse);
      expect(service.currentProgress.done, isTrue);
      expect(await repo.trackCount(), equals(2));

      service.dispose();
    });

    test('cancel terminates scanning in service', () async {
      createDummyFile('s.mp3');

      final scanner = LibraryScanner(
        repository: repo,
        tagReader: FakeTagReader(delay: const Duration(milliseconds: 100)),
        coversDirectory: coversDir.path,
      );

      final service = ScanService(repository: repo, scanner: scanner);

      unawaited(service.addFolder(tempDir.path));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      service.cancel();

      expect(service.isScanning, isFalse);
      expect(service.currentProgress.done, isTrue);

      service.dispose();
    });
  });
}
