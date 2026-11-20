import '../../library/models.dart';
import '../../library/text_normalizer.dart';
import 'release_kind.dart';

/// Section types rendered on the artist detail page in Apple Music order.
enum ArtistPageSectionKind {
  /// Full-length albums by this artist.
  albums,

  /// Singles and EPs by this artist.
  singlesAndEps,

  /// Various-artist compilations containing tracks by this artist.
  compilations,

  /// Releases by other primary artists featuring this artist.
  appearsOn,

  /// All tracks linked to this artist.
  tracks,
}

/// Non-empty album release section on the artist detail page.
class ArtistAlbumSection {
  /// Section identifier.
  final ArtistPageSectionKind kind;

  /// Albums in this section, sorted by year descending then title ascending.
  final List<AlbumSummary> albums;

  /// Creates an [ArtistAlbumSection].
  const ArtistAlbumSection({
    required this.kind,
    required this.albums,
  });
}

/// Pure-Dart presentation model for the Apple Music-style artist detail page.
class ArtistPageModel {
  /// Display name of the artist.
  final String artistName;

  /// Canonical artist key.
  final String artistKey;

  /// Total number of classified releases across the four album sections.
  final int albumCount;

  /// Total number of tracks linked to this artist.
  final int trackCount;

  /// Full-length albums sorted by year descending, then title.
  final List<AlbumSummary> albums;

  /// Merged singles and EPs sorted by year descending, then title.
  final List<AlbumSummary> singlesAndEps;

  /// Compilations sorted by year descending, then title.
  final List<AlbumSummary> compilations;

  /// Appears-on releases sorted by year descending, then title.
  final List<AlbumSummary> appearsOn;

  /// Tracks performed by this artist.
  final List<Track> tracks;

  /// Creates an [ArtistPageModel].
  const ArtistPageModel({
    required this.artistName,
    required this.artistKey,
    required this.albumCount,
    required this.trackCount,
    required this.albums,
    required this.singlesAndEps,
    required this.compilations,
    required this.appearsOn,
    required this.tracks,
  });

  /// Builds an [ArtistPageModel] from repository albums and artist tracks.
  factory ArtistPageModel.fromData({
    required String artistName,
    String? artistKey,
    required List<AlbumSummary> albums,
    required List<Track> tracks,
    Set<String> aliasKeys = const {},
  }) {
    final effectiveKey =
        (artistKey != null && artistKey.trim().isNotEmpty) ? artistKey : artistName;

    final classified = ReleaseKindClassifier.classifyAlbums(
      albums: albums,
      artistName: artistName,
      artistKey: effectiveKey,
      tracks: tracks,
      aliasKeys: aliasKeys,
    );

    final albumsList = List<AlbumSummary>.from(classified[ReleaseCategory.albums]!)
      ..sort(compareAlbumsByYearDescThenTitle);
    final singlesAndEpsList = <AlbumSummary>[
      ...classified[ReleaseCategory.singles]!,
      ...classified[ReleaseCategory.eps]!,
    ]..sort(compareAlbumsByYearDescThenTitle);
    final compilationsList =
        List<AlbumSummary>.from(classified[ReleaseCategory.compilations]!)
          ..sort(compareAlbumsByYearDescThenTitle);
    final appearsOnList =
        List<AlbumSummary>.from(classified[ReleaseCategory.appearsOn]!)
          ..sort(compareAlbumsByYearDescThenTitle);

    final unmodifiableAlbums = List<AlbumSummary>.unmodifiable(albumsList);
    final unmodifiableSingles =
        List<AlbumSummary>.unmodifiable(singlesAndEpsList);
    final unmodifiableCompilations =
        List<AlbumSummary>.unmodifiable(compilationsList);
    final unmodifiableAppearsOn = List<AlbumSummary>.unmodifiable(appearsOnList);
    final unmodifiableTracks = List<Track>.unmodifiable(tracks);

    final totalAlbums = unmodifiableAlbums.length +
        unmodifiableSingles.length +
        unmodifiableCompilations.length +
        unmodifiableAppearsOn.length;

    return ArtistPageModel(
      artistName: artistName,
      artistKey: effectiveKey,
      albumCount: totalAlbums,
      trackCount: unmodifiableTracks.length,
      albums: unmodifiableAlbums,
      singlesAndEps: unmodifiableSingles,
      compilations: unmodifiableCompilations,
      appearsOn: unmodifiableAppearsOn,
      tracks: unmodifiableTracks,
    );
  }

