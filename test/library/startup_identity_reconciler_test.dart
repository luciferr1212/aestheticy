import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/startup_identity_reconciler.dart';
import 'package:aestheticy/library/track_identity_models.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

class _FakeReconcileRepository extends Fake implements LibraryRepository {
  @override
  UserDataAccessMode userDataAccessMode;

  int reconcileCalls = 0;
  bool? lastMarkUnmatchedMissing;
  bool shouldThrow = false;

  _FakeReconcileRepository({
    this.userDataAccessMode = UserDataAccessMode.normal,
  });

  @override
  Future<RelinkReport> reconcileTrackIdentities({
    DateTime? now,
    bool markUnmatchedMissing = true,
  }) async {
    reconcileCalls++;
    lastMarkUnmatchedMissing = markUnmatchedMissing;
    if (shouldThrow) {
      throw StateError('Simulated reconcile error');
    }
    return const RelinkReport(created: 2, relinked: 1);
  }
}

void main() {
  group('StartupIdentityReconciler (S3)', () {
    test(
        'runs once, waits for library tracks to finish loading, passes markUnmatchedMissing=false, and is idempotent',
        () async {
      final repo = _FakeReconcileRepository();
      final libraryLoaded = Completer<void>();

      final reconciler = StartupIdentityReconciler(
        repository: repo,
        waitForLibraryReady: () => libraryLoaded.future,
      );

      final pending = reconciler.runOnce();
      await Future<void>.delayed(Duration.zero);
      // Must NOT reconcile before library has finished loading its tracks.
      expect(repo.reconcileCalls, equals(0));

      libraryLoaded.complete();
      final report = await pending;
      expect(report, isNotNull);
      expect(report!.created, equals(2));
      expect(report.relinked, equals(1));
      expect(repo.reconcileCalls, equals(1));
      expect(repo.lastMarkUnmatchedMissing, isFalse);

      // Second invocation is a no-op.
      final second = await reconciler.runOnce();
      expect(second, isNull);
      expect(repo.reconcileCalls, equals(1));
    });

    test('skips immediately in Safe Read-Only mode', () async {
      final repo = _FakeReconcileRepository(
        userDataAccessMode: UserDataAccessMode.safeReadOnly,
      );
      var gateChecked = false;
      final reconciler = StartupIdentityReconciler(
        repository: repo,
        waitForLibraryReady: () async {
          gateChecked = true;
        },
      );

      final result = await reconciler.runOnce();
      expect(result, isNull);
      expect(gateChecked, isFalse);
      expect(repo.reconcileCalls, equals(0));
    });

    test('skips while an active scan is in progress', () async {
      final repo = _FakeReconcileRepository();
      final reconciler = StartupIdentityReconciler(
        repository: repo,
        isScanning: () => true,
      );

      final result = await reconciler.runOnce();
      expect(result, isNull);
      expect(repo.reconcileCalls, equals(0));
    });

    test('catches errors cleanly and logs them without throwing', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('startup_reconciler_log_');
      addTearDown(() => tempDir.delete(recursive: true));

      final logBuffer = StringBuffer();
      final logger = AppLogger(customSink: logBuffer);
      final repo = _FakeReconcileRepository()..shouldThrow = true;

      final reconciler = StartupIdentityReconciler(
        repository: repo,
        logger: logger,
      );

      final result = await reconciler.runOnce();
      expect(result, isNull);
      expect(repo.reconcileCalls, equals(1));
      expect(logBuffer.toString(), contains('Startup identity reconciliation failed'));
    });

    test('openFile and fromDatabase do not run reconcile synchronously',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('startup_reconcile_sync_');
      addTearDown(() => tempDir.delete(recursive: true));

      final libPath = p.join(tempDir.path, 'library.db');
      final userPath = p.join(tempDir.path, 'userdata.db');
      final repo1 = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
      );
      await repo1.setFavorite('C:\\Music\\song.mp3', true);
      await repo1.close();

      // Reopen: openFile must NOT populate track_identity synchronously.
      final repo2 = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
      );
      addTearDown(repo2.close);
      expect(await repo2.listTrackIdentities(), isEmpty);

      // Post-frame reconciler creates/backfills identities once triggered.
      final report = await StartupIdentityReconciler(repository: repo2).runOnce();
      expect(report, isNotNull);
      expect(report!.backfilledUserPaths, equals(1));
      expect(await repo2.listTrackIdentities(), hasLength(1));
    });
  });
}
