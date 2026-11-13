import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Atomically persists string content to [target] using serialized, coalesced
/// temporary file writes and atomic filesystem renames without deleting the target first.
class AtomicFileWriter {
  /// The final destination file.
  final File target;

  /// Optional override hook for testing concurrency and slow disk writes.
  final Future<void> Function(String content)? onPerformWrite;

  int _counter = 0;
  int _writeId = 0;
  bool _isWriting = false;
  bool _disposed = false;

  String? _pendingContent;
  Completer<void>? _pendingCompleter;
  Completer<void>? _drainCompleter;

  /// Creates an [AtomicFileWriter] for [target].
  AtomicFileWriter(
    this.target, {
    @visibleForTesting this.onPerformWrite,
  });

  /// Enqueues [content] to be written to disk.
  ///
  /// Writes are executed on one serialized chain. If multiple writes are enqueued
  /// while a write is currently in flight, they are coalesced so that only the
  /// latest content is written. Failures never break the chain.
  Future<void> write(String content) {
    if (_disposed) return Future<void>.value();

    _pendingContent = content;
    _pendingCompleter ??= Completer<void>();
    final future = _pendingCompleter!.future;

    if (!_isWriting) {
      _startDrain();
    }

    return future;
  }

  void _startDrain() {
    _isWriting = true;
    _drainCompleter = Completer<void>();
    _drain();
  }

  Future<void> _drain() async {
    while (_pendingContent != null) {
      final content = _pendingContent!;
      _pendingContent = null;
      final completer = _pendingCompleter;
      _pendingCompleter = null;

      try {
        await performWrite(content);
      } catch (_) {
        // Failures never break the chain
      } finally {
        completer?.complete();
      }
    }

    _isWriting = false;
    final drain = _drainCompleter;
    _drainCompleter = null;
    drain?.complete();
  }

  /// Writes [content] to disk. Can be overridden in tests or delegated to [onPerformWrite].
  @visibleForTesting
  Future<void> performWrite(String content) async {
    if (onPerformWrite != null) {
      await onPerformWrite!(content);
      return;
    }
    await _writeContentToDisk(content);
  }

  Future<void> _writeContentToDisk(String content) async {
    final currentId = ++_writeId;
    final parentDir = target.parent;
    if (!parentDir.existsSync()) {
      try {
        await parentDir.create(recursive: true);
      } catch (_) {}
    }

    final tmpFile = File(p.join(
      parentDir.path,
      '${p.basename(target.path)}.${DateTime.now().microsecondsSinceEpoch}.${_counter++}.tmp',
    ));

    try {
      await tmpFile.writeAsString(content, flush: true);

      // Check if a newer write occurred before committing to disk
      if (_writeId != currentId) {
        return;
      }

      try {
        await tmpFile.rename(target.path);
      } catch (_) {
        // Fallback 1: copy temp to target, then delete temp
        try {
          await tmpFile.copy(target.path);
          try {
            if (tmpFile.existsSync()) {
              await tmpFile.delete();
            }
          } catch (_) {}
        } catch (_) {
          // Fallback 2: write directly to target
          try {
            await target.writeAsString(content, flush: true);
          } catch (_) {
            // Never throw to callers
          }
        }
      }
    } catch (_) {
      // Never throw to callers
    } finally {
      // Always delete leftover temp file
      try {
        if (tmpFile.existsSync()) {
          await tmpFile.delete();
        }
      } catch (_) {}
    }
  }

  /// Synchronously writes [content] to [target] using a temporary file and rename.
  ///
  /// Never deletes [target] before rename and cleans up any leftover temporary files.
  void writeSync(String content) {
    ++_writeId;
    final parentDir = target.parent;
    if (!parentDir.existsSync()) {
      try {
        parentDir.createSync(recursive: true);
      } catch (_) {}
    }

    final tmpFile = File(p.join(
      parentDir.path,
      '${p.basename(target.path)}.${DateTime.now().microsecondsSinceEpoch}.${_counter++}.tmp',
    ));

    try {
      tmpFile.writeAsStringSync(content, flush: true);
      try {
        tmpFile.renameSync(target.path);
      } catch (_) {
        // Fallback 1: copy temp to target, then delete temp
        try {
          tmpFile.copySync(target.path);
          try {
            if (tmpFile.existsSync()) {
              tmpFile.deleteSync();
            }
          } catch (_) {}
        } catch (_) {
          // Fallback 2: write directly to target
          try {
            target.writeAsStringSync(content, flush: true);
          } catch (_) {
            // Never throw to callers
          }
        }
      }
    } catch (_) {
      // Never throw to callers
    } finally {
      try {
        if (tmpFile.existsSync()) {
          tmpFile.deleteSync();
        }
      } catch (_) {}
    }
  }

  /// Waits until all writes enqueued up to this moment have completed.
  Future<void> flush() async {
    if (!_isWriting && _pendingContent == null) {
      return;
    }
    while (_isWriting || _pendingContent != null) {
      final drain = _drainCompleter;
      if (drain != null) {
        await drain.future;
      } else {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// Marks writer as closed. Any already pending writes will still finish when flushed.
  void dispose() {
    _disposed = true;
  }
}
