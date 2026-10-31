/// Pure Dart artist string parsing and multi-artist splitting.
library;

import 'package:aestheticy/library/text_normalizer.dart';

/// Represents a parsed artist with a display name and normalized key.
class SplitArtist {
  /// The artist display name as parsed from the track metadata.
  final String name;

  /// Normalized and alias-resolved key for artist aggregation and grouping.
  final String key;

  /// Creates a [SplitArtist] instance.
  const SplitArtist({required this.name, required this.key});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitArtist &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          key == other.key;

  @override
  int get hashCode => name.hashCode ^ key.hashCode;

  @override
  String toString() => 'SplitArtist(name: $name, key: $key)';
}

/// Utility for splitting multi-artist strings into individual artist entities.
abstract final class ArtistSplitter {
  /// Unambiguous separators that always split artist strings.
  /// Includes: ';', ' feat. ', ' feat ', ' ft. ', ' featuring '.
  static final RegExp _unambiguousRegex = RegExp(
    r'(?:\s*;\s*|\s+(?:feat\.?|ft\.?|featuring)\s+)',
    caseSensitive: false,
  );

  /// Ambiguous separators that split only when at least one part exists alone.
  /// Includes: ' & ', ' and ', ' اند ', ' و ', ',', '،', ' + '.
  /// Does NOT split on '/'.
  static final RegExp _ambiguousRegex = RegExp(
    r'(?:\s*,\s*|\s*،\s*|\s+&\s+|\s+and\s+|\s+[أإاآ]?ند\s+|\s+و[\u064B-\u065F]?\s+|\s+\+\s+)',
    caseSensitive: false,
  );

  /// Checks if [artistString] contains any ambiguous separators.
  static bool hasAmbiguousSeparator(String artistString) {
    return _ambiguousRegex.hasMatch(artistString);
  }

  /// Splits [rawArtist] into distinct [SplitArtist] entities.
  ///
  /// - Unambiguous separators (';', ' feat. ', etc.) always split.
  /// - Ambiguous separators (' & ', ' and ', ',', etc.) split only when at least
  ///   one resulting part matches a standalone artist in [standaloneArtistKeys]
  ///   (after normalization and [resolveAlias]).
  /// - Any string matching [noSplitKeys] is kept whole.
  /// - Never splits on '/'.
  static List<SplitArtist> split(
    String? rawArtist, {
    Set<String> standaloneArtistKeys = const {},
    Set<String> noSplitKeys = const {},
    String Function(String key)? resolveAlias,
  }) {
    final trimmed = rawArtist?.trim() ?? '';
    if (trimmed.isEmpty) {
      final defaultKey = TextNormalizer.normalize('Unknown Artist');
      final resolved = resolveAlias != null ? resolveAlias(defaultKey) : defaultKey;
      return [SplitArtist(name: 'Unknown Artist', key: resolved)];
    }

    String resolveKey(String norm) =>
        resolveAlias != null ? resolveAlias(norm) : norm;

    final fullNormalized = TextNormalizer.normalize(trimmed);
    if (noSplitKeys.contains(fullNormalized)) {
      return [SplitArtist(name: trimmed, key: resolveKey(fullNormalized))];
    }

    // 1. Always split on unambiguous separators.
    final unambiguousChunks = trimmed
        .split(_unambiguousRegex)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (unambiguousChunks.isEmpty) {
      final defaultKey = TextNormalizer.normalize('Unknown Artist');
      return [SplitArtist(name: 'Unknown Artist', key: resolveKey(defaultKey))];
    }

    final finalParts = <String>[];

    // 2. Evaluate ambiguous separators for each chunk.
    for (final chunk in unambiguousChunks) {
      final chunkNorm = TextNormalizer.normalize(chunk);
      if (noSplitKeys.contains(chunkNorm) || !_ambiguousRegex.hasMatch(chunk)) {
        finalParts.add(chunk);
        continue;
      }

      final candidateParts = chunk
          .split(_ambiguousRegex)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (candidateParts.length <= 1) {
        finalParts.add(chunk);
        continue;
      }

      // Check if at least one candidate part exists alone in the library.
      var shouldSplit = false;
      for (final candidate in candidateParts) {
        final candidateNorm = TextNormalizer.normalize(candidate);
        final candidateKey = resolveKey(candidateNorm);
        if (standaloneArtistKeys.contains(candidateKey)) {
          shouldSplit = true;
          break;
        }
      }

      if (shouldSplit) {
        finalParts.addAll(candidateParts);
      } else {
        finalParts.add(chunk);
      }
    }

    // Deduplicate by resolved key while preserving display name.
    final result = <SplitArtist>[];
    final seenKeys = <String>{};

    for (final part in finalParts) {
      final norm = TextNormalizer.normalize(part);
      final key = resolveKey(norm);
      if (seenKeys.add(key)) {
        result.add(SplitArtist(name: part, key: key));
      }
    }

    return result.isEmpty
        ? [SplitArtist(name: trimmed, key: resolveKey(fullNormalized))]
        : result;
  }
}
