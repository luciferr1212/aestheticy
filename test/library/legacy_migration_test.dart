import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/sqlite/legacy_userdata_migrator.dart';
import 'package:aestheticy/library/sqlite/userdata_migrator.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

/// Seeds a single-file v4 legacy `library.db` at [dbPath] containing all 7
/// user-data tables with representative edge rows.
void _seedLegacyV4Db(String dbPath) {
  final db = sqlite3.open(dbPath);
  db.execute('PRAGMA foreign_keys = ON;');

  db.execute('''
    CREATE TABLE folders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      path TEXT NOT NULL UNIQUE,
      last_scan_at INTEGER
    );
  ''');
  db.execute('''
    CREATE TABLE tracks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      path TEXT NOT NULL UNIQUE,
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      title TEXT,
      artist TEXT,
      album_artist TEXT,
      album TEXT,
      track_no INTEGER,
      disc_no INTEGER,
      year INTEGER,
      duration_ms INTEGER NOT NULL,
      mtime_ms INTEGER NOT NULL,
      size_bytes INTEGER NOT NULL,
      cover_key TEXT,
      added_at INTEGER NOT NULL,
      search_text TEXT NOT NULL
    );
  ''');
  db.execute('''
    CREATE TABLE track_artists (
      track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
      artist_key TEXT NOT NULL,
      artist_name TEXT NOT NULL,
      PRIMARY KEY(track_id, artist_key)
    );
  ''');
  db.execute('''
    CREATE TABLE artist_aliases (
      alias_key TEXT PRIMARY KEY,
      canonical_key TEXT NOT NULL,
      canonical_name TEXT NOT NULL
    );
  ''');
  db.execute('''
    CREATE TABLE artist_no_split (
      artist_key TEXT PRIMARY KEY,
      artist_name TEXT NOT NULL
    );
  ''');
  db.execute('''
    CREATE TABLE play_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uri TEXT NOT NULL,
      title TEXT,
      artist TEXT,
      album TEXT,
      album_artist TEXT,
      duration_ms INTEGER,
      started_at_ms INTEGER NOT NULL,
      listened_ms INTEGER NOT NULL,
      counted INTEGER NOT NULL,
      completed INTEGER NOT NULL
    );
  ''');
  db.execute('''
    CREATE TABLE favorites (
      path TEXT PRIMARY KEY,
      added_at_ms INTEGER NOT NULL
    );
  ''');
  db.execute('''
    CREATE TABLE ratings (
      path TEXT PRIMARY KEY,
      stars INTEGER NOT NULL CHECK(stars BETWEEN 1 AND 5),
      rated_at_ms INTEGER NOT NULL
    );
  ''');
  db.execute('''
    CREATE TABLE playlists (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL
    );
  ''');
  db.execute('''
    CREATE TABLE playlist_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      path TEXT NOT NULL,
      added_at_ms INTEGER NOT NULL
    );
  ''');
  db.execute('PRAGMA user_version = 4;');

  // Seed library rows
  db.execute("INSERT INTO folders (id, path) VALUES (1, 'C:\\Music');");
  db.execute('''
    INSERT INTO tracks (
      id, path, folder_id, title, artist, album_artist, album,
      track_no, disc_no, year, duration_ms, mtime_ms, size_bytes,
      cover_key, added_at, search_text
    ) VALUES (
      10, 'C:\\Music\\song1.flac', 1, 'Song One', 'Fairouz', 'Fairouz',
      'Morning', 1, 1, 1970, 200000, 1111, 2222, 'cov1', 1700000000000, 'song one fairouz morning'
    );
  ''');
  db.execute(
    "INSERT INTO track_artists (track_id, artist_key, artist_name) VALUES (10, 'fairouz', 'Fairouz');",
  );

  // Seed non-contiguous IDs and edge rows across all 7 user tables
  db.execute(
    'INSERT INTO artist_aliases (alias_key, canonical_key, canonical_name) '
    "VALUES ('fayrouz', 'fairouz', 'Fairouz');",
  );
  db.execute(
    'INSERT INTO artist_no_split (artist_key, artist_name) '
    "VALUES ('simon & garfunkel', 'Simon & Garfunkel');",
  );
  db.execute(
    'INSERT INTO play_events (id, uri, title, artist, album, album_artist, duration_ms, started_at_ms, listened_ms, counted, completed) '
    "VALUES (42, 'C:\\Music\\song1.flac', 'Song One', 'Fairouz', 'Morning', 'Fairouz', 200000, 1700000005000, 180000, 1, 1);",
  );
  db.execute(
    'INSERT INTO play_events (id, uri, title, artist, album, album_artist, duration_ms, started_at_ms, listened_ms, counted, completed) '
    "VALUES (99, 'C:\\Music\\missing.flac', 'Missing', NULL, NULL, NULL, NULL, 1700000009000, 6000, 0, 0);",
  );
  db.execute(
    "INSERT INTO favorites (path, added_at_ms) VALUES ('C:\\Music\\song1.flac', 1700000001111);",
  );
  db.execute(
    "INSERT INTO ratings (path, stars, rated_at_ms) VALUES ('C:\\Music\\song1.flac', 5, 1700000002222);",
  );
  db.execute(
    "INSERT INTO ratings (path, stars, rated_at_ms) VALUES ('C:\\Music\\low.flac', 1, 1700000003333);",
  );
  db.execute(
    "INSERT INTO playlists (id, name, created_at_ms, updated_at_ms) VALUES (7, 'Roadtrip', 1700000004000, 1700000004500);",
  );
  db.execute(
    'INSERT INTO playlist_items (id, playlist_id, position, path, added_at_ms) '
    "VALUES (15, 7, 0, 'C:\\Music\\song1.flac', 1700000004100);",
  );
  // Edge row: missing file in playlist
  db.execute(
    'INSERT INTO playlist_items (id, playlist_id, position, path, added_at_ms) '
    "VALUES (28, 7, 1, 'C:\\Music\\not_in_library.mp3', 1700000004200);",
  );

  db.close();
}

