/// Crash-recoverable one-time migration of legacy user tables from
/// `library.db` (`main`) into `userdata.db` (`userdata`).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/library/sqlite/userdata_migrator.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

/// Thrown by [LegacyMigrationTestHooks] to simulate a mid-migration crash.
class SimulatedCrashException implements Exception {
  /// Stage name where the crash was injected.
  final String stage;

  /// Creates a [SimulatedCrashException].
  const SimulatedCrashException(this.stage);

  @override
  String toString() => 'SimulatedCrashException($stage)';
}

/// Optional test hooks to inject failures or crashes at each migration step.
class LegacyMigrationTestHooks {
  /// Invoked right after the pre-split backup completes.
  final void Function()? onAfterBackup;

  /// Invoked right after step (b) commits `copied_verified` in `userdata.db`.
  final void Function()? onAfterCopyCommit;

  /// Invoked right after step (c) commits `ALTER TABLE ... RENAME` in `library.db`.
  final void Function()? onAfterRenameCommit;

  /// Invoked right before step (d) sets `legacy_migration_state = 'complete'`.
  final void Function()? onBeforeComplete;

  /// When returning true, forces the pre-split backup step to fail.
  final bool Function()? failBackup;

  /// When returning true, forces PK/row checksum verification inside step (b) to fail.
  final bool Function()? forceVerificationMismatch;

  /// When returning true, forces pre-split `VACUUM INTO` to fail so the
  /// checkpoint + copy fallback is exercised.
  final bool Function()? forceVacuumFailure;

  /// When returning true, simulates a backup row-count mismatch after backup
  /// creation to verify safe read-only abort behavior.
  final bool Function()? forceBackupRowCountMismatch;

  /// Creates [LegacyMigrationTestHooks].
  const LegacyMigrationTestHooks({
    this.onAfterBackup,
    this.onAfterCopyCommit,
    this.onAfterRenameCommit,
    this.onBeforeComplete,
    this.failBackup,
    this.forceVerificationMismatch,
    this.forceVacuumFailure,
    this.forceBackupRowCountMismatch,
  });
}

/// Outcome of [LegacyUserDataMigrator.run].
class LegacyMigrationResult {
  /// Resulting user-data access mode.
  final UserDataAccessMode accessMode;

  /// True if migration aborted before legacy tables were renamed so reads must
  /// target `main.<tableName>` instead of `userdata.<tableName>`.
  final bool readLegacyFromMain;

  /// Diagnostic reason when [accessMode] is [UserDataAccessMode.safeReadOnly].
  final String? failureReason;

  /// Pre-split backup directory created during step (a), if any.
  final Directory? preSplitBackupDir;

  /// Creates a [LegacyMigrationResult].
  const LegacyMigrationResult({
    required this.accessMode,
    this.readLegacyFromMain = false,
    this.failureReason,
    this.preSplitBackupDir,
  });

  /// Successful normal-mode migration result.
  const LegacyMigrationResult.normal({this.preSplitBackupDir})
      : accessMode = UserDataAccessMode.normal,
        readLegacyFromMain = false,
        failureReason = null;

  /// Aborted safe-read-only migration result.
  const LegacyMigrationResult.safeReadOnly({
    required this.readLegacyFromMain,
    required this.failureReason,
    this.preSplitBackupDir,
  }) : accessMode = UserDataAccessMode.safeReadOnly;
}

/// Executes the crash-recoverable state machine for migrating legacy user-data
/// tables from `library.db` (`main`) into `userdata.db` (`userdata`).
class LegacyUserDataMigrator {
  const LegacyUserDataMigrator._();

  /// `userdata.meta` key storing the state machine stage:
  /// `'none' | 'copied_verified' | 'complete'`.
  static const String metaStateKey = 'legacy_migration_state';

  /// `userdata.meta` key storing `'1'` once complete.
  static const String metaLegacyMigratedKey = 'legacy_migrated';

  static const Map<String, String> _primaryKeyByTable = {
    'artist_aliases': 'alias_key',
    'artist_no_split': 'artist_key',
    'play_events': 'id',
    'favorites': 'path',
    'ratings': 'path',
    'playlists': 'id',
    'playlist_items': 'id',
  };

  static const List<String> _reverseFkTableOrder = [
    'playlist_items',
    'playlists',
    'ratings',
    'favorites',
    'play_events',
    'artist_no_split',
    'artist_aliases',
  ];

