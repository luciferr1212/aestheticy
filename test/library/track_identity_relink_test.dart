import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/library/library_scanner.dart';
import 'package:aestheticy/library/migrations.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/userdata_migrator.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/tag_reader.dart';

class _MapTagReader implements TagReader {
  final Map<String, RawTags> tagsByPath;

  _MapTagReader(this.tagsByPath);

  @override
  RawTags readTags(String path, {bool readCover = true}) {
    return tagsByPath[path] ??
        const RawTags(
          title: 'Unknown',
          artist: 'Unknown',
          album: 'Unknown',
          durationMs: 180000,
        );
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('aestheticy_identity_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  Track makeTrack({
    required String path,
    required int folderId,
    String title = 'Song A',
    String artist = 'Artist A',
    String album = 'Album A',
    int durationMs = 200000,
    int sizeBytes = 4096,
  }) {
    return Track(
      path: path,
      folderId: folderId,
      title: title,
      artist: artist,
      albumArtist: artist,
      album: album,
      durationMs: durationMs,
      mtimeMs: 1000,
      sizeBytes: sizeBytes,
      addedAt: DateTime.utc(2026, 11, 20),
    );
  }

  group('Track Identity & Relink (S1 + S2)', () {
    test(
        'S1: upgrades v1 userdata.db to v2 with pre-migration backup and backfills existing user paths',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final userPath = p.join(tempDir.path, 'userdata.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));

      // Seed a v1 library.db + v1 userdata.db directly via raw sqlite3.
      final libDb = sqlite3.open(libPath);
      libDb.execute("ATTACH DATABASE '${userPath.replaceAll("'", "''")}' AS userdata;");
      SchemaMigrator.apply(libDb);
      UserDataMigrator.createV1SchemaStatements(libDb);
      libDb.execute('PRAGMA userdata.user_version = 1;');

      libDb.execute(
        "INSERT INTO folders (path, last_scan_at) VALUES ('C:\\Music', 1000);",
      );
      final folderId = libDb.lastInsertRowId;
      libDb.execute('''
        INSERT INTO tracks (path, folder_id, title, artist, album, duration_ms, mtime_ms, size_bytes, added_at, search_text)
        VALUES ('C:\\Music\\lib_song.mp3', ?, 'Lib Song', 'Lib Artist', 'Lib Album', 210000, 1000, 5000, 1000, 'lib song lib artist lib album');
      ''', [folderId]);

      libDb.execute(
        "INSERT INTO userdata.favorites (path, added_at_ms) VALUES ('C:\\Music\\fav_only.mp3', 100);",
      );
      libDb.execute(
        "INSERT INTO userdata.ratings (path, stars, rated_at_ms) VALUES ('C:\\Music\\rated_only.mp3', 5, 200);",
      );
      libDb.execute(
        "INSERT INTO userdata.playlists (name, created_at_ms, updated_at_ms) VALUES ('P1', 100, 100);",
      );
      final pid = libDb.lastInsertRowId;
      libDb.execute('''
        INSERT INTO userdata.playlist_items (playlist_id, position, path, added_at_ms)
        VALUES (?, 0, 'C:\\Music\\pl_only.mp3', 300);
      ''', [pid]);
      libDb.execute('''
        INSERT INTO userdata.play_events (uri, title, started_at_ms, listened_ms, counted, completed)
        VALUES ('C:\\Music\\hist_only.mp3', 'Hist', 400, 60000, 1, 1);
      ''');
      libDb.close();

      // Reopen via SqliteLibraryRepository.openFile -> upgrades v1 -> v2, runs pre-migration backup, and backfills.
      final repo = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
        clock: () => DateTime.utc(2026, 11, 26, 12, 0),
      );
      addTearDown(repo.close);

      expect(kUserDataSchemaVersion, equals(2));
      final userVersion = repo.rawDatabase
          .select('PRAGMA userdata.user_version;')
          .first
          .values
          .first as int;
      expect(userVersion, equals(2));

      // Verify pre-migration backup was written under tempDir/backups/userdata/
      final userBackupsDir = Directory(p.join(backupsDir.path, 'userdata'));
      expect(userBackupsDir.existsSync(), isTrue);
      final backupFiles = userBackupsDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).contains('pre-v1-to-v2'))
          .toList();
      expect(backupFiles, hasLength(1));

      // Verify index idx_track_identity_path exists
      final idxRows = repo.rawDatabase.select(
        "SELECT name FROM userdata.sqlite_master WHERE type = 'index' AND name = 'idx_track_identity_path';",
      );
      expect(idxRows, hasLength(1));

      // Verify all library + favorite + rating + playlist + history paths received 128-bit hex UIDs.
      final identities = await repo.listTrackIdentities();
      expect(identities, hasLength(5));
      for (final id in identities) {
        expect(id.uid, matches(RegExp(r'^[0-9a-f]{32}$')));
      }
      expect(await repo.resolveTrackUid('C:\\Music\\lib_song.mp3'), isNotNull);
      expect(await repo.resolveTrackUid('C:/Music/fav_only.mp3'), isNotNull);
      expect(await repo.resolveTrackUid('C:\\Music\\rated_only.mp3'), isNotNull);
      expect(await repo.resolveTrackUid('C:\\Music\\pl_only.mp3'), isNotNull);
      final histUid = await repo.resolveTrackUid('C:\\Music\\hist_only.mp3');
      expect(histUid, isNotNull);

      final eventRow = repo.rawDatabase
          .select('SELECT track_uid FROM userdata.play_events LIMIT 1;')
          .first;
      expect(eventRow['track_uid'], equals(histUid));
    });

