/// Access mode and startup diagnostics for the split library/user-data databases.
library;

import 'dart:io';

/// Controls whether user-data writes are permitted on the repository.
enum UserDataAccessMode {
  /// Normal read/write access to `userdata.db`.
  normal,

  /// Safe read-only fallback entered when backup, migration verification, or
  /// `userdata.db` open/restore fails.
  safeReadOnly,
}

/// Thrown when a blocked user-data mutation is attempted in
/// [UserDataAccessMode.safeReadOnly].
class UserDataReadOnlyException implements Exception {
  /// Name of the blocked operation (for logging/diagnostics).
  final String operation;

  /// Localization key in `AppStrings` explaining why the action is blocked.
  final String messageKey;

  /// Creates a [UserDataReadOnlyException].
  const UserDataReadOnlyException(
    this.operation, {
    this.messageKey = 'userdata.safeReadOnlyBlocked',
  });

  @override
  String toString() => 'UserDataReadOnlyException($operation)';
}

/// Summary of startup database checks, corruption recovery, and access mode.
class DatabaseStartupReport {
  /// Effective access mode for user data during this run.
  final UserDataAccessMode accessMode;

  /// True when `library.db` failed `PRAGMA quick_check`, was quarantined, and
  /// was recreated cleanly (requiring a full library rescan).
  final bool libraryRecreatedAfterCorruption;

  /// True when `userdata.db` failed `PRAGMA quick_check` and was restored from
  /// a verified daily backup.
  final bool userDataRestoredFromBackup;

  /// True when `userdata.db` failed `PRAGMA quick_check` and no valid backup
  /// existed, so a fresh empty `userdata.db` was started after quarantine.
  final bool userDataResetEmptyAfterCorruption;

  /// Optional human-readable diagnostic reason when [accessMode] is
  /// [UserDataAccessMode.safeReadOnly].
  final String? safeReadOnlyReason;

  /// Directory holding database backups (`backups/`), if file-backed.
  final Directory? backupsDirectory;

  /// Directory holding application log files, if resolved.
  final Directory? logsDirectory;

  /// Creates a [DatabaseStartupReport].
  const DatabaseStartupReport({
    this.accessMode = UserDataAccessMode.normal,
    this.libraryRecreatedAfterCorruption = false,
    this.userDataRestoredFromBackup = false,
    this.userDataResetEmptyAfterCorruption = false,
    this.safeReadOnlyReason,
    this.backupsDirectory,
    this.logsDirectory,
  });

  /// Creates a clean normal-mode report.
  const DatabaseStartupReport.normal({
    this.libraryRecreatedAfterCorruption = false,
    this.userDataRestoredFromBackup = false,
    this.userDataResetEmptyAfterCorruption = false,
    this.backupsDirectory,
    this.logsDirectory,
  })  : accessMode = UserDataAccessMode.normal,
        safeReadOnlyReason = null;

  /// Whether the repository is running in [UserDataAccessMode.safeReadOnly].
  bool get isSafeReadOnly => accessMode == UserDataAccessMode.safeReadOnly;
}
