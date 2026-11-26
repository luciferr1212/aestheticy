/// Startup SQLite integrity checks (`PRAGMA quick_check`), WAL setup, and
/// corruption quarantine/recovery for `library.db` and `userdata.db`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/diagnostics/app_logger.dart';

/// Optional test hooks to inject failures during corrupt `userdata.db` restore.
class UserDataRestoreTestHooks {
  /// Override copying [backup] to [restoringPath].
  final void Function(File backup, String restoringPath)? copyBackup;

  /// Override `PRAGMA quick_check` verification on [restoringPath].
  final QuickCheckResult Function(String restoringPath)? verifyRestoringFile;

  /// Override renaming [restoringFile] to [userDataPath].
  final void Function(File restoringFile, String userDataPath)? renameIntoPlace;

  /// Creates [UserDataRestoreTestHooks].
  const UserDataRestoreTestHooks({
    this.copyBackup,
    this.verifyRestoringFile,
    this.renameIntoPlace,
  });
}

/// Result of running `PRAGMA quick_check` on a SQLite file.
enum QuickCheckStatus {
  /// File passed `PRAGMA quick_check` (`ok`).
  ok,

  /// Database file does not exist yet.
  missing,

  /// File exists but failed `PRAGMA quick_check` or is not a valid database.
  corrupt,

  /// File is locked by another process, in a read-only location, or unreadable.
  lockedOrUnreadable,
}

/// Outcome of [DatabaseProtection.checkFile].
class QuickCheckResult {
  /// Integrity status.
  final QuickCheckStatus status;

  /// Optional error message when [status] is not [QuickCheckStatus.ok].
  final String? error;

  /// Creates a [QuickCheckResult].
  const QuickCheckResult(this.status, [this.error]);
}

/// Provides WAL configuration, `PRAGMA quick_check`, and corruption recovery
/// for `library.db` and `userdata.db`.
class DatabaseProtection {
  const DatabaseProtection._();

  /// Filename pattern for automatic daily backups of `userdata.db`.
  static final RegExp backupFilePattern = RegExp(r'^userdata-(\d{8})\.db$');

  /// Runs `PRAGMA quick_check` on a standalone SQLite file at [dbPath].
  ///
  /// When [verifyWritable] is `true`, also probes `BEGIN IMMEDIATE` +
  /// `ROLLBACK` so exclusive writer locks under WAL mode are detected cleanly
  /// as [QuickCheckStatus.lockedOrUnreadable].
  ///
  /// Distinguishes lock/permission errors ([QuickCheckStatus.lockedOrUnreadable])
  /// from actual database corruption ([QuickCheckStatus.corrupt]).
  static QuickCheckResult checkFile(
    String dbPath, {
    bool verifyWritable = false,
  }) {
    final file = File(dbPath);
    if (!file.existsSync()) {
      return const QuickCheckResult(QuickCheckStatus.missing);
    }

    Database? db;
    try {
      db = sqlite3.open(dbPath);
      db.execute('PRAGMA busy_timeout = 150;');
      final rows = db.select('PRAGMA quick_check;');
      if (rows.isEmpty) {
        return const QuickCheckResult(
          QuickCheckStatus.corrupt,
          'PRAGMA quick_check returned no rows',
        );
      }
      final firstVal = rows.first.values.first?.toString().trim().toLowerCase();
      if (rows.length == 1 && firstVal == 'ok') {
        if (verifyWritable) {
          db.execute('BEGIN IMMEDIATE TRANSACTION;');
          db.execute('ROLLBACK;');
        }
        return const QuickCheckResult(QuickCheckStatus.ok);
      }
      return QuickCheckResult(
        QuickCheckStatus.corrupt,
        'PRAGMA quick_check failed: ${rows.map((r) => r.values.first).join('; ')}',
      );
    } on SqliteException catch (e) {
      final primaryCode = e.resultCode & 0xFF;
      // 5=SQLITE_BUSY, 6=SQLITE_LOCKED, 8=SQLITE_READONLY, 10=SQLITE_IOERR, 14=SQLITE_CANTOPEN
      if (primaryCode == 5 ||
          primaryCode == 6 ||
          primaryCode == 8 ||
          primaryCode == 10 ||
          primaryCode == 14) {
        return QuickCheckResult(
          QuickCheckStatus.lockedOrUnreadable,
          e.toString(),
        );
      }
      // 11=SQLITE_CORRUPT, 26=SQLITE_NOTADB
      return QuickCheckResult(QuickCheckStatus.corrupt, e.toString());
    } on FileSystemException catch (e) {
      return QuickCheckResult(
        QuickCheckStatus.lockedOrUnreadable,
        e.toString(),
      );
    } catch (e) {
      return QuickCheckResult(
        QuickCheckStatus.lockedOrUnreadable,
        e.toString(),
      );
    } finally {
      try {
        db?.close();
      } catch (_) {}
    }
  }

