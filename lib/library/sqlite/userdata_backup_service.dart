/// Automatic daily backup and pre-migration backup service for `userdata.db`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/library/sqlite/database_protection.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

/// Contract for backing up `userdata.db` safely without touching user audio.
abstract class UserDataBackupService {
  /// Creates at most one verified backup per calendar day in
  /// `backups/userdata/userdata-<yyyyMMdd>.db` and rotates older backups to
  /// keep at most 5.
  ///
  /// Returns the created backup [File], or `null` when skipped (e.g. already
  /// backed up today or running in [UserDataAccessMode.safeReadOnly]) or on
  /// failure (logged, never throws).
  Future<File?> runDailyBackup({
    required UserDataAccessMode accessMode,
    DateTime? now,
  });

  /// Creates an immediate verified backup of `userdata.db` before a schema
  /// upgrade runs.
  Future<File?> backupBeforeSchemaMigration({
    int? fromVersion,
    int? toVersion,
    DateTime? now,
  });

  /// Lists existing daily backup files matching `userdata-<yyyyMMdd>.db`,
  /// ordered newest first.
  List<File> listBackups();
}

/// SQLite-backed implementation of [UserDataBackupService] using `VACUUM INTO`
/// with a `wal_checkpoint` + file copy fallback and `PRAGMA quick_check`.
class SqliteUserDataBackupService implements UserDataBackupService {
  /// Directory `.../Aestheticy/backups/userdata`.
  final Directory backupsUserDataDir;

  /// Path to the live `userdata.db` file.
  final String userDataDbPath;

  /// Optional provider returning the active repository [Database] connection
  /// (with `userdata` attached).
  final Database? Function()? databaseProvider;

  /// Clock used for daily calendar-date keys and timestamps.
  final DateTime Function() clock;

  /// Optional logger instance.
  final AppLogger? logger;

  /// Maximum number of daily `userdata-YYYYMMDD.db` backups to retain.
  final int maxBackups;

  /// Test-only switch to force `VACUUM INTO` failure and exercise the
  /// `wal_checkpoint` + copy fallback.
  final bool forceVacuumFailure;

  /// Creates a [SqliteUserDataBackupService].
  SqliteUserDataBackupService({
    required this.backupsUserDataDir,
    required this.userDataDbPath,
    this.databaseProvider,
    DateTime Function()? clock,
    this.logger,
    this.maxBackups = 5,
    this.forceVacuumFailure = false,
  }) : clock = clock ?? DateTime.now;

  AppLogger get _log => logger ?? AppLogger.instance;

  @override
  Future<File?> runDailyBackup({
    required UserDataAccessMode accessMode,
    DateTime? now,
  }) async {
    if (accessMode == UserDataAccessMode.safeReadOnly) {
      _log.info('Backup', 'Daily userdata backup skipped in safe read-only mode');
      return null;
    }

    final liveFile = File(userDataDbPath);
    if (!liveFile.existsSync()) {
      return null;
    }

    final current = now ?? clock();
    final dateKey = _formatDateKey(current);
    final targetPath = p.join(
      backupsUserDataDir.path,
      'userdata-$dateKey.db',
    );
    final targetFile = File(targetPath);

    try {
      if (!backupsUserDataDir.existsSync()) {
        backupsUserDataDir.createSync(recursive: true);
      }

      // At most one valid backup per calendar day.
      if (targetFile.existsSync()) {
        final existingCheck = DatabaseProtection.checkFile(targetPath);
        if (existingCheck.status == QuickCheckStatus.ok) {
          return null;
        }
        _log.warning(
          'Backup',
          'Existing daily backup ${p.basename(targetPath)} is invalid; replacing',
        );
      }

      final created = _writeVerifiedBackupTo(targetPath);
      if (created == null) {
        return null;
      }

      _rotateDailyBackups();
      _log.info(
        'Backup',
        'Daily userdata backup created: ${p.basename(created.path)}',
      );
      return created;
    } catch (e, st) {
      _log.error('Backup', 'Daily userdata backup failed: $e', e, st);
      return null;
    }
  }

