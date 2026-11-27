import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _windowsPlatformImportPattern = RegExp(
  r'''^\s*import\s+['"](?:package:aestheticy/platform/windows/|(?:(?:\.\./)*)windows/|(?:\.\./)+platform/windows/)''',
);

final RegExp _windowsPluginPackagePattern = RegExp(
  r'''^\s*import\s+['"]package:(?:smtc_windows|tray_manager|window_manager|win32)/''',
);

void main() {
  test('lib/platform/windows files are only imported from platform_services.dart or lib/app/', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue);

    final violations = <String>[];
    final files = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final relPath = file.path.replaceAll('\\', '/');
      final isAllowedImporter =
          relPath == 'lib/platform/platform_services.dart' ||
          relPath.startsWith('lib/app/') ||
          relPath.startsWith('lib/platform/windows/');

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!isAllowedImporter && _windowsPlatformImportPattern.hasMatch(line)) {
          violations.add(
            '$relPath:${i + 1}: imports lib/platform/windows outside platform_services.dart or lib/app/',
          );
        }
        if (!relPath.startsWith('lib/platform/windows/') &&
            _windowsPluginPackagePattern.hasMatch(line)) {
          violations.add(
            '$relPath:${i + 1}: imports Windows-only package outside lib/platform/windows/',
          );
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Windows platform isolation violations:\n${violations.join('\n')}',
    );
  });
}
