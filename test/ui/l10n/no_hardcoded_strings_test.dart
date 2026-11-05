import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('No hardcoded user-visible string literals in lib/ui outside AppStrings', () {
    final uiDirs = [
      Directory('lib/ui/library'),
      Directory('lib/ui/shell'),
      Directory('lib/ui/now_playing'),
      Directory('lib/ui/settings'),
      Directory('lib/ui/artist_names'),
      Directory('lib/ui/theme'),
      Directory('lib/ui/audio_panels'),
      Directory('lib/ui/quick_search'),
    ];

    final textRegex = RegExp(r"""\bText\(\s*['"]([^'"]+)['"]""");
    final tooltipRegex = RegExp(r"""tooltip:\s*['"]([^'"]+)['"]""");
    final semanticRegex = RegExp(r"""semanticLabel:\s*['"]([^'"]+)['"]""");
    final hintRegex = RegExp(r"""hintText:\s*['"]([^'"]+)['"]""");
    final labelRegex = RegExp(r"""labelText:\s*['"]([^'"]+)['"]""");

    // Allowed literals per prompt instructions (brand names, punctuation, numeric time strings)
    const allowedExact = {
      'Aestheticy',
      'by mido',
      'Last.fm',
      '—',
      '-',
      ':',
      '0:00',
      '#',
      '',
      '+',
      '1',
    };

    final violations = <String>[];

    for (final dir in uiDirs) {
      if (!dir.existsSync()) continue;

      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];

          for (final regex in [textRegex, tooltipRegex, semanticRegex, hintRegex, labelRegex]) {
            for (final match in regex.allMatches(line)) {
              final str = match.group(1)?.trim() ?? '';
              if (str.isEmpty) continue;
              if (allowedExact.contains(str)) continue;
              // Ignore pure digits or time formats (e.g. "1:24")
              if (RegExp(r'^[0-9:\s\-_/]+$').hasMatch(str)) continue;

              violations.add('${entity.path}:${i + 1} -> "$str"');
            }
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Hardcoded user-visible strings detected in lib/ui outside AppStrings:\n'
          '${violations.join('\n')}',
    );
  });
}
