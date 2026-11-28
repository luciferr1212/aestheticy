import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/legacy_userdata_migrator.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

Track _track({
  required int folderId,
  required String path,
  required String title,
  required String artist,
  required String album,
  String? albumArtist,
  int durationMs = 180000,
  required DateTime addedAt,
}) {
  return Track(
    path: path,
    folderId: folderId,
    title: title,
    artist: artist,
    albumArtist: albumArtist ?? artist,
    album: album,
    durationMs: durationMs,
    mtimeMs: 1000,
    sizeBytes: 2048,
    addedAt: addedAt,
  );
}

PlayEvent _play({
  required String uri,
  required DateTime startedAt,
  int listenedMs = 120000,
  bool counted = true,
  bool completed = true,
  String? trackUid,
}) {
  return PlayEvent(
    uri: uri,
    startedAt: startedAt,
    listenedMs: listenedMs,
    counted: counted,
    completed: completed,
    trackUid: trackUid,
  );
}

void main() {
  group('Home Read-Only Queries', () {
    test(
      'recentAlbumsPlayed orders distinct albums by last counted play, skips missing files, and resolves file:// + relinked UIDs',
      () async {
        final repo = SqliteLibraryRepository.inMemory();
        addTearDown(repo.close);
        final folder = await repo.addFolder('C:\\Music');

        final tA1 = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\A\\1.mp3',
          title: 'A1',
          artist: 'Artist A',
          album: 'Alpha',
          addedAt: DateTime.utc(2026, 1, 1),
        );
        final tA2 = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\A\\2.mp3',
          title: 'A2',
          artist: 'Artist A',
          album: 'Alpha',
          addedAt: DateTime.utc(2026, 1, 2),
        );
        final tB1 = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\B\\1.mp3',
          title: 'B1',
          artist: 'Artist B',
          album: 'Beta',
          addedAt: DateTime.utc(2026, 1, 3),
        );
        final tC1 = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\C\\1.mp3',
          title: 'C1',
          artist: 'Artist C',
          album: 'Gamma',
          addedAt: DateTime.utc(2026, 1, 4),
        );
        final tMissing = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\Missing\\1.mp3',
          title: 'Gone',
          artist: 'Ghost',
          album: 'Deleted Album',
          addedAt: DateTime.utc(2026, 1, 5),
        );

        await repo.upsertTracks([tA1, tA2, tB1, tC1, tMissing]);
        await repo.reconcileTrackIdentities();

        // Simulate a moved track for Gamma: old URI in play_events, track_uid points to new path
        final gammaUid = await repo.resolveTrackUid(tC1.path);
        expect(gammaUid, isNotNull);

        // Alpha played twice (oldest + latest), Beta tied with Alpha? Let's test exact order and tie
        await repo.insertPlayEvent(
          _play(uri: tA1.path, startedAt: DateTime.utc(2026, 11, 20, 10)),
        );
        await repo.insertPlayEvent(
          _play(
            uri: 'file:///C:/Music/A/2.mp3',
            startedAt: DateTime.utc(2026, 11, 25, 10),
          ),
        );
        await repo.insertPlayEvent(
          _play(uri: tB1.path, startedAt: DateTime.utc(2026, 11, 25, 10)),
        );
        await repo.insertPlayEvent(
          _play(
            uri: 'C:\\OldMusic\\Gamma_old.mp3',
            trackUid: gammaUid,
            startedAt: DateTime.utc(2026, 11, 26, 10),
          ),
        );
        // Uncounted play on Beta at newer timestamp must be ignored
        await repo.insertPlayEvent(
          _play(
            uri: tB1.path,
            startedAt: DateTime.utc(2026, 11, 27, 10),
            counted: false,
            listenedMs: 1000,
          ),
        );
        // Play on deleted track must be skipped
        await repo.insertPlayEvent(
          _play(uri: tMissing.path, startedAt: DateTime.utc(2026, 11, 28, 10)),
        );
        await repo.removeTracksByPath([tMissing.path]);

        final albums = await repo.recentAlbumsPlayed(limit: 8);
        expect(albums.map((a) => a.album).toList(), ['Gamma', 'Alpha', 'Beta']);
        // Full trackCount preserved for Alpha (2 tracks)
        expect(albums[1].trackCount, 2);

        final limited = await repo.recentAlbumsPlayed(limit: 2);
        expect(limited.map((a) => a.album).toList(), ['Gamma', 'Alpha']);
      },
    );

    test(
      'forgottenFavorites returns never-played first, then oldest plays < cutoff, skipping recent and missing files',
      () async {
        final repo = SqliteLibraryRepository.inMemory();
        addTearDown(repo.close);
        final folder = await repo.addFolder('C:\\Music');
        final now = DateTime.utc(2026, 11, 28, 12);

        final tNever = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\never.mp3',
          title: 'Never Played',
          artist: 'A',
          album: 'Al',
          addedAt: DateTime.utc(2026, 1, 1),
        );
        final tOldest = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\oldest.mp3',
          title: 'Oldest Play',
          artist: 'A',
          album: 'Al',
          addedAt: DateTime.utc(2026, 1, 1),
        );
        final tOld = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\old.mp3',
          title: 'Old Play',
          artist: 'A',
          album: 'Al',
          addedAt: DateTime.utc(2026, 1, 1),
        );
        final tRecent = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\recent.mp3',
          title: 'Recent Play',
          artist: 'A',
          album: 'Al',
          addedAt: DateTime.utc(2026, 1, 1),
        );
        final tDeletedFav = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\deleted.mp3',
          title: 'Deleted',
          artist: 'A',
          album: 'Al',
          addedAt: DateTime.utc(2026, 1, 1),
        );

        await repo.upsertTracks([tNever, tOldest, tOld, tRecent, tDeletedFav]);
        await repo.setFavorite(tNever.path, true);
        await repo.setFavorite(tOldest.path, true);
        await repo.setFavorite(tOld.path, true);
        await repo.setFavorite(tRecent.path, true);
        await repo.setFavorite(tDeletedFav.path, true);

        await repo.removeTracksByPath([tDeletedFav.path]);

        await repo.insertPlayEvent(
          _play(uri: tOldest.path, startedAt: now.subtract(const Duration(days: 90))),
        );
        await repo.insertPlayEvent(
          _play(uri: tOld.path, startedAt: now.subtract(const Duration(days: 45))),
        );
        await repo.insertPlayEvent(
          _play(uri: tRecent.path, startedAt: now.subtract(const Duration(days: 5))),
        );
        // Uncounted recent play on tNever should still treat it as never played
        await repo.insertPlayEvent(
          _play(
            uri: tNever.path,
            startedAt: now.subtract(const Duration(days: 1)),
            counted: false,
            listenedMs: 500,
          ),
        );

        final res = await repo.forgottenFavorites(
          olderThan: const Duration(days: 30),
          limit: 8,
          now: now,
        );
        expect(
          res.map((t) => t.title).toList(),
          ['Never Played', 'Oldest Play', 'Old Play'],
        );
      },
    );

    test(
      'onThisDay matches same month/day in earlier years, excludes current year, handles Feb 29, and respects limit',
      () async {
        final repo = SqliteLibraryRepository.inMemory();
        addTearDown(repo.close);
        final folder = await repo.addFolder('C:\\Music');

        final t2024 = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\2024.mp3',
          title: 'Memory 2024',
          artist: 'A',
          album: 'Al',
          addedAt: DateTime.utc(2024, 1, 1),
        );
        final t2025 = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\2025.mp3',
          title: 'Memory 2025',
          artist: 'A',
          album: 'Al',
          addedAt: DateTime.utc(2025, 1, 1),
        );
        final tSameYear = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\2026.mp3',
          title: 'Today 2026',
          artist: 'A',
          album: 'Al',
          addedAt: DateTime.utc(2026, 1, 1),
        );
        final tOtherDay = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\other.mp3',
          title: 'Other Day',
          artist: 'A',
          album: 'Al',
          addedAt: DateTime.utc(2025, 1, 1),
        );

        await repo.upsertTracks([t2024, t2025, tSameYear, tOtherDay]);

        await repo.insertPlayEvent(
          _play(uri: t2024.path, startedAt: DateTime.utc(2024, 11, 28, 15)),
        );
        await repo.insertPlayEvent(
          _play(uri: t2025.path, startedAt: DateTime.utc(2025, 11, 28, 9)),
        );
        await repo.insertPlayEvent(
          _play(uri: tSameYear.path, startedAt: DateTime.utc(2026, 11, 28, 8)),
        );
        await repo.insertPlayEvent(
          _play(uri: tOtherDay.path, startedAt: DateTime.utc(2025, 11, 27, 9)),
        );

        final res = await repo.onThisDay(DateTime.utc(2026, 11, 28, 20), limit: 8);
        expect(res.map((t) => t.title).toList(), ['Memory 2025', 'Memory 2024']);

        // Feb 29 leap-year check
        await repo.insertPlayEvent(
          _play(uri: t2024.path, startedAt: DateTime.utc(2024, 2, 29, 12)),
        );
        final leapRes = await repo.onThisDay(DateTime.utc(2028, 2, 29, 12));
        expect(leapRes.map((t) => t.title).toList(), ['Memory 2024']);
      },
    );

    test(
      'mostPlayedThisMonth ranks by play count then listenedMs then title and ignores prior months',
      () async {
        final repo = SqliteLibraryRepository.inMemory();
        addTearDown(repo.close);
        final folder = await repo.addFolder('C:\\Music');
        final now = DateTime.utc(2026, 11, 28, 12);

        final tTop = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\top.mp3',
          title: 'Top Song',
          artist: 'A',
          album: 'Al',
          addedAt: DateTime.utc(2026, 10, 1),
        );
        final tTieLong = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\tielong.mp3',
          title: 'Tie Longer',
          artist: 'A',
          album: 'Al',
          addedAt: DateTime.utc(2026, 10, 1),
        );
        final tTieShort = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\tieshort.mp3',
          title: 'Tie Shorter',
          artist: 'A',
          album: 'Al',
          addedAt: DateTime.utc(2026, 10, 1),
        );
        final tLastMonth = _track(
          folderId: folder.id!,
          path: 'C:\\Music\\lastmonth.mp3',
          title: 'October Hit',
          artist: 'A',
          album: 'Al',
          addedAt: DateTime.utc(2026, 10, 1),
        );

        await repo.upsertTracks([tTop, tTieLong, tTieShort, tLastMonth]);

        for (var i = 0; i < 3; i++) {
          await repo.insertPlayEvent(
            _play(
              uri: tTop.path,
              startedAt: DateTime.utc(2026, 11, 1 + i, 10),
              listenedMs: 60000,
            ),
          );
        }
        await repo.insertPlayEvent(
          _play(
            uri: tTieLong.path,
            startedAt: DateTime.utc(2026, 11, 10, 10),
            listenedMs: 200000,
          ),
        );
        await repo.insertPlayEvent(
          _play(
            uri: tTieShort.path,
            startedAt: DateTime.utc(2026, 11, 12, 10),
            listenedMs: 50000,
          ),
        );
        for (var i = 0; i < 5; i++) {
          await repo.insertPlayEvent(
            _play(
              uri: tLastMonth.path,
              startedAt: DateTime.utc(2026, 10, 15 + i, 10),
              listenedMs: 200000,
            ),
          );
        }

        final res = await repo.mostPlayedThisMonth(limit: 8, now: now);
        expect(
          res.map((t) => t.title).toList(),
          ['Top Song', 'Tie Longer', 'Tie Shorter'],
        );
      },
    );

    test(
      'recentlyAddedAlbums orders by latest addedAt descending with title tie-breaker',
      () async {
        final repo = SqliteLibraryRepository.inMemory();
        addTearDown(repo.close);
        final folder = await repo.addFolder('C:\\Music');

        await repo.upsertTracks([
          _track(
            folderId: folder.id!,
            path: 'C:\\Music\\old\\1.mp3',
            title: 'Old',
            artist: 'A',
            album: 'Older Album',
            addedAt: DateTime.utc(2026, 1, 1),
          ),
          _track(
            folderId: folder.id!,
            path: 'C:\\Music\\z\\1.mp3',
            title: 'Z',
            artist: 'A',
            album: 'Zebra Album',
            addedAt: DateTime.utc(2026, 11, 20),
          ),
          _track(
            folderId: folder.id!,
            path: 'C:\\Music\\a\\1.mp3',
            title: 'A',
            artist: 'A',
            album: 'Amber Album',
            addedAt: DateTime.utc(2026, 11, 20),
          ),
        ]);

        final res = await repo.recentlyAddedAlbums(limit: 2);
        expect(res.map((a) => a.album).toList(), ['Amber Album', 'Zebra Album']);
      },
    );

    test(
      'read-only queries succeed in UserDataAccessMode.safeReadOnly',
      () async {
        final tempDir =
            await Directory.systemTemp.createTemp('aestheticy_home_ro_');
        addTearDown(() async {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        });

        final libPath = p.join(tempDir.path, 'library.db');
        final backupsDir = Directory(p.join(tempDir.path, 'backups'));

        final db = sqlite3.open(libPath);
        db.execute('PRAGMA foreign_keys = ON;');
        db.execute('''
          CREATE TABLE folders (id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE, last_scan_at INTEGER);
          CREATE TABLE tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE,
            folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
            title TEXT, artist TEXT, album_artist TEXT, album TEXT,
            track_no INTEGER, disc_no INTEGER, year INTEGER,
            duration_ms INTEGER NOT NULL, mtime_ms INTEGER NOT NULL, size_bytes INTEGER NOT NULL,
            cover_key TEXT, added_at INTEGER NOT NULL, search_text TEXT NOT NULL
          );
          CREATE TABLE track_artists (
            track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
            artist_key TEXT NOT NULL, artist_name TEXT NOT NULL, PRIMARY KEY(track_id, artist_key)
          );
          CREATE TABLE artist_aliases (alias_key TEXT PRIMARY KEY, canonical_key TEXT NOT NULL, canonical_name TEXT NOT NULL);
          CREATE TABLE artist_no_split (artist_key TEXT PRIMARY KEY, artist_name TEXT NOT NULL);
          CREATE TABLE play_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT, uri TEXT NOT NULL, title TEXT, artist TEXT,
            album TEXT, album_artist TEXT, duration_ms INTEGER, started_at_ms INTEGER NOT NULL,
            listened_ms INTEGER NOT NULL, counted INTEGER NOT NULL, completed INTEGER NOT NULL
          );
          CREATE TABLE favorites (path TEXT PRIMARY KEY, added_at_ms INTEGER NOT NULL);
          CREATE TABLE ratings (path TEXT PRIMARY KEY, stars INTEGER NOT NULL CHECK(stars BETWEEN 1 AND 5), rated_at_ms INTEGER NOT NULL);
          CREATE TABLE playlists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL);
          CREATE TABLE playlist_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT, playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
            position INTEGER NOT NULL, path TEXT NOT NULL, added_at_ms INTEGER NOT NULL
          );
          PRAGMA user_version = 4;
        ''');
        db.execute("INSERT INTO folders (id, path) VALUES (1, 'C:\\Music');");
        db.execute(
          'INSERT INTO tracks (id, path, folder_id, title, artist, album, duration_ms, mtime_ms, size_bytes, added_at, search_text) '
          "VALUES (1, 'C:\\Music\\s1.mp3', 1, 'S1', 'Artist 1', 'Album 1', 200000, 10, 10, ${DateTime.utc(2026, 11, 1).millisecondsSinceEpoch}, 's1 artist 1');",
        );
        db.execute(
          "INSERT INTO favorites VALUES ('C:\\Music\\s1.mp3', ${DateTime.utc(2026, 11, 2).millisecondsSinceEpoch});",
        );
        db.execute(
          'INSERT INTO play_events (id, uri, title, artist, album, duration_ms, started_at_ms, listened_ms, counted, completed) '
          "VALUES (1, 'C:\\Music\\s1.mp3', 'S1', 'Artist 1', 'Album 1', 200000, ${DateTime.utc(2026, 11, 20).millisecondsSinceEpoch}, 180000, 1, 1);",
        );
        db.close();

        final ro = SqliteLibraryRepository.openFile(
          libPath,
          backupsDir: backupsDir,
          migrationHooks: LegacyMigrationTestHooks(failBackup: () => true),
        );
        addTearDown(ro.close);
        expect(ro.userDataAccessMode, UserDataAccessMode.safeReadOnly);

        // All 5 Home read queries succeed and read legacy main tables
        final recentAlbums = await ro.recentAlbumsPlayed();
        expect(recentAlbums.map((a) => a.album).toList(), ['Album 1']);
        expect(
          await ro.forgottenFavorites(
            olderThan: const Duration(days: 30),
            now: DateTime.utc(2026, 11, 28),
          ),
          isEmpty,
        );
        expect(await ro.onThisDay(DateTime.utc(2026, 11, 28)), isEmpty);
        final topMonth = await ro.mostPlayedThisMonth(
          now: DateTime.utc(2026, 11, 28),
        );
        expect(topMonth.map((t) => t.title).toList(), ['S1']);
        final recentAdded = await ro.recentlyAddedAlbums();
        expect(recentAdded.map((a) => a.album).toList(), ['Album 1']);
      },
    );
  });
}
