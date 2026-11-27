import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Severity levels for application diagnostic logging.
enum LogLevel {
  debug,
  info,
  warn,
  error,
}

/// Robust diagnostics logger that writes to a rotating log file in the support directory.
class AppLogger {
  /// Maximum single log file size before rotation (1 MB).
  static const int maxFileSizeBytes = 1024 * 1024;

  /// Maximum total log files kept on disk (`aestheticy.log` + `.1.log`..`.4.log`).
  static const int maxLogFiles = 5;

  /// Maximum number of rotated log archives to keep (`aestheticy.1.log`..`aestheticy.4.log`).
  static const int maxRotatedFiles = maxLogFiles - 1;

  /// Exact pattern matching rotated archive files owned by [AppLogger].
  static final RegExp _rotatedFilePattern =
      RegExp(r'^aestheticy\.(\d+)\.log$');

  /// Maximum character length per log message before truncation.
  static const int maxMessageLength = 500;

  final Directory? logsDirectory;
  final Future<Directory> Function()? directoryProvider;
  final StringSink? customSink;
  final String Function()? userNameProvider;
  final LogLevel minLevel;
  final int _effectiveMaxFileSizeBytes;

  Directory? _resolvedDir;
  File? _currentLogFile;
  final List<String> _writeBuffer = [];
  Timer? _flushTimer;
  bool _isFlushing = false;
  bool _isDisposed = false;
  bool _disabled = false;

  /// Creates an [AppLogger] with optional injected directory, sink, or log level.
  AppLogger({
    this.logsDirectory,
    this.directoryProvider,
    this.customSink,
    this.userNameProvider,
    this.minLevel = LogLevel.debug,
    @visibleForTesting int? maxFileSizeBytesOverride,
  }) : _effectiveMaxFileSizeBytes =
            maxFileSizeBytesOverride ?? maxFileSizeBytes;

  static AppLogger? _instance;

  /// Global shared logger instance.
  static AppLogger get instance => _instance ??= AppLogger();
  static set instance(AppLogger logger) => _instance = logger;

  /// The directory containing the log files.
  Directory? get logDirectory => _resolvedDir;

  /// Initializes the logger, ensuring directory exists and files are prepared.
  Future<void> init() async {
    if (customSink != null) return;
    try {
      if (logsDirectory != null) {
        _resolvedDir = logsDirectory;
      } else if (directoryProvider != null) {
        _resolvedDir = await directoryProvider!();
      } else {
        final supportDir = await getApplicationSupportDirectory();
        _resolvedDir = Directory(p.join(supportDir.path, 'Aestheticy', 'logs'));
      }

      if (!_resolvedDir!.existsSync()) {
        _resolvedDir!.createSync(recursive: true);
      }
      _currentLogFile = File(p.join(_resolvedDir!.path, 'aestheticy.log'));
      _checkRotationSync();
    } catch (_) {
      // ignore-silent: AppLogger.init disables file logging when support dir is unwritable
      _disabled = true;
    }
  }

  /// Records an intentionally swallowed non-fatal error at [LogLevel.debug].
  static void swallow(
    Object error,
    StackTrace stack, {
    required String where,
    String? context,
  }) {
    final message = (context == null || context.isEmpty)
        ? 'Swallowed error in $where'
        : 'Swallowed error in $where ($context)';
    instance.debug(where, message, error, stack);
  }

  /// Logs a debug message with optional error and stack trace.
  void debug(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    final sb = StringBuffer(message);
    if (error != null) sb.write(' | error: $error');
    if (stackTrace != null) sb.write(' | $stackTrace');
    _log(LogLevel.debug, tag, sb.toString());
  }

  /// Logs an informational message.
  void info(String tag, String message) {
    _log(LogLevel.info, tag, message);
  }

  /// Logs a warning message with optional error and stack trace.
  void warn(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    final sb = StringBuffer(message);
    if (error != null) sb.write(' | error: $error');
    if (stackTrace != null) sb.write(' | $stackTrace');
    _log(LogLevel.warn, tag, sb.toString());
  }

  /// Alias for [warn] kept for compatibility with existing callers.
  void warning(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    warn(tag, message, error, stackTrace);
  }

  /// Logs an error message and immediately flushes the buffer.
  void error(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    final sb = StringBuffer(message);
    if (error != null) sb.write(' | error: $error');
    if (stackTrace != null) sb.write(' | $stackTrace');
    _log(LogLevel.error, tag, sb.toString(), immediateFlush: true);
  }

  void _log(LogLevel level, String tag, String rawMessage, {bool immediateFlush = false}) {
    if (_isDisposed || level.index < minLevel.index) return;

    final sanitized = sanitizeMessage(rawMessage, userName: userNameProvider?.call());
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final formattedLine = '$timestamp [${level.name.toUpperCase()}] [$tag] $sanitized';

    if (customSink != null) {
      try {
        customSink!.writeln(formattedLine);
      } catch (_) {
        // ignore-silent: writing to injected customSink inside AppLogger cannot recurse
      }
      return;
    }

    if (_disabled || _currentLogFile == null) return;

    _writeBuffer.add(formattedLine);

    if (immediateFlush || level == LogLevel.error) {
      unawaited(flush());
    } else {
      _scheduleFlush();
    }
  }

