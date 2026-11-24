import '../../library/album_identity.dart';
import '../../library/artist_splitter.dart';
import '../../library/models.dart';
import '../../library/text_normalizer.dart';

/// Available release categories for filtering tracks on the artist detail screen.
enum ReleaseCategory {
  /// All tracks by this artist without category filtering.
  all,

  /// Full-length albums (7+ tracks or 1-3 tracks longer than 20 minutes).
  albums,

  /// Singles (1-3 tracks under 20 minutes, titled hints, or tracks without an album).
  singles,

  /// Extended plays (4-6 tracks or titled with EP hints).
  eps,

  /// Compilation releases or "Various Artists" albums.
  compilations,

  /// Releases where this artist is featured or track-level rather than album artist.
  appearsOn,
}

/// Classifies tracks into release categories using pure Dart heuristics on owned library tracks.
///
/// Rules per album (grouped by album title plus album artist) in order:
/// 1. Album artist is "Various Artists" (case-insensitive, also "Various", "VA") -> Compilations.
/// 2. The artist is not the album artist (featured / track-level only) -> Appears on.
/// 3. Title ends with "- Single" or "(Single)" -> Singles. Ends with "- EP" or "(EP)" or has "EP" as last word -> EPs.
/// 4. By track count: 1-3 tracks and total < 20 min -> Singles; 4-6 tracks -> EPs; 7+ tracks -> Albums.
///    A 1-3 track album over 20 minutes counts as an Album.
/// 5. Tracks without an album -> Singles.
abstract final class ReleaseKindClassifier {
  static const int _kTwentyMinutesMs = 20 * 60 * 1000;

  static final RegExp _epWordRegex =
      RegExp(r'(?:^|\s)ep$', caseSensitive: false);

  /// Builds the canonical album identity key used to match [Track] records
  /// with [AlbumSummary] releases via [AlbumIdentity].
  static String albumGroupKey({
    required String? albumTitle,
    required String? albumArtist,
    String? artist,
    String? trackPath,
  }) {
    return AlbumIdentity.key(
      album: albumTitle,
      albumArtist: albumArtist,
      artist: artist,
      trackPath: trackPath,
    );
  }

