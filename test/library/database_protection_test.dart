import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/database_protection.dart';
import 'package:aestheticy/library/sqlite/userdata_backup_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

void main() {
  group('S3: SQLite WAL, quick_check, and corruption recovery', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('db_protection_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('file-backed databases enable WAL and synchronous=NORMAL; inMemory uses memory journal',
        () async {
      final memRepo = SqliteLibraryRepository.inMemory();
      final memJournal = memRepo.rawDatabase
          .select('PRAGMA main.journal_mode;')
          .single
          .values
          .first
          .toString()
          .toLowerCase();
      expect(memJournal, equals('memory'));
      await memRepo.close();

      final libPath = p.join(tempDir.path, 'library.db');
      final fileRepo = SqliteLibraryRepository.openFile(libPath);
      final mainJournal = fileRepo.rawDatabase
          .select('PRAGMA main.journal_mode;')
          .single
          .values
          .first
          .toString()
          .toLowerCase();
      final userJournal = fileRepo.rawDatabase
          .select('PRAGMA userdata.journal_mode;')
          .single
          .values
          .first
          .toString()
          .toLowerCase();
      final mainSync = fileRepo.rawDatabase
          .select('PRAGMA main.synchronous;')
          .single
          .values
          .first;
      final userSync = fileRepo.rawDatabase
          .select('PRAGMA userdata.synchronous;')
          .single
          .values
          .first;

      expect(mainJournal, equals('wal'));
      expect(userJournal, equals('wal'));
      expect(mainSync, equals(1)); // NORMAL == 1
      expect(userSync, equals(1));
      await fileRepo.close();
    });

    test('corrupt library.db is moved aside, fresh library.db created, userdata preserved, and flag set',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final repo1 = SqliteLibraryRepository.openFile(libPath);
      final folder = await repo1.addFolder('C:\\Music');
      await repo1.upsertTracks([
        Track(
          path: 'C:\\Music\\song.mp3',
          folderId: folder.id!,
          title: 'Song',
          durationMs: 120000,
          mtimeMs: 1,
          sizeBytes: 1,
          addedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);
      await repo1.setFavorite('C:\\Music\\song.mp3', true);
      await repo1.close();

      // Replace library.db with garbage bytes
      File(libPath).writeAsBytesSync(List<int>.generate(256, (i) => i ^ 0xAA));

      final repo2 = SqliteLibraryRepository.openFile(
        libPath,
        clock: () => DateTime.utc(2026, 11, 26, 10, 15, 20),
      );
      addTearDown(repo2.close);

      expect(repo2.userDataAccessMode, equals(UserDataAccessMode.normal));
      expect(repo2.startupReport.libraryRecreatedAfterCorruption, isTrue);
      expect(repo2.startupReport.userDataRestoredFromBackup, isFalse);
      expect(await repo2.trackCount(), equals(0));
      // User data remains completely intact
      expect(await repo2.favoritePaths(), equals({'C:\\Music\\song.mp3'}));

      final corruptFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('library.db.corrupt-'))
          .toList();
      expect(corruptFiles, hasLength(1));
    });

    test('corrupt userdata.db restores newest valid backup (skipping corrupt newer backup)',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final userPath = p.join(tempDir.path, 'userdata.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));
      final userBackupsDir = Directory(p.join(backupsDir.path, 'userdata'));

      final repo1 = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
      );
      await repo1.setFavorite('C:\\Music\\preserved.mp3', true);
      await repo1.setRating('C:\\Music\\preserved.mp3', 5);
      final pl = await repo1.createPlaylist('Good Mix');
      await repo1.addToPlaylist(pl.id, ['C:\\Music\\preserved.mp3']);

      final backupSvc = SqliteUserDataBackupService(
        backupsUserDataDir: userBackupsDir,
        userDataDbPath: userPath,
        databaseProvider: () => repo1.rawDatabase,
      );
      final validBackup = await backupSvc.runDailyBackup(
        accessMode: UserDataAccessMode.normal,
        now: DateTime(2026, 11, 25),
      );
      expect(validBackup, isNotNull);
      await repo1.close();

      // Create a newer but CORRUPT backup on 2026-11-26 (must be skipped)
      File(p.join(userBackupsDir.path, 'userdata-20261126.db'))
          .writeAsStringSync('garbage backup bytes');

      // Corrupt live userdata.db
      File(userPath).writeAsStringSync('not a valid sqlite file');

      final repo2 = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
        clock: () => DateTime.utc(2026, 11, 26, 11, 0, 0),
      );
      addTearDown(repo2.close);

      expect(repo2.userDataAccessMode, equals(UserDataAccessMode.normal));
      expect(repo2.startupReport.userDataRestoredFromBackup, isTrue);
      expect(repo2.startupReport.userDataResetEmptyAfterCorruption, isFalse);
      expect(await repo2.favoritePaths(), equals({'C:\\Music\\preserved.mp3'}));
      expect(await repo2.allRatings(), equals({'C:\\Music\\preserved.mp3': 5}));
      expect((await repo2.listPlaylists()).single.name, equals('Good Mix'));

      final corruptFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('userdata.db.corrupt-'))
          .toList();
      expect(corruptFiles, hasLength(1));
    });

    test('corrupt userdata.db with no valid backup moves bad file aside and starts empty without crashing',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final userPath = p.join(tempDir.path, 'userdata.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));

      final repo1 = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
      );
      await repo1.setFavorite('C:\\Music\\lost.mp3', true);
      await repo1.close();

      File(userPath).writeAsStringSync('corrupted userdata');

      final repo2 = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
        clock: () => DateTime.utc(2026, 11, 26, 12, 0, 0),
      );
      addTearDown(repo2.close);

      expect(repo2.userDataAccessMode, equals(UserDataAccessMode.normal));
      expect(repo2.startupReport.userDataRestoredFromBackup, isFalse);
      expect(repo2.startupReport.userDataResetEmptyAfterCorruption, isTrue);
      expect(await repo2.favoritePaths(), isEmpty);

      final corruptFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('userdata.db.corrupt-'))
          .toList();
      expect(corruptFiles, hasLength(1));
    });

    test('locked userdata.db enters safeReadOnly without moving or corrupting userdata.db',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final userPath = p.join(tempDir.path, 'userdata.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));

      final repo1 = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
      );
      await repo1.setFavorite('C:\\Music\\locked_song.mp3', true);
      await repo1.close();

      // Hold an exclusive lock on userdata.db from another handle
      final locker = sqlite3.open(userPath);
      locker.execute('BEGIN EXCLUSIVE TRANSACTION;');
      var lockerClosed = false;
      addTearDown(() {
        if (!lockerClosed) {
          lockerClosed = true;
          try {
            locker.execute('ROLLBACK;');
          } catch (_) {}
          locker.close();
        }
      });

      final repo2 = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
      );
      addTearDown(repo2.close);

      expect(repo2.userDataAccessMode, equals(UserDataAccessMode.safeReadOnly));
      // Original userdata.db must NOT be quarantined as corrupt
      final corruptFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('userdata.db.corrupt-'))
          .toList();
      expect(corruptFiles, isEmpty);

      // Release lock and verify original userdata.db is still intact
      locker.execute('ROLLBACK;');
      locker.close();
      lockerClosed = true;
      await repo2.close();

      final repo3 = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
      );
      addTearDown(repo3.close);
      expect(repo3.userDataAccessMode, equals(UserDataAccessMode.normal));
      expect(
        await repo3.favoritePaths(),
        equals({'C:\\Music\\locked_song.mp3'}),
      );
    });

    test('S1: restore failure cases (copy, verify, rename) leave original corrupt userdata.db untouched, clean .restoring-* temp file, and enter safeReadOnly',
        () async {
      for (final mode in ['copy_fails', 'verify_fails', 'rename_fails']) {
        final caseDir = Directory(p.join(tempDir.path, mode))..createSync();
        final libPath = p.join(caseDir.path, 'library.db');
        final userPath = p.join(caseDir.path, 'userdata.db');
        final backupsDir = Directory(p.join(caseDir.path, 'backups'));
        final userBackupsDir = Directory(p.join(backupsDir.path, 'userdata'));

        final repo1 = SqliteLibraryRepository.openFile(
          libPath,
          userDataPath: userPath,
          backupsDir: backupsDir,
        );
        await repo1.setFavorite('C:\\Music\\ok.mp3', true);
        final backupSvc = SqliteUserDataBackupService(
          backupsUserDataDir: userBackupsDir,
          userDataDbPath: userPath,
          databaseProvider: () => repo1.rawDatabase,
        );
        expect(
          await backupSvc.runDailyBackup(
            accessMode: UserDataAccessMode.normal,
            now: DateTime(2026, 11, 25),
          ),
          isNotNull,
        );
        await repo1.close();

        // Write distinct corrupt payload so we can prove original stays untouched.
        final corruptBytes = 'corrupt-payload-$mode'.codeUnits;
        File(userPath).writeAsBytesSync(corruptBytes);

        final hooks = UserDataRestoreTestHooks(
          copyBackup: mode == 'copy_fails'
              ? (backup, dest) {
                  File(dest).writeAsStringSync('partial copy');
                  throw const FileSystemException('Simulated disk full on copy');
                }
              : null,
          verifyRestoringFile: mode == 'verify_fails'
              ? (_) => const QuickCheckResult(
                    QuickCheckStatus.corrupt,
                    'Simulated quick_check failure on restoring temp',
                  )
              : null,
          renameIntoPlace: mode == 'rename_fails'
              ? (_, _) =>
                  throw const FileSystemException('Simulated lock on rename')
              : null,
        );

        final repo2 = SqliteLibraryRepository.openFile(
          libPath,
          userDataPath: userPath,
          backupsDir: backupsDir,
          clock: () => DateTime.utc(2026, 11, 26, 9, 0, 0),
          restoreHooks: hooks,
        );
        addTearDown(repo2.close);

        expect(repo2.userDataAccessMode, equals(UserDataAccessMode.safeReadOnly));
        expect(repo2.startupReport.userDataRestoredFromBackup, isFalse);

        // Original corrupt file stays at original path with exact original bytes.
        expect(File(userPath).existsSync(), isTrue);
        expect(File(userPath).readAsBytesSync(), equals(corruptBytes));

        // No .restoring-* or .corrupt-* files remain.
        final files = caseDir.listSync().whereType<File>().map((f) => p.basename(f.path)).toList();
        expect(files.where((n) => n.contains('.restoring-')), isEmpty);
        expect(files.where((n) => n.contains('.corrupt-')), isEmpty);
      }
    });

    test('S1: startup cleans leftover .restoring-* temp files matching exact pattern and leaves unrelated files intact',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final userPath = p.join(tempDir.path, 'userdata.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));

      final repo1 = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
      );
      await repo1.setFavorite('C:\\Music\\kept.mp3', true);
      await repo1.close();

      final leftover1 = File('$userPath.restoring-20261125-010203')
        ..writeAsStringSync('stale temp 1');
      final leftover2 = File('$userPath.restoring-20261125-010203-42')
        ..writeAsStringSync('stale temp 2');
      final unrelated = File('$userPath.restoring-note.txt')
        ..writeAsStringSync('do not touch');
      final otherUserFile = File(p.join(tempDir.path, 'notes.txt'))
        ..writeAsStringSync('keep me');

      final repo2 = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
      );
      addTearDown(repo2.close);

      expect(repo2.userDataAccessMode, equals(UserDataAccessMode.normal));
      expect(await repo2.favoritePaths(), equals({'C:\\Music\\kept.mp3'}));
      expect(leftover1.existsSync(), isFalse);
      expect(leftover2.existsSync(), isFalse);
      expect(unrelated.existsSync(), isTrue);
      expect(otherUserFile.existsSync(), isTrue);
    });
  });
}
