import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/core/result.dart';
import 'package:aestheticy/library/library_scanner.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';

import 'fake_library_repository.dart';

class _ControlledFakeScanner extends LibraryScanner {
  final List<String> scannedFolderPaths = [];
  final Map<String, List<ScanProgress>> scriptedProgress = {};
  final Map<String, Completer<void>> folderGates = {};
  final List<String> removedWhenUncancelled = [];
  bool wasCancelled = false;

  _ControlledFakeScanner({required super.repository});

  @override
  void cancel() {
    wasCancelled = true;
    super.cancel();
    for (final gate in folderGates.values) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
  }

  @override
  Stream<ScanProgress> scan(dynamic folder) async* {
    final target = folder as LibraryFolder;
    scannedFolderPaths.add(target.path);

    final steps = scriptedProgress[target.path] ??
        const [
          ScanProgress(found: 1, processed: 0, done: false),
          ScanProgress(found: 1, processed: 1, done: true),
        ];

    for (var i = 0; i < steps.length; i++) {
      if (wasCancelled) {
        yield steps[i].copyWith(done: true);
        return;
      }
      if (i == 1) {
        final gate = folderGates[target.path];
        if (gate != null && !gate.isCompleted) {
          await gate.future;
        }
      }
      if (wasCancelled) {
        yield steps[i].copyWith(done: true);
        return;
      }
      yield steps[i];
    }

    if (!wasCancelled && removedWhenUncancelled.isNotEmpty) {
      await repository.removeTracksByPath(removedWhenUncancelled);
    }
  }
}

