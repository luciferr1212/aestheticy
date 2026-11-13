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

  /// Classifies a single album group according to the defined heuristic rules.
  static ReleaseCategory classifyAlbumGroup({
    required String? albumTitle,
    required String? albumArtist,
    required List<Track> tracks,
    required String artistName,
    String? artistKey,
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

    final targetKey = TextNormalizer.normalize(artistKey ?? artistName);

    // 2. The artist is not the album artist (a featured or track-level artist only): Appears on.
    if (trimmedAlbumArtist.isNotEmpty) {
      final albumArtistKey = TextNormalizer.normalize(trimmedAlbumArtist);
      if (albumArtistKey != targetKey) {
        return ReleaseCategory.appearsOn;
      }
    } else {
      // Album artist tag is absent. Check if target artist is only featured across all tracks.
      var isFeaturedOnly = tracks.isNotEmpty;
      for (final track in tracks) {
        final trackArtist = track.artist?.trim() ?? '';
        if (trackArtist.isNotEmpty) {
          final splits = ArtistSplitter.split(trackArtist);
          if (splits.isNotEmpty && splits.first.key == targetKey) {
            isFeaturedOnly = false;
            break;
          }
        }
      }
      if (isFeaturedOnly && tracks.isNotEmpty) {
        return ReleaseCategory.appearsOn;
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
    final count = tracks.length;
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

  /// Groups [tracks] by album title + album artist and maps each [ReleaseCategory] to its tracks.
  static Map<ReleaseCategory, List<Track>> classifyTracks({
    required List<Track> tracks,
    required String artistName,
    String? artistKey,
  }) {
    final groups = <String, List<Track>>{};
    for (final track in tracks) {
      final key =
          '${track.album?.trim().toLowerCase() ?? ''}|${track.albumArtist?.trim().toLowerCase() ?? ''}';
      groups.putIfAbsent(key, () => []).add(track);
    }

    final result = <ReleaseCategory, List<Track>>{
      ReleaseCategory.all: List.unmodifiable(tracks),
      ReleaseCategory.albums: [],
      ReleaseCategory.singles: [],
      ReleaseCategory.eps: [],
      ReleaseCategory.compilations: [],
      ReleaseCategory.appearsOn: [],
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
      result[category]!.addAll(groupTracks);
    }

    return result;
  }
}
