import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Severity levels for application diagnostic logging.
enum LogLevel {
  info,
  warning,
  error,
}

/// Robust diagnostics logger that writes to a rotating log file in the support directory.
class AppLogger {
  /// Maximum single log file size before rotation (1 MB).
  static const int maxFileSizeBytes = 1024 * 1024;

  /// Maximum number of rotated log archives to keep.
  static const int maxRotatedFiles = 3;

  /// Maximum character length per log message before truncation.
  static const int maxMessageLength = 500;

  final Directory? logsDirectory;
  final Future<Directory> Function()? directoryProvider;
  final StringSink? customSink;
  final String Function()? userNameProvider;

  Directory? _resolvedDir;
  File? _currentLogFile;
  final List<String> _writeBuffer = [];
  Timer? _flushTimer;
  bool _isFlushing = false;
  bool _isDisposed = false;
  bool _disabled = false;

  /// Creates an [AppLogger] with optional injected directory or sink for testing.
  AppLogger({
    this.logsDirectory,
    this.directoryProvider,
    this.customSink,
    this.userNameProvider,
  });

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
      _disabled = true;
    }
  }

  /// Logs an informational message.
  void info(String tag, String message) {
    _log(LogLevel.info, tag, message);
  }

  /// Logs a warning message with optional error and stack trace.
  void warning(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    final sb = StringBuffer(message);
    if (error != null) sb.write(' | error: $error');
    if (stackTrace != null) sb.write(' | $stackTrace');
    _log(LogLevel.warning, tag, sb.toString());
  }

  /// Logs an error message and immediately flushes the buffer.
  void error(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    final sb = StringBuffer(message);
    if (error != null) sb.write(' | error: $error');
    if (stackTrace != null) sb.write(' | $stackTrace');
    _log(LogLevel.error, tag, sb.toString(), immediateFlush: true);
  }

  void _log(LogLevel level, String tag, String rawMessage, {bool immediateFlush = false}) {
    if (_isDisposed) return;

    final sanitized = sanitizeMessage(rawMessage, userName: userNameProvider?.call());
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final formattedLine = '$timestamp [${level.name.toUpperCase()}] [$tag] $sanitized';

    if (customSink != null) {
      try {
        customSink!.writeln(formattedLine);
      } catch (_) {}
      return;
    }

    if (_disabled) return;

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

    // 3. Strip full directory paths down to file/folder name only
    text = text.replaceAllMapped(
      RegExp(r'(?:[a-zA-Z]:[\\/]|file:\/\/\/?|\/)[^\s"<>]+[\\/]([^\s\\/]+)'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'(?:\\{1,2}[^\s"<>]+[\\/])([^\s\\/]+)'),
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
      // Unwritable -> do not throw
    } finally {
      _isFlushing = false;
    }
  }

  void _checkRotationSync() {
    if (_currentLogFile == null || !_currentLogFile!.existsSync()) return;

    try {
      final length = _currentLogFile!.lengthSync();
      if (length >= maxFileSizeBytes) {
        _rotateLogsSync();
      }
    } catch (_) {}
  }

  void _rotateLogsSync() {
    if (_resolvedDir == null) return;
    try {
      final base = _resolvedDir!.path;
      // aestheticy.3.log is overwritten/deleted
      final file3 = File(p.join(base, 'aestheticy.3.log'));
      if (file3.existsSync()) {
        try {
          file3.deleteSync();
        } catch (_) {}
      }

      // aestheticy.2.log -> aestheticy.3.log
      final file2 = File(p.join(base, 'aestheticy.2.log'));
      if (file2.existsSync()) {
        try {
          file2.renameSync(file3.path);
        } catch (_) {}
      }

      // aestheticy.1.log -> aestheticy.2.log
      final file1 = File(p.join(base, 'aestheticy.1.log'));
      if (file1.existsSync()) {
        try {
          file1.renameSync(file2.path);
        } catch (_) {}
      }

      // aestheticy.log -> aestheticy.1.log
      if (_currentLogFile != null && _currentLogFile!.existsSync()) {
        try {
          _currentLogFile!.renameSync(file1.path);
        } catch (_) {}
      }
    } catch (_) {}
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

      // If we need more lines, check aestheticy.1.log
      if (lines.length < limit) {
        final file1 = File(p.join(_resolvedDir!.path, 'aestheticy.1.log'));
        if (file1.existsSync()) {
          final olderLines = file1.readAsLinesSync();
          lines.insertAll(0, olderLines);
        }
      }

      if (lines.length <= limit) {
        return lines;
      }
      return lines.sublist(lines.length - limit);
    } catch (_) {
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