  @override
  Future<File?> backupBeforeSchemaMigration({
    int? fromVersion,
    int? toVersion,
    DateTime? now,
  }) async {
    return backupBeforeSchemaMigrationSync(
      fromVersion: fromVersion,
      toVersion: toVersion,
      now: now,
    );
  }

  /// Synchronous variant of [backupBeforeSchemaMigration] used directly inside
  /// [UserDataMigrator.apply] before upgrading `userdata.db`.
  File? backupBeforeSchemaMigrationSync({
    int? fromVersion,
    int? toVersion,
    DateTime? now,
  }) {
    final liveFile = File(userDataDbPath);
    if (!liveFile.existsSync()) {
      return null;
    }

    final current = now ?? clock();
    final stamp = _formatDateTimeStamp(current);
    final versionTag = (fromVersion != null && toVersion != null)
        ? 'v$fromVersion-to-v$toVersion'
        : 'migration';
    final targetPath = p.join(
      backupsUserDataDir.path,
      'userdata-pre-$versionTag-$stamp.db',
    );

    try {
      if (!backupsUserDataDir.existsSync()) {
        backupsUserDataDir.createSync(recursive: true);
      }
      final created = _writeVerifiedBackupTo(targetPath);
      if (created != null) {
        _log.info(
          'Backup',
          'Pre-migration userdata backup created: ${p.basename(created.path)}',
        );
      }
      return created;
    } catch (e, st) {
      _log.error('Backup', 'Pre-migration userdata backup failed: $e', e, st);
      return null;
    }
  }

  @override
  List<File> listBackups() {
    if (!backupsUserDataDir.existsSync()) return const [];
    final matched = <({File file, String dateKey})>[];
    for (final entity in backupsUserDataDir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final m = DatabaseProtection.backupFilePattern.firstMatch(name);
      if (m != null) {
        matched.add((file: entity, dateKey: m.group(1)!));
      }
    }
    matched.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    return matched.map((e) => e.file).toList(growable: false);
  }

  File? _writeVerifiedBackupTo(String targetPath) {
    final tmpPath = '$targetPath.tmp';
    final tmpFile = File(tmpPath);
    _deleteIfExists(tmpFile);

    var wrote = false;
    if (!forceVacuumFailure) {
      wrote = _tryVacuumInto(tmpPath);
    }
    if (!wrote) {
      wrote = _tryCheckpointAndCopy(tmpPath);
    }
    if (!wrote || !tmpFile.existsSync()) {
      _deleteIfExists(tmpFile);
      return null;
    }

    final qc = DatabaseProtection.checkFile(tmpPath);
    if (qc.status != QuickCheckStatus.ok) {
      _log.error(
        'Backup',
        'Backup verification failed (${qc.error}); discarding ${p.basename(tmpPath)}',
      );
      _deleteIfExists(tmpFile);
      return null;
    }

    final targetFile = File(targetPath);
    _deleteIfExists(targetFile);
    tmpFile.renameSync(targetPath);
    return targetFile;
  }

  bool _tryVacuumInto(String destPath) {
    final escapedDest = destPath.replaceAll("'", "''");
    final attachedDb = databaseProvider?.call();
    if (attachedDb != null) {
      try {
        attachedDb.execute("VACUUM userdata INTO '$escapedDest';");
        return true;
      } catch (e) {
        _log.warning(
          'Backup',
          'VACUUM userdata INTO failed, falling back to checkpoint+copy: $e',
        );
        _deleteIfExists(File(destPath));
      }
    }

    Database? standalone;
    try {
      standalone = sqlite3.open(userDataDbPath);
      standalone.execute('PRAGMA busy_timeout = 1000;');
      standalone.execute("VACUUM INTO '$escapedDest';");
      return true;
    } catch (e) {
      _log.warning(
        'Backup',
        'Standalone VACUUM INTO failed, falling back to checkpoint+copy: $e',
      );
      _deleteIfExists(File(destPath));
      return false;
    } finally {
      try {
        standalone?.close();
      } catch (e, st) {
        // ignore-silent: closing standalone SQLite backup connection after VACUUM INTO
        _log.debug('Backup', 'Failed closing standalone backup connection', e, st);
      }
    }
  }

