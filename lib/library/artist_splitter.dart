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
  /// Unambiguous collaboration tokens regex.
  static final RegExp _featRegex = RegExp(
    r'\s+(?:feat\.?|ft\.?|featuring)\s+',
    caseSensitive: false,
  );

  /// Ambiguous separators that split only when at least one part exists alone.
  /// Includes: ' & ', ' and ', ' اند ', ' و ', ',', '،', ' + '.
  /// Does NOT split on '/'.
  static final RegExp _ambiguousRegex = RegExp(
    r'(?:\s*,\s*|\s*،\s*|\s+&\s+|\s+and\s+|\s+[أإاآ]?ند\s+|\s+و[\u064B-\u065F]?\s+|\s+\+\s+)',
    caseSensitive: false,
  );

  /// Matches bracketed feature patterns like '(feat. B)', '[feat. B]', '(ft. B)', '[ft. B]'.
  static final RegExp _bracketedFeatRegex = RegExp(
    r'\s*[\(\[]\s*(?:feat\.?|ft\.?|featuring)\s+([^\)\]]+)[\)\]]',
    caseSensitive: false,
  );

  /// Checks if [artistString] contains any ambiguous separators.
  static bool hasAmbiguousSeparator(String artistString) {
    // Quick pre-filter: avoid regex evaluation if none of the candidate characters exist.
    if (!artistString.contains(',') &&
        !artistString.contains('،') &&
        !artistString.contains('&') &&
        !artistString.contains('+') &&
        !artistString.contains('و') &&
        !artistString.contains('ند') &&
        !artistString.toLowerCase().contains('and')) {
      return false;
    }
    return _ambiguousRegex.hasMatch(artistString);
  }

  /// Splits [rawArtist] into distinct [SplitArtist] entities.
  ///
  /// - Unambiguous separators (';', ' feat. ', etc.) and bracketed features
  ///   ('(feat. B)', '[feat. B]', '(ft. B)') always split with brackets stripped.
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

    final lower = trimmed.toLowerCase();
    final hasFeatToken = lower.contains('feat') || lower.contains('ft');
    final hasBrackets = (trimmed.contains('(') || trimmed.contains('[')) && hasFeatToken;
    final hasSemicolon = trimmed.contains(';');
    final hasFeat = hasFeatToken && _featRegex.hasMatch(trimmed);
    final hasAmbiguous = hasAmbiguousSeparator(trimmed);

    if (!hasBrackets && !hasSemicolon && !hasFeat && !hasAmbiguous) {
      return [SplitArtist(name: trimmed, key: resolveKey(fullNormalized))];
    }

    // 1. Unpack bracketed features: '(feat. B)' or '[ft. B]' -> '; B'
    final String withBracketFeaturesResolved;
    if (hasBrackets) {
      withBracketFeaturesResolved = trimmed.replaceAllMapped(
        _bracketedFeatRegex,
        (match) {
          final inner = match.group(1)?.trim() ?? '';
          return inner.isNotEmpty ? '; $inner' : '';
        },
      );
    } else {
      withBracketFeaturesResolved = trimmed;
    }

    // 2. Always split on unambiguous separators (semicolon and feat tokens).
    final List<String> unambiguousChunks;
    if (withBracketFeaturesResolved.contains(';')) {
      final chunks = <String>[];
      for (final part in withBracketFeaturesResolved.split(';')) {
        final t = part.trim();
        if (t.isEmpty) continue;
        final tLower = t.toLowerCase();
        if ((tLower.contains('feat') || tLower.contains('ft')) && _featRegex.hasMatch(t)) {
          chunks.addAll(
            t.split(_featRegex).map((s) => s.trim()).where((s) => s.isNotEmpty),
          );
        } else {
          chunks.add(t);
        }
      }
      unambiguousChunks = chunks;
    } else if (hasFeatToken && _featRegex.hasMatch(withBracketFeaturesResolved)) {
      unambiguousChunks = withBracketFeaturesResolved
          .split(_featRegex)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      unambiguousChunks = [withBracketFeaturesResolved];
    }

    if (unambiguousChunks.isEmpty) {
      final defaultKey = TextNormalizer.normalize('Unknown Artist');
      return [SplitArtist(name: 'Unknown Artist', key: resolveKey(defaultKey))];
    }

    final finalParts = <({String name, String normKey})>[];

    // 3. Evaluate ambiguous separators for each chunk.
    for (final chunk in unambiguousChunks) {
      final chunkNorm = TextNormalizer.normalize(chunk);
      if (noSplitKeys.contains(chunkNorm) || !hasAmbiguousSeparator(chunk)) {
        finalParts.add((name: chunk, normKey: chunkNorm));
        continue;
      }

      final candidateParts = chunk
          .split(_ambiguousRegex)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (candidateParts.length <= 1) {
        finalParts.add((name: chunk, normKey: chunkNorm));
        continue;
      }

      // Check if at least one candidate part exists alone in the library.
      var shouldSplit = false;
      final candidatesWithNorm = candidateParts.map((c) {
        final norm = TextNormalizer.normalize(c);
        return (name: c, normKey: norm);
      }).toList();

      for (final candidate in candidatesWithNorm) {
        final candidateKey = resolveKey(candidate.normKey);
        if (standaloneArtistKeys.contains(candidateKey)) {
          shouldSplit = true;
          break;
        }
      }

      if (shouldSplit) {
        finalParts.addAll(candidatesWithNorm);
      } else {
        finalParts.add((name: chunk, normKey: chunkNorm));
      }
    }

    // Deduplicate by resolved key while preserving display name.
    final result = <SplitArtist>[];
    final seenKeys = <String>{};

    for (final part in finalParts) {
      final key = resolveKey(part.normKey);
      if (seenKeys.add(key)) {
        result.add(SplitArtist(name: part.name, key: key));
      }
    }

    return result.isEmpty
        ? [SplitArtist(name: trimmed, key: resolveKey(fullNormalized))]
        : result;
  }
}
