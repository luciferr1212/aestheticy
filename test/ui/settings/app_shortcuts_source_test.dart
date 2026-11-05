import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('No file under lib/ui references or compares LogicalKeyboardKey directly except app_shortcuts.dart', () {
    final uiDir = Directory('lib/ui');
    expect(uiDir.existsSync(), isTrue);

    final violations = <String>[];
    const allowedFile = 'lib/ui/settings/app_shortcuts.dart';

    for (final entity in uiDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final normalizedPath = entity.path.replaceAll(r'\', '/');
      if (normalizedPath == allowedFile) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('LogicalKeyboardKey')) {
          violations.add('$normalizedPath:${i + 1} -> "$line"');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Direct references or comparisons to LogicalKeyboardKey found outside app_shortcuts.dart:\n'
          '${violations.join('\n')}',
    );
  });
}
