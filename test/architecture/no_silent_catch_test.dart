import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Allowlist for catch blocks awaiting cleanup — must stay empty.
const Map<String, String> kSilentCatchAllowlist = {};

final RegExp _handlerPattern = RegExp(
  r'\bAppLogger\b|\bErrorPresenter\b|\bonError\b|\brethrow\b|\b(?:log|_log|logger|_logger)\??\.(?:debug|info|warn|warning|error)\s*\(',
);

final RegExp _ignoreSilentLinePattern = RegExp(r'//\s*ignore-silent\s*:(.*)');
final RegExp _vagueReasonPattern = RegExp(
  r'^(?:best\s*effort|not\s*important|ignored?|later|todo|fixme|none)\.?$',
  caseSensitive: false,
);

void main() {
  test('kSilentCatchAllowlist must remain empty', () {
    expect(kSilentCatchAllowlist, isEmpty);
  });

  test('no silent catch or on Object blocks exist in lib/', () {
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
      if (kSilentCatchAllowlist.containsKey(relPath)) continue;

      final source = file.readAsStringSync();
      for (final block in _extractCatchBlocks(source)) {
        final ignoreMatch = _ignoreSilentLinePattern.firstMatch(block.body);
        if (ignoreMatch != null) {
          final reason = ignoreMatch.group(1)?.trim() ?? '';
          if (reason.length < 10 || _vagueReasonPattern.hasMatch(reason)) {
            violations.add(
              '$relPath:${block.line}: // ignore-silent requires a specific reason',
            );
          }
          continue;
        }

        final codeWithoutComments = _stripComments(block.body).trim();
        if (codeWithoutComments.isEmpty) {
          violations.add('$relPath:${block.line}: empty catch block');
          continue;
        }

        if (!_handlerPattern.hasMatch(codeWithoutComments)) {
          violations.add(
            '$relPath:${block.line}: catch block handles error silently without AppLogger/ErrorPresenter/onError/rethrow or // ignore-silent',
          );
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Silent or undocumented catch blocks found:\n${violations.join('\n')}',
    );
  });
}

class _CatchBlock {
  final int line;
  final String body;
  const _CatchBlock(this.line, this.body);
}

List<_CatchBlock> _extractCatchBlocks(String source) {
  final blocks = <_CatchBlock>[];
  final len = source.length;
  var i = 0;
  var line = 1;
  final validOnPositions = <int>{};

  bool isIdentChar(int codeUnit) =>
      (codeUnit >= 48 && codeUnit <= 57) ||
      (codeUnit >= 65 && codeUnit <= 90) ||
      (codeUnit >= 97 && codeUnit <= 122) ||
      codeUnit == 95 ||
      codeUnit == 36;

  void advanceOne() {
    if (source.codeUnitAt(i) == 10) line++;
    i++;
  }

  int skipWhitespaceAndComments(int pos) {
    while (pos < len) {
      final c = source[pos];
      if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
        pos++;
      } else if (pos + 1 < len && c == '/' && source[pos + 1] == '/') {
        while (pos < len && source[pos] != '\n') {
          pos++;
        }
      } else if (pos + 1 < len && c == '/' && source[pos + 1] == '*') {
        pos += 2;
        while (pos + 1 < len &&
            !(source[pos] == '*' && source[pos + 1] == '/')) {
          pos++;
        }
        pos = (pos + 2 <= len) ? pos + 2 : len;
      } else {
        break;
      }
    }
    return pos;
  }

  int? matchKeywordAt(int pos, String keyword) {
    if (pos + keyword.length > len) return null;
    if (pos > 0 && isIdentChar(source.codeUnitAt(pos - 1))) return null;
    if (!source.startsWith(keyword, pos)) return null;
    final after = pos + keyword.length;
    if (after < len && isIdentChar(source.codeUnitAt(after))) return null;
    return after;
  }

  int skipBalancedParens(int pos) {
    var depth = 0;
    while (pos < len) {
      final c = source[pos];
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0) return pos + 1;
      }
      pos++;
    }
    return pos;
  }

  while (i < len) {
    final c = source[i];
    // Skip comments
    if (i + 1 < len && c == '/' && source[i + 1] == '/') {
      while (i < len && source[i] != '\n') {
        advanceOne();
      }
      continue;
    }
    if (i + 1 < len && c == '/' && source[i + 1] == '*') {
      advanceOne();
      advanceOne();
      while (i + 1 < len && !(source[i] == '*' && source[i + 1] == '/')) {
        advanceOne();
      }
      if (i + 1 < len) {
        advanceOne();
        advanceOne();
      }
      continue;
    }

    // Skip raw string literals r'...' / r"..." / r'''...''' / r"""..."""
    if (c == 'r' &&
        i + 1 < len &&
        (source[i + 1] == "'" || source[i + 1] == '"')) {
      final q = source[i + 1];
      final triple = i + 3 < len && source[i + 2] == q && source[i + 3] == q;
      advanceOne(); // r
      if (triple) {
        advanceOne();
        advanceOne();
        advanceOne();
        while (i < len) {
          if (i + 2 < len &&
              source[i] == q &&
              source[i + 1] == q &&
              source[i + 2] == q) {
            advanceOne();
            advanceOne();
            advanceOne();
            break;
          }
          advanceOne();
        }
      } else {
        advanceOne();
        while (i < len) {
          if (source[i] == q) {
            advanceOne();
            break;
          }
          if (source[i] == '\n') break;
          advanceOne();
        }
      }
      continue;
    }

    // Skip string literals
    if (c == "'" || c == '"') {
      final triple = i + 2 < len && source[i + 1] == c && source[i + 2] == c;
      final q = c;
      if (triple) {
        advanceOne();
        advanceOne();
        advanceOne();
        while (i < len) {
          if (source[i] == r'\' && i + 1 < len) {
            advanceOne();
            advanceOne();
            continue;
          }
          if (i + 2 < len &&
              source[i] == q &&
              source[i + 1] == q &&
              source[i + 2] == q) {
            advanceOne();
            advanceOne();
            advanceOne();
            break;
          }
          advanceOne();
        }
      } else {
        advanceOne();
        while (i < len) {
          if (source[i] == r'\' && i + 1 < len) {
            advanceOne();
            advanceOne();
            continue;
          }
          if (source[i] == q) {
            advanceOne();
            break;
          }
          if (source[i] == '\n') break;
          advanceOne();
        }
      }
      continue;
    }

    // Record `on` clause positions attached to any `try { ... }` chain so
    // `extension ... on ...` and `mixin ... on ...` are never matched.
    final tryAfter = matchKeywordAt(i, 'try');
    if (tryAfter != null) {
      var probe = skipWhitespaceAndComments(tryAfter);
      if (probe < len && source[probe] == '{') {
        var blockEnd = _findMatchingBrace(source, probe);
        while (blockEnd != null) {
          probe = skipWhitespaceAndComments(blockEnd + 1);
          final onClauseAfter = matchKeywordAt(probe, 'on');
          if (onClauseAfter != null) {
            validOnPositions.add(probe);
            var s = skipWhitespaceAndComments(onClauseAfter);
            while (s < len && source[s] != '{' && source[s] != ';') {
              final cInOn = matchKeywordAt(s, 'catch');
              if (cInOn != null) {
                final p = skipWhitespaceAndComments(cInOn);
                if (p < len && source[p] == '(') {
                  s = skipWhitespaceAndComments(skipBalancedParens(p));
                }
                break;
              }
              s++;
            }
            s = skipWhitespaceAndComments(s);
            if (s < len && source[s] == '{') {
              blockEnd = _findMatchingBrace(source, s);
              continue;
            }
          }
          final catchClauseAfter = matchKeywordAt(probe, 'catch');
          if (catchClauseAfter != null) {
            var s = skipWhitespaceAndComments(catchClauseAfter);
            if (s < len && source[s] == '(') {
              s = skipWhitespaceAndComments(skipBalancedParens(s));
              if (s < len && source[s] == '{') {
                blockEnd = _findMatchingBrace(source, s);
                continue;
              }
            }
          }
          break;
        }
      }
    }

    // Check for `on Type [catch (e)] { ... }` or `catch (...) { ... }`
    final onAfter = validOnPositions.contains(i) ? matchKeywordAt(i, 'on') : null;
    if (onAfter != null) {
      final headerLine = line;
      var scan = skipWhitespaceAndComments(onAfter);
      // Scan type token(s) up to '{' or 'catch'
      while (scan < len && source[scan] != '{' && source[scan] != ';') {
        final catchInOn = matchKeywordAt(scan, 'catch');
        if (catchInOn != null) {
          final pStart = skipWhitespaceAndComments(catchInOn);
          if (pStart < len && source[pStart] == '(') {
            scan = skipWhitespaceAndComments(skipBalancedParens(pStart));
          }
          break;
        }
        scan++;
      }
      scan = skipWhitespaceAndComments(scan);
      if (scan < len && source[scan] == '{') {
        final bodyEnd = _findMatchingBrace(source, scan);
        if (bodyEnd != null) {
          blocks.add(_CatchBlock(headerLine, source.substring(scan + 1, bodyEnd)));
          i = _advanceLineCounter(source, i, scan + 1, (delta) => line += delta);
          continue;
        }
      }
    }

    final catchAfter = matchKeywordAt(i, 'catch');
    if (catchAfter != null) {
      final headerLine = line;
      var scan = skipWhitespaceAndComments(catchAfter);
      if (scan < len && source[scan] == '(') {
        scan = skipWhitespaceAndComments(skipBalancedParens(scan));
        if (scan < len && source[scan] == '{') {
          final bodyEnd = _findMatchingBrace(source, scan);
          if (bodyEnd != null) {
            blocks.add(_CatchBlock(headerLine, source.substring(scan + 1, bodyEnd)));
            i = _advanceLineCounter(source, i, scan + 1, (delta) => line += delta);
            continue;
          }
        }
      }
    }

    advanceOne();
  }

  return blocks;
}

int? _findMatchingBrace(String source, int openIndex) {
  final len = source.length;
  var depth = 0;
  var i = openIndex;
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
        i++;
      }
      i += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      final q = c;
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
        if (source[i] == '\n') break;
        i++;
      }
      continue;
    }
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return null;
}

int _advanceLineCounter(
  String source,
  int from,
  int to,
  void Function(int lines) addLines,
) {
  var count = 0;
  for (var idx = from; idx < to; idx++) {
    if (source[idx] == '\n') count++;
  }
  addLines(count);
  return to;
}

String _stripComments(String input) {
  return input
      .replaceAll(RegExp(r'//[^\n]*'), '')
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
}