  bool _tryCheckpointAndCopy(String destPath) {
    final attachedDb = databaseProvider?.call();
    if (attachedDb != null) {
      try {
        attachedDb.execute('PRAGMA userdata.wal_checkpoint(TRUNCATE);');
      } catch (e, st) {
        _log.debug('Backup', 'Attached WAL checkpoint skipped before copy', e, st);
      }
    } else {
      Database? standalone;
      try {
        standalone = sqlite3.open(userDataDbPath);
        standalone.execute('PRAGMA busy_timeout = 1000;');
        standalone.execute('PRAGMA wal_checkpoint(TRUNCATE);');
      } catch (e, st) {
        _log.debug('Backup', 'Standalone WAL checkpoint skipped before copy', e, st);
      } finally {
        try {
          standalone?.close();
        } catch (e, st) {
          // ignore-silent: closing standalone SQLite connection after WAL checkpoint
          _log.debug('Backup', 'Failed closing standalone checkpoint connection', e, st);
        }
      }
    }

    try {
      File(userDataDbPath).copySync(destPath);
      return true;
    } catch (e, st) {
      _log.error('Backup', 'Checkpoint+copy backup failed: $e', e, st);
      return false;
    }
  }

  void _rotateDailyBackups() {
    final backups = listBackups();
    if (backups.length <= maxBackups) return;

    // Delete ONLY older files matching `^userdata-\d{8}\.db$` inside backupsUserDataDir.
    for (final oldBackup in backups.skip(maxBackups)) {
      final name = p.basename(oldBackup.path);
      if (!DatabaseProtection.backupFilePattern.hasMatch(name)) continue;
      if (p.dirname(oldBackup.path) != backupsUserDataDir.path) continue;
      try {
        oldBackup.deleteSync();
      } catch (e) {
        _log.warning('Backup', 'Failed removing old backup $name: $e');
      }
    }
  }

  static void _deleteIfExists(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e, st) {
      // ignore-silent: deleting temporary backup file created by UserDataBackupService
      AppLogger.instance.debug(
        'Backup',
        'Failed deleting temporary backup file',
        e,
        st,
      );
    }
  }

  static String _formatDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  static String _formatDateTimeStamp(DateTime dt) {
    final date = _formatDateKey(dt);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$date-$hh$mm$ss';
  }
}

/// In-memory test double for [UserDataBackupService].
class FakeUserDataBackupService implements UserDataBackupService {
  /// Number of times [runDailyBackup] was invoked.
  int dailyBackupCalls = 0;

  /// Number of times [backupBeforeSchemaMigration] was invoked.
  int migrationBackupCalls = 0;

  /// Recorded [UserDataAccessMode] values passed to [runDailyBackup].
  final List<UserDataAccessMode> seenAccessModes = [];

  /// Optional file to return from [runDailyBackup].
  File? nextDailyBackupResult;

  /// Optional file list returned by [listBackups].
  List<File> backups = [];

  @override
  Future<File?> runDailyBackup({
    required UserDataAccessMode accessMode,
    DateTime? now,
  }) async {
    dailyBackupCalls++;
    seenAccessModes.add(accessMode);
    if (accessMode == UserDataAccessMode.safeReadOnly) {
      return null;
    }
    return nextDailyBackupResult;
  }

  @override
  Future<File?> backupBeforeSchemaMigration({
    int? fromVersion,
    int? toVersion,
    DateTime? now,
  }) async {
    migrationBackupCalls++;
    return nextDailyBackupResult;
  }

  @override
  List<File> listBackups() => List.unmodifiable(backups);
}
