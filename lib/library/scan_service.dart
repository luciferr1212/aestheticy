/// High-level library scanning service coordinated with [LibraryRepository].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

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

  /// Creates a [ScanService].
  ScanService({
    required this.repository,
    LibraryScanner? scanner,
  }) : scanner = scanner ?? LibraryScanner(repository: repository);

  /// Current progress state of the active or most recent scan.
  ScanProgress get currentProgress => _currentProgress;

  /// Whether a scan operation is currently in progress.
  bool get isScanning => _isScanning;

  /// Broadcast stream of [ScanProgress] events emitted during scans.
  Stream<ScanProgress> get progressStream => _progressController.stream;

  /// Adds a filesystem folder path to the library and scans it immediately.
  Future<LibraryFolder> addFolder(String path) async {
    final folder = await repository.addFolder(path);
    await _scanSingleFolder(folder);
    return folder;
  }

  /// Rescans all registered library folders sequentially.
  Future<void> rescanAll() async {
    if (_isScanning) return;
    final folders = await repository.listFolders();
    _isCancelled = false;

    for (final folder in folders) {
      if (_isCancelled || _disposed) break;
      await _scanSingleFolder(folder);
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
    notifyListeners();
  }

  Future<void> _scanSingleFolder(LibraryFolder folder) async {
    _isScanning = true;
    _isCancelled = false;
    notifyListeners();

    try {
      await for (final progress in scanner.scan(folder)) {
        if (_disposed) break;
        _currentProgress = progress;
        if (!_progressController.isClosed) {
          _progressController.add(progress);
        }
        notifyListeners();
      }
    } finally {
      _isScanning = false;
      if (!_disposed) {
        notifyListeners();
      }
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
