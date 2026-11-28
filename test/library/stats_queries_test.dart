import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/legacy_userdata_migrator.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

void main() {
  group('listeningByWeekdayAndHour', () {
    test('aggregates local weekday/hour buckets, respects countedOnly and bounds', () async {
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);

      // 2026-11-23 is a local Monday (weekday = 1)
      // 2026-11-29 is a local Sunday (weekday = 7)
      final monNineA = DateTime(2026, 11, 23, 9, 10);
      final monNineB = DateTime(2026, 11, 23, 9, 45);
      final monUncounted = DateTime(2026, 11, 23, 9, 55);
      final sunNight = DateTime(2026, 11, 29, 23, 15);
      final outsideBefore = DateTime(2026, 11, 22, 23, 50);

      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\a.mp3',
          title: 'A',
          artist: 'Artist',
          album: 'Album',
          startedAt: outsideBefore,
          listenedMs: 120000,
          counted: true,
          completed: true,
        ),
      );
      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\a.mp3',
          title: 'A',
          artist: 'Artist',
          album: 'Album',
          startedAt: monNineA,
          listenedMs: 90000,
          counted: true,
          completed: true,
        ),
      );
      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\b.mp3',
          title: 'B',
          artist: 'Artist',
          album: 'Album',
          startedAt: monNineB,
          listenedMs: 60000,
          counted: true,
          completed: true,
        ),
      );
      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\c.mp3',
          title: 'C',
          artist: 'Artist',
          album: 'Album',
          startedAt: monUncounted,
          listenedMs: 5000,
          counted: false,
          completed: false,
        ),
      );
      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\d.mp3',
          title: 'D',
          artist: 'Artist',
          album: 'Album',
          startedAt: sunNight,
          listenedMs: 180000,
          counted: true,
          completed: true,
        ),
      );

      final start = DateTime(2026, 11, 23, 0, 0, 0);
      final end = DateTime(2026, 11, 29, 23, 59, 59, 999);

      final counted = await repo.listeningByWeekdayAndHour(
        start,
        end,
        countedOnly: true,
      );
      expect(counted.length, 2);

      final monCell = counted.firstWhere((c) => c.weekday == 1 && c.hour == 9);
      expect(monCell.totalListenedMs, 150000);
      expect(monCell.playCount, 2);

      final sunCell = counted.firstWhere((c) => c.weekday == 7 && c.hour == 23);
      expect(sunCell.totalListenedMs, 180000);
      expect(sunCell.playCount, 1);

      final all = await repo.listeningByWeekdayAndHour(
        start,
        end,
        countedOnly: false,
      );
      final monAll = all.firstWhere((c) => c.weekday == 1 && c.hour == 9);
      expect(monAll.totalListenedMs, 155000);
      expect(monAll.playCount, 3);
    });

    test('works in UserDataAccessMode.safeReadOnly against legacy schema', () async {
      final dir = Directory.systemTemp.createTempSync('aestheticy_stats_ro_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final libPath = p.join(dir.path, 'library.db');
      final backupsDir = Directory(p.join(dir.path, 'backups'));

      final db = sqlite3.open(libPath);
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
      final playedAt = DateTime(2026, 11, 24, 14, 20); // Tuesday 14:20 local
      db.execute("INSERT INTO folders (id, path) VALUES (1, 'C:\\Music');");
      db.execute(
        'INSERT INTO play_events (id, uri, title, artist, album, duration_ms, started_at_ms, listened_ms, counted, completed) '
        "VALUES (1, 'C:\\Music\\s1.mp3', 'S1', 'Artist 1', 'Album 1', 200000, ${playedAt.millisecondsSinceEpoch}, 180000, 1, 1);",
      );
      db.close();

      final ro = SqliteLibraryRepository.openFile(
        libPath,
        backupsDir: backupsDir,
        migrationHooks: LegacyMigrationTestHooks(failBackup: () => true),
      );
      addTearDown(ro.close);
      expect(ro.userDataAccessMode, UserDataAccessMode.safeReadOnly);

      final cells = await ro.listeningByWeekdayAndHour(
        DateTime(2026, 11, 23),
        DateTime(2026, 11, 29, 23, 59, 59, 999),
      );
      expect(cells.length, 1);
      expect(cells.first.weekday, DateTime.tuesday);
      expect(cells.first.hour, 14);
      expect(cells.first.totalListenedMs, 180000);
    });
  });
}
