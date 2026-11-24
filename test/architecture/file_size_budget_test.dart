import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Maximum allowed line count for source files under `lib/`.
const int kMaxLibFileLines = 1000;

/// Explicit allowlist of `lib/` files permitted to exceed [kMaxLibFileLines],
/// mapped to a one-line justification.
const Map<String, String> kFileSizeAllowlist = {
  'lib/ui/l10n/app_strings.dart':
      'Static English and Arabic localization dictionary data.',
  // TODO split: handled in the Foundation task.
  'lib/main.dart':
      'App entry point and bootstrap wiring; handled in the Foundation task.',
  // TODO split: handled in the Foundation task.
  'lib/audio/playback_controller.dart':
      'Core playback coordinator; handled in the Foundation task.',
};

void main() {
  test('No file in lib/ exceeds $kMaxLibFileLines lines unless allowlisted', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ directory must exist');

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    final violations = <String>[];
    final seenPaths = <String>{};

    for (final file in dartFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      seenPaths.add(normalizedPath);
      final lineCount = file.readAsLinesSync().length;
      if (lineCount > kMaxLibFileLines &&
          !kFileSizeAllowlist.containsKey(normalizedPath)) {
        violations.add(
          '$normalizedPath ($lineCount lines > $kMaxLibFileLines)',
        );
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Files in lib/ exceeding $kMaxLibFileLines lines must be split or explicitly allowlisted:\n${violations.join('\n')}',
    );

    // Ensure allowlist stays free of stale paths or entries that now fit under budget.
    for (final entry in kFileSizeAllowlist.entries) {
      expect(
        seenPaths.contains(entry.key),
        isTrue,
        reason: 'Allowlisted file no longer exists: ${entry.key}',
      );
      final lineCount = File(entry.key).readAsLinesSync().length;
      expect(
        lineCount > kMaxLibFileLines,
        isTrue,
        reason:
            'Allowlisted file ${entry.key} ($lineCount lines) is now <= $kMaxLibFileLines lines and should be removed from kFileSizeAllowlist.',
      );
    }
  });
}