  /// Runs or recovers the legacy migration on [db] (with `userdata` already
  /// attached).
  ///
  /// Every write transaction touches ONLY ONE database file (`main` OR
  /// `userdata`). Simulated crashes via [hooks] are rethrown directly.
  static LegacyMigrationResult run(
    Database db, {
    String? libraryFilePath,
    Directory? backupsDir,
    DateTime Function()? clock,
    AppLogger? logger,
    void Function(int fromVersion, int toVersion)? onBeforeUserDataUpgrade,
    LegacyMigrationTestHooks? hooks,
  }) {
    final log = logger ?? AppLogger.instance;
    final nowFn = clock ?? DateTime.now;

    try {
      // Ensure userdata schema is up-to-date before reading state.
      UserDataMigrator.apply(db, onBeforeUpgrade: onBeforeUserDataUpgrade);

      final state = _readState(db);
      final legacyTablesInMain = _existingLegacyTables(db);
      final renamedTablesInMain = _existingRenamedLegacyTables(db);

      if (state == 'complete') {
        return const LegacyMigrationResult.normal();
      }

      if (state == 'none' && legacyTablesInMain.isEmpty) {
        // Fresh installation (or already clean): mark complete.
        _commitCompleteState(db, hooks: hooks);
        return const LegacyMigrationResult.normal();
      }

      if (state == 'copied_verified') {
        if (legacyTablesInMain.isEmpty && renamedTablesInMain.isNotEmpty) {
          // Crash happened after (c) commit and before (d) commit.
          log.info(
            'Migration',
            'Recovering legacy migration: state=copied_verified, tables already renamed -> completing (d)',
          );
          _commitCompleteState(db, hooks: hooks);
          return const LegacyMigrationResult.normal();
        }

        if (legacyTablesInMain.isEmpty) {
          _commitCompleteState(db, hooks: hooks);
          return const LegacyMigrationResult.normal();
        }

        // Crash happened after (b) commit and before (c) commit.
        log.info(
          'Migration',
          'Recovering legacy migration: state=copied_verified, re-verifying against main',
        );
        final matches = _verifyAllCountsAndChecksums(
          db,
          legacyTablesInMain,
          hooks: hooks,
        );
        if (!matches) {
          log.warning(
            'Migration',
            'Re-verification mismatch in copied_verified recovery -> clearing userdata and re-copying',
          );
          final copyOk = _copyAndVerifyInUserDataTx(
            db,
            legacyTablesInMain,
            log: log,
            hooks: hooks,
          );
          if (!copyOk) {
            return const LegacyMigrationResult.safeReadOnly(
              readLegacyFromMain: true,
              failureReason: 'Legacy migration verification failed during recovery',
            );
          }
        }

        _renameLegacyTablesInMainTx(db, legacyTablesInMain, hooks: hooks);
        _commitCompleteState(db, hooks: hooks);
        log.info('Migration', 'Legacy migration recovery completed');
        return const LegacyMigrationResult.normal();
      }

      // state == 'none' and legacyTablesInMain is non-empty -> run from (a).
      Directory? preSplitDir;
      if (libraryFilePath != null && backupsDir != null) {
        final backupOutcome = _backupLibraryBeforeSplit(
          db,
          libraryFilePath: libraryFilePath,
          backupsDir: backupsDir,
          now: nowFn(),
          log: log,
          hooks: hooks,
        );
        if (!backupOutcome.success) {
          return LegacyMigrationResult.safeReadOnly(
            readLegacyFromMain: true,
            failureReason: backupOutcome.error ?? 'Pre-split backup failed',
          );
        }
        preSplitDir = backupOutcome.backupDir;
      }
      hooks?.onAfterBackup?.call();

      final copied = _copyAndVerifyInUserDataTx(
        db,
        legacyTablesInMain,
        log: log,
        hooks: hooks,
      );
      if (!copied) {
        return LegacyMigrationResult.safeReadOnly(
          readLegacyFromMain: true,
          failureReason: 'Legacy migration verification failed',
          preSplitBackupDir: preSplitDir,
        );
      }

      _renameLegacyTablesInMainTx(db, legacyTablesInMain, hooks: hooks);
      _commitCompleteState(db, hooks: hooks);
      log.info('Migration', 'Legacy migration completed successfully');
      return LegacyMigrationResult.normal(preSplitBackupDir: preSplitDir);
    } on UserDataUpgradeBackupException catch (e, st) {
      log.error('Migration', 'Pre-upgrade backup failed: ${e.message}', e, st);
      return LegacyMigrationResult.safeReadOnly(
        readLegacyFromMain: _safeHasLegacyTables(db),
        failureReason: e.message,
      );
    } on SimulatedCrashException {
      rethrow;
    } catch (e, st) {
      log.error('Migration', 'Legacy migration failed unexpectedly: $e', e, st);
      final stillHasLegacy = _safeHasLegacyTables(db);
      return LegacyMigrationResult.safeReadOnly(
        readLegacyFromMain: stillHasLegacy,
        failureReason: 'Legacy migration error: $e',
      );
    }
  }

