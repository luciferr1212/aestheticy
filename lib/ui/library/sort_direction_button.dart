import 'package:flutter/material.dart';

import '../../library/library_repository.dart';
import '../../library/text_normalizer.dart';
import '../l10n/app_strings.dart';

/// Small consistent model representing ascending or descending sort direction.
enum SortDirection {
  /// Natural or chronological order (A to Z, 0 to 9, oldest to newest).
  ascending,

  /// Reversed order (Z to A, 9 to 0, newest to oldest).
  descending;

  /// Whether this direction is [SortDirection.ascending].
  bool get isAscending => this == SortDirection.ascending;

  /// Whether this direction is [SortDirection.descending].
  bool get isDescending => this == SortDirection.descending;

  /// Returns the inverted sort direction.
  SortDirection get toggled =>
      isAscending ? SortDirection.descending : SortDirection.ascending;

  /// Creates a [SortDirection] from a boolean where true means descending.
  static SortDirection fromReversed(bool reversed) =>
      reversed ? SortDirection.descending : SortDirection.ascending;

  /// Converts this direction to a boolean where true means descending (reversed).
  bool get isReversed => isDescending;

  /// Returns the natural sort reversal state for a given sort key.
  ///
  /// 'mostPlayed', 'mostSongs', 'mostAlbums', 'recentlyAdded', and 'year'
  /// default to descending (true).
  /// 'title', 'album', 'name', 'artist', and 'duration'
  /// default to ascending (false).
  static bool defaultReversedFor(String sortKey) {
    switch (sortKey) {
      case 'mostPlayed':
      case 'mostSongs':
      case 'mostAlbums':
      case 'recentlyAdded':
      case 'year':
        return true;
      case 'title':
      case 'album':
      case 'name':
      case 'artist':
      case 'duration':
      default:
        return false;
    }
  }

  /// Returns the natural sort direction for a given sort key.
  static SortDirection defaultFor(String sortKey) =>
      fromReversed(defaultReversedFor(sortKey));
}

/// Shared sort direction toggle button used across all library list pages.
class SortDirectionButton extends StatelessWidget {
  /// Current sort direction.
  final SortDirection direction;

  /// Callback when user taps to toggle sort direction.
  final ValueChanged<SortDirection> onChanged;

  /// Whether animations are disabled.
  final bool reduceMotion;

  /// Optional specific widget key for the underlying button.
  final Key? buttonKey;

  /// Optional override for the tooltip text.
  final String? tooltip;

  /// Optional override for the accessibility semantic label.
  final String? semanticLabel;

  /// Creates a [SortDirectionButton].
  const SortDirectionButton({
    super.key,
    required this.direction,
    required this.onChanged,
    this.reduceMotion = false,
    this.buttonKey,
    this.tooltip,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTooltip = tooltip ??
        (direction.isDescending
            ? context.t('common.sortDescending')
            : context.t('common.sortAscending'));
    final effectiveSemantic = semanticLabel ?? effectiveTooltip;

    return Semantics(
      button: true,
      label: effectiveSemantic,
      child: IconButton(
        key: buttonKey ?? const Key('sort_direction_button'),
        icon: AnimatedRotation(
          turns: direction.isDescending ? 0.5 : 0.0,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 140),
          curve: Curves.easeInOut,
          child: const Icon(Icons.arrow_upward, size: 18),
        ),
        tooltip: effectiveTooltip,
        onPressed: () => onChanged(direction.toggled),
      ),
    );
  }
}

/// Helper for stable, locale-aware string comparison for Arabic and Latin text.
int compareLocaleAware(String a, String b) {
  final normA = TextNormalizer.normalize(a);
  final normB = TextNormalizer.normalize(b);
  return normA.compareTo(normB);
}

/// Clean abstract interface for retrieving track play counts.
abstract interface class TrackPlayCountSource {
  /// Returns a map of track URI/path to listening play count.
  Future<Map<String, int>> getPlayCounts();
}

/// Default implementation querying play events from [LibraryRepository].
class RepositoryPlayCountSource implements TrackPlayCountSource {
  /// The underlying library data repository.
  final LibraryRepository repository;

  /// Creates a [RepositoryPlayCountSource].
  const RepositoryPlayCountSource(this.repository);

  @override
  Future<Map<String, int>> getPlayCounts() async {
    try {
      final events = await repository.recentPlayEvents(limit: 5000);
      final counts = <String, int>{};
      for (final event in events) {
        counts[event.uri] = (counts[event.uri] ?? 0) + 1;
      }
      return counts;
    } catch (_) {
      return const {};
    }
  }
}

/// Fake implementation of [TrackPlayCountSource] for unit and widget tests.
class FakePlayCountSource implements TrackPlayCountSource {
  /// Static map of track path to play counts.
  final Map<String, int> counts;

  /// Creates a [FakePlayCountSource].
  FakePlayCountSource([this.counts = const {}]);

  @override
  Future<Map<String, int>> getPlayCounts() async => Map.unmodifiable(counts);
}
