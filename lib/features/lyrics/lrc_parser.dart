/// Pure Dart parser for LRC and Enhanced LRC files with Windows-1256 fallback.
library;

import 'dart:convert';

import 'lyrics_models.dart';

const int _kMaxLyricsLines = 20000;

final RegExp _lineTimestampRegex =
    RegExp(r'\[(\d+):(\d{2})(?:\.(\d+))?\]');

final RegExp _wordTimestampRegex =
    RegExp(r'<(\d+):(\d{2})(?:\.(\d+))?>');

final RegExp _offsetRegex =
    RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]$', caseSensitive: false);

final RegExp _metadataTagRegex =
    RegExp(r'^\[[a-zA-Z]+:.*\]$');

/// Windows-1256 code page table for bytes 0x80 to 0xFF.
const List<int> _cp1256Table = [
  0x20AC, 0x067E, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, // 0x80 - 0x87
  0x02C6, 0x2030, 0x0679, 0x2039, 0x0152, 0x0686, 0x0698, 0x0688, // 0x88 - 0x8F
  0x06AF, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, // 0x90 - 0x97
  0x06A9, 0x2122, 0x0691, 0x203A, 0x0153, 0x200C, 0x200D, 0x06BA, // 0x98 - 0x9F
  0x00A0, 0x060C, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7, // 0xA0 - 0xA7
  0x00A8, 0x00A9, 0x06BE, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF, // 0xA8 - 0xAF
  0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7, // 0xB0 - 0xB7
  0x00B8, 0x00B9, 0x061B, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x061F, // 0xB8 - 0xBF
  0x06C1, 0x0621, 0x0622, 0x0623, 0x0624, 0x0625, 0x0626, 0x0627, // 0xC0 - 0xC7
  0x0628, 0x0629, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x062F, // 0xC8 - 0xCF
  0x0630, 0x0631, 0x0632, 0x0633, 0x0634, 0x0635, 0x0636, 0x00D7, // 0xD0 - 0xD7
  0x0637, 0x0638, 0x0639, 0x063A, 0x0640, 0x0641, 0x0642, 0x0643, // 0xD8 - 0xDF
  0x00E0, 0x0644, 0x00E2, 0x0645, 0x0646, 0x0647, 0x0648, 0x00E7, // 0xE0 - 0xE7
  0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x0649, 0x064A, 0x00EE, 0x00EF, // 0xE8 - 0xEF
  0x064B, 0x064C, 0x064D, 0x064E, 0x00F4, 0x064F, 0x0650, 0x00F7, // 0xF0 - 0xF7
  0x0651, 0x00F9, 0x0652, 0x00FB, 0x00FC, 0x200E, 0x200F, 0x06D2, // 0xF8 - 0xFF
];

/// Decodes binary byte payload to a String using strict UTF-8 first,
/// falling back to Windows-1256 for legacy Arabic text. Never throws.
String decodeLyricsBytes(List<int> bytes) {
  if (bytes.isEmpty) return '';

  try {
    return const Utf8Decoder(allowMalformed: false).convert(bytes);
  } catch (_) {
    final sb = StringBuffer();
    for (final b in bytes) {
      if (b >= 0 && b <= 0x7F) {
        sb.writeCharCode(b);
      } else if (b >= 0x80 && b <= 0xFF) {
        sb.writeCharCode(_cp1256Table[b - 0x80]);
      } else {
        sb.writeCharCode(0xFFFD);
      }
    }
    return sb.toString();
  }
}

int _parseTimestampMs(String minStr, String secStr, String? fracStr) {
  final minutes = int.parse(minStr);
  final seconds = int.parse(secStr);
  var fracMs = 0;
  if (fracStr != null && fracStr.isNotEmpty) {
    if (fracStr.length == 1) {
      fracMs = int.parse(fracStr) * 100;
    } else if (fracStr.length == 2) {
      fracMs = int.parse(fracStr) * 10;
    } else if (fracStr.length >= 3) {
      fracMs = int.parse(fracStr.substring(0, 3));
    }
  }
  return minutes * 60000 + seconds * 1000 + fracMs;
}

class _RawLine {
  final int startMs;
  final String text;
  final List<LyricsWord>? words;

  const _RawLine({
    required this.startMs,
    required this.text,
    this.words,
  });
}

