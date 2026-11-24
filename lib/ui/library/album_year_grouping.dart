import '../../library/models.dart';
import 'sort_direction_button.dart';

/// A section of albums sharing the same release [year] (or `null` for unknown).
class AlbumYearGroup {
  /// Release year for this group, or `null` when the release year is unknown.
  final int? year;

  /// Albums belonging to this year, sorted alphabetically by artist then title.
  final List<AlbumSummary> albums;

  /// Creates an [AlbumYearGroup].
  const AlbumYearGroup({
    required this.year,
    required this.albums,
  });
}

/// Groups [albums] by release year (newest first by default, oldest first when [reversed] is true, unknown years last).
///
/// Within each year group, albums are sorted alphabetically by artist then
/// title. Null or non-positive (`<= 0`) years are placed together in a single
/// trailing group with `year == null`.
List<AlbumYearGroup> groupAlbumsByYear(
  List<AlbumSummary> albums, {
  bool reversed = false,
  String Function(AlbumSummary)? artistResolver,
}) {
  final byYear = <int, List<AlbumSummary>>{};
  final unknown = <AlbumSummary>[];

  for (final album in albums) {
    final year = album.year;
    if (year != null && year > 0) {
      byYear.putIfAbsent(year, () => <AlbumSummary>[]).add(album);
    } else {
      unknown.add(album);
    }
  }

  String resolveArtist(AlbumSummary album) =>
      artistResolver?.call(album) ?? album.displayArtist ?? album.albumArtist ?? '';

  int compareWithinGroup(AlbumSummary a, AlbumSummary b) {
    final artistCmp = compareLocaleAware(resolveArtist(a), resolveArtist(b));
    if (artistCmp != 0) return artistCmp;
    return compareLocaleAware(a.album, b.album);
  }

  final years = byYear.keys.toList()
    ..sort((a, b) => reversed ? a.compareTo(b) : b.compareTo(a));
  final groups = <AlbumYearGroup>[];
  for (final year in years) {
    final items = byYear[year]!..sort(compareWithinGroup);
    groups.add(AlbumYearGroup(year: year, albums: items));
  }

  if (unknown.isNotEmpty) {
    unknown.sort(compareWithinGroup);
    groups.add(AlbumYearGroup(year: null, albums: unknown));
  }

  return groups;
}