  /// Checks `library.db` at [libraryPath]. If corrupt, quarantines it to
  /// `library.db.corrupt-<timestamp>` so a fresh rebuildable database is
  /// created.
  static ({bool recreated, bool lockedOrUnreadable, String? error})
      prepareLibraryDb(
    String libraryPath, {
    DateTime Function()? clock,
    AppLogger? logger,
  }) {
    final log = logger ?? AppLogger.instance;
    final nowFn = clock ?? DateTime.now;
    final qc = checkFile(libraryPath);

    switch (qc.status) {
      case QuickCheckStatus.missing:
      case QuickCheckStatus.ok:
        return (recreated: false, lockedOrUnreadable: false, error: null);
      case QuickCheckStatus.lockedOrUnreadable:
        log.error(
          'Database',
          'library.db is locked or unreadable: ${qc.error}',
        );
        return (
          recreated: false,
          lockedOrUnreadable: true,
          error: qc.error,
        );
      case QuickCheckStatus.corrupt:
        final targetBase = _quarantineDatabaseFiles(
          libraryPath,
          now: nowFn(),
          log: log,
        );
        if (targetBase == null) {
          return (
            recreated: false,
            lockedOrUnreadable: true,
            error: 'Failed to quarantine corrupt library.db',
          );
        }
        log.warning(
          'Database',
          'Corrupt library.db quarantined; a fresh library database will be created and rescanned',
        );
        return (recreated: true, lockedOrUnreadable: false, error: qc.error);
    }
  }

