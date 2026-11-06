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

  /// Computed display artist for UI representation.
  final String? displayArtist;

  /// Creates an immutable [AlbumSummary] instance.
  const AlbumSummary({
    required this.album,
    this.albumArtist,
    this.year,
    required this.trackCount,
    this.coverKey,
    this.displayArtist,
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
          coverKey == other.coverKey &&
          displayArtist == other.displayArtist;

  @override
  int get hashCode =>
      album.hashCode ^
      albumArtist.hashCode ^
      year.hashCode ^
      trackCount.hashCode ^
      coverKey.hashCode ^
      displayArtist.hashCode;

  @override
  String toString() =>
      'AlbumSummary(album: $album, albumArtist: $albumArtist, year: $year, trackCount: $trackCount)';
}

/// Lightweight read model for an artist derived on-the-fly from track records.
class ArtistSummary {
  /// Unique normalized canonical key for grouping and aliases.
  final String key;

  /// Artist name (most frequent spelling).
  final String name;

  /// Total number of distinct albums by this artist.
  final int albumCount;

  /// Total number of tracks by this artist.
  final int trackCount;

  /// Creates an immutable [ArtistSummary] instance.
  const ArtistSummary({
    String? key,
    required this.name,
    required this.albumCount,
    required this.trackCount,
  }) : key = key ?? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtistSummary &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          name == other.name &&
          albumCount == other.albumCount &&
          trackCount == other.trackCount;

  @override
  int get hashCode =>
      key.hashCode ^ name.hashCode ^ albumCount.hashCode ^ trackCount.hashCode;

  @override
  String toString() =>
      'ArtistSummary(key: $key, name: $name, albumCount: $albumCount, trackCount: $trackCount)';
}

/// An artist alias mapping an alternative spelling or name to a canonical artist.
class ArtistAlias {
  /// The normalized alias key being merged.
  final String aliasKey;

  /// The normalized canonical artist key merged into.
  final String canonicalKey;

  /// The display name of the canonical artist.
  final String canonicalName;

  /// Creates an immutable [ArtistAlias] instance.
  const ArtistAlias({
    required this.aliasKey,
    required this.canonicalKey,
    required this.canonicalName,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtistAlias &&
          runtimeType == other.runtimeType &&
          aliasKey == other.aliasKey &&
          canonicalKey == other.canonicalKey &&
          canonicalName == other.canonicalName;

  @override
  int get hashCode =>
      aliasKey.hashCode ^ canonicalKey.hashCode ^ canonicalName.hashCode;

  @override
  String toString() =>
      'ArtistAlias(aliasKey: $aliasKey, canonicalKey: $canonicalKey, canonicalName: $canonicalName)';
}

/// An artist rule preventing a specific string from being split.
class ArtistNoSplit {
  /// The normalized artist key that should never be split.
  final String artistKey;

  /// The display name of the artist.
  final String artistName;

  /// Creates an immutable [ArtistNoSplit] instance.
  const ArtistNoSplit({
    required this.artistKey,
    required this.artistName,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtistNoSplit &&
          runtimeType == other.runtimeType &&
          artistKey == other.artistKey &&
          artistName == other.artistName;

  @override
  int get hashCode => artistKey.hashCode ^ artistName.hashCode;

  @override
  String toString() =>
      'ArtistNoSplit(artistKey: $artistKey, artistName: $artistName)';
}

/// An immutable record of a playback session in listening history.
class PlayEvent {
  /// Unique database row ID, or null if not yet persisted.
  final int? id;

  /// Audio track resource URI (file path).
  final String uri;

  /// Track title at the time of playback.
  final String? title;

  /// Primary artist at the time of playback.
  final String? artist;

  /// Album title at the time of playback.
  final String? album;

  /// Album artist at the time of playback.
  final String? albumArtist;

  /// Track total duration in milliseconds, if known.
  final int? durationMs;

  /// Playback session start time in UTC.
  final DateTime startedAt;

  /// Total accumulated listening time in milliseconds.
  final int listenedMs;

  /// Whether this session qualified as a counted play.
  final bool counted;

  /// Whether the track played completely to its natural end.
  final bool completed;

  /// Creates an immutable [PlayEvent] instance.
  const PlayEvent({
    this.id,
    required this.uri,
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.durationMs,
    required this.startedAt,
    required this.listenedMs,
    required this.counted,
    required this.completed,
  });

  /// Creates a copy of this [PlayEvent] with the given fields replaced.
  PlayEvent copyWith({
    int? id,
    String? uri,
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    int? durationMs,
    DateTime? startedAt,
    int? listenedMs,
    bool? counted,
    bool? completed,
  }) {
    return PlayEvent(
      id: id ?? this.id,
      uri: uri ?? this.uri,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      durationMs: durationMs ?? this.durationMs,
      startedAt: startedAt ?? this.startedAt,
      listenedMs: listenedMs ?? this.listenedMs,
      counted: counted ?? this.counted,
      completed: completed ?? this.completed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayEvent &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          uri == other.uri &&
          title == other.title &&
          artist == other.artist &&
          album == other.album &&
          albumArtist == other.albumArtist &&
          durationMs == other.durationMs &&
          startedAt == other.startedAt &&
          listenedMs == other.listenedMs &&
          counted == other.counted &&
          completed == other.completed;

  @override
  int get hashCode => Object.hash(
        id,
        uri,
        title,
        artist,
        album,
        albumArtist,
        durationMs,
        startedAt,
        listenedMs,
        counted,
        completed,
      );

  @override
  String toString() =>
      'PlayEvent(id: $id, uri: $uri, title: $title, artist: $artist, '
      'startedAt: $startedAt, listenedMs: $listenedMs, counted: $counted, completed: $completed)';
}
