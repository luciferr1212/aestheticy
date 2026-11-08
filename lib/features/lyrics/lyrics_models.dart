/// Domain models for parsed synced and plain lyrics documents.
library;

/// Classification of the lyrics content.
enum LyricsKind {
  /// Time-synchronized lyrics with line or word timestamps.
  synced,

  /// Plain unsynchronized text lyrics.
  plain,

  /// Pure instrumental track with no sung vocals.
  instrumental,
}

/// The origin from which lyrics were resolved.
enum LyricsSourceOrigin {
  /// Local sidecar file (.lrc or .txt).
  local,

  /// Embedded audio file metadata tag.
  embedded,

  /// Remote online lookup from LRCLIB.
  lrclib,
}

/// A single word with explicit timing information within an Enhanced LRC line.
class LyricsWord {
  /// Start time of the word in milliseconds from track start.
  final int startMs;

  /// End time of the word in milliseconds, if determinable.
  final int? endMs;

  /// The text content of this word.
  final String text;

  /// Creates a [LyricsWord].
  const LyricsWord({
    required this.startMs,
    this.endMs,
    required this.text,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsWord &&
          runtimeType == other.runtimeType &&
          startMs == other.startMs &&
          endMs == other.endMs &&
          text == other.text;

  @override
  int get hashCode => Object.hash(startMs, endMs, text);

  @override
  String toString() => 'LyricsWord($startMs..${endMs ?? "?"}: "$text")';
}

/// A line of lyrics with start timestamp and optional word timings.
class LyricsLine {
  /// Line start time in milliseconds from track start (0 for plain lyrics).
  final int startMs;

  /// Clean display text of the line without timing tags.
  final String text;

  /// Per-word timings for Enhanced LRC lines, or null if line-level only.
  final List<LyricsWord>? words;

  /// Creates a [LyricsLine].
  const LyricsLine({
    required this.startMs,
    required this.text,
    this.words,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsLine &&
          runtimeType == other.runtimeType &&
          startMs == other.startMs &&
          text == other.text &&
          _listEquals(words, other.words);

  @override
  int get hashCode => Object.hash(startMs, text, words?.length);

  @override
  String toString() => 'LyricsLine($startMs: "$text", words: ${words?.length})';

  static bool _listEquals(List<LyricsWord>? a, List<LyricsWord>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A fully resolved lyrics document.
class LyricsDocument {
  /// Whether the document is synced, plain, or instrumental.
  final LyricsKind kind;

  /// Chronologically ordered lines of lyrics.
  final List<LyricsLine> lines;

  /// Source where these lyrics were retrieved.
  final LyricsSourceOrigin source;

  /// Whether this document contains real per-word timestamps.
  final bool hasWordTiming;

  /// Creates a [LyricsDocument].
  const LyricsDocument({
    required this.kind,
    required this.lines,
    required this.source,
    required this.hasWordTiming,
  });

  /// Empty document placeholder.
  static const empty = LyricsDocument(
    kind: LyricsKind.plain,
    lines: [],
    source: LyricsSourceOrigin.local,
    hasWordTiming: false,
  );

  /// Creates an instrumental placeholder document.
  factory LyricsDocument.instrumental({
    LyricsSourceOrigin source = LyricsSourceOrigin.local,
  }) =>
      LyricsDocument(
        kind: LyricsKind.instrumental,
        lines: const [],
        source: source,
        hasWordTiming: false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsDocument &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          source == other.source &&
          hasWordTiming == other.hasWordTiming &&
          _linesEquals(lines, other.lines);

  @override
  int get hashCode => Object.hash(kind, source, hasWordTiming, lines.length);

  @override
  String toString() =>
      'LyricsDocument($kind, lines: ${lines.length}, source: $source, wordTiming: $hasWordTiming)';

  static bool _linesEquals(List<LyricsLine> a, List<LyricsLine> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
