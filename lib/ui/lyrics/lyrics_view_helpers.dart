import '../../features/lyrics/lyrics_models.dart';

/// Computes the visual opacity for a lyrics line based on its distance from the active line.
///
/// Falloff table:
/// - Current active line: 1.0
/// - Distance 1 upcoming: 0.55 (next line)
/// - Distance 2 upcoming: 0.38
/// - Distance 3 upcoming: 0.26
/// - Distance 4+ upcoming: 0.20 (floor)
/// - Past lines are dimmer than upcoming ones (distance 1: 0.44, distance 2: 0.30, distance 3: 0.21, distance 4+: 0.20)
/// - Hover raises opacity by 0.18 (clamped to 1.0)
double computeLineOpacity({
  required int index,
  required int activeIndex,
  bool isHovered = false,
}) {
  if (activeIndex < 0) {
    // Before first line starts: index 0 is distance 1
    final d = index + 1;
    final base = switch (d) {
      1 => 0.55,
      2 => 0.38,
      3 => 0.26,
      _ => 0.20,
    };
    return isHovered ? (base + 0.18).clamp(0.20, 1.0) : base;
  }

  if (index == activeIndex) {
    return 1.0;
  }

  final diff = index - activeIndex;
  final double base;
  if (diff > 0) {
    // Upcoming lines
    base = switch (diff) {
      1 => 0.55,
      2 => 0.38,
      3 => 0.26,
      _ => 0.20,
    };
  } else {
    // Past lines: dimmer than upcoming ones
    final pastDist = -diff;
    base = switch (pastDist) {
      1 => 0.44,
      2 => 0.30,
      3 => 0.21,
      _ => 0.20,
    };
  }

  if (isHovered) {
    return (base + 0.18).clamp(0.20, 1.0);
  }
  return base;
}

/// Character range within [LyricsLine.text] mapped to a [LyricsWord] entry.
class WordCharRange {
  /// 0-based index of the word inside [LyricsLine.words].
  final int wordIndex;

  /// Inclusive start character index in [LyricsLine.text].
  final int start;

  /// Exclusive end character index in [LyricsLine.text].
  final int end;

  /// Creates a [WordCharRange].
  const WordCharRange({
    required this.wordIndex,
    required this.start,
    required this.end,
  });
}

/// Maps [words] sequentially onto character ranges in [lineText].
///
/// Returns `null` if any word is empty or cannot be found sequentially in
/// [lineText], signalling callers to fall back to line highlight without
/// estimating timings or altering layout text.
List<WordCharRange>? mapWordsToLineRanges(
  String lineText,
  List<LyricsWord> words,
) {
  if (words.isEmpty) return null;
  final ranges = <WordCharRange>[];
  var cursor = 0;
  for (var i = 0; i < words.length; i++) {
    final wordText = words[i].text;
    if (wordText.isEmpty) {
      return null;
    }
    final found = lineText.indexOf(wordText, cursor);
    if (found < 0) {
      return null;
    }
    ranges.add(
      WordCharRange(
        wordIndex: i,
        start: found,
        end: found + wordText.length,
      ),
    );
    cursor = found + wordText.length;
  }
  return ranges;
}

/// Layout density mode for lyrics view typography, padding, and chrome.
enum LyricsViewDensity {
  /// Dedicated Lyrics navigation destination.
  page,

  /// Full Screen now playing view.
  fullScreen,

  /// Compact expanded panel inside the frameless Mini Player.
  mini,

  /// Docked side panel in the desktop shell.
  sidePanel,
}
