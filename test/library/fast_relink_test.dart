import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/file_path_utils.dart';
import 'package:aestheticy/library/migrations.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/userdata_migrator.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('aestheticy_fast_relink_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  group('Fast Indexed Relink & UserData v3 (S2)', () {
    test(
        'v2 -> v3 migration creates pre-migration backup, adds indexed key columns, and backfills in batches',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final userPath = p.join(tempDir.path, 'userdata.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));

      // Seed a v2 userdata.db with 4500 play_events (exceeds batchSize=2000).
      final raw = sqlite3.open(libPath);
      raw.execute(
        "ATTACH DATABASE '${userPath.replaceAll("'", "''")}' AS userdata;",
      );
      SchemaMigrator.apply(raw);
      UserDataMigrator.createV1SchemaStatements(raw);
      UserDataMigrator.createV2SchemaStatements(raw);
      raw.execute('PRAGMA userdata.user_version = 2;');

      raw.execute(
        "INSERT INTO userdata.favorites (path, added_at_ms) VALUES ('C:\\Music\\fav.mp3', 100);",
      );
      raw.execute(
        "INSERT INTO userdata.ratings (path, stars, rated_at_ms) VALUES ('C:\\Music\\rate.mp3', 5, 200);",
      );
      raw.execute(
        "INSERT INTO userdata.playlists (id, name, created_at_ms, updated_at_ms) VALUES (1, 'Mix', 100, 100);",
      );
      raw.execute(
        "INSERT INTO userdata.playlist_items (playlist_id, position, path, added_at_ms) VALUES (1, 0, 'C:\\Music\\pl.mp3', 300);",
      );

      raw.execute('BEGIN IMMEDIATE TRANSACTION;');
      final stmt = raw.prepare('''
        INSERT INTO userdata.play_events (uri, started_at_ms, listened_ms, counted, completed)
        VALUES (?, 1000, 60000, 1, 1);
      ''');
      for (var i = 0; i < 4500; i++) {
        stmt.execute(['C:\\Music\\Track_$i.mp3']);
      }
      stmt.close();
      raw.execute('COMMIT;');
      raw.close();

      final repo = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
        clock: () => DateTime.utc(2026, 11, 27, 1, 0),
      );
      addTearDown(repo.close);

      expect(repo.userDataAccessMode, equals(UserDataAccessMode.normal));
      final v = repo.rawDatabase
          .select('PRAGMA userdata.user_version;')
          .first
          .values
          .first as int;
      expect(v, equals(3));

      // Verify pre-v2-to-v3 backup exists
      final userBackups = Directory(p.join(backupsDir.path, 'userdata'))
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).contains('pre-v2-to-v3'))
          .toList();
      expect(userBackups, hasLength(1));

      // Verify all 5 v3 indexes exist
      final indexes = repo.rawDatabase
          .select("SELECT name FROM userdata.sqlite_master WHERE type = 'index';")
          .map((r) => r['name'] as String)
          .toSet();
      expect(
        indexes,
        containsAll([
          'idx_favorites_path_key',
          'idx_ratings_path_key',
          'idx_playlist_items_path_key',
          'idx_play_events_uri_key',
          'idx_track_identity_path_key',
        ]),
      );

      // Verify zero NULL path_key/uri_key remain across all tables
      expect(
        repo.rawDatabase
            .select('SELECT COUNT(*) AS c FROM userdata.play_events WHERE uri_key IS NULL;')
            .single['c'],
        equals(0),
      );
      expect(
        repo.rawDatabase
            .select('SELECT path_key FROM userdata.favorites;')
            .single['path_key'],
        equals(FilePathUtils.canonicalKey('C:\\Music\\fav.mp3')),
      );
      expect(
        repo.rawDatabase
            .select('SELECT path_key FROM userdata.ratings;')
            .single['path_key'],
        equals(FilePathUtils.canonicalKey('C:\\Music\\rate.mp3')),
      );
      expect(
        repo.rawDatabase
            .select('SELECT path_key FROM userdata.playlist_items;')
            .single['path_key'],
        equals(FilePathUtils.canonicalKey('C:\\Music\\pl.mp3')),
      );
    });

    test(
        'failed pre-migration backup on v2 -> v3 upgrade aborts into Safe Read-Only leaving v2 intact',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final userPath = p.join(tempDir.path, 'userdata.db');
      // Blocker file where backupsDir would be created forces backup failure.
      final blockedBackups = File(p.join(tempDir.path, 'backups_blocker'))
        ..writeAsStringSync('blocker');

      final raw = sqlite3.open(libPath);
      raw.execute(
        "ATTACH DATABASE '${userPath.replaceAll("'", "''")}' AS userdata;",
      );
      SchemaMigrator.apply(raw);
      UserDataMigrator.createV1SchemaStatements(raw);
      UserDataMigrator.createV2SchemaStatements(raw);
      raw.execute('PRAGMA userdata.user_version = 2;');
      raw.execute(
        "INSERT INTO userdata.favorites (path, added_at_ms) VALUES ('C:\\Music\\safe.mp3', 100);",
      );
      raw.close();

      final repo = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: Directory(blockedBackups.path),
      );
      addTearDown(repo.close);

      expect(repo.userDataAccessMode, equals(UserDataAccessMode.safeReadOnly));
      expect(repo.userDataSchema, equals('userdata'));
      expect(
        repo.rawDatabase
            .select('PRAGMA userdata.user_version;')
            .first
            .values
            .first,
        equals(2),
      );
      expect(await repo.favoritePaths(), equals({'C:\\Music\\safe.mp3'}));
    });

    test(
        'writes from collections & history keep path_key/uri_key synchronized and small-data relink matches exact semantics',
        () async {
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);

      final folder = await repo.addFolder('C:\\Music');
      const oldPath = 'C:\\Music\\FolderA\\Track.flac';
      const newPath = 'C:\\Music\\FolderB\\TrackRenamed.flac';

      await repo.upsertTracksFromScan([
        Track(
          path: oldPath,
          folderId: folder.id!,
          title: 'Track',
          artist: 'Artist',
          album: 'Album',
          durationMs: 210000,
          mtimeMs: 1000,
          sizeBytes: 987654,
          addedAt: DateTime.utc(2026, 11, 20),
        ),
      ]);
      await repo.reconcileTrackIdentities();

      await repo.setFavorite(oldPath, true);
      await repo.setRating(oldPath, 4);
      final pl = await repo.createPlaylist('Sync Test');
      await repo.addToPlaylist(pl.id, [oldPath]);
      await repo.insertPlayEvent(PlayEvent(
        uri: oldPath,
        title: 'Track',
        startedAt: DateTime.utc(2026, 11, 25),
        listenedMs: 90000,
        counted: true,
        completed: true,
      ));

      final expectedOldKey = FilePathUtils.canonicalKey(oldPath);
      expect(
        repo.rawDatabase
            .select('SELECT path_key FROM userdata.favorites;')
            .single['path_key'],
        equals(expectedOldKey),
      );
      expect(
        repo.rawDatabase
            .select('SELECT uri_key FROM userdata.play_events;')
            .single['uri_key'],
        equals(expectedOldKey),
      );

      // Relink move
      await repo.removeTracksByPath([oldPath]);
      await repo.upsertTracksFromScan([
        Track(
          path: newPath,
          folderId: folder.id!,
          title: 'Track',
          artist: 'Artist',
          album: 'Album',
          durationMs: 210000,
          mtimeMs: 1000,
          sizeBytes: 987654,
          addedAt: DateTime.utc(2026, 11, 20),
        ),
      ]);
      final report = await repo.reconcileTrackIdentities();
      expect(report.relinked, equals(1));

      final expectedNewKey = FilePathUtils.canonicalKey(newPath);
      expect(
        repo.rawDatabase
            .select('SELECT path_key FROM userdata.favorites;')
            .single['path_key'],
        equals(expectedNewKey),
      );
      expect(
        repo.rawDatabase
            .select('SELECT path_key FROM userdata.ratings;')
            .single['path_key'],
        equals(expectedNewKey),
      );
      expect(
        repo.rawDatabase
            .select('SELECT path_key FROM userdata.playlist_items;')
            .single['path_key'],
        equals(expectedNewKey),
      );
      expect(
        repo.rawDatabase
            .select('SELECT uri_key FROM userdata.play_events;')
            .single['uri_key'],
        equals(expectedNewKey),
      );
    });

    test(
        'performance: 3000 identities, 3000 favorites, 5000 playlist items, 100000 play events, 2000 relinks completes well under 10s',
        () async {
      final libPath = p.join(tempDir.path, 'perf_lib.db');
      final userPath = p.join(tempDir.path, 'perf_user.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));

      final repo = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
      );
      addTearDown(repo.close);

      final folder = await repo.addFolder('C:\\Music');
      final now = DateTime.utc(2026, 11, 26);

      // 1. Seed 3000 tracks
      final initialTracks = List.generate(
        3000,
        (i) => Track(
          path: 'C:\\Music\\Orig\\song_$i.mp3',
          folderId: folder.id!,
          title: 'Song $i',
          artist: 'Artist ${i % 100}',
          album: 'Album ${i % 300}',
          durationMs: 180000 + i,
          mtimeMs: 1000,
          sizeBytes: 1000000 + i,
          addedAt: now,
        ),
      );
      await repo.upsertTracksFromScan(initialTracks);
      await repo.reconcileTrackIdentities(now: now);

      // 2. Seed 3000 favorites, 5000 playlist items, and 100,000 play_events in SQLite directly for fast setup
      final db = repo.rawDatabase;
      db.execute('BEGIN IMMEDIATE TRANSACTION;');
      try {
        final favStmt = db.prepare(
          'INSERT INTO userdata.favorites (path, added_at_ms, path_key) VALUES (?, ?, ?);',
        );
        for (var i = 0; i < 3000; i++) {
          final path = 'C:\\Music\\Orig\\song_$i.mp3';
          favStmt.execute([path, 1000 + i, FilePathUtils.canonicalKey(path)]);
        }
        favStmt.close();

        db.execute(
          "INSERT INTO userdata.playlists (id, name, created_at_ms, updated_at_ms) VALUES (1, 'Big', 1000, 1000);",
        );
        final plStmt = db.prepare(
          'INSERT INTO userdata.playlist_items (playlist_id, position, path, added_at_ms, path_key) VALUES (1, ?, ?, 1000, ?);',
        );
        for (var i = 0; i < 5000; i++) {
          final trackIdx = i % 3000;
          final path = 'C:\\Music\\Orig\\song_$trackIdx.mp3';
          plStmt.execute([i, path, FilePathUtils.canonicalKey(path)]);
        }
        plStmt.close();

        final identityMap = <String, String>{};
        for (final row in db.select('SELECT uid, path_key FROM userdata.track_identity;')) {
          identityMap[row['path_key'] as String] = row['uid'] as String;
        }

        final playStmt = db.prepare('''
          INSERT INTO userdata.play_events (
            uri, uri_key, track_uid, title, started_at_ms, listened_ms, counted, completed, source, ended_reason
          ) VALUES (?, ?, ?, ?, ?, 120000, 1, 1, 'queue', 'completed');
        ''');
        for (var i = 0; i < 100000; i++) {
          final trackIdx = i % 3000;
          final path = 'C:\\Music\\Orig\\song_$trackIdx.mp3';
          final key = FilePathUtils.canonicalKey(path);
          playStmt.execute([path, key, identityMap[key], 'Song $trackIdx', 1000000 + i]);
        }
        playStmt.close();
        db.execute('COMMIT;');
      } catch (e) {
        db.execute('ROLLBACK;');
        rethrow;
      }

      // 3. Move 2000 tracks (0..1999) to C:\Music\Moved\
      final removedPaths = List.generate(2000, (i) => 'C:\\Music\\Orig\\song_$i.mp3');
      final movedTracks = List.generate(
        2000,
        (i) => Track(
          path: 'C:\\Music\\Moved\\song_$i.mp3',
          folderId: folder.id!,
          title: 'Song $i',
          artist: 'Artist ${i % 100}',
          album: 'Album ${i % 300}',
          durationMs: 180000 + i,
          mtimeMs: 2000,
          sizeBytes: 1000000 + i,
          addedAt: now,
        ),
      );
      await repo.removeTracksByPath(removedPaths);
      await repo.upsertTracksFromScan(movedTracks);

      // 4. Time the reconcile
      final sw = Stopwatch()..start();
      final report = await repo.reconcileTrackIdentities();
      sw.stop();

      expect(report.relinked, equals(2000));
      expect(sw.elapsedMilliseconds, lessThan(10000));

      // Verify updated records across favorites, playlist_items, and play_events
      expect(
        db
            .select(
              r"SELECT COUNT(*) AS c FROM userdata.favorites WHERE path LIKE 'C:\Music\Moved\%';",
            )
            .single['c'],
        equals(2000),
      );
      expect(
        db.select(
          'SELECT COUNT(*) AS c FROM userdata.play_events WHERE uri_key = ?;',
          [FilePathUtils.canonicalKey('C:\\Music\\Moved\\song_0.mp3')],
        ).single['c'],
        greaterThan(30),
      );
      expect(
        db.select(
          'SELECT COUNT(*) AS c FROM userdata.play_events WHERE uri_key = ?;',
          [FilePathUtils.canonicalKey('C:\\Music\\Orig\\song_0.mp3')],
        ).single['c'],
        equals(0),
      );
    });
  });
}
