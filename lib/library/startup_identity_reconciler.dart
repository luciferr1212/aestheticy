/// Post-first-frame coordinator for one-time startup track identity
/// reconciliation.
library;

import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/track_identity_models.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

/// Runs non-blocking startup identity reconciliation once after the first frame
/// and once the library finishes loading its tracks.
class StartupIdentityReconciler {
  /// Target library repository.
  final LibraryRepository repository;

  /// Optional future gate resolving once the library has finished initial load.
  final Future<void> Function()? waitForLibraryReady;

  /// Optional check returning `true` while a library folder scan is active.
  final bool Function()? isScanning;

  /// Optional check returning `true` if the host lifecycle was disposed.
  final bool Function()? shouldAbort;

  /// Optional logger override for tests.
  final AppLogger? logger;

  bool _hasRun = false;

  /// Creates a [StartupIdentityReconciler].
  StartupIdentityReconciler({
    required this.repository,
    this.waitForLibraryReady,
    this.isScanning,
    this.shouldAbort,
    this.logger,
  });

  /// Whether [runOnce] has already executed.
  bool get hasRun => _hasRun;

  /// Executes `reconcileTrackIdentities(markUnmatchedMissing: false)` at most
  /// once after [waitForLibraryReady] completes, skipping in
  /// [UserDataAccessMode.safeReadOnly] or when [isScanning] is `true`.
  ///
  /// Errors are logged via [AppLogger] and never propagated to UI callers.
  Future<RelinkReport?> runOnce() async {
    if (_hasRun) return null;
    _hasRun = true;

    if (shouldAbort?.call() == true) return null;
    if (repository.userDataAccessMode == UserDataAccessMode.safeReadOnly) {
      return null;
    }

    final log = logger ?? AppLogger.instance;
    try {
      if (waitForLibraryReady != null) {
        await waitForLibraryReady!();
      }
      if (shouldAbort?.call() == true) return null;
      if (repository.userDataAccessMode == UserDataAccessMode.safeReadOnly) {
        return null;
      }
      if (isScanning?.call() == true) {
        return null;
      }
      return await repository.reconcileTrackIdentities(
        markUnmatchedMissing: false,
      );
    } catch (e, st) {
      log.warning(
        'Identity',
        'Startup identity reconciliation failed: $e',
        e,
        st,
      );
      return null;
    }
  }
}
