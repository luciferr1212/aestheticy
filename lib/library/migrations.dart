/// Database schema definitions and migration runner for SQLite.
library;

import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/artist_splitter.dart';

/// Target schema version for `library.db`.
const int kLibrarySchemaVersion = 4;

/// Runs database migrations for `library.db` (`main`) up to
/// [kLibrarySchemaVersion].
class SchemaMigrator {
  /// Applies any pending migrations on `main` of [db] and configures connection
  /// pragmas.
  ///
  /// User-data tables (`favorites`, `ratings`, `playlists`, `playlist_items`,
  /// `play_events`, `artist_aliases`, `artist_no_split`) live in the attached
  /// `userdata` database managed by `UserDataMigrator`.
  static void apply(Database db) {
    // Foreign keys must be enabled on every open connection in SQLite.
    db.execute('PRAGMA foreign_keys = ON;');

    final versionRow = db.select('PRAGMA main.user_version;');
    final currentVersion = versionRow.first.values.first as int;

    if (currentVersion < 1) {
      _migrateToV1(db);
    }
    if (currentVersion < 2) {
      _migrateToV2(db);
    }
    if (currentVersion < 3) {
      _migrateToV3(db);
    }
    if (currentVersion < 4) {
      _migrateToV4(db);
    }
  }

