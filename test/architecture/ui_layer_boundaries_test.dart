import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Explicit allowlist of `lib/ui/` files permitted to import the abstract
/// `WindowService` contract until window-mode state moves out of `lib/ui/`.
const Map<String, String> kUiLayerImportAllowlist = {
  'lib/ui/mini_player/mini_player_controller.dart':
      'Depends on abstract platform WindowService interface for mini-player geometry; no OS plugin import.',
  'lib/ui/shell/app_shell.dart':
      'Passes abstract platform WindowService interface into FullScreenView; no OS plugin import.',
};

final List<_ForbiddenImportRule> _forbiddenImportRules = [
  _ForbiddenImportRule(
    'lib/platform',
    RegExp(r'''import\s+['"](?:package:aestheticy/|\.\./)+platform/'''),
  ),
  _ForbiddenImportRule(
    'lib/library/sqlite*',
    RegExp(r'''import\s+['"](?:package:aestheticy/|\.\./)+library/sqlite'''),
  ),
  _ForbiddenImportRule(
    'package:sqlite3',
    RegExp(r'''import\s+['"]package:sqlite3/'''),
  ),
  _ForbiddenImportRule(
    'package:mpv_audio_kit',
    RegExp(r'''import\s+['"]package:mpv_audio_kit/'''),
  ),
  _ForbiddenImportRule(
    'package:smtc_windows',
    RegExp(r'''import\s+['"]package:smtc_windows/'''),
  ),
  _ForbiddenImportRule(
    'package:tray_manager',
    RegExp(r'''import\s+['"]package:tray_manager/'''),
  ),
  _ForbiddenImportRule(
    'package:window_manager',
    RegExp(r'''import\s+['"]package:window_manager/'''),
  ),
];

void main() {
  test('lib/ui must not import forbidden platform, sqlite, or native plugin packages', () {
    final uiDir = Directory('lib/ui');
    expect(uiDir.existsSync(), isTrue);

    final violations = <String>[];
    final seenAllowed = <String>{};

    final files = uiDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final relPath = file.path.replaceAll('\\', '/');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('import ')) continue;
        for (final rule in _forbiddenImportRules) {
          if (rule.pattern.hasMatch(line)) {
            if (kUiLayerImportAllowlist.containsKey(relPath) &&
                rule.label == 'lib/platform' &&
                line.contains('window_service.dart')) {
              seenAllowed.add(relPath);
              continue;
            }
            violations.add('$relPath:${i + 1}: forbidden import (${rule.label}) -> $line');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Forbidden imports found in lib/ui:\n${violations.join('\n')}',
    );

    for (final entry in kUiLayerImportAllowlist.entries) {
      expect(entry.value.trim(), isNotEmpty, reason: '${entry.key} requires a non-empty reason');
      expect(
        File(entry.key).existsSync(),
        isTrue,
        reason: 'Allowlisted file ${entry.key} does not exist',
      );
      expect(
        seenAllowed.contains(entry.key),
        isTrue,
        reason: 'Stale allowlist entry ${entry.key} no longer imports lib/platform',
      );
    }
  });
}

class _ForbiddenImportRule {
  final String label;
  final RegExp pattern;
  const _ForbiddenImportRule(this.label, this.pattern);
}
