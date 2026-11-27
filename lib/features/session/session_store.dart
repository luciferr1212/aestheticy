import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/result.dart';
import '../../diagnostics/app_logger.dart';
import '../persistence/atomic_file_writer.dart';
import '../persistence/versioned_json_store.dart';
import 'saved_session.dart';

/// Single source of truth managing playback session persistence to `session.json`.
class SessionStore {
  static const int currentSchemaVersion = 1;
  static const Set<String> _knownKeys = {
    'queue',
    'currentIndex',
    'currentEntryId',
    'currentUri',
    'positionMs',
    'shuffle',
    'repeatMode',
    'savedAt',
  };

  final Future<Directory> Function()? directoryProvider;
  Directory? directory;
  final void Function(AppError error)? onError;
  SavedSession _session = SavedSession.empty;
  Timer? _debounceTimer;
  int _writeGeneration = 0;
  AtomicFileWriter? _writer;
  Map<String, Object?> _unknownFields = const {};
  final VersionedJsonStoreHelper _versionHelper = VersionedJsonStoreHelper(
    storeName: 'Session',
    fileName: 'session.json',
    currentSchemaVersion: currentSchemaVersion,
    knownKeys: _knownKeys,
  );

  /// Creates a [SessionStore] with an optional injected [directory] or [directoryProvider].
  SessionStore({
    this.directoryProvider,
    this.directory,
    this.onError,
    SavedSession initialSession = SavedSession.empty,
  }) : _session = initialSession {
    if (directory != null) {
      _writer = AtomicFileWriter(
        File(p.join(directory!.path, 'session.json')),
        onError: onError,
      );
    }
  }

  /// Current in-memory session snapshot.
  SavedSession get session => _session;

  /// Current write generation counter.
  @visibleForTesting
  int get writeGeneration => _writeGeneration;

  AtomicFileWriter? _getWriter() {
    if (_writer != null) return _writer;
    if (directory != null) {
      return _writer = AtomicFileWriter(
        File(p.join(directory!.path, 'session.json')),
        onError: onError,
      );
    }
    return null;
  }

  /// Initializes the store and loads the last session from disk.
  Future<void> init() async {
    try {
      if (directory == null) {
        if (directoryProvider != null) {
          directory = await directoryProvider!();
        } else {
          final supportDir = await getApplicationSupportDirectory();
          directory = Directory(p.join(supportDir.path, 'Aestheticy'));
        }
      }
      if (!directory!.existsSync()) {
        directory!.createSync(recursive: true);
      }
      _writer ??= AtomicFileWriter(
        File(p.join(directory!.path, 'session.json')),
        onError: onError,
      );
      await _loadFromFile();
    } catch (e, st) {
      // Keep empty defaults, never throw to playback
      AppLogger.instance.warn(
        'Session',
        'SessionStore.init failed, continuing with empty session',
        e,
        st,
      );
    }
  }

  /// Updates the stored session and schedules a debounced atomic write.
  void save(SavedSession newSession, {bool debounce = true}) {
    _writeGeneration++;
    _session = newSession;
    if (debounce) {
      _scheduleWrite();
    } else {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _writeToDisk();
    }
  }

  /// Updates the stored session and writes it to disk synchronously and atomically.
  void saveSync(SavedSession newSession) {
    _writeGeneration++;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _session = newSession;
    writeToDiskSync();
  }

  /// Synchronously writes session snapshot to disk atomically.
  void writeToDiskSync() {
    final writer = _getWriter();
    if (writer == null) return;
    try {
      final payload = _versionHelper.preparePayload(
        _session.toJson(),
        _unknownFields,
      );
      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
      writer.writeSync(jsonStr);
      final dir = directory;
      if (dir != null) {
        _versionHelper.writeRollingBackupSync(dir, jsonStr);
      }
    } catch (e, st) {
      // In-memory value preserved, failed write does not crash
      AppLogger.instance.error(
        'Session',
        'Synchronous session write failed',
        e,
        st,
      );
      onError?.call(AppError.fromException(e, st, 'error.ioFailure'));
    }
  }

  /// Clears the stored session and writes an empty session to disk.
  Future<void> clear() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _session = SavedSession.empty;
    await _writeToDisk();
    await _writer?.flush();
  }

  Future<void> _loadFromFile() async {
    final dir = directory;
    if (dir == null) return;
    final loaded = await _versionHelper.load(dir);
    if (loaded.wasQuarantined) {
      _session = SavedSession.empty;
      _unknownFields = const {};
      return;
    }
    if (loaded.data != null) {
      _session = SavedSession.fromJson(loaded.data);
      _unknownFields = loaded.unknownFields;
    }
  }

  void _scheduleWrite() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      _writeToDisk();
    });
  }

  Future<void> _writeToDisk() async {
    final writer = _getWriter();
    if (writer == null) return;
    final gen = _writeGeneration;
    try {
      final payload = _versionHelper.preparePayload(
        _session.toJson(),
        _unknownFields,
      );
      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
      if (_writeGeneration != gen) return;
      await writer.write(jsonStr);
      final dir = directory;
      if (dir != null && _writeGeneration == gen) {
        _versionHelper.writeRollingBackupSync(dir, jsonStr);
      }
    } catch (e, st) {
      // In-memory value preserved, failed write does not crash
      AppLogger.instance.error(
        'Session',
        'Async session write failed',
        e,
        st,
      );
      onError?.call(AppError.fromException(e, st, 'error.ioFailure'));
    }
  }

  /// Immediately flushes pending writes to disk (for unit testing).
  @visibleForTesting
  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _writeToDisk();
    await _writer?.flush();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _writer?.dispose();
  }
}