  /// Checks `userdata.db` at [userDataPath].
  ///
  /// - Cleans up any leftover `.restoring-<timestamp>` temp files from an
  ///   interrupted prior restore matching the exact temp filename pattern.
  /// - If locked/unreadable: returns `safeReadOnly: true` without touching files.
  /// - If corrupt and a verified backup exists in [backupsUserDataDir]: copies
  ///   the backup to `userdata.db.restoring-<timestamp>`, runs `quick_check` on
  ///   the copy, and only after verification succeeds quarantines the corrupt
  ///   file and renames the verified copy into place. On any failure, leaves
  ///   the original file untouched, removes only `.restoring-*`, and enters
  ///   `safeReadOnly`.
  /// - If corrupt and no valid backup exists: quarantines the corrupt file so
  ///   an empty `userdata.db` can start cleanly.
  static ({
    bool restoredFromBackup,
    bool resetEmpty,
    bool safeReadOnly,
    String? error,
  }) prepareUserDataDb({
    required String userDataPath,
    required Directory backupsUserDataDir,
    DateTime Function()? clock,
    AppLogger? logger,
    UserDataRestoreTestHooks? restoreHooks,
  }) {
    final log = logger ?? AppLogger.instance;
    final nowFn = clock ?? DateTime.now;
    _cleanupLeftoverRestoringFiles(userDataPath, log: log);

    final qc = checkFile(userDataPath, verifyWritable: true);

    switch (qc.status) {
      case QuickCheckStatus.missing:
      case QuickCheckStatus.ok:
        return (
          restoredFromBackup: false,
          resetEmpty: false,
          safeReadOnly: false,
          error: null,
        );
      case QuickCheckStatus.lockedOrUnreadable:
        log.error(
          'Database',
          'userdata.db is locked or unreadable: ${qc.error}',
        );
        return (
          restoredFromBackup: false,
          resetEmpty: false,
          safeReadOnly: true,
          error: qc.error,
        );
      case QuickCheckStatus.corrupt:
        log.error(
          'Database',
          'userdata.db failed quick_check (${qc.error}); attempting backup restore',
        );
        final validBackup = findNewestValidBackup(
          backupsUserDataDir,
          logger: log,
        );
        if (validBackup == null) {
          final targetBase = _quarantineDatabaseFiles(
            userDataPath,
            now: nowFn(),
            log: log,
          );
          if (targetBase == null) {
            return (
              restoredFromBackup: false,
              resetEmpty: false,
              safeReadOnly: true,
              error: 'Failed to quarantine corrupt userdata.db',
            );
          }
          log.warning(
            'Database',
            'No valid userdata backup found; starting with an empty userdata.db',
          );
          return (
            restoredFromBackup: false,
            resetEmpty: true,
            safeReadOnly: false,
            error: qc.error,
          );
        }

        final now = nowFn();
        final stamp = _formatStamp(now);
        var restoringPath = '$userDataPath.restoring-$stamp';
        if (File(restoringPath).existsSync()) {
          restoringPath = '$restoringPath-${now.millisecond}';
        }

        // Step 1: Copy backup to staging temp file.
        try {
          if (restoreHooks?.copyBackup != null) {
            restoreHooks!.copyBackup!(validBackup, restoringPath);
          } else {
            validBackup.copySync(restoringPath);
          }
        } catch (e, st) {
          _deleteTempFileIfExists(restoringPath);
          log.error(
            'Database',
            'Failed copying backup to restoring temp file: $e',
            e,
            st,
          );
          return (
            restoredFromBackup: false,
            resetEmpty: false,
            safeReadOnly: true,
            error: 'Backup copy failed: $e',
          );
        }

        // Step 2: Verify the staged copy passes PRAGMA quick_check BEFORE touching corrupt file.
        final QuickCheckResult stagedCheck;
        try {
          stagedCheck =
              restoreHooks?.verifyRestoringFile?.call(restoringPath) ??
                  checkFile(restoringPath);
        } catch (e, st) {
          _deleteTempFileIfExists(restoringPath);
          log.error(
            'Database',
            'Failed verifying restoring temp file: $e',
            e,
            st,
          );
          return (
            restoredFromBackup: false,
            resetEmpty: false,
            safeReadOnly: true,
            error: 'Backup verification failed: $e',
          );
        }
        if (stagedCheck.status != QuickCheckStatus.ok) {
          _deleteTempFileIfExists(restoringPath);
          final reason = stagedCheck.error ??
              'Restoring temp file failed quick_check (${stagedCheck.status.name})';
          log.error('Database', reason);
          return (
            restoredFromBackup: false,
            resetEmpty: false,
            safeReadOnly: true,
            error: reason,
          );
        }

        // Step 3: Quarantine corrupt userdata.db (only now that verified replacement exists).
        final quarantinedBase = _quarantineDatabaseFiles(
          userDataPath,
          now: now,
          log: log,
        );
        if (quarantinedBase == null) {
          _deleteTempFileIfExists(restoringPath);
          return (
            restoredFromBackup: false,
            resetEmpty: false,
            safeReadOnly: true,
            error: 'Failed to quarantine corrupt userdata.db',
          );
        }

        // Step 4: Rename verified copy into place; roll back quarantine if rename fails.
        try {
          final stagedFile = File(restoringPath);
          if (restoreHooks?.renameIntoPlace != null) {
            restoreHooks!.renameIntoPlace!(stagedFile, userDataPath);
          } else {
            stagedFile.renameSync(userDataPath);
          }
          log.warning(
            'Database',
            'Restored userdata.db from backup ${p.basename(validBackup.path)}',
          );
          return (
            restoredFromBackup: true,
            resetEmpty: false,
            safeReadOnly: false,
            error: null,
          );
        } catch (e, st) {
          _rollbackQuarantine(quarantinedBase, userDataPath, log: log);
          _deleteTempFileIfExists(restoringPath);
          log.error(
            'Database',
            'Failed renaming verified backup into place: $e',
            e,
            st,
          );
          return (
            restoredFromBackup: false,
            resetEmpty: false,
            safeReadOnly: true,
            error: 'Backup rename failed: $e',
          );
        }
    }
  }