  /// Cleanses [input] according to privacy rules:
  /// - Strips user names
  /// - Redacts tokens, keys, passwords
  /// - Strips directory paths to leave only filenames
  /// - Truncates to [maxMessageLength] characters.
  static String sanitizeMessage(String input, {String? userName}) {
    var text = input;

    // 1. Scrub user name if known
    if (userName != null && userName.trim().isNotEmpty) {
      text = text.replaceAll(userName.trim(), '[REDACTED_USER]');
    }

    // 2. Redact tokens, keys, secrets, passwords
    text = text.replaceAllMapped(
      RegExp(r'\b(token|bearer|api[-_ ]?key|key|secret|password)[\s:=]+([^\s,;:&]+)', caseSensitive: false),
      (m) => '${m.group(1)}: [REDACTED]',
    );

    // 3. Strip full directory paths (quoted or unquoted) down to file/folder name only
    text = text.replaceAllMapped(
      RegExp(r'"(?:[a-zA-Z]:[\\/]|file:\/\/\/?|\/)[^"\r\n]+[\\/]([^"\\/\r\n]+)"'),
      (m) => '"${m.group(1) ?? ''}"',
    );
    text = text.replaceAllMapped(
      RegExp(r"'(?:[a-zA-Z]:[\\/]|file:\/\/\/?|\/)[^'\r\n]+[\\/]([^'\\/\r\n]+)'"),
      (m) => "'${m.group(1) ?? ''}'",
    );
    text = text.replaceAllMapped(
      RegExp(r'(?:[a-zA-Z]:[\\/]|file:\/\/\/?|\/)[^\s"<>]+[\\/]([^\s\\/]+)'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'(?:\\{1,2}[^\s"<>]+[\\/])([^\s\\/]+)'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\b[a-zA-Z]:[\\/]([^\s\\/"]+)'),
      (m) => m.group(1) ?? '',
    );

    // 4. Flatten newlines and control characters
    text = text.replaceAll('\r', ' ').replaceAll('\n', ' ');

    // 5. Truncate to maxMessageLength
    if (text.length > maxMessageLength) {
      text = text.substring(0, maxMessageLength);
    }

    return text.trim();
  }

  void _scheduleFlush() {
    if (_flushTimer != null && _flushTimer!.isActive) return;
    _flushTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(flush());
    });
  }

  /// Flushes pending buffered log lines to disk.
  Future<void> flush() async {
    _flushTimer?.cancel();
    if (_isFlushing || _writeBuffer.isEmpty || _disabled || _currentLogFile == null) {
      return;
    }
    _isFlushing = true;
    try {
      _checkRotationSync();
      final linesToWrite = List<String>.from(_writeBuffer);
      _writeBuffer.clear();

      final content = '${linesToWrite.join('\n')}\n';
      _currentLogFile!.writeAsStringSync(
        content,
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // ignore-silent: AppLogger.flush avoids recursion when log file is unwritable
    } finally {
      _isFlushing = false;
    }
  }

  void _checkRotationSync() {
    if (_currentLogFile == null || !_currentLogFile!.existsSync()) return;

    try {
      final length = _currentLogFile!.lengthSync();
      if (length >= _effectiveMaxFileSizeBytes) {
        _rotateLogsSync();
      }
    } catch (_) {
      // ignore-silent: reading log file length for rotation avoids AppLogger recursion
    }
  }

  void _rotateLogsSync() {
    if (_resolvedDir == null) return;
    try {
      final base = _resolvedDir!.path;
      // Delete only exact rotated archive files strictly beyond maxRotatedFiles.
      for (final entity in _resolvedDir!.listSync()) {
        if (entity is! File) continue;
        final match = _rotatedFilePattern.firstMatch(p.basename(entity.path));
        if (match == null) continue;
        final index = int.tryParse(match.group(1)!);
        if (index != null && index >= maxRotatedFiles) {
          try {
            entity.deleteSync();
          } catch (_) {
            // ignore-silent: deleting expired rotated log archive created by AppLogger
          }
        }
      }

      // Shift aestheticy.(i).log -> aestheticy.(i+1).log from (maxRotatedFiles - 1) down to 1.
      for (var i = maxRotatedFiles - 1; i >= 1; i--) {
        final src = File(p.join(base, 'aestheticy.$i.log'));
        final dst = File(p.join(base, 'aestheticy.${i + 1}.log'));
        if (src.existsSync()) {
          if (dst.existsSync()) {
            dst.deleteSync();
          }
          src.renameSync(dst.path);
        }
      }

      // aestheticy.log -> aestheticy.1.log
      if (_currentLogFile != null && _currentLogFile!.existsSync()) {
        final file1 = File(p.join(base, 'aestheticy.1.log'));
        if (file1.existsSync()) {
          file1.deleteSync();
        }
        _currentLogFile!.renameSync(file1.path);
      }
    } catch (_) {
      // ignore-silent: rotating/renaming AppLogger archive files avoids recursive logging
    }
  }

  /// Reads up to [limit] most recent log lines from the current and archive files.
  Future<List<String>> readRecentLines({int limit = 100}) async {
    if (_disabled || _resolvedDir == null) return [];

    try {
      await flush();
      final lines = <String>[];

      // Read current log file
      if (_currentLogFile != null && _currentLogFile!.existsSync()) {
        final currentLines = _currentLogFile!.readAsLinesSync();
        lines.addAll(currentLines);
      }

      // Backfill from newest rotated archives until limit is reached.
      for (var i = 1; i <= maxRotatedFiles && lines.length < limit; i++) {
        final rotated = File(p.join(_resolvedDir!.path, 'aestheticy.$i.log'));
        if (rotated.existsSync()) {
          final olderLines = rotated.readAsLinesSync();
          lines.insertAll(0, olderLines);
        }
      }

      if (lines.length <= limit) {
        return lines;
      }
      return lines.sublist(lines.length - limit);
    } catch (_) {
      // ignore-silent: reading optional recent log cache returns empty list on failure
      return [];
    }
  }

  /// Flushes remaining lines and closes resources.
  Future<void> dispose() async {
    _isDisposed = true;
    _flushTimer?.cancel();
    await flush();
  }
}