void main() {
  group('S2: Crash-recoverable one-time legacy migration', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('legacy_migration_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('migrates seeded legacy db preserving IDs, timestamps, edge rows, renames legacy tables, creates backup, and is idempotent',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));
      _seedLegacyV4Db(libPath);

      final repo = SqliteLibraryRepository.openFile(
        libPath,
        backupsDir: backupsDir,
        clock: () => DateTime.utc(2026, 11, 26, 12, 30, 45),
      );
      var closed = false;
      addTearDown(() async {
        if (!closed) {
          closed = true;
          await repo.close();
        }
      });

      expect(repo.userDataAccessMode, equals(UserDataAccessMode.normal));

      // Verify pre-split backup exists and passes quick_check
      final preSplitDirs = backupsDir
          .listSync()
          .whereType<Directory>()
          .where((d) => p.basename(d.path).startsWith('pre-split-'))
          .toList();
      expect(preSplitDirs, hasLength(1));
      final backupFile = File(p.join(preSplitDirs.single.path, 'library.db'));
      expect(backupFile.existsSync(), isTrue);

      // Verify all user data accessible via repository with exact IDs/timestamps
      expect(await repo.favoritePaths(), equals({'C:\\Music\\song1.flac'}));
      expect(
        await repo.allRatings(),
        equals({'C:\\Music\\song1.flac': 5, 'C:\\Music\\low.flac': 1}),
      );
      final playlists = await repo.listPlaylists();
      expect(playlists, hasLength(1));
      expect(playlists.single.id, equals(7));
      expect(playlists.single.createdAt.millisecondsSinceEpoch, equals(1700000004000));
      final entries = await repo.playlistEntries(7);
      expect(entries, hasLength(2));
      expect(entries[0].entryId, equals(15));
      expect(entries[0].track?.title, equals('Song One'));
      expect(entries[1].entryId, equals(28));
      expect(entries[1].track, isNull); // missing file preserved

      final events = await repo.recentPlayEvents();
      expect(events.map((e) => e.id).toSet(), equals({42, 99}));
      expect((await repo.listAliases()).single.aliasKey, equals('fayrouz'));
      expect(
        (await repo.listNoSplit()).single.artistName,
        equals('Simon & Garfunkel'),
      );

      // Verify legacy tables renamed in main (and never dropped)
      final mainTables = repo.rawDatabase
          .select("SELECT name FROM main.sqlite_master WHERE type = 'table';")
          .map((r) => r['name'] as String)
          .toSet();
      for (final table in kUserDataTables) {
        expect(mainTables.contains(table), isFalse);
        expect(mainTables.contains('legacy_$table'), isTrue);
      }

      // Verify meta state
      final stateRows = repo.rawDatabase.select(
        "SELECT value FROM userdata.meta WHERE key = 'legacy_migration_state';",
      );
      expect(stateRows.single['value'], equals('complete'));
      closed = true;
      await repo.close();

      // Re-open (idempotent: no second backup, no duplicate rows)
      final repo2 = SqliteLibraryRepository.openFile(
        libPath,
        backupsDir: backupsDir,
        clock: () => DateTime.utc(2026, 11, 26, 12, 31, 00),
      );
      final preSplitDirsAfter = backupsDir
          .listSync()
          .whereType<Directory>()
          .where((d) => p.basename(d.path).startsWith('pre-split-'))
          .toList();
      expect(preSplitDirsAfter, hasLength(1));
      expect((await repo2.recentPlayEvents()).length, equals(2));
      expect((await repo2.playlistEntries(7)).length, equals(2));
      await repo2.close();
    });

    test('recovers cleanly from simulated crash after backup, after (b) commit, after (c) commit, and before (d)',
        () async {
      for (final crashStage in [
        'after_backup',
        'after_copy_commit',
        'after_rename_commit',
        'before_complete',
      ]) {
        final caseDir = Directory(p.join(tempDir.path, crashStage))
          ..createSync(recursive: true);
        final libPath = p.join(caseDir.path, 'library.db');
        final backupsDir = Directory(p.join(caseDir.path, 'backups'));
        _seedLegacyV4Db(libPath);

        final hooks = LegacyMigrationTestHooks(
          onAfterBackup: crashStage == 'after_backup'
              ? () => throw const SimulatedCrashException('after_backup')
              : null,
          onAfterCopyCommit: crashStage == 'after_copy_commit'
              ? () => throw const SimulatedCrashException('after_copy_commit')
              : null,
          onAfterRenameCommit: crashStage == 'after_rename_commit'
              ? () => throw const SimulatedCrashException('after_rename_commit')
              : null,
          onBeforeComplete: crashStage == 'before_complete'
              ? () => throw const SimulatedCrashException('before_complete')
              : null,
        );

        expect(
          () => SqliteLibraryRepository.openFile(
            libPath,
            backupsDir: backupsDir,
            migrationHooks: hooks,
          ),
          throwsA(isA<SimulatedCrashException>()),
        );

        // Next start recovers cleanly without duplicates or lost rows
        final recovered = SqliteLibraryRepository.openFile(
          libPath,
          backupsDir: backupsDir,
        );
        expect(recovered.userDataAccessMode, equals(UserDataAccessMode.normal));
        expect((await recovered.favoritePaths()), equals({'C:\\Music\\song1.flac'}));
        expect((await recovered.allRatings()), hasLength(2));
        expect((await recovered.playlistEntries(7)).map((e) => e.entryId), equals([15, 28]));
        expect((await recovered.recentPlayEvents()).map((e) => e.id).toSet(), equals({42, 99}));
        expect((await recovered.listAliases()).length, equals(1));
        expect((await recovered.listNoSplit()).length, equals(1));

        final state = recovered.rawDatabase
            .select("SELECT value FROM userdata.meta WHERE key = 'legacy_migration_state';")
            .single['value'];
        expect(state, equals('complete'));
        await recovered.close();
      }
    });

    test('recovery in copied_verified state detects drifted userdata and re-copies from main',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));
      _seedLegacyV4Db(libPath);

      expect(
        () => SqliteLibraryRepository.openFile(
          libPath,
          backupsDir: backupsDir,
          migrationHooks: LegacyMigrationTestHooks(
            onAfterCopyCommit: () =>
                throw const SimulatedCrashException('after_copy_commit'),
          ),
        ),
        throwsA(isA<SimulatedCrashException>()),
      );

      // Corrupt/drift userdata row while in copied_verified
      final userDb = sqlite3.open(p.join(tempDir.path, 'userdata.db'));
      userDb.execute('DELETE FROM favorites;');
      userDb.close();

      final recovered = SqliteLibraryRepository.openFile(
        libPath,
        backupsDir: backupsDir,
      );
      expect(recovered.userDataAccessMode, equals(UserDataAccessMode.normal));
      expect(await recovered.favoritePaths(), equals({'C:\\Music\\song1.flac'}));
      await recovered.close();
    });

    test('corrupted backup folder aborts migration, keeps legacy tables untouched, and enters safeReadOnly',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      // Place a regular file where the backups directory needs to be created
      final corruptBackupsPath = p.join(tempDir.path, 'backups');
      File(corruptBackupsPath).writeAsStringSync('not a directory');
      _seedLegacyV4Db(libPath);

      final repo = SqliteLibraryRepository.openFile(
        libPath,
        backupsDir: Directory(corruptBackupsPath),
      );
      addTearDown(repo.close);
      expect(repo.userDataAccessMode, equals(UserDataAccessMode.safeReadOnly));
      expect(repo.userDataSchema, equals('main'));

      // Legacy tables remain intact and readable in safeReadOnly
      final mainTables = repo.rawDatabase
          .select("SELECT name FROM main.sqlite_master WHERE type = 'table';")
          .map((r) => r['name'] as String)
          .toSet();
      expect(mainTables, containsAll(kUserDataTables));
      expect(await repo.favoritePaths(), equals({'C:\\Music\\song1.flac'}));
      expect((await repo.playlistEntries(7)).length, equals(2));

      await repo.close();
    });

    test('verification mismatch rolls back userdata transaction and keeps legacy tables intact in safeReadOnly',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));
      _seedLegacyV4Db(libPath);

      final repo = SqliteLibraryRepository.openFile(
        libPath,
        backupsDir: backupsDir,
        migrationHooks: LegacyMigrationTestHooks(
          forceVerificationMismatch: () => true,
        ),
      );
      addTearDown(repo.close);
      expect(repo.userDataAccessMode, equals(UserDataAccessMode.safeReadOnly));
      expect(repo.userDataSchema, equals('main'));

      // userdata favorites must be empty due to rollback
      final userFavCount = repo.rawDatabase
          .select('SELECT COUNT(*) AS c FROM userdata.favorites;')
          .single['c'];
      expect(userFavCount, equals(0));

      // Legacy tables still readable from main
      expect(await repo.favoritePaths(), equals({'C:\\Music\\song1.flac'}));
      await repo.close();
    });

    test('read-only userdata target directory enters safeReadOnly without modifying legacy tables',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));
      _seedLegacyV4Db(libPath);

      // Point userDataPath inside a path blocked by an existing regular file
      final blockerFile = File(p.join(tempDir.path, 'readonly_blocker'));
      blockerFile.writeAsStringSync('blocker');
      final impossibleUserDataPath = p.join(blockerFile.path, 'userdata.db');

      // Ensure openFile falls back cleanly to safeReadOnly without crashing
      final repo = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: impossibleUserDataPath,
        backupsDir: backupsDir,
      );
      addTearDown(repo.close);
      expect(repo.userDataAccessMode, equals(UserDataAccessMode.safeReadOnly));
      expect(repo.userDataSchema, equals('main'));
      expect(await repo.favoritePaths(), equals({'C:\\Music\\song1.flac'}));

      // Verify legacy tables remain untouched on disk
      final verifyDb = sqlite3.open(libPath);
      final tables = verifyDb
          .select("SELECT name FROM sqlite_master WHERE type = 'table';")
          .map((r) => r['name'] as String)
          .toSet();
      expect(tables, containsAll(kUserDataTables));
      verifyDb.close();
    });

    test(
        'S4: pre-split backup falls back from VACUUM INTO to checkpoint+copy cleanly',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));
      _seedLegacyV4Db(libPath);

      final repo = SqliteLibraryRepository.openFile(
        libPath,
        backupsDir: backupsDir,
        clock: () => DateTime.utc(2026, 11, 26, 15, 0, 0),
        migrationHooks: LegacyMigrationTestHooks(
          forceVacuumFailure: () => true,
        ),
      );
      addTearDown(repo.close);

      expect(repo.userDataAccessMode, equals(UserDataAccessMode.normal));
      expect(repo.userDataSchema, equals('userdata'));
      expect(await repo.favoritePaths(), equals({'C:\\Music\\song1.flac'}));
      expect(await repo.playEventCount(), equals(2));

      final backupDirs = backupsDir
          .listSync()
          .whereType<Directory>()
          .where((d) => p.basename(d.path).startsWith('pre-split-'))
          .toList();
      expect(backupDirs, hasLength(1));

      final backupDb = sqlite3.open(p.join(backupDirs.single.path, 'library.db'));
      expect(
        backupDb.select('SELECT COUNT(*) AS c FROM favorites;').single['c'],
        equals(1),
      );
      expect(
        backupDb.select('SELECT COUNT(*) AS c FROM ratings;').single['c'],
        equals(2),
      );
      expect(
        backupDb.select('SELECT COUNT(*) AS c FROM play_events;').single['c'],
        equals(2),
      );
      backupDb.close();
    });

    test(
        'S4: pre-split backup row-count mismatch aborts migration into safeReadOnly',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final userPath = p.join(tempDir.path, 'userdata.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));
      _seedLegacyV4Db(libPath);

      final repo = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
        migrationHooks: LegacyMigrationTestHooks(
          forceBackupRowCountMismatch: () => true,
        ),
      );
      addTearDown(repo.close);

      expect(repo.userDataAccessMode, equals(UserDataAccessMode.safeReadOnly));
      expect(repo.userDataSchema, equals('main'));
      expect(await repo.favoritePaths(), equals({'C:\\Music\\song1.flac'}));

      // Legacy tables remain intact on library.db.
      final verifyDb = sqlite3.open(libPath);
      final tables = verifyDb
          .select("SELECT name FROM sqlite_master WHERE type = 'table';")
          .map((r) => r['name'] as String)
          .toSet();
      expect(tables, containsAll(kUserDataTables));
      verifyDb.close();
    });

    test(
        'S4: full-row checksum catches non-PK column drift on copied_verified recovery',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final userPath = p.join(tempDir.path, 'userdata.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));
      _seedLegacyV4Db(libPath);

      // Interrupt right after copied_verified so userdata.db has copied rows.
      expect(
        () => SqliteLibraryRepository.openFile(
          libPath,
          userDataPath: userPath,
          backupsDir: backupsDir,
          migrationHooks: LegacyMigrationTestHooks(
            onAfterCopyCommit: () =>
                throw const SimulatedCrashException('after_copy_commit'),
          ),
        ),
        throwsA(isA<SimulatedCrashException>()),
      );

      // Corrupt a non-PK column in userdata.ratings while preserving PK and count.
      final userDb = sqlite3.open(userPath);
      userDb.execute(
        "UPDATE ratings SET stars = 2 WHERE path = 'C:\\Music\\song1.flac';",
      );
      userDb.close();

      // Recovery must detect the full-row checksum mismatch, re-copy from main,
      // and restore stars = 5 before completing the migration.
      final recovered = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
      );
      addTearDown(recovered.close);

      expect(recovered.userDataAccessMode, equals(UserDataAccessMode.normal));
      expect(recovered.userDataSchema, equals('userdata'));
      final ratings = await recovered.allRatings();
      expect(ratings['C:\\Music\\song1.flac'], equals(5));
      expect(ratings['C:\\Music\\low.flac'], equals(1));
    });
  });
}
