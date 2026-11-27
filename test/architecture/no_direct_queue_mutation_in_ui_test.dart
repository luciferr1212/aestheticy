import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _directQueueMutationPattern = RegExp(
  r'\bqueue\s*\.\s*(?:add|addAll|addToQueue|advance|clear|clearUpcoming|insert|jumpTo|move|next|playNext|previous|remove|removeAt|removeById|removeByIds|replaceAll|replaceAllEntries|restoreSnapshot|setShuffle)\s*\(|\bqueue\s*\.\s*repeatMode\s*=',
);

void main() {
  test('widgets in lib/ui must not mutate PlaybackQueue directly', () {
    final uiDir = Directory('lib/ui');
    expect(uiDir.existsSync(), isTrue);

    final violations = <String>[];
    final files = uiDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final relPath = file.path.replaceAll('\\', '/');
      final stripped = _stripCommentsAndStrings(file.readAsStringSync());
      final lines = stripped.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (_directQueueMutationPattern.hasMatch(lines[i])) {
          violations.add(
            '$relPath:${i + 1}: direct queue mutation detected; route through PlaybackController',
          );
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Direct PlaybackQueue mutations found in lib/ui:\n${violations.join('\n')}',
    );
  });
}

/// Strips comments and string literals while preserving newlines so line
/// numbers remain accurate.
String _stripCommentsAndStrings(String source) {
  final out = StringBuffer();
  final len = source.length;
  var i = 0;
  while (i < len) {
    final c = source[i];
    if (i + 1 < len && c == '/' && source[i + 1] == '/') {
      while (i < len && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (i + 1 < len && c == '/' && source[i + 1] == '*') {
      i += 2;
      while (i + 1 < len && !(source[i] == '*' && source[i + 1] == '/')) {
        if (source[i] == '\n') out.write('\n');
        i++;
      }
      i += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      final q = c;
      final triple = i + 2 < len && source[i + 1] == q && source[i + 2] == q;
      if (triple) {
        i += 3;
        while (i < len) {
          if (source[i] == r'\' && i + 1 < len) {
            if (source[i + 1] == '\n') out.write('\n');
            i += 2;
            continue;
          }
          if (i + 2 < len &&
              source[i] == q &&
              source[i + 1] == q &&
              source[i + 2] == q) {
            i += 3;
            break;
          }
          if (source[i] == '\n') out.write('\n');
          i++;
        }
      } else {
        i++;
        while (i < len) {
          if (source[i] == r'\' && i + 1 < len) {
            i += 2;
            continue;
          }
          if (source[i] == q) {
            i++;
            break;
          }
          if (source[i] == '\n') {
            out.write('\n');
            i++;
            break;
          }
          i++;
        }
      }
      out.write(' ');
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}