  /// Classifies a single album group according to the defined heuristic rules.
  static ReleaseCategory classifyAlbumGroup({
    required String? albumTitle,
    required String? albumArtist,
    required List<Track> tracks,
    required String artistName,
    String? artistKey,
    int? albumTrackCount,
    String? fallbackDisplayArtist,
    Set<String> aliasKeys = const {},
  }) {
    // 5. Tracks without an album: Singles.
    final trimmedTitle = albumTitle?.trim() ?? '';
    if (trimmedTitle.isEmpty) {
      return ReleaseCategory.singles;
    }

    final trimmedAlbumArtist = albumArtist?.trim() ?? '';
    final lowerAlbumArtist = trimmedAlbumArtist.toLowerCase();

    // 1. Album artist is "Various Artists" (case-insensitive, also "Various", "VA"): Compilations.
    if (lowerAlbumArtist == 'various artists' ||
        lowerAlbumArtist == 'various' ||
        lowerAlbumArtist == 'va') {
      return ReleaseCategory.compilations;
    }

    final targetKeys = <String>{
      TextNormalizer.normalize(artistKey ?? artistName),
      if (artistKey != null && artistKey.trim().isNotEmpty)
        TextNormalizer.normalize(artistName),
      for (final key in aliasKeys) TextNormalizer.normalize(key),
    }..removeWhere((k) => k.isEmpty);

    // 2. The artist is not the album artist (a featured or track-level artist only): Appears on.
    if (trimmedAlbumArtist.isNotEmpty) {
      final albumArtistKey = TextNormalizer.normalize(trimmedAlbumArtist);
      if (!targetKeys.contains(albumArtistKey)) {
        return ReleaseCategory.appearsOn;
      }
    } else if (tracks.isNotEmpty) {
      // Album artist tag is absent. Check if target artist is only featured across all tracks.
      var isFeaturedOnly = true;
      for (final track in tracks) {
        final trackArtist = track.artist?.trim() ?? '';
        if (trackArtist.isNotEmpty) {
          final splits = ArtistSplitter.split(trackArtist);
          if (splits.isNotEmpty && targetKeys.contains(splits.first.key)) {
            isFeaturedOnly = false;
            break;
          }
        }
      }
      if (isFeaturedOnly) {
        return ReleaseCategory.appearsOn;
      }
    } else {
      final trimmedFallback = fallbackDisplayArtist?.trim() ?? '';
      if (trimmedFallback.isNotEmpty &&
          trimmedFallback.toLowerCase() != 'various') {
        final splits = ArtistSplitter.split(trimmedFallback);
        if (splits.isNotEmpty && !targetKeys.contains(splits.first.key)) {
          return ReleaseCategory.appearsOn;
        }
      }
    }

    // 3. Album title ends with "- Single" or "(Single)" (case-insensitive): Singles.
    //    Ends with "- EP" or "(EP)" or has "EP" as its last word: EPs.
    final lowerTitle = trimmedTitle.toLowerCase();
    if (lowerTitle.endsWith('- single') ||
        lowerTitle.endsWith('(single)') ||
        lowerTitle.endsWith('-single')) {
      return ReleaseCategory.singles;
    }
    if (lowerTitle.endsWith('- ep') ||
        lowerTitle.endsWith('(ep)') ||
        lowerTitle.endsWith('-ep') ||
        _epWordRegex.hasMatch(trimmedTitle)) {
      return ReleaseCategory.eps;
    }

    // 4. By owned track count: 1 to 3 tracks and total under 20 minutes: Singles;
    //    4 to 6 tracks: EPs; 7 or more: Albums.
    //    A 1 to 3 track album over 20 minutes counts as an Album.
    final count = (albumTrackCount != null && albumTrackCount > 0)
        ? albumTrackCount
        : tracks.length;
    final totalDurationMs =
        tracks.fold<int>(0, (sum, t) => sum + t.durationMs);

    if (count >= 7) {
      return ReleaseCategory.albums;
    }
    if (count >= 4) {
      return ReleaseCategory.eps;
    }
    if (count >= 1) {
      if (totalDurationMs > _kTwentyMinutesMs) {
        return ReleaseCategory.albums;
      }
      return ReleaseCategory.singles;
    }

    return ReleaseCategory.singles;
  }

  /// Classifies a single [AlbumSummary] using its matching album [tracks].
  static ReleaseCategory classifyAlbum({
    required AlbumSummary album,
    required String artistName,
    String? artistKey,
    List<Track> tracks = const [],
    Set<String> aliasKeys = const {},
  }) {
    return classifyAlbumGroup(
      albumTitle: album.album,
      albumArtist: album.albumArtist,
      tracks: tracks,
      artistName: artistName,
      artistKey: artistKey,
      albumTrackCount: album.trackCount,
      fallbackDisplayArtist: album.displayArtist,
      aliasKeys: aliasKeys,
    );
  }

