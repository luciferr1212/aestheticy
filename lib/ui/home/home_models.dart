import '../../features/session/saved_session.dart';
import '../../library/models.dart';

/// Kinds of daily rotating highlight rows displayed on the Home screen.
enum HomeRotatingRowKind {
  /// Recently added albums (`addedAt` descending).
  recentlyAdded,

  /// Favorited tracks not played recently or never played.
  forgottenFavorites,

  /// Tracks played on the same month/day in previous years.
  onThisDay,

  /// Most played tracks in the current calendar month.
  mostPlayedThisMonth,
}

/// Data for the single rotating Home row.
class HomeRotatingRow {
  /// Selected row kind.
  final HomeRotatingRowKind kind;

  /// Album items when [kind] is [HomeRotatingRowKind.recentlyAdded].
  final List<AlbumSummary> albums;

  /// Track items for track-based rotating rows.
  final List<Track> tracks;

  /// Creates a [HomeRotatingRow].
  const HomeRotatingRow({
    required this.kind,
    this.albums = const [],
    this.tracks = const [],
  });

  /// Whether this row renders album cards rather than track cards.
  bool get isAlbumRow => kind == HomeRotatingRowKind.recentlyAdded;

  /// Whether this row has no items to show.
  bool get isEmpty => isAlbumRow ? albums.isEmpty : tracks.isEmpty;
}

/// Snapshot of the currently active track for the Home hero card.
class HomeNowPlayingSummary {
  /// Active track URI, if any.
  final String? uri;

  /// Display title.
  final String title;

  /// Raw artist string (resolved through display translation in UI).
  final String? artist;

  /// Album title.
  final String? album;

  /// Cover cache key.
  final String? coverKey;

  /// Whether audio is currently playing.
  final bool isPlaying;

  /// Whether a track is loaded in the player.
  bool get hasTrack => uri != null && uri!.isNotEmpty;

  /// Empty idle summary.
  static const HomeNowPlayingSummary empty = HomeNowPlayingSummary(
    title: '',
    isPlaying: false,
  );

  /// Creates a [HomeNowPlayingSummary].
  const HomeNowPlayingSummary({
    this.uri,
    required this.title,
    this.artist,
    this.album,
    this.coverKey,
    required this.isPlaying,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeNowPlayingSummary &&
          runtimeType == other.runtimeType &&
          uri == other.uri &&
          title == other.title &&
          artist == other.artist &&
          album == other.album &&
          coverKey == other.coverKey &&
          isPlaying == other.isPlaying;

  @override
  int get hashCode =>
      Object.hash(uri, title, artist, album, coverKey, isPlaying);
}

/// Summary built from [SessionStore] when nothing is currently playing.
class HomeResumeSessionSummary {
  /// Title of the track where the saved session left off.
  final String title;

  /// Raw artist of that track, if known.
  final String? artist;

  /// Cover key of that track, if known.
  final String? coverKey;

  /// Total queued items in the saved session.
  final int trackCount;

  /// Underlying saved session snapshot.
  final SavedSession session;

  /// Creates a [HomeResumeSessionSummary].
  const HomeResumeSessionSummary({
    required this.title,
    this.artist,
    this.coverKey,
    required this.trackCount,
    required this.session,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeResumeSessionSummary &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          artist == other.artist &&
          coverKey == other.coverKey &&
          trackCount == other.trackCount &&
          session == other.session;

  @override
  int get hashCode =>
      Object.hash(title, artist, coverKey, trackCount, session);
}
