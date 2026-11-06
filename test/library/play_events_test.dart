import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/migrations.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';

void main() {
  group('Schema V3 & PlayEvents Migration Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('play_events_test_');
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('Fresh database initializes at current schema version', () {
      final db = sqlite3.openInMemory();
      SchemaMigrator.apply(db);

      final versionRow = db.select('PRAGMA user_version;');
      expect(versionRow.first.values.first, equals(4));

      // play_events table must exist
      final tables = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='play_events';",
      );
      expect(tables, isNotEmpty);
      db.close();
    });

    test('Migrating a real v2 database preserves folders, tracks, aliases, and no-split rows', () {
      final dbPath = '${tempDir.path}/v2_migration.db';
      final rawDb = sqlite3.open(dbPath);

      // Create v1 schema
      rawDb.execute('PRAGMA foreign_keys = ON;');
      rawDb.execute('''
        CREATE TABLE folders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          path TEXT NOT NULL UNIQUE,
          last_scan_at INTEGER
        );
      ''');
      rawDb.execute('''
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
      // Create v2 tables
      rawDb.execute('''
        CREATE TABLE track_artists (
          track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
          artist_key TEXT NOT NULL,
          artist_name TEXT NOT NULL,
          PRIMARY KEY(track_id, artist_key)
        );
      ''');
      rawDb.execute('''
        CREATE TABLE artist_aliases (
          alias_key TEXT PRIMARY KEY,
          canonical_key TEXT NOT NULL,
          canonical_name TEXT NOT NULL
        );
      ''');
      rawDb.execute('''
        CREATE TABLE artist_no_split (
          artist_key TEXT PRIMARY KEY,
          artist_name TEXT NOT NULL
        );
      ''');
      rawDb.execute('PRAGMA user_version = 2;');

      // Insert test v2 data
      rawDb.execute("INSERT INTO folders (path) VALUES ('/music');");
      rawDb.execute('''
        INSERT INTO tracks (
          path, folder_id, title, artist, album_artist, album,
          duration_ms, mtime_ms, size_bytes, added_at, search_text
        ) VALUES ('/music/song1.mp3', 1, 'Song 1', 'Artist A', 'Artist A', 'Album 1',
                  180000, 1000, 5000, 1000, 'song 1 artist a');
      ''');
      rawDb.execute("INSERT INTO track_artists (track_id, artist_key, artist_name) VALUES (1, 'artist a', 'Artist A');");
      rawDb.execute("INSERT INTO artist_aliases (alias_key, canonical_key, canonical_name) VALUES ('alias_a', 'artist a', 'Artist A');");
      rawDb.execute("INSERT INTO artist_no_split (artist_key, artist_name) VALUES ('artist a', 'Artist A');");
      rawDb.close();

      // Open via repository (which runs SchemaMigrator.apply -> migrates v2 to v3)
      final repo = SqliteLibraryRepository.openFile(dbPath);

      // Verify schema version
      final rawCheck = sqlite3.open(dbPath);
      final version = rawCheck.select('PRAGMA user_version;').first.values.first as int;
      expect(version, equals(4));
      rawCheck.close();

      // Verify existing rows are preserved
      expect(repo.listFolders(), completion(hasLength(1)));
      expect(repo.trackCount(), completion(equals(1)));
      expect(repo.listAliases(), completion(hasLength(1)));
      expect(repo.listNoSplit(), completion(hasLength(1)));

      repo.close();
    });

    test('PlayEvent CRUD and ordering (recentPlayEvents newest first)', () async {
      final repo = SqliteLibraryRepository.inMemory();

      final baseTime = DateTime.utc(2026, 11, 5, 20, 0, 0);

      final event1 = PlayEvent(
        uri: '/music/song1.mp3',
        title: 'Song 1',
        artist: 'Artist 1',
        album: 'Album 1',
        albumArtist: 'Artist 1',
        durationMs: 200000,
        startedAt: baseTime,
        listenedMs: 120000,
        counted: true,
        completed: false,
      );

      final event2 = PlayEvent(
        uri: '/music/song2.mp3',
        title: 'Song 2',
        artist: 'Artist 2',
        album: 'Album 2',
        albumArtist: 'Artist 2',
        durationMs: 150000,
        startedAt: baseTime.add(const Duration(minutes: 5)),
        listenedMs: 6000,
        counted: false,
        completed: false,
      );

      final id1 = await repo.insertPlayEvent(event1);
      final id2 = await repo.insertPlayEvent(event2);

      expect(id1, isPositive);
      expect(id2, isPositive);
      expect(id2, isNot(equals(id1)));

      // Count checks
      expect(await repo.playEventCount(), equals(2));
      expect(await repo.playEventCount(countedOnly: true), equals(1));

      // Recent events ordering: event2 was started at +5 mins, so it comes first
      final recent = await repo.recentPlayEvents();
      expect(recent.length, equals(2));
      expect(recent.first.id, equals(id2));
      expect(recent.first.uri, equals('/music/song2.mp3'));
      expect(recent.first.counted, isFalse);
      expect(recent[1].id, equals(id1));
      expect(recent[1].uri, equals('/music/song1.mp3'));
      expect(recent[1].counted, isTrue);

      // Update event1: finalize listenedMs and completed
      await repo.updatePlayEvent(
        id1,
        listenedMs: 195000,
        counted: true,
        completed: true,
      );

      final updatedRecent = await repo.recentPlayEvents();
      final updated1 = updatedRecent.firstWhere((e) => e.id == id1);
      expect(updated1.listenedMs, equals(195000));
      expect(updated1.counted, isTrue);
      expect(updated1.completed, isTrue);

      // Clear play events
      await repo.clearPlayEvents();
      expect(await repo.playEventCount(), equals(0));
      expect(await repo.recentPlayEvents(), isEmpty);

      await repo.close();
    });
  });
}