  /// Classifies [albums] into [ReleaseCategory] buckets using [tracks] grouped by
  /// [AlbumIdentity] to determine duration and null-album-artist ownership.
  static Map<ReleaseCategory, List<AlbumSummary>> classifyAlbums({
    required List<AlbumSummary> albums,
    required String artistName,
    String? artistKey,
    List<Track> tracks = const [],
    Set<String> aliasKeys = const {},
  }) {
    final tracksByGroup = <String, List<Track>>{};
    final tracksByTitle = <String, List<Track>>{};
    for (final track in tracks) {
      if (!AlbumIdentity.hasAlbumTag(track.album)) continue;
      final groupKey = AlbumIdentity.forTrack(track);
      tracksByGroup.putIfAbsent(groupKey, () => []).add(track);
      if (track.albumArtist == null || track.albumArtist!.trim().isEmpty) {
        final normTitle = TextNormalizer.normalize(track.album);
        tracksByTitle.putIfAbsent(normTitle, () => []).add(track);
      }
    }

    final classified = <ReleaseCategory, List<AlbumSummary>>{
      ReleaseCategory.all: List<AlbumSummary>.unmodifiable(albums),
      ReleaseCategory.albums: <AlbumSummary>[],
      ReleaseCategory.singles: <AlbumSummary>[],
      ReleaseCategory.eps: <AlbumSummary>[],
      ReleaseCategory.compilations: <AlbumSummary>[],
      ReleaseCategory.appearsOn: <AlbumSummary>[],
    };

    for (final album in albums) {
      final groupKey = AlbumIdentity.forSummary(album);
      var groupTracks = tracksByGroup[groupKey];
      if (groupTracks == null &&
          album.identityKey == null &&
          (album.albumArtist == null || album.albumArtist!.trim().isEmpty) &&
          (album.displayArtist == null || album.displayArtist!.trim().isEmpty) &&
          AlbumIdentity.hasAlbumTag(album.album)) {
        groupTracks = tracksByTitle[TextNormalizer.normalize(album.album)];
      }
      final category = classifyAlbum(
        album: album,
        artistName: artistName,
        artistKey: artistKey,
        tracks: groupTracks ?? const <Track>[],
        aliasKeys: aliasKeys,
      );
      classified[category]!.add(album);
    }

    return classified;
  }

  /// Classifies [tracks] into release categories and counts distinct releases per category.
  static ReleaseClassification classify({
    required List<Track> tracks,
    required String artistName,
    String? artistKey,
  }) {
    final groups = <String, List<Track>>{};
    for (final track in tracks) {
      final key = AlbumIdentity.forTrack(track);
      groups.putIfAbsent(key, () => []).add(track);
    }

    final tracksMap = <ReleaseCategory, List<Track>>{
      ReleaseCategory.all: List.unmodifiable(tracks),
      ReleaseCategory.albums: [],
      ReleaseCategory.singles: [],
      ReleaseCategory.eps: [],
      ReleaseCategory.compilations: [],
      ReleaseCategory.appearsOn: [],
    };

    final releaseCounts = <ReleaseCategory, int>{
      ReleaseCategory.all: 0,
      ReleaseCategory.albums: 0,
      ReleaseCategory.singles: 0,
      ReleaseCategory.eps: 0,
      ReleaseCategory.compilations: 0,
      ReleaseCategory.appearsOn: 0,
    };

    for (final entry in groups.entries) {
      final groupTracks = entry.value;
      final first = groupTracks.first;
      final category = classifyAlbumGroup(
        albumTitle: first.album,
        albumArtist: first.albumArtist,
        tracks: groupTracks,
        artistName: artistName,
        artistKey: artistKey,
      );
      tracksMap[category]!.addAll(groupTracks);
      releaseCounts[category] = (releaseCounts[category] ?? 0) + 1;
    }

    releaseCounts[ReleaseCategory.all] = groups.length;

    return ReleaseClassification(
      tracks: tracksMap,
      releaseCounts: releaseCounts,
    );
  }

  /// Groups [tracks] by album title + album artist and maps each [ReleaseCategory] to its tracks.
  static Map<ReleaseCategory, List<Track>> classifyTracks({
    required List<Track> tracks,
    required String artistName,
    String? artistKey,
  }) {
    return classify(
      tracks: tracks,
      artistName: artistName,
      artistKey: artistKey,
    ).tracks;
  }

  /// Returns the release counts for each [ReleaseCategory].
  static Map<ReleaseCategory, int> countReleases({
    required List<Track> tracks,
    required String artistName,
    String? artistKey,
  }) {
    return classify(
      tracks: tracks,
      artistName: artistName,
      artistKey: artistKey,
    ).releaseCounts;
  }
}

/// Result of classifying tracks into release categories, including track lists and release counts.
class ReleaseClassification {
  /// Map of [ReleaseCategory] to the list of tracks belonging to it.
  final Map<ReleaseCategory, List<Track>> tracks;

  /// Map of [ReleaseCategory] to the number of distinct releases (albums / singles).
  final Map<ReleaseCategory, int> releaseCounts;

  /// Creates a [ReleaseClassification].
  const ReleaseClassification({
    required this.tracks,
    required this.releaseCounts,
  });
}
