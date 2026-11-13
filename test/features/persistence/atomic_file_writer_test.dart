import 'dart:async';
import 'dart:io';

import 'package:aestheticy/features/persistence/atomic_file_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AtomicFileWriter Tests', () {
    late Directory tempDir;
    late File target;
    late AtomicFileWriter writer;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('atomic_writer_test_');
      target = File(p.join(tempDir.path, 'target.json'));
      writer = AtomicFileWriter(target);
    });

    tearDown(() async {
      writer.dispose();
      if (tempDir.existsSync()) {
        for (var i = 0; i < 5; i++) {
          try {
            await tempDir.delete(recursive: true);
            break;
          } on FileSystemException {
            if (i < 4) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }
        }
      }
    });

    test('target file never disappears while 50 rapid writes happen', () async {
      await writer.write('initial_content');
      expect(target.existsSync(), isTrue);

      for (var i = 0; i < 50; i++) {
        unawaited(writer.write('content_$i'));
      }

      // Poll existsSync in a loop during active writes: must remain true throughout
      for (var i = 0; i < 100; i++) {
        expect(target.existsSync(), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      await writer.flush();
      expect(target.existsSync(), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('final content is the LAST written content', () async {
      for (var i = 0; i < 30; i++) {
        unawaited(writer.write('payload_$i'));
      }
      await writer.flush();
      expect(await target.readAsString(), equals('payload_29'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('writes never run concurrently via slow probe', () async {
      var activeWrites = 0;
      var maxActiveWrites = 0;
      var totalExecutions = 0;

      final probeWriter = AtomicFileWriter(
        target,
        onPerformWrite: (content) async {
          activeWrites++;
          if (activeWrites > maxActiveWrites) {
            maxActiveWrites = activeWrites;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await target.writeAsString(content);
          activeWrites--;
          totalExecutions++;
        },
      );

      for (var i = 0; i < 15; i++) {
        unawaited(probeWriter.write('probe_$i'));
      }

      await probeWriter.flush();
      probeWriter.dispose();

      expect(maxActiveWrites, equals(1));
      expect(await target.readAsString(), equals('probe_14'));
      expect(totalExecutions, greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('flush waits for all queued writes to complete', () async {
      var isWriteFinished = false;

      final slowWriter = AtomicFileWriter(
        target,
        onPerformWrite: (content) async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          await target.writeAsString(content);
          isWriteFinished = true;
        },
      );

      unawaited(slowWriter.write('slow_content'));
      expect(isWriteFinished, isFalse);

      await slowWriter.flush();
      expect(isWriteFinished, isTrue);
      expect(await target.readAsString(), equals('slow_content'));
      slowWriter.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('failure of one write does not stop the next', () async {
      var shouldFail = true;

      final failingWriter = AtomicFileWriter(
        target,
        onPerformWrite: (content) async {
          if (shouldFail) {
            shouldFail = false;
            throw const FileSystemException('simulated disk failure');
          }
          await target.writeAsString(content);
        },
      );

      // First write fails internally but never breaks the chain or throws
      await failingWriter.write('bad_content');
      await failingWriter.write('good_content');
      await failingWriter.flush();

      expect(await target.readAsString(), equals('good_content'));
      failingWriter.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('leftover temp files are removed after writes', () async {
      for (var i = 0; i < 20; i++) {
        unawaited(writer.write('temp_check_$i'));
      }
      await writer.flush();

      final tempFiles =
          tempDir.listSync().where((f) => f.path.endsWith('.tmp')).toList();
      expect(tempFiles, isEmpty);
      expect(await target.readAsString(), equals('temp_check_19'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('writeSync works and does not delete target before rename', () async {
      target.writeAsStringSync('sync_initial');
      expect(target.existsSync(), isTrue);

      writer.writeSync('sync_updated');
      expect(target.existsSync(), isTrue);
      expect(target.readAsStringSync(), equals('sync_updated'));

      final tempFiles =
          tempDir.listSync().where((f) => f.path.endsWith('.tmp')).toList();
      expect(tempFiles, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