/// Parses LRC or plain lyrics text into a structured [LyricsDocument].
LyricsDocument parseLrc(
  String text, {
  LyricsSourceOrigin source = LyricsSourceOrigin.local,
  bool isInstrumental = false,
}) {
  if (isInstrumental) {
    return LyricsDocument.instrumental(source: source);
  }

  // Strip UTF-8 BOM if present
  var clean = text;
  if (clean.startsWith('\uFEFF')) {
    clean = clean.substring(1);
  }

  final rawLines = clean.split(RegExp(r'\r\n|\r|\n'));

  // First pass: extract [offset:+/-ms] tag if present
  var offsetMs = 0;
  for (final line in rawLines) {
    final trimmed = line.trim();
    final match = _offsetRegex.firstMatch(trimmed);
    if (match != null) {
      final parsed = int.tryParse(match.group(1)!);
      if (parsed != null) {
        offsetMs = parsed;
      }
    }
  }

  final parsedLines = <_RawLine>[];
  var totalTimestampsFound = 0;
  var hasAnyWordTiming = false;

  for (final rawLine in rawLines) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;

    // Ignore metadata tags such as [ti:...], [ar:...], [offset:...]
    if (_metadataTagRegex.hasMatch(trimmed) &&
        !_lineTimestampRegex.hasMatch(trimmed)) {
      continue;
    }

    final timestampMatches = _lineTimestampRegex.allMatches(trimmed).toList();
    if (timestampMatches.isNotEmpty) {
      totalTimestampsFound += timestampMatches.length;

      // Extract the lyric text after removing line timestamps
      final rawLyric = trimmed.replaceAll(_lineTimestampRegex, '').trim();

      // Check for Enhanced LRC word tags: <mm:ss.xx>
      List<LyricsWord>? lineWords;
      final wordMatches = _wordTimestampRegex.allMatches(rawLyric).toList();
      if (wordMatches.isNotEmpty) {
        hasAnyWordTiming = true;
        final wordsDraft = <LyricsWord>[];

        for (var i = 0; i < wordMatches.length; i++) {
          final wm = wordMatches[i];
          final rawWordStart = _parseTimestampMs(
            wm.group(1)!,
            wm.group(2)!,
            wm.group(3),
          );
          final shiftedStart = rawWordStart - offsetMs;
          final wordStart = shiftedStart < 0 ? 0 : shiftedStart;

          final nextStart = (i + 1 < wordMatches.length)
              ? wordMatches[i + 1].start
              : rawLyric.length;
          final wordText = rawLyric.substring(wm.end, nextStart).trim();

          if (wordText.isNotEmpty) {
            wordsDraft.add(LyricsWord(
              startMs: wordStart,
              text: wordText,
            ));
          }
        }

        // Link endMs = next word's startMs
        if (wordsDraft.isNotEmpty) {
          lineWords = <LyricsWord>[];
          for (var i = 0; i < wordsDraft.length; i++) {
            final w = wordsDraft[i];
            final end = (i + 1 < wordsDraft.length)
                ? wordsDraft[i + 1].startMs
                : null;
            lineWords.add(LyricsWord(
              startMs: w.startMs,
              endMs: end,
              text: w.text,
            ));
          }
        }
      }

      final displayText = rawLyric
          .replaceAll(_wordTimestampRegex, '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      for (final tm in timestampMatches) {
        final rawStart = _parseTimestampMs(
          tm.group(1)!,
          tm.group(2)!,
          tm.group(3),
        );
        final shifted = rawStart - offsetMs;
        final startMs = shifted < 0 ? 0 : shifted;

        parsedLines.add(_RawLine(
          startMs: startMs,
          text: displayText,
          words: lineWords,
        ));
      }
    }
  }

  // If no timestamp tags were found anywhere, treat as plain lyrics
  if (totalTimestampsFound == 0) {
    final plainLines = rawLines
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !_metadataTagRegex.hasMatch(l))
        .take(_kMaxLyricsLines)
        .map((l) => LyricsLine(startMs: 0, text: l))
        .toList();

    return LyricsDocument(
      kind: LyricsKind.plain,
      lines: plainLines,
      source: source,
      hasWordTiming: false,
    );
  }

  // Sort synced lines chronologically
  parsedLines.sort((a, b) => a.startMs.compareTo(b.startMs));

  // Cap lines at 20,000
  final capped = parsedLines.length > _kMaxLyricsLines
      ? parsedLines.sublist(0, _kMaxLyricsLines)
      : parsedLines;

  // Final pass: resolve endMs for the last word of each line using next line's startMs
  final finalLines = <LyricsLine>[];
  for (var i = 0; i < capped.length; i++) {
    final item = capped[i];
    if (item.words == null || item.words!.isEmpty) {
      finalLines.add(LyricsLine(
        startMs: item.startMs,
        text: item.text,
        words: null,
      ));
    } else {
      final words = item.words!;
      final nextLineStart = (i + 1 < capped.length) ? capped[i + 1].startMs : null;

      final updatedWords = <LyricsWord>[];
      for (var wIdx = 0; wIdx < words.length; wIdx++) {
        final w = words[wIdx];
        if (wIdx == words.length - 1) {
          // Last word endMs = next line start
          updatedWords.add(LyricsWord(
            startMs: w.startMs,
            endMs: nextLineStart,
            text: w.text,
          ));
        } else {
          updatedWords.add(w);
        }
      }

      finalLines.add(LyricsLine(
        startMs: item.startMs,
        text: item.text,
        words: updatedWords,
      ));
    }
  }

  return LyricsDocument(
    kind: LyricsKind.synced,
    lines: finalLines,
    source: source,
    hasWordTiming: hasAnyWordTiming,
  );
}