  static void _migrateToV1(Database db) {
    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      // 1. Folders table
      db.execute('''
        CREATE TABLE IF NOT EXISTS main.folders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          path TEXT NOT NULL UNIQUE,
          last_scan_at INTEGER
        );
      ''');

      // 2. Tracks table
      db.execute('''
        CREATE TABLE IF NOT EXISTS main.tracks (
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
        'CREATE INDEX IF NOT EXISTS main.idx_tracks_folder_id ON tracks(folder_id);',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS main.idx_tracks_album ON tracks(album);',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS main.idx_tracks_artist ON tracks(artist);',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS main.idx_tracks_search_text ON tracks(search_text);',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS main.idx_tracks_added_at ON tracks(added_at);',
      );

      db.execute('PRAGMA main.user_version = 1;');
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static void _migrateToV2(Database db) {
    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      // 1. track_artists table (rebuildable library link table)
      db.execute('''
        CREATE TABLE IF NOT EXISTS main.track_artists (
          track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
          artist_key TEXT NOT NULL,
          artist_name TEXT NOT NULL,
          PRIMARY KEY(track_id, artist_key)
        );
      ''');
      db.execute(
        'CREATE INDEX IF NOT EXISTS main.idx_track_artists_artist_key ON track_artists(artist_key);',
      );

      // 2. Populate track_artists for existing tracks inside the migration
      rebuildArtistLinksSync(db, inTransaction: true);

      db.execute('PRAGMA main.user_version = 2;');
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static void _migrateToV3(Database db) {
    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      // play_events now lives in userdata.db; keep main schema version aligned.
      db.execute('PRAGMA main.user_version = 3;');
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static void _migrateToV4(Database db) {
    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      // favorites, ratings, playlists, and playlist_items now live in userdata.db.
      db.execute('PRAGMA main.user_version = 4;');
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static bool _hasAttachedSchema(Database db, String schema) {
    final rows = db.select('PRAGMA database_list;');
    for (final row in rows) {
      if (row['name'] == schema) return true;
    }
    return false;
  }

  static bool _tableExistsInSchema(
    Database db,
    String schema,
    String tableName,
  ) {
    if (schema != 'main' && !_hasAttachedSchema(db, schema)) {
      return false;
    }
    final rows = db.select(
      "SELECT 1 FROM $schema.sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  /// Rebuilds all rows in `main.track_artists` based on distinct artist strings
  /// in `main.tracks`, applying splitting rules, aliases, and no-split rules.
  static void rebuildArtistLinksSync(
    Database db, {
    bool inTransaction = false,
    String? userDataSchema,
  }) {
    void executeRebuild() {
      // 1. Fetch all distinct raw artists from tracks
      final distinctRows = db.select('''
        SELECT DISTINCT COALESCE(NULLIF(artist, ''), 'Unknown Artist') AS raw_artist
        FROM main.tracks;
      ''');

      if (distinctRows.isEmpty) {
        db.execute('DELETE FROM main.track_artists;');
        return;
      }

      // 2. Fetch artist_no_split from userdata (or legacy main fallback)
      final noSplitSchema = userDataSchema != null
          ? (_tableExistsInSchema(db, userDataSchema, 'artist_no_split')
              ? userDataSchema
              : null)
          : (_tableExistsInSchema(db, 'userdata', 'artist_no_split')
              ? 'userdata'
              : (_tableExistsInSchema(db, 'main', 'artist_no_split')
                  ? 'main'
                  : null));

      final noSplitKeys = noSplitSchema == null
          ? <String>{}
          : db
              .select('SELECT artist_key FROM $noSplitSchema.artist_no_split;')
              .map((r) => r['artist_key'] as String)
              .toSet();

      // 3. Fetch artist_aliases and flatten alias chains (A->B, B->C => A->C)
      final aliasSchema = userDataSchema != null
          ? (_tableExistsInSchema(db, userDataSchema, 'artist_aliases')
              ? userDataSchema
              : null)
          : (_tableExistsInSchema(db, 'userdata', 'artist_aliases')
              ? 'userdata'
              : (_tableExistsInSchema(db, 'main', 'artist_aliases')
                  ? 'main'
                  : null));

      final aliasRows = aliasSchema == null
          ? const <Row>[]
          : db.select(
              'SELECT alias_key, canonical_key, canonical_name '
              'FROM $aliasSchema.artist_aliases;',
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
      // and pre-compute their splits so they never need re-splitting.
      final standaloneKeys = <String>{};
      final distinctSplits = <String, List<SplitArtist>>{};
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
          distinctSplits[raw] = splits;
        }
      }

      // 5. Split remaining distinct artist strings that contain ambiguous separators
      for (final row in distinctRows) {
        final raw = row['raw_artist'] as String;
        if (!distinctSplits.containsKey(raw)) {
          final splits = ArtistSplitter.split(
            raw,
            standaloneArtistKeys: standaloneKeys,
            noSplitKeys: noSplitKeys,
            resolveAlias: resolveAlias,
          );
          distinctSplits[raw] = splits;
        }
      }

      // 6. Rewrite main.track_artists via a temporary mapping table and a single set-based JOIN
      db.execute('DELETE FROM main.track_artists;');
      db.execute('''
        CREATE TEMP TABLE IF NOT EXISTS _temp_splits (
          raw_artist TEXT NOT NULL,
          artist_key TEXT NOT NULL,
          artist_name TEXT NOT NULL
        );
      ''');
      db.execute('DELETE FROM _temp_splits;');

      final insertTempStmt = db.prepare('''
        INSERT INTO _temp_splits (raw_artist, artist_key, artist_name)
        VALUES (?, ?, ?);
      ''');

      for (final entry in distinctSplits.entries) {
        for (final s in entry.value) {
          insertTempStmt.execute([entry.key, s.key, s.name]);
        }
      }
      insertTempStmt.close();

      db.execute('''
        CREATE INDEX IF NOT EXISTS _idx_temp_splits_raw ON _temp_splits (raw_artist);
      ''');

      db.execute('''
        INSERT OR IGNORE INTO main.track_artists (track_id, artist_key, artist_name)
        SELECT t.id, s.artist_key, s.artist_name
        FROM main.tracks t
        JOIN _temp_splits s ON s.raw_artist = t.artist
        WHERE t.artist IS NOT NULL AND t.artist != '';
      ''');

      db.execute('''
        INSERT OR IGNORE INTO main.track_artists (track_id, artist_key, artist_name)
        SELECT t.id, s.artist_key, s.artist_name
        FROM main.tracks t
        JOIN _temp_splits s ON s.raw_artist = 'Unknown Artist'
        WHERE t.artist IS NULL OR t.artist = '';
      ''');

      db.execute('DELETE FROM _temp_splits;');
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