  static bool _safeHasLegacyTables(Database db) {
    try {
      return _existingLegacyTables(db).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static String _readState(Database db) {
    final rows = db.select(
      'SELECT value FROM userdata.meta WHERE key = ? LIMIT 1;',
      [metaStateKey],
    );
    if (rows.isEmpty) {
      // Backwards compatibility with legacy_migrated if present.
      final migratedRows = db.select(
        'SELECT value FROM userdata.meta WHERE key = ? LIMIT 1;',
        [metaLegacyMigratedKey],
      );
      if (migratedRows.isNotEmpty && migratedRows.first['value'] == '1') {
        return 'complete';
      }
      return 'none';
    }
    final value = rows.first['value'] as String;
    if (value == 'copied_verified' || value == 'complete') {
      return value;
    }
    return 'none';
  }

  static List<String> _existingLegacyTables(Database db) {
    final existing = db
        .select("SELECT name FROM main.sqlite_master WHERE type = 'table';")
        .map((r) => r['name'] as String)
        .toSet();
    return kUserDataTables.where(existing.contains).toList();
  }

  static List<String> _existingRenamedLegacyTables(Database db) {
    final existing = db
        .select("SELECT name FROM main.sqlite_master WHERE type = 'table';")
        .map((r) => r['name'] as String)
        .toSet();
    return kUserDataTables
        .map((t) => 'legacy_$t')
        .where(existing.contains)
        .toList();
  }

  static ({bool success, Directory? backupDir, String? error})
      _backupLibraryBeforeSplit(
    Database db, {
    required String libraryFilePath,
    required Directory backupsDir,
    required DateTime now,
    required AppLogger log,
    LegacyMigrationTestHooks? hooks,
  }) {
    if (hooks?.failBackup?.call() == true) {
      log.error('Migration', 'Pre-split backup forced failure (test hook)');
      return (success: false, backupDir: null, error: 'Backup forced failure');
    }

    try {
      log.info('Migration', 'Step (a): creating pre-split backup of library.db');
      if (!backupsDir.existsSync()) {
        backupsDir.createSync(recursive: true);
      }

      final stamp = _formatBackupStamp(now);
      var targetDir = Directory(p.join(backupsDir.path, 'pre-split-$stamp'));
      if (targetDir.existsSync()) {
        targetDir = Directory(
          p.join(
            backupsDir.path,
            'pre-split-$stamp-${now.millisecond.toString().padLeft(3, '0')}',
          ),
        );
      }
      targetDir.createSync(recursive: true);

      final destFile = File(p.join(targetDir.path, 'library.db'));
      var vacuumed = false;
      if (hooks?.forceVacuumFailure?.call() != true) {
        try {
          final escapedDest = destFile.path.replaceAll("'", "''");
          db.execute("VACUUM main INTO '$escapedDest';");
          vacuumed = destFile.existsSync();
        } catch (e) {
          log.warning(
            'Migration',
            'Pre-split VACUUM INTO failed, falling back to checkpoint + copy: $e',
          );
          if (destFile.existsSync()) {
            try {
              destFile.deleteSync();
            } catch (_) {}
          }
        }
      }

      if (!vacuumed) {
        try {
          db.execute('PRAGMA main.wal_checkpoint(TRUNCATE);');
        } catch (_) {
          // Non-WAL databases or read-only handles may ignore checkpoint.
        }
        final sourceFile = File(libraryFilePath);
        if (!sourceFile.existsSync()) {
          log.error(
            'Migration',
            'Pre-split backup failed: source library.db missing',
          );
          return (
            success: false,
            backupDir: null,
            error: 'Source library.db does not exist',
          );
        }
        sourceFile.copySync(destFile.path);
      }

      // Verify copied backup is a readable SQLite DB with matching user table row counts.
      final verifyDb = sqlite3.open(destFile.path, mode: OpenMode.readOnly);
      try {
        final qc = verifyDb.select('PRAGMA quick_check;');
        final status =
            qc.isNotEmpty ? qc.first.values.first?.toString() : null;
        if (status != 'ok') {
          log.error(
            'Migration',
            'Pre-split backup quick_check failed: $status',
          );
          return (
            success: false,
            backupDir: null,
            error: 'Pre-split backup quick_check returned $status',
          );
        }

        if (hooks?.forceBackupRowCountMismatch?.call() == true) {
          log.error(
            'Migration',
            'Pre-split backup row count mismatch (forced hook)',
          );
          return (
            success: false,
            backupDir: null,
            error: 'Pre-split backup row count mismatch',
          );
        }

        const verifiedTables = [
          'favorites',
          'ratings',
          'playlists',
          'playlist_items',
          'play_events',
        ];
        final mainTables = db
            .select("SELECT name FROM main.sqlite_master WHERE type = 'table';")
            .map((r) => r['name'] as String)
            .toSet();
        final backupTables = verifyDb
            .select("SELECT name FROM sqlite_master WHERE type = 'table';")
            .map((r) => r['name'] as String)
            .toSet();

        for (final table in verifiedTables) {
          if (!mainTables.contains(table)) continue;
          if (!backupTables.contains(table)) {
            log.error(
              'Migration',
              'Pre-split backup missing user table $table',
            );
            return (
              success: false,
              backupDir: null,
              error: 'Pre-split backup missing table $table',
            );
          }
          final mainCount = db
              .select('SELECT COUNT(*) AS c FROM main.$table;')
              .single['c'] as int;
          final backupCount = verifyDb
              .select('SELECT COUNT(*) AS c FROM $table;')
              .single['c'] as int;
          if (mainCount != backupCount) {
            log.error(
              'Migration',
              'Pre-split backup row count mismatch for $table: main=$mainCount backup=$backupCount',
            );
            return (
              success: false,
              backupDir: null,
              error:
                  'Pre-split backup row count mismatch for $table ($mainCount != $backupCount)',
            );
          }
        }
      } finally {
        verifyDb.close();
      }

      log.info('Migration', 'Pre-split backup created: ${targetDir.path}');
      return (success: true, backupDir: targetDir, error: null);
    } catch (e, st) {
      log.error('Migration', 'Pre-split backup failed: $e', e, st);
      return (success: false, backupDir: null, error: e.toString());
    }
  }

  static bool _copyAndVerifyInUserDataTx(
    Database db,
    List<String> legacyTables, {
    required AppLogger log,
    LegacyMigrationTestHooks? hooks,
  }) {
    log.info(
      'Migration',
      'Step (b): copying ${legacyTables.length} legacy tables into userdata.db',
    );
    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      UserDataMigrator.createV1SchemaStatements(db);
      UserDataMigrator.createV2SchemaStatements(db);
      UserDataMigrator.createV3SchemaStatements(db);

      // Clear any partial rows from prior aborted attempts (reverse FK order).
      for (final table in _reverseFkTableOrder) {
        db.execute('DELETE FROM userdata.$table;');
      }

      // Copy each existing legacy table in FK-safe order preserving IDs & timestamps.
      for (final table in legacyTables) {
        final mainCols = db
            .select('PRAGMA main.table_info($table);')
            .map((r) => r['name'] as String)
            .toList(growable: false);
        final userCols = db
            .select('PRAGMA userdata.table_info($table);')
            .map((r) => r['name'] as String)
            .toSet();
        final commonCols =
            mainCols.where(userCols.contains).toList(growable: false);
        final colList = commonCols.join(', ');
        db.execute(
          'INSERT INTO userdata.$table ($colList) SELECT $colList FROM main.$table;',
        );
      }

      // Verify per-table row count and primary-key checksum INSIDE the transaction.
      final verified = _verifyAllCountsAndChecksums(
        db,
        legacyTables,
        hooks: hooks,
      );
      if (!verified) {
        log.error(
          'Migration',
          'Step (b) verification failed: row count or PK checksum mismatch',
        );
        db.execute('ROLLBACK;');
        return false;
      }

      db.execute(
        'INSERT OR REPLACE INTO userdata.meta (key, value) VALUES (?, ?);',
        [metaStateKey, 'copied_verified'],
      );
      db.execute(
        'UPDATE userdata.favorites SET path_key = normalize_file_path(path) WHERE path_key IS NULL;',
      );
      db.execute(
        'UPDATE userdata.ratings SET path_key = normalize_file_path(path) WHERE path_key IS NULL;',
      );
      db.execute(
        'UPDATE userdata.playlist_items SET path_key = normalize_file_path(path) WHERE path_key IS NULL;',
      );
      db.execute(
        'UPDATE userdata.play_events SET uri_key = normalize_file_path(uri) WHERE uri_key IS NULL;',
      );
      db.execute('PRAGMA userdata.user_version = $kUserDataSchemaVersion;');
      db.execute('COMMIT;');
    } catch (e, st) {
      try {
        db.execute('ROLLBACK;');
      } catch (_) {}
      log.error('Migration', 'Step (b) copy transaction failed: $e', e, st);
      return false;
    }

    hooks?.onAfterCopyCommit?.call();
    return true;
  }

  static void _renameLegacyTablesInMainTx(
    Database db,
    List<String> legacyTables, {
    LegacyMigrationTestHooks? hooks,
  }) {
    // Rename child tables (playlist_items) before parent tables (playlists).
    final orderedToRename = _reverseFkTableOrder
        .where(legacyTables.contains)
        .toList(growable: false);

    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      for (final table in orderedToRename) {
        // Never DROP legacy_* tables in this task; a later release may drop them.
        db.execute('ALTER TABLE main.$table RENAME TO legacy_$table;');
      }
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }

    hooks?.onAfterRenameCommit?.call();
  }

