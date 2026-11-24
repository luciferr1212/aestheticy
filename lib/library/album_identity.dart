/// Single source of truth for canonical album identity across repository
/// queries, cover artwork caching, scanning, and release classification.
library;

import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/text_normalizer.dart';

/// Computes canonical album identity keys and fallback artist resolution.
///
/// Grouping rules:
/// - Tracks with a non-empty [album] tag use
///   `album::<normalized album title>::<normalized effective artist>`,
///   where the effective artist is [albumArtist] if non-empty, falling back to
///   [artist].
/// - Tracks without an [album] tag (`null` or whitespace) use
///   `track::<lowercased trimmed trackPath>` so loose singles stay separate
///   from each other and never collapse into one folder or "Unknown Album".
abstract final class AlbumIdentity {
  /// Sentinel album title displayed in read models when a track has no album tag.
  static const String unknownAlbumTitle = 'Unknown Album';

  /// Returns whether [album] carries a non-empty album tag.
  static bool hasAlbumTag(String? album) =>
      album != null && album.trim().isNotEmpty;

  /// Resolves the effective album-level artist: trimmed [albumArtist] if
  /// non-empty, otherwise trimmed [artist] if non-empty, otherwise empty string.
  static String effectiveArtist({String? albumArtist, String? artist}) {
    final trimmedAlbumArtist = albumArtist?.trim() ?? '';
    if (trimmedAlbumArtist.isNotEmpty) {
      return trimmedAlbumArtist;
    }
    final trimmedArtist = artist?.trim() ?? '';
    if (trimmedArtist.isNotEmpty) {
      return trimmedArtist;
    }
    return '';
  }

  /// Normalizes the effective album artist using [TextNormalizer.normalize].
  static String normalizedArtist({String? albumArtist, String? artist}) {
    return TextNormalizer.normalize(
      effectiveArtist(albumArtist: albumArtist, artist: artist),
    );
  }

  /// Computes the canonical album identity string for the given metadata.
  static String key({
    String? album,
    String? albumArtist,
    String? artist,
    String? trackPath,
  }) {
    final trimmedAlbum = album?.trim() ?? '';
    if (trimmedAlbum.isEmpty) {
      final trimmedPath = trackPath?.trim() ?? '';
      if (trimmedPath.isNotEmpty) {
        return 'track::${trimmedPath.toLowerCase()}';
      }
      final normArtist = normalizedArtist(
        albumArtist: albumArtist,
        artist: artist,
      );
      return 'unknown::$normArtist';
    }

    final normAlbum = TextNormalizer.normalize(trimmedAlbum);
    final normArtist = normalizedArtist(
      albumArtist: albumArtist,
      artist: artist,
    );
    return 'album::$normAlbum::$normArtist';
  }

  /// Computes the canonical album identity key for a [Track].
  static String forTrack(Track track) {
    return key(
      album: track.album,
      albumArtist: track.albumArtist,
      artist: track.artist,
      trackPath: track.path,
    );
  }

  /// Returns [AlbumSummary.identityKey] when present, or computes a canonical
  /// identity key from [summary]'s metadata.
  static String forSummary(AlbumSummary summary) {
    final explicitKey = summary.identityKey?.trim();
    if (explicitKey != null && explicitKey.isNotEmpty) {
      return explicitKey;
    }
    final fallbackArtist =
        (summary.displayArtist != null && summary.displayArtist != 'various')
            ? summary.displayArtist
            : null;
    final effectiveAlbum =
        summary.album.trim() == unknownAlbumTitle ? null : summary.album;
    return key(
      album: effectiveAlbum,
      albumArtist: summary.albumArtist,
      artist: fallbackArtist,
    );
  }
}
