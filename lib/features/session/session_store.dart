import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../diagnostics/app_logger.dart';
import 'saved_session.dart';

/// Single source of truth managing playback session persistence to `session.json`.
class SessionStore {
  final Future<Directory> Function()? directoryProvider;
  Directory? directory;
  SavedSession _session = SavedSession.empty;
  Timer? _debounceTimer;
  int _writeGeneration = 0;

  /// Creates a [SessionStore] with an optional injected [directory] or [directoryProvider].
  SessionStore({
    this.directoryProvider,
    this.directory,
    SavedSession initialSession = SavedSession.empty,
  }) : _session = initialSession;

  /// Current in-memory session snapshot.
  SavedSession get session => _session;

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
      await _loadFromFile();
    } catch (_) {
      // Keep empty defaults, never throw to playback
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
      unawaited(_writeToDisk());
    }
  }

  /// Updates the stored session and writes it to disk synchronously and atomically.
  void saveSync(SavedSession newSession) {
    _writeGeneration++;
    _debounceTimer?.cancel();
    _session = newSession;
    writeToDiskSync();
  }

  /// Synchronously writes session snapshot to disk atomically.
  void writeToDiskSync() {
    if (directory == null) return;
    try {
      final targetPath = p.join(directory!.path, 'session.json');
      final tmpPath = p.join(
        directory!.path,
        'session.json.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      final tmpFile = File(tmpPath);
      final jsonStr =
          const JsonEncoder.withIndent('  ').convert(_session.toJson());

      tmpFile.writeAsStringSync(jsonStr, flush: true);

      if (tmpFile.existsSync()) {
        final targetFile = File(targetPath);
        try {
          if (targetFile.existsSync()) {
            targetFile.deleteSync();
          }
          tmpFile.renameSync(targetPath);
        } catch (_) {
          try {
            tmpFile.copySync(targetPath);
            tmpFile.deleteSync();
          } catch (_) {
            File(targetPath).writeAsStringSync(jsonStr, flush: true);
          }
        }
      }
    } catch (_) {
      // In-memory value preserved, failed write does not crash
    }
  }

  /// Clears the stored session and writes an empty session to disk.
  Future<void> clear() async {
    _debounceTimer?.cancel();
    _session = SavedSession.empty;
    await _writeToDisk();
  }

  Future<void> _loadFromFile() async {
    if (directory == null) return;
    final file = File(p.join(directory!.path, 'session.json'));
    if (!file.existsSync()) return;

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, Object?>) {
        _session = SavedSession.fromJson(decoded);
      } else if (decoded is Map) {
        _session = SavedSession.fromJson(Map<String, Object?>.from(decoded));
      } else {
        _handleCorruptFile(file);
      }
    } catch (_) {
      _handleCorruptFile(file);
    }
  }

  void _handleCorruptFile(File file) {
    _session = SavedSession.empty;
    AppLogger.instance.warning(
      'Session',
      'Corrupt session.json backed up to session.json.bad',
    );
    try {
      final badPath = p.join(directory!.path, 'session.json.bad');
      final badFile = File(badPath);
      if (badFile.existsSync()) {
        badFile.deleteSync();
      }
      file.renameSync(badPath);
    } catch (_) {}
  }

  void _scheduleWrite() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      unawaited(_writeToDisk());
    });
  }

  Future<void> _writeToDisk() async {
    if (directory == null) return;
    final gen = _writeGeneration;
    try {
      final targetPath = p.join(directory!.path, 'session.json');
      final tmpPath = p.join(
        directory!.path,
        'session.json.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      final tmpFile = File(tmpPath);
      final jsonStr =
          const JsonEncoder.withIndent('  ').convert(_session.toJson());

      await tmpFile.writeAsString(jsonStr, flush: true);

      if (_writeGeneration != gen) {
        // Newer write occurred while writing; discard stale file
        try {
          if (tmpFile.existsSync()) tmpFile.deleteSync();
        } catch (_) {}
        return;
      }

      if (tmpFile.existsSync()) {
        final targetFile = File(targetPath);
        try {
          if (targetFile.existsSync()) {
            await targetFile.delete();
          }
          await tmpFile.rename(targetPath);
        } catch (_) {
          try {
            await tmpFile.copy(targetPath);
            await tmpFile.delete();
          } catch (_) {
            await File(targetPath).writeAsString(jsonStr, flush: true);
          }
        }
      }
    } catch (_) {
      // In-memory value preserved, failed write does not crash
    }
  }

  /// Immediately flushes pending writes to disk (for unit testing).
  @visibleForTesting
  Future<void> flush() async {
    _debounceTimer?.cancel();
    await _writeToDisk();
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
}
