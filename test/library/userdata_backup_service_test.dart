import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/library/sqlite/database_protection.dart';
import 'package:aestheticy/library/sqlite/userdata_backup_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

void main() {
  group('S4: UserDataBackupService', () {
    late Directory tempDir;
    late Directory backupsUserDataDir;
    late String libPath;
    late String userPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('userdata_backup_test_');
      backupsUserDataDir = Directory(p.join(tempDir.path, 'backups', 'userdata'));
      libPath = p.join(tempDir.path, 'library.db');
      userPath = p.join(tempDir.path, 'userdata.db');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('creates at most one valid backup per calendar day via VACUUM INTO',
        () async {
      final repo = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
      );
      addTearDown(repo.close);
      await repo.setFavorite('C:\\Music\\one.mp3', true);

      final svc = SqliteUserDataBackupService(
        backupsUserDataDir: backupsUserDataDir,
        userDataDbPath: userPath,
        databaseProvider: () => repo.rawDatabase,
      );

      final day1 = DateTime(2026, 11, 20, 9, 0);
      final first = await svc.runDailyBackup(
        accessMode: UserDataAccessMode.normal,
        now: day1,
      );
      expect(first, isNotNull);
      expect(p.basename(first!.path), equals('userdata-20261120.db'));
      expect(
        DatabaseProtection.checkFile(first.path).status,
        equals(QuickCheckStatus.ok),
      );

      // Second call on the same calendar day is a no-op
      final second = await svc.runDailyBackup(
        accessMode: UserDataAccessMode.normal,
        now: DateTime(2026, 11, 20, 22, 30),
      );
      expect(second, isNull);
      expect(svc.listBackups(), hasLength(1));

      // Next calendar day creates a new backup
      final third = await svc.runDailyBackup(
        accessMode: UserDataAccessMode.normal,
        now: DateTime(2026, 11, 21, 8, 0),
      );
      expect(third, isNotNull);
      expect(p.basename(third!.path), equals('userdata-20261121.db'));
      expect(svc.listBackups(), hasLength(2));
    });

    test('rotation keeps newest 5 backups and never deletes non-matching files or subdirectories',
        () async {
      final repo = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
      );
      addTearDown(repo.close);

      backupsUserDataDir.createSync(recursive: true);
      final unrelatedFile = File(p.join(backupsUserDataDir.path, 'keep_me.txt'))
        ..writeAsStringSync('do not delete');
      final unrelatedDb =
          File(p.join(backupsUserDataDir.path, 'manual-snapshot.db'))
            ..writeAsStringSync('do not delete');
      final subDir = Directory(p.join(backupsUserDataDir.path, 'nested'))
        ..createSync();

      final svc = SqliteUserDataBackupService(
        backupsUserDataDir: backupsUserDataDir,
        userDataDbPath: userPath,
        databaseProvider: () => repo.rawDatabase,
      );

      for (var day = 1; day <= 7; day++) {
        await svc.runDailyBackup(
          accessMode: UserDataAccessMode.normal,
          now: DateTime(2026, 11, day),
        );
      }

      final retainedNames =
          svc.listBackups().map((f) => p.basename(f.path)).toList();
      expect(
        retainedNames,
        equals([
          'userdata-20261107.db',
          'userdata-20261106.db',
          'userdata-20261105.db',
          'userdata-20261104.db',
          'userdata-20261103.db',
        ]),
      );

      expect(unrelatedFile.existsSync(), isTrue);
      expect(unrelatedDb.existsSync(), isTrue);
      expect(subDir.existsSync(), isTrue);
    });

    test('falls back to wal_checkpoint + copy when VACUUM INTO fails',
        () async {
      final repo = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
      );
      addTearDown(repo.close);
      await repo.setRating('C:\\Music\\fallback.mp3', 4);

      final svc = SqliteUserDataBackupService(
        backupsUserDataDir: backupsUserDataDir,
        userDataDbPath: userPath,
        databaseProvider: () => repo.rawDatabase,
        forceVacuumFailure: true,
      );

      final backup = await svc.runDailyBackup(
        accessMode: UserDataAccessMode.normal,
        now: DateTime(2026, 11, 26),
      );
      expect(backup, isNotNull);
      expect(
        DatabaseProtection.checkFile(backup!.path).status,
        equals(QuickCheckStatus.ok),
      );
    });

    test('safeReadOnly skips daily backup and backupBeforeSchemaMigration creates verified snapshot',
        () async {
      final repo = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
      );
      addTearDown(repo.close);
      await repo.setFavorite('C:\\Music\\pre.mp3', true);

      final svc = SqliteUserDataBackupService(
        backupsUserDataDir: backupsUserDataDir,
        userDataDbPath: userPath,
        databaseProvider: () => repo.rawDatabase,
      );

      final skipped = await svc.runDailyBackup(
        accessMode: UserDataAccessMode.safeReadOnly,
        now: DateTime(2026, 11, 26),
      );
      expect(skipped, isNull);

      final preMigration = await svc.backupBeforeSchemaMigration(
        fromVersion: 1,
        toVersion: 2,
        now: DateTime(2026, 11, 26, 15, 30, 0),
      );
      expect(preMigration, isNotNull);
      expect(
        p.basename(preMigration!.path),
        equals('userdata-pre-v1-to-v2-20261126-153000.db'),
      );
      expect(
        DatabaseProtection.checkFile(preMigration.path).status,
        equals(QuickCheckStatus.ok),
      );
    });
  });
}