  static void _commitCompleteState(
    Database db, {
    LegacyMigrationTestHooks? hooks,
  }) {
    hooks?.onBeforeComplete?.call();

    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      db.execute(
        'INSERT OR REPLACE INTO userdata.meta (key, value) VALUES (?, ?);',
        [metaStateKey, 'complete'],
      );
      db.execute(
        'INSERT OR REPLACE INTO userdata.meta (key, value) VALUES (?, ?);',
        [metaLegacyMigratedKey, '1'],
      );
      db.execute('PRAGMA userdata.user_version = $kUserDataSchemaVersion;');
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static bool _verifyAllCountsAndChecksums(
    Database db,
    List<String> tables, {
    LegacyMigrationTestHooks? hooks,
  }) {
    if (hooks?.forceVerificationMismatch?.call() == true) {
      return false;
    }

    for (final table in tables) {
      final pk = _primaryKeyByTable[table]!;
      final mainCols = db
          .select('PRAGMA main.table_info($table);')
          .map((r) => r['name'] as String)
          .toList(growable: false);
      final mainStats = _tableCountAndRowChecksum(db, 'main', table, pk, mainCols);
      final userStats =
          _tableCountAndRowChecksum(db, 'userdata', table, pk, mainCols);
      if (mainStats.count != userStats.count ||
          mainStats.checksum != userStats.checksum) {
        return false;
      }
    }
    return true;
  }

  static ({int count, String checksum}) _tableCountAndRowChecksum(
    Database db,
    String schema,
    String table,
    String pkColumn,
    List<String> columns,
  ) {
    final selectList = columns.join(', ');
    final rows = db.select(
      'SELECT $selectList FROM $schema.$table ORDER BY $pkColumn ASC;',
    );
    final buffer = StringBuffer('${rows.length}:');
    for (final row in rows) {
      for (final col in columns) {
        final v = row[col];
        if (v == null) {
          buffer.write('N;');
        } else if (v is int) {
          buffer.write('I:$v;');
        } else if (v is double) {
          buffer.write('D:$v;');
        } else if (v is Uint8List) {
          buffer.write('B:${v.length}:${base64Encode(v)};');
        } else {
          final s = v.toString();
          buffer.write('S:${s.length}:$s;');
        }
      }
      buffer.write('|');
    }
    final digest = sha256.convert(utf8.encode(buffer.toString())).toString();
    return (count: rows.length, checksum: digest);
  }

  static String _formatBackupStamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y$m$d-$hh$mm$ss';
  }
}