  /// Compares two [AlbumSummary] entries by release year descending (unknown/<=0
  /// years last), then normalized album title ascending.
  static int compareAlbumsByYearDescThenTitle(AlbumSummary a, AlbumSummary b) {
    final aYear = a.year;
    final bYear = b.year;
    final aKnown = aYear != null && aYear > 0;
    final bKnown = bYear != null && bYear > 0;

    if (aKnown && bKnown) {
      final yearCmp = bYear.compareTo(aYear);
      if (yearCmp != 0) return yearCmp;
    } else if (aKnown != bKnown) {
      return aKnown ? -1 : 1;
    }

    final normA = TextNormalizer.normalize(a.album);
    final normB = TextNormalizer.normalize(b.album);
    final normCmp = normA.compareTo(normB);
    if (normCmp != 0) return normCmp;

    final lowerCmp = a.album.toLowerCase().compareTo(b.album.toLowerCase());
    if (lowerCmp != 0) return lowerCmp;

    final exactCmp = a.album.compareTo(b.album);
    if (exactCmp != 0) return exactCmp;

    return (a.albumArtist ?? '')
        .toLowerCase()
        .compareTo((b.albumArtist ?? '').toLowerCase());
  }

  /// Whether the Albums section has any items.
  bool get hasAlbums => albums.isNotEmpty;

  /// Whether the Singles & EPs section has any items.
  bool get hasSinglesAndEps => singlesAndEps.isNotEmpty;

  /// Whether the Compilations section has any items.
  bool get hasCompilations => compilations.isNotEmpty;

  /// Whether the Appears on section has any items.
  bool get hasAppearsOn => appearsOn.isNotEmpty;

  /// Whether the Tracks section has any items.
  bool get hasTracks => tracks.isNotEmpty;

  /// Ordered list of non-empty sections to display.
  List<ArtistPageSectionKind> get visibleSections => [
        if (hasAlbums) ArtistPageSectionKind.albums,
        if (hasSinglesAndEps) ArtistPageSectionKind.singlesAndEps,
        if (hasCompilations) ArtistPageSectionKind.compilations,
        if (hasAppearsOn) ArtistPageSectionKind.appearsOn,
        if (hasTracks) ArtistPageSectionKind.tracks,
      ];

  /// Ordered list of non-empty album card sections to display.
  List<ArtistAlbumSection> get albumSections => [
        if (hasAlbums)
          ArtistAlbumSection(
            kind: ArtistPageSectionKind.albums,
            albums: albums,
          ),
        if (hasSinglesAndEps)
          ArtistAlbumSection(
            kind: ArtistPageSectionKind.singlesAndEps,
            albums: singlesAndEps,
          ),
        if (hasCompilations)
          ArtistAlbumSection(
            kind: ArtistPageSectionKind.compilations,
            albums: compilations,
          ),
        if (hasAppearsOn)
          ArtistAlbumSection(
            kind: ArtistPageSectionKind.appearsOn,
            albums: appearsOn,
          ),
      ];

  /// Filters [tracks] by [query] using normalized title and album matching
  /// (case-insensitive and Arabic/Latin diacritic tolerant).
  List<Track> filterTracks(String query) {
    final normalized = TextNormalizer.normalize(query);
    if (normalized.isEmpty) return tracks;

    final terms =
        normalized.split(' ').where((term) => term.isNotEmpty).toList();
    if (terms.isEmpty) return tracks;

    return tracks.where((track) {
      final haystack = TextNormalizer.normalize(
        '${track.title ?? ''} ${track.album ?? ''}',
      );
      return terms.every(haystack.contains);
    }).toList();
  }
}
