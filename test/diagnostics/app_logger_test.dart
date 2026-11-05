import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/diagnostics/app_logger.dart';

void main() {
  group('AppLogger Diagnostics Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('app_logger_test_');
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('Log format includes ISO timestamp, level, tag, and message', () async {
      final logDir = Directory('${tempDir.path}/logs');
      final logger = AppLogger(logsDirectory: logDir);
      await logger.init();

      logger.info('TestTag', 'Hello world diagnostic event');
      await logger.flush();

      final lines = await logger.readRecentLines();
      expect(lines, hasLength(1));
      final line = lines.first;
      expect(line, contains('[INFO]'));
      expect(line, contains('[TestTag]'));
      expect(line, contains('Hello world diagnostic event'));
      // Verify ISO timestamp pattern: 2026-xx-xxT...
      expect(line, matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'));

      await logger.dispose();
    });

    test('Privacy rules: sanitizes paths, redacts keys/tokens, truncates long messages, scrubs user name', () {
      const rawUserName = 'mido';
      const input =
          'Error loading C:\\Users\\mido\\Music\\Rock\\hotel_california.mp3 with token: secret12345678 '
          'and key=abcde987654321 for user mido';

      final sanitized = AppLogger.sanitizeMessage(input, userName: rawUserName);

      // Full path is stripped to filename
      expect(sanitized, isNot(contains('C:\\Users\\mido\\Music\\Rock')));
      expect(sanitized, contains('hotel_california.mp3'));

      // Tokens and keys are redacted
      expect(sanitized, isNot(contains('secret12345678')));
      expect(sanitized, isNot(contains('abcde987654321')));
      expect(sanitized, contains('[REDACTED]'));

      // User name is scrubbed
      expect(sanitized, isNot(contains('user mido')));
      expect(sanitized, contains('[REDACTED_USER]'));

      // Truncation rule: long text > 500 chars truncated to 500
      final veryLong = 'A' * 600;
      final truncated = AppLogger.sanitizeMessage(veryLong);
      expect(truncated.length, equals(500));

      // Posix path sanitization
      const posixInput = 'Failed: /home/mido/tracks/jazz/take_five.flac not found';
      final posixSanitized = AppLogger.sanitizeMessage(posixInput, userName: 'mido');
      expect(posixSanitized, isNot(contains('/home/mido/tracks/jazz')));
      expect(posixSanitized, contains('take_five.flac'));
    });

    test('Rotation rotates when exceeding 1 MB and keeps at most 3 old files', () async {
      final logDir = Directory('${tempDir.path}/logs_rotation');
      final logger = AppLogger(logsDirectory: logDir);
      await logger.init();

      final logFile = File('${logDir.path}/aestheticy.log');
      // Create a large file > 1MB
      final largeChunk = 'x' * (1024 * 512); // 512 KB
      await logFile.writeAsString(largeChunk);
      await logFile.writeAsString(largeChunk, mode: FileMode.append);
      expect(logFile.lengthSync(), greaterThanOrEqualTo(AppLogger.maxFileSizeBytes));

      // Writing a new message triggers rotation
      logger.info('Rotation', 'Message after 1st rotation trigger');
      await logger.flush();

      expect(File('${logDir.path}/aestheticy.1.log').existsSync(), isTrue);

      // Trigger 2nd rotation
      await logFile.writeAsString(largeChunk);
      await logFile.writeAsString(largeChunk, mode: FileMode.append);
      logger.info('Rotation', 'Message after 2nd rotation trigger');
      await logger.flush();
      expect(File('${logDir.path}/aestheticy.2.log').existsSync(), isTrue);

      // Trigger 3rd rotation
      await logFile.writeAsString(largeChunk);
      await logFile.writeAsString(largeChunk, mode: FileMode.append);
      logger.info('Rotation', 'Message after 3rd rotation trigger');
      await logger.flush();
      expect(File('${logDir.path}/aestheticy.3.log').existsSync(), isTrue);

      // Trigger 4th rotation (3.log overwritten, never 4.log)
      await logFile.writeAsString(largeChunk);
      await logFile.writeAsString(largeChunk, mode: FileMode.append);
      logger.info('Rotation', 'Message after 4th rotation trigger');
      await logger.flush();
      expect(File('${logDir.path}/aestheticy.3.log').existsSync(), isTrue);
      expect(File('${logDir.path}/aestheticy.4.log').existsSync(), isFalse);

      await logger.dispose();
    });

    test('Unwritable directory does not throw and becomes silent no-op', () async {
      // Pointing to a file as a directory causes Directory.createSync to fail
      final obstacle = File('${tempDir.path}/obstacle');
      await obstacle.writeAsString('not a directory');

      final unwritableDir = Directory('${obstacle.path}/logs');
      final logger = AppLogger(logsDirectory: unwritableDir);

      // Must not throw
      await logger.init();
      logger.info('Test', 'Should be ignored silently');
      logger.error('Test', 'Should also be ignored silently');
      await logger.flush();
      await logger.dispose();
    });

    test('Buffered writes are flushed on dispose', () async {
      final logDir = Directory('${tempDir.path}/logs_buffered');
      final logger = AppLogger(logsDirectory: logDir);
      await logger.init();

      logger.info('Buffering', 'Message 1 in buffer');
      logger.info('Buffering', 'Message 2 in buffer');

      // Dispose should flush the buffer
      await logger.dispose();

      final lines = await logger.readRecentLines();
      expect(lines, hasLength(2));
      expect(lines[0], contains('Message 1 in buffer'));
      expect(lines[1], contains('Message 2 in buffer'));
    });
  });
}