void main() {
  group('S3 Scanning Continuity & Cancellation', () {
    test('rescanAll keeps isScanning true across all folders and suppresses intermediate done events', () async {
      final repo = FakeLibraryRepository();
      await repo.addFolder(r'C:\Music\Folder1');
      await repo.addFolder(r'C:\Music\Folder2');

      final scanner = _ControlledFakeScanner(repository: repo)
        ..scriptedProgress[r'C:\Music\Folder1'] = const [
          ScanProgress(found: 2, processed: 1, done: false),
          ScanProgress(found: 2, processed: 2, done: true),
        ]
        ..scriptedProgress[r'C:\Music\Folder2'] = const [
          ScanProgress(found: 3, processed: 1, done: false),
          ScanProgress(found: 3, processed: 3, done: true),
        ];

      final gate1 = Completer<void>();
      final gate2 = Completer<void>();
      scanner.folderGates[r'C:\Music\Folder1'] = gate1;
      scanner.folderGates[r'C:\Music\Folder2'] = gate2;

      final scanService = ScanService(repository: repo, scanner: scanner);
      addTearDown(scanService.dispose);

      final isScanningHistory = <bool>[];
      final emittedDoneFlags = <bool>[];

      scanService.addListener(() {
        isScanningHistory.add(scanService.isScanning);
      });
      final sub = scanService.progressStream.listen((progress) {
        emittedDoneFlags.add(progress.done);
      });
      addTearDown(sub.cancel);

      final future = scanService.rescanAll();
      await Future<void>.delayed(Duration.zero);
      expect(scanService.isScanning, isTrue);

      // Finish folder 1 (note scripted folder1 last step has done: true!)
      gate1.complete();
      await Future<void>.delayed(Duration.zero);

      // Between folder 1 and folder 2, isScanning must STILL be true and no done: true emitted
      expect(scanner.scannedFolderPaths, equals([r'C:\Music\Folder1', r'C:\Music\Folder2']));
      expect(scanService.isScanning, isTrue);
      expect(isScanningHistory.where((v) => v == false), isEmpty);
      expect(emittedDoneFlags, everyElement(isFalse));

      // Finish folder 2
      gate2.complete();
      await future;

      expect(scanService.isScanning, isFalse);
      // Every notification before completion had isScanning == true; only final notification had false.
      expect(isScanningHistory.first, isTrue);
      expect(isScanningHistory.last, isFalse);
      expect(
        isScanningHistory.sublist(0, isScanningHistory.length - 1),
        everyElement(isTrue),
      );
      expect(emittedDoneFlags.last, isTrue);
      expect(emittedDoneFlags.where((d) => d == true).length, equals(1));
    });

    test('cancelling rescanAll skips remaining folders and never removes tracks in unscanned folders', () async {
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);

      final f1 = await repo.addFolder(r'C:\Music\Folder1');
      final f2 = await repo.addFolder(r'C:\Music\Folder2');
      await repo.upsertTracks([
        Track(
          path: r'C:\Music\Folder1\track1.mp3',
          folderId: f1.id!,
          title: 'Track 1',
          artist: 'Artist 1',
          durationMs: 120000,
          mtimeMs: 10,
          sizeBytes: 100,
          addedAt: DateTime.utc(2026, 1, 1),
        ),
        Track(
          path: r'C:\Music\Folder2\track2.mp3',
          folderId: f2.id!,
          title: 'Track 2',
          artist: 'Artist 2',
          durationMs: 120000,
          mtimeMs: 10,
          sizeBytes: 100,
          addedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);

      final scanner = _ControlledFakeScanner(repository: repo)
        ..removedWhenUncancelled.add(r'C:\Music\Folder1\track1.mp3');
      final gate1 = Completer<void>();
      scanner.folderGates[r'C:\Music\Folder1'] = gate1;

      final scanService = ScanService(repository: repo, scanner: scanner);
      addTearDown(scanService.dispose);

      final future = scanService.rescanAll();
      await Future<void>.delayed(Duration.zero);
      expect(scanService.isScanning, isTrue);

      scanService.cancel();
      await future;

      expect(scanService.isScanning, isFalse);
      expect(scanner.scannedFolderPaths, equals([r'C:\Music\Folder1']));

      final remaining = await repo.listTracks();
      expect(
        remaining.map((t) => t.path).toList(),
        containsAll([
          r'C:\Music\Folder1\track1.mp3',
          r'C:\Music\Folder2\track2.mp3',
        ]),
      );
    });

    test('computeMissingPaths returns empty when cancelled or unreadable dirs present, and detects missing only on complete clean scans', () {
      const existing = [
        r'C:\Music\seen.mp3',
        r'C:\Music\unscanned.mp3',
      ];
      const scanned = {r'C:\Music\seen.mp3'};

      expect(
        computeMissingPaths(
          existingPaths: existing,
          scannedPaths: scanned,
          isCancelled: true,
          unreadableDirsCount: 0,
        ),
        isEmpty,
      );

      expect(
        computeMissingPaths(
          existingPaths: existing,
          scannedPaths: scanned,
          isCancelled: false,
          unreadableDirsCount: 1,
        ),
        isEmpty,
      );

      expect(
        computeMissingPaths(
          existingPaths: existing,
          scannedPaths: scanned,
          isCancelled: false,
          unreadableDirsCount: 0,
        ),
        equals([r'C:\Music\unscanned.mp3']),
      );
    });

    test('real LibraryScanner keeps tracks in folder when cancelled mid-scan', () async {
      final tempDir = await Directory.systemTemp.createTemp('scan_cancel_test_');
      addTearDown(() async {
        try {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        } catch (_) {}
      });

      final coversDir = Directory(p.join(tempDir.path, 'covers'))..createSync();
      final musicDir = Directory(p.join(tempDir.path, 'music'))..createSync();
      final filePath = p.join(musicDir.path, 'ghost.mp3');

      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);

      final folder = await repo.addFolder(musicDir.path);
      // Pre-seed a DB track that is NOT present in musicDir; a completed clean
      // scan would mark it missing and delete it, whereas cancelling must keep it.
      await repo.upsertTracks([
        Track(
          path: filePath,
          folderId: folder.id!,
          title: 'Preserved On Cancel',
          artist: 'Artist',
          durationMs: 1000,
          mtimeMs: 1,
          sizeBytes: 1,
          addedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);

      final scanner = LibraryScanner(
        repository: repo,
        coversDirectory: coversDir.path,
      );
      final events = <ScanProgress>[];
      final stream = scanner.scan(folder);
      await for (final progress in stream) {
        events.add(progress);
        if (events.length == 1) {
          scanner.cancel();
        }
      }

      expect(await repo.trackCount(), equals(1));
      expect((await repo.listTracks()).single.path, equals(filePath));
    });

    test('addFolderResult returns Ok on success and Err(AppError) when repository fails',
        () async {
      final repo = SqliteLibraryRepository.inMemory();
      final tempDir = await Directory.systemTemp.createTemp('add_folder_res_');
      final musicDir = Directory(p.join(tempDir.path, 'music'))..createSync();
      final coversDir = Directory(p.join(tempDir.path, 'covers'))..createSync();
      addTearDown(() async {
        await repo.close();
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final scanService = ScanService(
        repository: repo,
        scanner: LibraryScanner(
          repository: repo,
          coversDirectory: coversDir.path,
        ),
      );
      addTearDown(scanService.dispose);

      final okRes = await scanService.addFolderResult(musicDir.path);
      expect(okRes.isOk, isTrue);
      expect(okRes.valueOrNull?.path, equals(musicDir.path));

      // Closing the DB forces addFolder to fail -> returns Err(DatabaseFailure)
      await repo.close();
      final errRes = await scanService.addFolderResult(musicDir.path);
      expect(errRes.isErr, isTrue);
      expect(errRes.errorOrNull, isA<DatabaseFailure>());
      expect(errRes.errorOrNull?.messageKey, equals('error.folderAddFailed'));
    });
  });
}
