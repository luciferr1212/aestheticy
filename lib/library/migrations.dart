/// Database schema definitions and migration runner for SQLite.
library;

import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/artist_splitter.dart';

/// Target schema version.
const int kLibrarySchemaVersion = 2;

/// Runs database migrations up to [kLibrarySchemaVersion].
class SchemaMigrator {
  /// Applies any pending migrations on [db] and configures connection pragmas.
  static void apply(Database db) {
    // Foreign keys must be enabled on every open connection in SQLite.
    db.execute('PRAGMA foreign_keys = ON;');

    final versionRow = db.select('PRAGMA user_version;');
    final currentVersion = versionRow.first.values.first as int;

    if (currentVersion < 1) {
      _migrateToV1(db);
    }
    if (currentVersion < 2) {
      _migrateToV2(db);
    }
  }

  static void _migrateToV1(Database db) {
    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      // 1. Folders table
      db.execute('''
        CREATE TABLE IF NOT EXISTS folders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          path TEXT NOT NULL UNIQUE,
          last_scan_at INTEGER
        );
      ''');

      // 2. Tracks table
      db.execute('''
        CREATE TABLE IF NOT EXISTS tracks (
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

      // 3. Performance & lookup indexes
      db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tracks_folder_id ON tracks(folder_id);',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album);',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist);',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tracks_search_text ON tracks(search_text);',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tracks_added_at ON tracks(added_at);',
      );

      db.execute('PRAGMA user_version = 1;');
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static void _migrateToV2(Database db) {
    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      // 1. track_artists table
      db.execute('''
        CREATE TABLE IF NOT EXISTS track_artists (
          track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
          artist_key TEXT NOT NULL,
          artist_name TEXT NOT NULL,
          PRIMARY KEY(track_id, artist_key)
        );
      ''');
      db.execute(
        'CREATE INDEX IF NOT EXISTS idx_track_artists_artist_key ON track_artists(artist_key);',
      );

      // 2. artist_aliases table
      db.execute('''
        CREATE TABLE IF NOT EXISTS artist_aliases (
          alias_key TEXT PRIMARY KEY,
          canonical_key TEXT NOT NULL,
          canonical_name TEXT NOT NULL
        );
      ''');

      // 3. artist_no_split table
      db.execute('''
        CREATE TABLE IF NOT EXISTS artist_no_split (
          artist_key TEXT PRIMARY KEY,
          artist_name TEXT NOT NULL
        );
      ''');

      // 4. Populate track_artists for existing tracks inside the migration
      rebuildArtistLinksSync(db, inTransaction: true);

      db.execute('PRAGMA user_version = 2;');
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Rebuilds all rows in `track_artists` based on distinct artist strings in `tracks`,
  /// applying splitting rules, aliases, and no-split rules.
  static void rebuildArtistLinksSync(Database db, {bool inTransaction = false}) {
    void executeRebuild() {
      // 1. Fetch all distinct raw artists from tracks
      final distinctRows = db.select('''
        SELECT DISTINCT COALESCE(NULLIF(artist, ''), 'Unknown Artist') AS raw_artist
        FROM tracks;
      ''');

      if (distinctRows.isEmpty) {
        db.execute('DELETE FROM track_artists;');
        return;
      }

      // 2. Fetch artist_no_split
      final noSplitRows = db.select('SELECT artist_key FROM artist_no_split;');
      final noSplitKeys =
          noSplitRows.map((r) => r['artist_key'] as String).toSet();

      // 3. Fetch artist_aliases and flatten alias chains (A->B, B->C => A->C)
      final aliasRows = db.select(
        'SELECT alias_key, canonical_key, canonical_name FROM artist_aliases;',
      );
      final rawAliases = <String, String>{};
      for (final row in aliasRows) {
        rawAliases[row['alias_key'] as String] = row['canonical_key'] as String;
      }

      final resolvedAliases = <String, String>{};
      for (final aliasKey in rawAliases.keys) {
        var current = aliasKey;
        final visited = <String>{current};
        while (rawAliases.containsKey(current)) {
          final next = rawAliases[current]!;
          if (!visited.add(next)) break; // cycle guard
          current = next;
        }
        resolvedAliases[aliasKey] = current;
      }

      String resolveAlias(String key) => resolvedAliases[key] ?? key;

      // 4. Identify standalone artist keys from distinct strings containing no ambiguous separator
      final standaloneKeys = <String>{};
      for (final row in distinctRows) {
        final raw = row['raw_artist'] as String;
        if (!ArtistSplitter.hasAmbiguousSeparator(raw)) {
          final splits = ArtistSplitter.split(
            raw,
            noSplitKeys: noSplitKeys,
            resolveAlias: resolveAlias,
          );
          for (final s in splits) {
            standaloneKeys.add(s.key);
          }
        }
      }

      // 5. Split each distinct artist string
      final distinctSplits = <String, List<SplitArtist>>{};
      for (final row in distinctRows) {
        final raw = row['raw_artist'] as String;
        final splits = ArtistSplitter.split(
          raw,
          standaloneArtistKeys: standaloneKeys,
          noSplitKeys: noSplitKeys,
          resolveAlias: resolveAlias,
        );
        distinctSplits[raw] = splits;
      }

      // 6. Rewrite track_artists
      db.execute('DELETE FROM track_artists;');

      final trackRows = db.select('''
        SELECT id, COALESCE(NULLIF(artist, ''), 'Unknown Artist') AS raw_artist
        FROM tracks;
      ''');

      final insertStmt = db.prepare('''
        INSERT OR IGNORE INTO track_artists (track_id, artist_key, artist_name)
        VALUES (?, ?, ?);
      ''');

      for (final trackRow in trackRows) {
        final trackId = trackRow['id'] as int;
        final rawArtist = trackRow['raw_artist'] as String;
        final splits = distinctSplits[rawArtist] ?? const [];
        for (final s in splits) {
          insertStmt.execute([trackId, s.key, s.name]);
        }
      }

      insertStmt.close();
    }

    if (inTransaction) {
      executeRebuild();
    } else {
      db.execute('BEGIN IMMEDIATE TRANSACTION;');
      try {
        executeRebuild();
        db.execute('COMMIT;');
      } catch (e) {
        db.execute('ROLLBACK;');
        rethrow;
      }
    }
  }
}