    test(
        'S2: relinks moved file by exact size+duration and carries favorites, ratings, playlists, and play history',
        () async {
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);

      final folder = await repo.addFolder('C:\\Music');
      const oldPath = 'C:\\Music\\Original\\TrackOne.mp3';
      const newPath = 'C:\\Music\\Moved\\TrackOneRenamed.mp3';

      await repo.upsertTracks([
        makeTrack(
          path: oldPath,
          folderId: folder.id!,
          title: 'Track One',
          artist: 'Artist A',
          album: 'Album A',
          durationMs: 215000,
          sizeBytes: 8192000,
        ),
      ]);
      final originalUid = await repo.resolveTrackUid(oldPath);
      expect(originalUid, isNotNull);

      await repo.setFavorite(oldPath, true);
      await repo.setRating(oldPath, 4);
      final playlist = await repo.createPlaylist('Favorites Mix');
      await repo.addToPlaylist(playlist.id, [oldPath]);
      await repo.insertPlayEvent(PlayEvent(
        uri: oldPath,
        title: 'Track One',
        startedAt: DateTime.utc(2026, 11, 25, 10),
        listenedMs: 120000,
        counted: true,
        completed: true,
      ));

      // Simulate move/rename in library without eagerly creating a separate identity:
      await repo.removeTracksByPath([oldPath]);
      await repo.upsertTracksFromScan([
        makeTrack(
          path: newPath,
          folderId: folder.id!,
          title: 'Track One',
          artist: 'Artist A',
          album: 'Album A',
          durationMs: 215000,
          sizeBytes: 8192000,
        ),
      ]);

      final report = await repo.reconcileTrackIdentities();
      expect(report.relinked, equals(1));
      expect(await repo.resolveTrackUid(oldPath), isNull);
      expect(await repo.resolveTrackUid(newPath), equals(originalUid));

      // Favorites followed the move
      final favs = await repo.favoritePaths();
      expect(favs, contains(newPath));
      expect(favs, isNot(contains(oldPath)));

      // Ratings followed the move
      final ratings = await repo.allRatings();
      expect(ratings[newPath], equals(4));
      expect(ratings.containsKey(oldPath), isFalse);

      // Playlist items followed the move
      final entries = await repo.playlistEntries(playlist.id);
      expect(entries, hasLength(1));
      expect(entries.first.path, equals(newPath));

      // Play history followed the move and kept track_uid
      final events = await repo.recentPlayEvents();
      expect(events, hasLength(1));
      expect(events.first.uri, equals(newPath));
      final recentTracks = await repo.recentlyPlayedTracks();
      expect(recentTracks.map((t) => t.path), contains(newPath));
    });

    test(
        'S2: relinks by normalized tags when size changes slightly (duration diff <= 1500ms) and skips when > 1500ms',
        () async {
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);

      final folder = await repo.addFolder('C:\\Music');
      const oldPath = 'C:\\Music\\close_match.mp3';
      const newPath = 'C:\\Music\\reencoded_match.flac';
      const farOld = 'C:\\Music\\far_old.mp3';
      const farNew = 'C:\\Music\\far_new.mp3';

      await repo.upsertTracks([
        makeTrack(
          path: oldPath,
          folderId: folder.id!,
          title: '  Café   Song  ',
          artist: 'Artist Alpha',
          album: 'Album Alpha',
          durationMs: 200000,
          sizeBytes: 3000000,
        ),
        makeTrack(
          path: farOld,
          folderId: folder.id!,
          title: 'Other Song',
          artist: 'Artist Beta',
          album: 'Album Beta',
          durationMs: 200000,
          sizeBytes: 3500000,
        ),
      ]);
      final closeUid = await repo.resolveTrackUid(oldPath);
      final farUid = await repo.resolveTrackUid(farOld);

      await repo.removeTracksByPath([oldPath, farOld]);
      await repo.upsertTracksFromScan([
        makeTrack(
          path: newPath,
          folderId: folder.id!,
          title: 'cafe song',
          artist: 'artist alpha',
          album: 'album alpha',
          durationMs: 201200, // 1200ms delta <= 1500ms -> should relink
          sizeBytes: 9000000,
        ),
        makeTrack(
          path: farNew,
          folderId: folder.id!,
          title: 'Other Song',
          artist: 'Artist Beta',
          album: 'Album Beta',
          durationMs: 205000, // 5000ms delta > 1500ms -> should NOT relink
          sizeBytes: 9500000,
        ),
      ]);

      final report = await repo.reconcileTrackIdentities();
      expect(report.relinked, equals(1));
      expect(await repo.resolveTrackUid(newPath), equals(closeUid));
      expect(await repo.resolveTrackUid(farNew), isNot(equals(farUid)));
    });

    test('S2: ambiguous relink candidates are skipped and logged without relinking',
        () async {
      final previousLogger = AppLogger.instance;
      final testLogger = AppLogger(
        logsDirectory: Directory(p.join(tempDir.path, 'logs')),
      );
      await testLogger.init();
      AppLogger.instance = testLogger;
      addTearDown(() => AppLogger.instance = previousLogger);
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);

      final folder = await repo.addFolder('C:\\Music');
      const oldPath = 'C:\\Music\\dup_source.mp3';
      const cand1 = 'C:\\Music\\copy1.mp3';
      const cand2 = 'C:\\Music\\copy2.mp3';

      await repo.upsertTracks([
        makeTrack(
          path: oldPath,
          folderId: folder.id!,
          durationMs: 190000,
          sizeBytes: 5120000,
        ),
      ]);
      final oldUid = await repo.resolveTrackUid(oldPath);
      await repo.setFavorite(oldPath, true);

      await repo.removeTracksByPath([oldPath]);
      await repo.upsertTracksFromScan([
        makeTrack(
          path: cand1,
          folderId: folder.id!,
          title: 'Copy 1',
          durationMs: 190000,
          sizeBytes: 5120000,
        ),
        makeTrack(
          path: cand2,
          folderId: folder.id!,
          title: 'Copy 2',
          durationMs: 190000,
          sizeBytes: 5120000,
        ),
      ]);

      final report = await repo.reconcileTrackIdentities();
      expect(report.relinked, equals(0));
      expect(report.ambiguousCount, equals(1));
      expect(await repo.resolveTrackUid(oldPath), equals(oldUid));
      expect(await repo.favoritePaths(), contains(oldPath));
    });

    test(
        'S2: PK conflict during relink keeps newest favorite added_at_ms and newest rating',
        () async {
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);

      final folder = await repo.addFolder('C:\\Music');
      const oldPath = 'C:\\Music\\old.mp3';
      const newPath = 'C:\\Music\\new.mp3';

      await repo.upsertTracks([
        makeTrack(
          path: oldPath,
          folderId: folder.id!,
          durationMs: 175000,
          sizeBytes: 4200000,
        ),
      ]);

      // Seed both old and target entries in favorites & ratings with known timestamps.
      repo.rawDatabase.execute(
        'INSERT INTO userdata.favorites (path, added_at_ms) VALUES (?, ?);',
        [oldPath, 1000],
      );
      repo.rawDatabase.execute(
        'INSERT INTO userdata.favorites (path, added_at_ms) VALUES (?, ?);',
        [newPath, 5000], // Newer favorite timestamp on target
      );
      repo.rawDatabase.execute(
        'INSERT INTO userdata.ratings (path, stars, rated_at_ms) VALUES (?, ?, ?);',
        [oldPath, 5, 9000], // Newer rating timestamp on source
      );
      repo.rawDatabase.execute(
        'INSERT INTO userdata.ratings (path, stars, rated_at_ms) VALUES (?, ?, ?);',
        [newPath, 2, 3000],
      );

      await repo.removeTracksByPath([oldPath]);
      await repo.upsertTracksFromScan([
        makeTrack(
          path: newPath,
          folderId: folder.id!,
          durationMs: 175000,
          sizeBytes: 4200000,
        ),
      ]);

      final report = await repo.reconcileTrackIdentities();
      expect(report.relinked, equals(1));

      final favRow = repo.rawDatabase
          .select('SELECT path, added_at_ms FROM userdata.favorites;')
          .single;
      expect(favRow['added_at_ms'], equals(5000));

      final rateRow = repo.rawDatabase
          .select('SELECT path, stars, rated_at_ms FROM userdata.ratings;')
          .single;
      expect(rateRow['stars'], equals(5));
      expect(rateRow['rated_at_ms'], equals(9000));
    });

    test(
        'S2: temporarily missing file sets missing_since_ms without deleting user data and clears it on return',
        () async {
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);

      final folder = await repo.addFolder('E:\\External');
      const trackPath = 'E:\\External\\Album\\Song.mp3';

      await repo.upsertTracks([
        makeTrack(path: trackPath, folderId: folder.id!),
      ]);
      final originalUid = await repo.resolveTrackUid(trackPath);
      await repo.setFavorite(trackPath, true);
      await repo.setRating(trackPath, 5);
      final pl = await repo.createPlaylist('Roadtrip');
      await repo.addToPlaylist(pl.id, [trackPath]);
      await repo.insertPlayEvent(PlayEvent(
        uri: trackPath,
        startedAt: DateTime.utc(2026, 11, 20),
        listenedMs: 90000,
        counted: true,
        completed: true,
      ));

      // Drive unplugged -> track disappears from main.tracks.
      await repo.removeTracksByPath([trackPath]);
      final t1 = DateTime.utc(2026, 11, 25, 10);
      final missingReport = await repo.reconcileTrackIdentities(now: t1);
      expect(missingReport.markedMissing, equals(1));

      final idMissing = (await repo.listTrackIdentities()).single;
      expect(idMissing.uid, equals(originalUid));
      expect(idMissing.missingSinceMs, equals(t1.millisecondsSinceEpoch));

      // All user data remains untouched!
      expect(await repo.favoritePaths(), contains(trackPath));
      expect(await repo.allRatings(), hasLength(1));
      expect(await repo.playlistEntries(pl.id), hasLength(1));
      expect(await repo.playEventCount(), equals(1));

      // Drive plugged back in -> track returns!
      await repo.upsertTracksFromScan([
        makeTrack(path: trackPath, folderId: folder.id!),
      ]);
      final t2 = DateTime.utc(2026, 11, 25, 12);
      await repo.reconcileTrackIdentities(now: t2);

      final idReturned = (await repo.listTrackIdentities()).single;
      expect(idReturned.uid, equals(originalUid));
      expect(idReturned.missingSinceMs, isNull);
      expect(idReturned.lastSeenMs, equals(t2.millisecondsSinceEpoch));
    });

    test(
        'S2: LibraryScanner end-to-end scan relinks renamed/moved file cleanly',
        () async {
      final musicDir = Directory(p.join(tempDir.path, 'music'))..createSync();
      final subA = Directory(p.join(musicDir.path, 'disc1'))..createSync();
      final subB = Directory(p.join(musicDir.path, 'disc2'))..createSync();
      final fileA = File(p.join(subA.path, 'track.mp3'))
        ..writeAsBytesSync(List<int>.filled(4321, 7));

      final tagReader = _MapTagReader({
        fileA.path: const RawTags(
          title: 'Scan Song',
          artist: 'Scan Artist',
          album: 'Scan Album',
          durationMs: 222000,
        ),
      });

      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);
      final folder = await repo.addFolder(musicDir.path);
      final coversDir = p.join(tempDir.path, 'covers');
      final scanner = LibraryScanner(
        repository: repo,
        tagReader: tagReader,
        coversDirectory: coversDir,
      );

      await for (final _ in scanner.scan(folder)) {}

      final uid1 = await repo.resolveTrackUid(fileA.path);
      expect(uid1, isNotNull);
      await repo.setFavorite(fileA.path, true);

      // Move and rename fileA -> fileB with identical bytes and duration.
      final fileB = File(p.join(subB.path, 'track_moved.mp3'))
        ..writeAsBytesSync(List<int>.filled(4321, 7));
      fileA.deleteSync();
      tagReader.tagsByPath[fileB.path] = const RawTags(
        title: 'Scan Song',
        artist: 'Scan Artist',
        album: 'Scan Album',
        durationMs: 222000,
      );

      final scanner2 = LibraryScanner(
        repository: repo,
        tagReader: tagReader,
        coversDirectory: coversDir,
      );
      await for (final _ in scanner2.scan(folder)) {}

      expect(await repo.resolveTrackUid(fileB.path), equals(uid1));
      final favs = await repo.favoriteTracks();
      expect(favs.map((t) => t.path), equals([fileB.path]));
    });
  });
}
