/// Database schema definitions and migration runner for SQLite.
library;

import 'package:sqlite3/sqlite3.dart';

/// Target schema version.
const int kLibrarySchemaVersion = 1;

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
}
