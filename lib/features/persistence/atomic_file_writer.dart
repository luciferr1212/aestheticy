import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/result.dart';
import '../../diagnostics/app_logger.dart';

/// Atomically persists string content to [target] using serialized, coalesced
/// temporary file writes and atomic filesystem renames without deleting the target first.
class AtomicFileWriter {
  /// The final destination file.
  final File target;

  /// Optional override hook for testing concurrency and slow disk writes.
  final Future<void> Function(String content)? onPerformWrite;

  /// Optional error callback invoked when persisting [target] fails.
  final void Function(AppError error)? onError;

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
    this.onError,
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
      } catch (e, st) {
        // Failures never break the chain
        AppLogger.instance.error(
          'AtomicFileWriter',
          'Queued atomic write failed for ${p.basename(target.path)}',
          e,
          st,
        );
        onError?.call(AppError.fromException(e, st, 'error.ioFailure'));
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
      } catch (e, st) {
        AppLogger.instance.warn(
          'AtomicFileWriter',
          'Failed creating parent directory for ${p.basename(target.path)}',
          e,
          st,
        );
      }
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
      } catch (renameErr, renameSt) {
        AppLogger.instance.debug(
          'AtomicFileWriter',
          'Atomic rename failed, attempting copy fallback',
          renameErr,
          renameSt,
        );
        // Fallback 1: copy temp to target, then delete temp
        try {
          await tmpFile.copy(target.path);
          try {
            if (tmpFile.existsSync()) {
              await tmpFile.delete();
            }
          } catch (delErr, delSt) {
            // ignore-silent: deleting temporary file created by AtomicFileWriter
            AppLogger.instance.debug(
              'AtomicFileWriter',
              'Failed removing temp file after copy fallback',
              delErr,
              delSt,
            );
          }
        } catch (copyErr, copySt) {
          AppLogger.instance.debug(
            'AtomicFileWriter',
            'Copy fallback failed, attempting direct write',
            copyErr,
            copySt,
          );
          // Fallback 2: write directly to target
          try {
            await target.writeAsString(content, flush: true);
          } catch (directErr, directSt) {
            AppLogger.instance.error(
              'AtomicFileWriter',
              'All write fallbacks failed for ${p.basename(target.path)}',
              directErr,
              directSt,
            );
            onError?.call(
              AppError.fromException(directErr, directSt, 'error.ioFailure'),
            );
          }
        }
      }
    } catch (e, st) {
      AppLogger.instance.error(
        'AtomicFileWriter',
        'Temp write failed for ${p.basename(target.path)}',
        e,
        st,
      );
      onError?.call(AppError.fromException(e, st, 'error.ioFailure'));
    } finally {
      // Always delete leftover temp file
      try {
        if (tmpFile.existsSync()) {
          await tmpFile.delete();
        }
      } catch (e, st) {
        // ignore-silent: deleting temporary file created by AtomicFileWriter
        AppLogger.instance.debug(
          'AtomicFileWriter',
          'Failed deleting leftover temp file',
          e,
          st,
        );
      }
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
      } catch (e, st) {
        AppLogger.instance.warn(
          'AtomicFileWriter',
          'Failed creating parent directory synchronously',
          e,
          st,
        );
      }
    }

    final tmpFile = File(p.join(
      parentDir.path,
      '${p.basename(target.path)}.${DateTime.now().microsecondsSinceEpoch}.${_counter++}.tmp',
    ));

    try {
      tmpFile.writeAsStringSync(content, flush: true);
      try {
        tmpFile.renameSync(target.path);
      } catch (renameErr, renameSt) {
        AppLogger.instance.debug(
          'AtomicFileWriter',
          'Sync rename failed, attempting copy fallback',
          renameErr,
          renameSt,
        );
        // Fallback 1: copy temp to target, then delete temp
        try {
          tmpFile.copySync(target.path);
          try {
            if (tmpFile.existsSync()) {
              tmpFile.deleteSync();
            }
          } catch (delErr, delSt) {
            // ignore-silent: deleting temporary file created by AtomicFileWriter
            AppLogger.instance.debug(
              'AtomicFileWriter',
              'Failed removing temp file after sync copy fallback',
              delErr,
              delSt,
            );
          }
        } catch (copyErr, copySt) {
          AppLogger.instance.debug(
            'AtomicFileWriter',
            'Sync copy fallback failed, attempting direct write',
            copyErr,
            copySt,
          );
          // Fallback 2: write directly to target
          try {
            target.writeAsStringSync(content, flush: true);
          } catch (directErr, directSt) {
            AppLogger.instance.error(
              'AtomicFileWriter',
              'All sync write fallbacks failed for ${p.basename(target.path)}',
              directErr,
              directSt,
            );
            onError?.call(
              AppError.fromException(directErr, directSt, 'error.ioFailure'),
            );
          }
        }
      }
    } catch (e, st) {
      AppLogger.instance.error(
        'AtomicFileWriter',
        'Sync temp write failed for ${p.basename(target.path)}',
        e,
        st,
      );
      onError?.call(AppError.fromException(e, st, 'error.ioFailure'));
    } finally {
      try {
        if (tmpFile.existsSync()) {
          tmpFile.deleteSync();
        }
      } catch (e, st) {
        // ignore-silent: deleting temporary file created by AtomicFileWriter
        AppLogger.instance.debug(
          'AtomicFileWriter',
          'Failed deleting leftover sync temp file',
          e,
          st,
        );
      }
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
