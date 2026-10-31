/// Core immutable domain and read models for the library data layer.
///
/// Plain Dart value types with no external dependencies or audio imports.
library;

/// Sort options for querying tracks.
enum TrackSort {
  /// Sort by track title ascending (A-Z).
  titleAsc,

  /// Sort by track title descending (Z-A).
  titleDesc,

  /// Sort by artist name ascending (A-Z).
  artistAsc,

  /// Sort by artist name descending (Z-A).
  artistDesc,

  /// Sort by album name ascending (A-Z).
  albumAsc,

  /// Sort by album name descending (Z-A).
  albumDesc,

  /// Sort by date added ascending (oldest first).
  addedAtAsc,

  /// Sort by date added descending (newest first).
  addedAtDesc,
}

/// A scanned audio track persisted in the library database.
class Track {
  /// Unique database row ID, or null if not yet persisted.
  final int? id;

  /// Absolute filesystem path to the audio file.
  final String path;

  /// Reference to the parent [LibraryFolder.id].
  final int folderId;

  /// Track title (from audio tags or fallback filename).
  final String? title;

  /// Primary artist name.
  final String? artist;

  /// Album artist (e.g. compilation or primary band).
  final String? albumArtist;

  /// Album title.
  final String? album;

  /// Track index within the album or disc.
  final int? trackNo;

  /// Disc index in multi-disc albums.
  final int? discNo;

  /// Release year.
  final int? year;

  /// Duration in milliseconds.
  final int durationMs;

  /// File modification timestamp (milliseconds since Unix epoch).
  final int mtimeMs;

  /// File size in bytes.
  final int sizeBytes;

  /// Artwork identifier or file path for cover art.
  final String? coverKey;

  /// Timestamp when the track was added to the library.
  final DateTime addedAt;

  /// Creates an immutable [Track] instance.
  const Track({
    this.id,
    required this.path,
    required this.folderId,
    this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.trackNo,
    this.discNo,
    this.year,
    required this.durationMs,
    required this.mtimeMs,
    required this.sizeBytes,
    this.coverKey,
    required this.addedAt,
  });

  /// Creates a copy of this [Track] with the given fields replaced.
  Track copyWith({
    int? id,
    String? path,
    int? folderId,
    String? title,
    String? artist,
    String? albumArtist,
    String? album,
    int? trackNo,
    int? discNo,
    int? year,
    int? durationMs,
    int? mtimeMs,
    int? sizeBytes,
    String? coverKey,
    DateTime? addedAt,
  }) {
    return Track(
      id: id ?? this.id,
      path: path ?? this.path,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      albumArtist: albumArtist ?? this.albumArtist,
      album: album ?? this.album,
      trackNo: trackNo ?? this.trackNo,
      discNo: discNo ?? this.discNo,
      year: year ?? this.year,
      durationMs: durationMs ?? this.durationMs,
      mtimeMs: mtimeMs ?? this.mtimeMs,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      coverKey: coverKey ?? this.coverKey,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          path == other.path &&
          folderId == other.folderId &&
          title == other.title &&
          artist == other.artist &&
          albumArtist == other.albumArtist &&
          album == other.album &&
          trackNo == other.trackNo &&
          discNo == other.discNo &&
          year == other.year &&
          durationMs == other.durationMs &&
          mtimeMs == other.mtimeMs &&
          sizeBytes == other.sizeBytes &&
          coverKey == other.coverKey &&
          addedAt == other.addedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      path.hashCode ^
      folderId.hashCode ^
      title.hashCode ^
      artist.hashCode ^
      albumArtist.hashCode ^
      album.hashCode ^
      trackNo.hashCode ^
      discNo.hashCode ^
      year.hashCode ^
      durationMs.hashCode ^
      mtimeMs.hashCode ^
      sizeBytes.hashCode ^
      coverKey.hashCode ^
      addedAt.hashCode;

  @override
  String toString() =>
      'Track(id: $id, path: $path, title: $title, artist: $artist, album: $album)';
}

/// A watched filesystem directory configured in the user library.
class LibraryFolder {
  /// Unique database row ID, or null if not yet persisted.
  final int? id;

  /// Absolute filesystem directory path.
  final String path;

  /// Timestamp of the last successful directory scan, or null if never scanned.
  final DateTime? lastScanAt;

  /// Creates an immutable [LibraryFolder] instance.
  const LibraryFolder({
    this.id,
    required this.path,
    this.lastScanAt,
  });

  /// Creates a copy of this [LibraryFolder] with the given fields replaced.
  LibraryFolder copyWith({
    int? id,
    String? path,
    DateTime? lastScanAt,
  }) {
    return LibraryFolder(
      id: id ?? this.id,
      path: path ?? this.path,
      lastScanAt: lastScanAt ?? this.lastScanAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryFolder &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          path == other.path &&
          lastScanAt == other.lastScanAt;

  @override
  int get hashCode => id.hashCode ^ path.hashCode ^ lastScanAt.hashCode;

  @override
  String toString() =>
      'LibraryFolder(id: $id, path: $path, lastScanAt: $lastScanAt)';
}

/// Lightweight read model for an album derived on-the-fly from track records.
class AlbumSummary {
  /// Album title.
  final String album;

  /// Primary album artist, if available.
  final String? albumArtist;

  /// Release year of the album.
  final int? year;

  /// Total number of tracks in this album.
  final int trackCount;

  /// Cover artwork key for this album, if available.
  final String? coverKey;

  /// Creates an immutable [AlbumSummary] instance.
  const AlbumSummary({
    required this.album,
    this.albumArtist,
    this.year,
    required this.trackCount,
    this.coverKey,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlbumSummary &&
          runtimeType == other.runtimeType &&
          album == other.album &&
          albumArtist == other.albumArtist &&
          year == other.year &&
          trackCount == other.trackCount &&
          coverKey == other.coverKey;

  @override
  int get hashCode =>
      album.hashCode ^
      albumArtist.hashCode ^
      year.hashCode ^
      trackCount.hashCode ^
      coverKey.hashCode;

  @override
  String toString() =>
      'AlbumSummary(album: $album, albumArtist: $albumArtist, year: $year, trackCount: $trackCount)';
}

/// Lightweight read model for an artist derived on-the-fly from track records.
class ArtistSummary {
  /// Artist name.
  final String name;

  /// Total number of distinct albums by this artist.
  final int albumCount;

  /// Total number of tracks by this artist.
  final int trackCount;

  /// Creates an immutable [ArtistSummary] instance.
  const ArtistSummary({
    required this.name,
    required this.albumCount,
    required this.trackCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtistSummary &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          albumCount == other.albumCount &&
          trackCount == other.trackCount;

  @override
  int get hashCode => name.hashCode ^ albumCount.hashCode ^ trackCount.hashCode;

  @override
  String toString() =>
      'ArtistSummary(name: $name, albumCount: $albumCount, trackCount: $trackCount)';
}