  /// Returns the newest backup file matching `userdata-<yyyyMMdd>.db` in
  /// [backupsUserDataDir] that passes `PRAGMA quick_check`.
  static File? findNewestValidBackup(
    Directory backupsUserDataDir, {
    AppLogger? logger,
  }) {
    final log = logger ?? AppLogger.instance;
    if (!backupsUserDataDir.existsSync()) return null;

    final candidates = <({File file, String dateKey})>[];
    try {
      for (final entity in backupsUserDataDir.listSync()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        final match = backupFilePattern.firstMatch(name);
        if (match != null) {
          candidates.add((file: entity, dateKey: match.group(1)!));
        }
      }
    } catch (e) {
      log.warning('Database', 'Failed listing userdata backups: $e');
      return null;
    }

    candidates.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    for (final candidate in candidates) {
      final qc = checkFile(candidate.file.path);
      if (qc.status == QuickCheckStatus.ok) {
        return candidate.file;
      }
      log.warning(
        'Database',
        'Skipping invalid backup ${p.basename(candidate.file.path)}: ${qc.error}',
      );
    }
    return null;
  }

  /// Enables `WAL` journal mode and `synchronous=NORMAL` on file-backed
  /// databases (`main` and optionally `userdata`). Never called on `:memory:`.
  static void enableWalForFileDbs(
    Database db, {
    required bool hasFileUserData,
    AppLogger? logger,
  }) {
    db.execute('PRAGMA busy_timeout = 5000;');
    db.execute('PRAGMA main.journal_mode = WAL;');
    db.execute('PRAGMA main.synchronous = NORMAL;');
    if (hasFileUserData) {
      try {
        db.execute('PRAGMA userdata.journal_mode = WAL;');
        db.execute('PRAGMA userdata.synchronous = NORMAL;');
      } catch (e) {
        (logger ?? AppLogger.instance).warning(
          'Database',
          'Could not enable WAL on userdata.db: $e',
        );
      }
    }
  }

  static void _cleanupLeftoverRestoringFiles(
    String userDataPath, {
    required AppLogger log,
  }) {
    final parent = File(userDataPath).parent;
    if (!parent.existsSync()) return;
    final baseName = p.basename(userDataPath);
    final pattern = RegExp(
      '^${RegExp.escape(baseName)}\\.restoring-\\d{8}-\\d{6}(?:-\\d+)?\$',
    );
    try {
      for (final entity in parent.listSync()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (pattern.hasMatch(name)) {
          try {
            entity.deleteSync();
            log.info('Database', 'Removed leftover restore temp file: $name');
          } catch (e) {
            log.warning(
              'Database',
              'Failed removing leftover restore temp file $name: $e',
            );
          }
        }
      }
    } catch (e) {
      log.warning('Database', 'Failed scanning for leftover restore files: $e');
    }
  }

  static void _deleteTempFileIfExists(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) {
        f.deleteSync();
      }
    } catch (_) {}
  }

  static void _rollbackQuarantine(
    String quarantinedBase,
    String userDataPath, {
    required AppLogger log,
  }) {
    if (quarantinedBase.isEmpty) return;
    try {
      final quarantinedMain = File(quarantinedBase);
      if (quarantinedMain.existsSync() && !File(userDataPath).existsSync()) {
        quarantinedMain.renameSync(userDataPath);
      }
      for (final suffix in const ['-wal', '-shm']) {
        final qSide = File('$quarantinedBase$suffix');
        final origSide = File('$userDataPath$suffix');
        if (qSide.existsSync() && !origSide.existsSync()) {
          try {
            qSide.renameSync(origSide.path);
          } catch (_) {}
        }
      }
    } catch (e, st) {
      log.error(
        'Database',
        'Failed rolling back quarantine for $userDataPath: $e',
        e,
        st,
      );
    }
  }

  static String? _quarantineDatabaseFiles(
    String dbPath, {
    required DateTime now,
    required AppLogger log,
  }) {
    try {
      final stamp = _formatStamp(now);
      var targetBase = '$dbPath.corrupt-$stamp';
      if (File(targetBase).existsSync()) {
        targetBase = '$dbPath.corrupt-$stamp-${now.millisecond}';
      }
      final mainFile = File(dbPath);
      var movedMain = false;
      if (mainFile.existsSync()) {
        mainFile.renameSync(targetBase);
        movedMain = true;
      }
      for (final suffix in const ['-wal', '-shm']) {
        final sidecar = File('$dbPath$suffix');
        if (sidecar.existsSync()) {
          try {
            sidecar.renameSync('$targetBase$suffix');
          } catch (_) {}
        }
      }
      return movedMain ? targetBase : '';
    } catch (e, st) {
      log.error('Database', 'Failed quarantining $dbPath: $e', e, st);
      return null;
    }
  }

  static String _formatStamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y$m$d-$hh$mm$ss';
  }
}
