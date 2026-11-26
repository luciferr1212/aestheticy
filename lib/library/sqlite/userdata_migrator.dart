/// Schema definitions and migrations for the attached `userdata` database.
library;

import 'package:sqlite3/sqlite3.dart';

/// Current schema version for `userdata.db`.
const int kUserDataSchemaVersion = 2;

/// Ordered list of user-data tables stored in `userdata.db`.
///
/// Ordered so parent tables (`playlists`) precede child tables
/// (`playlist_items`) for foreign-key-safe inserts.
const List<String> kUserDataTables = [
  'artist_aliases',
  'artist_no_split',
  'play_events',
  'favorites',
  'ratings',
  'playlists',
  'playlist_items',
];

/// Runs schema migrations on the attached `userdata` database up to
/// [kUserDataSchemaVersion].
class UserDataMigrator {
  const UserDataMigrator._();

  /// Applies pending migrations on the attached `userdata` schema of [db].
  ///
  /// Every write transaction touches ONLY `userdata` so single-file crash
  /// atomicity is preserved.
  static void apply(
    Database db, {
    void Function(int fromVersion, int toVersion)? onBeforeUpgrade,
  }) {
    final versionRow = db.select('PRAGMA userdata.user_version;');
    final currentVersion = versionRow.first.values.first as int;

    if (currentVersion > 0 && currentVersion < kUserDataSchemaVersion) {
      onBeforeUpgrade?.call(currentVersion, kUserDataSchemaVersion);
    }

    if (currentVersion < 1) {
      _migrateToV1(db);
    }
    if (currentVersion < 2) {
      _migrateToV2(db);
    }
  }

  /// Ensures `userdata.meta` exists inside a `userdata`-only transaction.
  static void ensureMetaTable(Database db) {
    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      db.execute('''
        CREATE TABLE IF NOT EXISTS userdata.meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
      ''');
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Creates all `userdata` v1 tables and indexes (idempotent with
  /// `IF NOT EXISTS`). Must be called inside an active transaction or standalone.
  static void createV1SchemaStatements(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS userdata.meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS userdata.artist_aliases (
        alias_key TEXT PRIMARY KEY,
        canonical_key TEXT NOT NULL,
        canonical_name TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS userdata.artist_no_split (
        artist_key TEXT PRIMARY KEY,
        artist_name TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS userdata.play_events (
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
    db.execute(
      'CREATE INDEX IF NOT EXISTS userdata.idx_play_events_started_at_ms '
      'ON play_events(started_at_ms);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS userdata.idx_play_events_uri '
      'ON play_events(uri);',
    );

    db.execute('''
      CREATE TABLE IF NOT EXISTS userdata.favorites (
        path TEXT PRIMARY KEY,
        added_at_ms INTEGER NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS userdata.ratings (
        path TEXT PRIMARY KEY,
        stars INTEGER NOT NULL CHECK(stars BETWEEN 1 AND 5),
        rated_at_ms INTEGER NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS userdata.playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS userdata.playlist_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        path TEXT NOT NULL,
        added_at_ms INTEGER NOT NULL
      );
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS userdata.idx_playlist_items_playlist_pos '
      'ON playlist_items(playlist_id, position);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS userdata.idx_playlist_items_path '
      'ON playlist_items(path);',
    );
  }

  static void _migrateToV1(Database db) {
    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      createV1SchemaStatements(db);
      db.execute('PRAGMA userdata.user_version = 1;');
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Creates all `userdata` v2 tables, additive `play_events` columns, and
  /// indexes idempotently inside an active transaction or standalone.
  static void createV2SchemaStatements(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS userdata.track_identity (
        uid TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        size_bytes INTEGER,
        duration_ms INTEGER,
        title_key TEXT,
        artist_key TEXT,
        album_key TEXT,
        first_seen_ms INTEGER,
        last_seen_ms INTEGER,
        missing_since_ms INTEGER
      );
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS userdata.idx_track_identity_path '
      'ON track_identity(path);',
    );

    final existingCols = db
        .select('PRAGMA userdata.table_info(play_events);')
        .map((r) => r['name'] as String)
        .toSet();
    if (!existingCols.contains('track_uid')) {
      db.execute('ALTER TABLE userdata.play_events ADD COLUMN track_uid TEXT;');
    }
    if (!existingCols.contains('source')) {
      db.execute('ALTER TABLE userdata.play_events ADD COLUMN source TEXT;');
    }
    if (!existingCols.contains('session_id')) {
      db.execute('ALTER TABLE userdata.play_events ADD COLUMN session_id TEXT;');
    }
    if (!existingCols.contains('ended_reason')) {
      db.execute(
        'ALTER TABLE userdata.play_events ADD COLUMN ended_reason TEXT;',
      );
    }
    db.execute(
      'CREATE INDEX IF NOT EXISTS userdata.idx_play_events_started_at_ms '
      'ON play_events(started_at_ms);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS userdata.idx_play_events_track_uid '
      'ON play_events(track_uid);',
    );
  }

  static void _migrateToV2(Database db) {
    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      createV2SchemaStatements(db);
      db.execute('PRAGMA userdata.user_version = 2;');
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }
}
