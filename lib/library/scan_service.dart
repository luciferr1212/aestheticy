/// High-level library scanning service coordinated with [LibraryRepository].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:aestheticy/core/result.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/library_scanner.dart';
import 'package:aestheticy/library/models.dart';

/// Application service coordinating folder discovery, scanning progress,
/// and reactive updates for user interfaces.
class ScanService extends ChangeNotifier {
  /// The underlying music storage repository.
  final LibraryRepository repository;

  /// The active scanner instance.
  final LibraryScanner scanner;

  final StreamController<ScanProgress> _progressController =
      StreamController<ScanProgress>.broadcast();

  ScanProgress _currentProgress = const ScanProgress();
  bool _isScanning = false;
  bool _isCancelled = false;
  bool _disposed = false;
  int _libraryVersion = 0;

  /// Creates a [ScanService].
  ScanService({
    required this.repository,
    LibraryScanner? scanner,
  }) : scanner = scanner ?? LibraryScanner(repository: repository);

  /// Current progress state of the active or most recent scan.
  ScanProgress get currentProgress => _currentProgress;

  /// Whether a scan operation is currently in progress.
  bool get isScanning => _isScanning;

  /// Monotonically incremented whenever a scan finishes or a library folder is
  /// added/removed so dependent caches and pages revalidate consistently.
  int get libraryVersion => _libraryVersion;

  /// Broadcast stream of [ScanProgress] events emitted during scans.
  Stream<ScanProgress> get progressStream => _progressController.stream;

  /// Adds a filesystem folder path to the library and scans it immediately,
  /// returning a typed [Result] without throwing on I/O or database failures.
  Future<Result<LibraryFolder>> addFolderResult(String path) async {
    try {
      final folder = await addFolder(path);
      return Ok(folder);
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        'ScanService',
        'Failed to add folder',
        error,
        stackTrace,
      );
      return Err(
        AppError.fromException(error, stackTrace, 'error.folderAddFailed'),
      );
    }
  }

  /// Adds a filesystem folder path to the library and scans it immediately.
  Future<LibraryFolder> addFolder(String path) async {
    final folder = await repository.addFolder(path);
    _isScanning = true;
    _isCancelled = false;
    _currentProgress = const ScanProgress();
    notifyListeners();

    try {
      await _scanFolders([folder]);
    } finally {
      _finishScanSession();
    }
    return folder;
  }

  /// Removes a library folder, deletes its tracks, and notifies listeners so
  /// all library views refresh without flicker.
  Future<void> removeFolder(int folderId) async {
    await repository.removeFolder(folderId);
    _libraryVersion++;
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Rescans all registered library folders sequentially while keeping
  /// [isScanning] continuously `true` until the entire run completes.
  Future<void> rescanAll() async {
    if (_isScanning) return;
    _isScanning = true;
    _isCancelled = false;
    _currentProgress = const ScanProgress();
    notifyListeners();

    try {
      final folders = await repository.listFolders();
      await _scanFolders(folders);
    } finally {
      _finishScanSession();
    }
  }

  /// Cancels any currently executing scan.
  void cancel() {
    _isCancelled = true;
    scanner.cancel();
    _isScanning = false;
    _currentProgress = _currentProgress.copyWith(done: true);
    if (!_progressController.isClosed) {
      _progressController.add(_currentProgress);
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _scanFolders(List<LibraryFolder> folders) async {
    for (var i = 0; i < folders.length; i++) {
      if (_isCancelled || _disposed) break;
      final isLast = i == folders.length - 1;
      await for (final progress in scanner.scan(folders[i])) {
        if (_disposed || _isCancelled) break;
        final forwarded = isLast ? progress : progress.copyWith(done: false);
        _currentProgress = forwarded;
        if (!_progressController.isClosed) {
          _progressController.add(forwarded);
        }
        notifyListeners();
      }
    }
  }

  void _finishScanSession() {
    _isScanning = false;
    _libraryVersion++;
    if (!_disposed) {
      if (!_currentProgress.done) {
        _currentProgress = _currentProgress.copyWith(done: true);
        if (!_progressController.isClosed) {
          _progressController.add(_currentProgress);
        }
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    _progressController.close();
    super.dispose();
  }
}
