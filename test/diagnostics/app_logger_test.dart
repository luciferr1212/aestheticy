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

      // Quoted paths with spaces, UNC paths, and file:// URIs strip to basename
      const extraInput =
          'Opened "C:\\Users\\mido\\My Music\\Artist Name\\track 01.mp3" '
          'from \\\\NAS\\MusicShare\\Albums\\cover.jpg and file:///D:/Audio/song.wav';
      final extraSanitized = AppLogger.sanitizeMessage(extraInput, userName: 'mido');
      expect(extraSanitized, isNot(contains('My Music')));
      expect(extraSanitized, isNot(contains('NAS')));
      expect(extraSanitized, isNot(contains('D:/Audio')));
      expect(extraSanitized, contains('"track 01.mp3"'));
      expect(extraSanitized, contains('cover.jpg'));
      expect(extraSanitized, contains('song.wav'));
    });

    test('Levels debug/info/warn/error, minLevel filtering, customSink, and AppLogger.swallow',
        () async {
      final buffer = StringBuffer();
      final logger = AppLogger(
        customSink: buffer,
        minLevel: LogLevel.warn,
        userNameProvider: () => 'mido',
      );
      await logger.init();

      logger.debug('Audio', 'Filtered debug');
      logger.info('Audio', 'Filtered info');
      logger.warn('Audio', 'Kept warn C:\\Users\\mido\\Music\\warn.mp3');
      logger.error('Audio', 'Kept error');

      final out = buffer.toString();
      expect(out, isNot(contains('Filtered debug')));
      expect(out, isNot(contains('Filtered info')));
      expect(out, contains('[WARN] [Audio] Kept warn warn.mp3'));
      expect(out, contains('[ERROR] [Audio] Kept error'));
      await logger.dispose();

      // AppLogger.swallow emits debug entry via instance with redacted context
      final swallowBuffer = StringBuffer();
      final prev = AppLogger.instance;
      AppLogger.instance = AppLogger(
        customSink: swallowBuffer,
        minLevel: LogLevel.debug,
      );
      addTearDown(() => AppLogger.instance = prev);

      try {
        throw StateError('failed reading C:\\Users\\mido\\Music\\bad.flac');
      } catch (e, st) {
        AppLogger.swallow(
          e,
          st,
          where: 'TrackScanner',
          context: 'while cleaning C:\\Users\\mido\\temp\\work.tmp',
        );
      }

      final swallowOut = swallowBuffer.toString();
      expect(swallowOut, contains('[DEBUG] [TrackScanner]'));
      expect(swallowOut, contains('Swallowed error in TrackScanner'));
      expect(swallowOut, contains('work.tmp'));
      expect(swallowOut, contains('bad.flac'));
      expect(swallowOut, isNot(contains('C:\\Users\\mido')));
    });

    test('Rotation rotates when exceeding 1 MB, keeps 5 files total, and preserves unrelated files',
        () async {
      final logDir = Directory('${tempDir.path}/logs_rotation');
      logDir.createSync(recursive: true);
      final unrelated = File('${logDir.path}/custom_notes.txt')
        ..writeAsStringSync('keep me');
      final staleArchive = File('${logDir.path}/aestheticy.5.log')
        ..writeAsStringSync('old archive beyond keep-5');

      final logger = AppLogger(logsDirectory: logDir);
      await logger.init();

      final logFile = File('${logDir.path}/aestheticy.log');
      final largeChunk = 'x' * (1024 * 512); // 512 KB

      for (var round = 1; round <= 5; round++) {
        await logFile.writeAsString(largeChunk);
        await logFile.writeAsString(largeChunk, mode: FileMode.append);
        expect(logFile.lengthSync(), greaterThanOrEqualTo(AppLogger.maxFileSizeBytes));
        logger.info('Rotation', 'Message after rotation trigger #$round');
        await logger.flush();
      }

      // Keeps aestheticy.log + aestheticy.1.log .. aestheticy.4.log (5 total)
      expect(logFile.existsSync(), isTrue);
      for (var i = 1; i <= 4; i++) {
        expect(File('${logDir.path}/aestheticy.$i.log').existsSync(), isTrue);
      }
      expect(File('${logDir.path}/aestheticy.5.log').existsSync(), isFalse);
      expect(staleArchive.existsSync(), isFalse);

      // Unrelated files in the log directory are never touched
      expect(unrelated.existsSync(), isTrue);
      expect(unrelated.readAsStringSync(), equals('keep me'));

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
