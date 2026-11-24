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
      Directory('lib/ui/lyrics'),
      Directory('lib/ui/queue'),
      Directory('lib/ui/mini_player'),
      Directory('lib/features/library'),
    ];

    String? readDartStringLiteral(String source, int quoteIndex) {
      if (quoteIndex >= source.length) return null;
      final quote = source[quoteIndex];
      if (quote != "'" && quote != '"') return null;
      final buf = StringBuffer();
      var i = quoteIndex + 1;
      while (i < source.length) {
        final ch = source[i];
        if (ch == r'\' && i + 1 < source.length) {
          buf.write(source[i]);
          buf.write(source[i + 1]);
          i += 2;
          continue;
        }
        if (ch == r'$' && i + 1 < source.length && source[i + 1] == '{') {
          var depth = 1;
          i += 2;
          while (i < source.length && depth > 0) {
            final inner = source[i];
            if (inner == "'" || inner == '"') {
              // Skip inner quoted string inside ${...} without breaking depth
              var j = i + 1;
              while (j < source.length) {
                if (source[j] == r'\' && j + 1 < source.length) {
                  j += 2;
                  continue;
                }
                if (source[j] == inner) {
                  j++;
                  break;
                }
                j++;
              }
              i = j;
              continue;
            }
            if (inner == '{') depth++;
            if (inner == '}') depth--;
            i++;
          }
          continue;
        }
        if (ch == quote) {
          return buf.toString();
        }
        buf.write(ch);
        i++;
      }
      return null;
    }

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
      '•',
      '…',
      '.',
    };

    bool isAllowed(String raw) {
      final cleaned = raw
          .replaceAll(RegExp(r'\$[a-zA-Z_][a-zA-Z0-9_]*'), '')
          .trim();
      if (cleaned.isEmpty || allowedExact.contains(cleaned)) return true;
      if (RegExp(r'^[0-9:\s\-_/•·.()"]+$').hasMatch(cleaned)) return true;
      return false;
    }

    final triggerPatterns = [
      // Text('...') / Text(cond ? '...' : '...')
      RegExp(r'\bText\(\s*(?:const\s+)?'),
      RegExp(r'(?:tooltip|semanticLabel|hintText|labelText):\s*'),
    ];
    final ternaryTrigger = RegExp(r'\bText\(\s*[^;{}()]*?\?\s*');

    final violations = <String>[];

    void checkQuoteAt(
      String path,
      String content,
      int quoteIndex,
      int triggerStart,
    ) {
      final literal = readDartStringLiteral(content, quoteIndex);
      if (literal == null) return;
      if (!isAllowed(literal)) {
        final lineNo =
            '\n'.allMatches(content.substring(0, triggerStart)).length + 1;
        final entry = '$path:$lineNo -> "${literal.trim()}"';
        if (!violations.contains(entry)) {
          violations.add(entry);
        }
      }
    }

    for (final dir in uiDirs) {
      if (!dir.existsSync()) continue;

      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final content = entity.readAsStringSync();
        for (final trigger in triggerPatterns) {
          for (final match in trigger.allMatches(content)) {
            if (match.end < content.length &&
                (content[match.end] == "'" || content[match.end] == '"')) {
              checkQuoteAt(entity.path, content, match.end, match.start);
            }
          }
        }

        for (final match in ternaryTrigger.allMatches(content)) {
          final pos = match.end;
          if (pos < content.length &&
              (content[pos] == "'" || content[pos] == '"')) {
            checkQuoteAt(entity.path, content, pos, match.start);
            final first = readDartStringLiteral(content, pos);
            if (first != null) {
              final afterColon = RegExp(r'\s*:\s*')
                  .matchAsPrefix(content, content.indexOf(content[pos], pos + 1) + 1);
              if (afterColon != null && afterColon.end < content.length) {
                checkQuoteAt(entity.path, content, afterColon.end, match.start);
              }
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
