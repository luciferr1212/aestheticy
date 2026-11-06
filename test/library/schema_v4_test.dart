import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/migrations.dart';

void main() {
  group('Schema V4 Migration Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('schema_v4_test_');
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('Fresh database initializes at schema version 4 with all v4 tables', () {
      final db = sqlite3.openInMemory();
      SchemaMigrator.apply(db);

      final versionRow = db.select('PRAGMA user_version;');
      expect(versionRow.first.values.first, equals(4));

      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type='table';")
          .map((r) => r['name'] as String)
          .toSet();

      expect(tables.contains('favorites'), isTrue);
      expect(tables.contains('ratings'), isTrue);
      expect(tables.contains('playlists'), isTrue);
      expect(tables.contains('playlist_items'), isTrue);

      final indexes = db
          .select("SELECT name FROM sqlite_master WHERE type='index';")
          .map((r) => r['name'] as String)
          .toSet();

      expect(indexes.contains('idx_playlist_items_playlist_pos'), isTrue);
      expect(indexes.contains('idx_playlist_items_path'), isTrue);

      db.close();
    });

    test('Migrating a real v3 database preserves folders, tracks, aliases, and play_events', () {
      final dbPath = '${tempDir.path}/v3_database.db';
      final rawDb = sqlite3.open(dbPath);

      // Create v1, v2, v3 schema
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
      rawDb.execute('''
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
      rawDb.execute('PRAGMA user_version = 3;');

      // Seed v3 data
      rawDb.execute("INSERT INTO folders (path) VALUES ('D:/Music');");
      rawDb.execute('''
        INSERT INTO tracks (path, folder_id, title, artist, album, duration_ms, mtime_ms, size_bytes, added_at, search_text)
        VALUES ('D:/Music/track1.flac', 1, 'Track 1', 'Fairouz', 'Album A', 180000, 1000, 5000000, 100, 'track 1 fairouz');
      ''');
      rawDb.execute('''
        INSERT INTO track_artists (track_id, artist_key, artist_name)
        VALUES (1, 'fairouz', 'Fairouz');
      ''');
      rawDb.execute('''
        INSERT INTO artist_aliases (alias_key, canonical_key, canonical_name)
        VALUES ('fayrouz', 'fairouz', 'Fairouz');
      ''');
      rawDb.execute('''
        INSERT INTO play_events (uri, title, artist, album, duration_ms, started_at_ms, listened_ms, counted, completed)
        VALUES ('D:/Music/track1.flac', 'Track 1', 'Fairouz', 'Album A', 180000, 2000, 180000, 1, 1);
      ''');
      rawDb.close();

      // Migrate to v4
      final dbToMigrate = sqlite3.open(dbPath);
      SchemaMigrator.apply(dbToMigrate);

      final versionRow = dbToMigrate.select('PRAGMA user_version;');
      expect(versionRow.first.values.first, equals(4));

      // Check rows preserved
      final folderRows = dbToMigrate.select('SELECT path FROM folders;');
      expect(folderRows.length, equals(1));
      expect(folderRows.first['path'], equals('D:/Music'));

      final trackRows = dbToMigrate.select('SELECT title, path FROM tracks;');
      expect(trackRows.length, equals(1));
      expect(trackRows.first['title'], equals('Track 1'));
      expect(trackRows.first['path'], equals('D:/Music/track1.flac'));

      final aliasRows = dbToMigrate.select('SELECT alias_key FROM artist_aliases;');
      expect(aliasRows.length, equals(1));
      expect(aliasRows.first['alias_key'], equals('fayrouz'));

      final playRows = dbToMigrate.select('SELECT uri, counted FROM play_events;');
      expect(playRows.length, equals(1));
      expect(playRows.first['uri'], equals('D:/Music/track1.flac'));
      expect(playRows.first['counted'], equals(1));

      // Test inserting into new v4 tables
      dbToMigrate.execute('''
        INSERT INTO favorites (path, added_at_ms)
        VALUES ('D:/Music/track1.flac', 123456);
      ''');
      dbToMigrate.execute('''
        INSERT INTO ratings (path, stars, rated_at_ms)
        VALUES ('D:/Music/track1.flac', 5, 123456);
      ''');
      dbToMigrate.execute('''
        INSERT INTO playlists (name, created_at_ms, updated_at_ms)
        VALUES ('Chill', 1000, 1000);
      ''');
      dbToMigrate.execute('''
        INSERT INTO playlist_items (playlist_id, position, path, added_at_ms)
        VALUES (1, 0, 'D:/Music/track1.flac', 1000);
      ''');

      final favs = dbToMigrate.select('SELECT path FROM favorites;');
      expect(favs.length, equals(1));

      final ratings = dbToMigrate.select('SELECT stars FROM ratings;');
      expect(ratings.first['stars'], equals(5));

      final playlists = dbToMigrate.select('SELECT name FROM playlists;');
      expect(playlists.first['name'], equals('Chill'));

      final items = dbToMigrate.select('SELECT path FROM playlist_items;');
      expect(items.first['path'], equals('D:/Music/track1.flac'));

      dbToMigrate.close();
    });
  });
}
