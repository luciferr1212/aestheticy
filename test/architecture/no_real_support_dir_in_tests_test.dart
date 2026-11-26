import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/library/sqlite_library_repository.dart';

void main() {
  test('no test resolves the real path_provider application support directory',
      () {
    final testDir = Directory('test');
    expect(testDir.existsSync(), isTrue);

    final violations = <String>[];
    final getSupportPattern = RegExp(r'\bgetApplicationSupportDirectory\s*\(');
    final openDefaultPattern = RegExp(r'\bopenDefault\s*\(([^)]*)\)', dotAll: true);

    for (final entity in testDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized == 'test/architecture/no_real_support_dir_in_tests_test.dart') {
        continue;
      }

      final source = entity.readAsStringSync();
      if (getSupportPattern.hasMatch(source)) {
        violations.add('$normalized calls getApplicationSupportDirectory()');
      }

      for (final match in openDefaultPattern.allMatches(source)) {
        final args = match.group(1) ?? '';
        if (!args.contains('supportDir') && !args.contains('supportDirProvider')) {
          violations.add(
            '$normalized calls openDefault(...) without injecting supportDir/supportDirProvider',
          );
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Tests must only operate inside in-memory DBs or temp directories:\n'
          '${violations.join('\n')}',
    );
  });

  test('SqliteLibraryRepository.openDefault with injected temp dir never invokes path_provider',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('support_dir_inject_');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final repo = await SqliteLibraryRepository.openDefault(
      supportDir: tempDir,
    );
    expect(
      File(p.join(tempDir.path, 'Aestheticy', 'library.db')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(tempDir.path, 'Aestheticy', 'userdata.db')).existsSync(),
      isTrue,
    );
    await repo.close();
  });
}
