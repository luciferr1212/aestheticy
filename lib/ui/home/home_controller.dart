import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../diagnostics/app_logger.dart';
import '../../features/session/saved_session.dart';
import '../../features/session/session_store.dart';
import '../../library/file_path_utils.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../library/library_data_cache.dart';
import 'home_models.dart';

/// Coordinates Home screen data: Now Playing / resume summary, continue
/// listening albums, and one daily rotating highlight row.
class HomeController extends ChangeNotifier {
  /// Library storage repository (used for read-only Home queries).
  final LibraryRepository repository;

  /// Active playback controller.
  final PlaybackController playbackController;

  /// Shared library cache used for stale-while-revalidate triggers.
  final LibraryDataCache dataCache;

  /// Optional session store for building the "Resume last session" card.
  final SessionStore? sessionStore;

  /// Injectable clock returning the current timestamp.
  final DateTime Function() clock;

  /// Minimum inactivity window for [HomeRotatingRowKind.forgottenFavorites].
  final Duration forgottenOlderThan;

  /// Maximum items requested per Home row.
  final int rowLimit;

  final List<StreamSubscription<dynamic>> _subs = [];
  int _lastCacheRevision = -1;
  bool _disposed = false;
  bool _isRefreshing = false;
  bool _pendingRefresh = false;
  bool _hasLoaded = false;

  HomeNowPlayingSummary _nowPlaying = HomeNowPlayingSummary.empty;
  HomeResumeSessionSummary? _resumeSession;
  List<AlbumSummary> _continueListening = const [];
  HomeRotatingRow? _rotatingRow;

  /// Creates a [HomeController].
  HomeController({
    required this.repository,
    required this.playbackController,
    required this.dataCache,
    this.sessionStore,
    DateTime Function()? clock,
    this.forgottenOlderThan = const Duration(days: 30),
    this.rowLimit = 8,
  }) : clock = clock ?? DateTime.now {
    _lastCacheRevision = dataCache.revision;
    _nowPlaying = _buildNowPlayingSummary();
    _resumeSession = _buildResumeSessionSummary();

    dataCache.addListener(_onDataCacheChanged);
    _subs.add(
      playbackController.currentStream.listen((_) => _syncPlaybackAndSession()),
    );
    _subs.add(
      playbackController.stateStream.listen((_) => _syncPlaybackAndSession()),
    );
    _subs.add(
      playbackController.queueChangeStream.listen(
        (_) => _syncPlaybackAndSession(),
      ),
    );
  }

  /// Current active track summary for the hero card.
  HomeNowPlayingSummary get nowPlaying => _nowPlaying;

  /// Saved session summary when nothing is currently loaded in the player.
  HomeResumeSessionSummary? get resumeSession => _resumeSession;

  /// Up to [rowLimit] recently played albums.
  List<AlbumSummary> get continueListening => _continueListening;

  /// Single daily rotating row chosen deterministically by local date, or `null`
  /// when all candidate rows are empty.
  HomeRotatingRow? get rotatingRow => _rotatingRow;

  /// Whether at least one [refresh] cycle has completed.
  bool get hasLoaded => _hasLoaded;

  /// Whether a background refresh is currently running.
  bool get isRefreshing => _isRefreshing;

  /// Whether both Continue Listening and the rotating row are empty.
  bool get isHistoryEmpty =>
      _continueListening.isEmpty && (_rotatingRow == null || _rotatingRow!.isEmpty);

  /// Computes local calendar days since the Unix epoch (1970-01-01).
  static int localDaysSinceEpoch(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final dayUtc = DateTime.utc(local.year, local.month, local.day);
    return dayUtc.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  }

  /// Picks one non-empty candidate row deterministically for [localDate].
  static HomeRotatingRow? pickRotatingRow({
    required DateTime localDate,
    required List<AlbumSummary> recentlyAdded,
    required List<Track> forgottenFavorites,
    required List<Track> onThisDay,
    required List<Track> mostPlayedThisMonth,
  }) {
    final candidates = <HomeRotatingRow>[
      if (recentlyAdded.isNotEmpty)
        HomeRotatingRow(
          kind: HomeRotatingRowKind.recentlyAdded,
          albums: List.unmodifiable(recentlyAdded),
        ),
      if (forgottenFavorites.isNotEmpty)
        HomeRotatingRow(
          kind: HomeRotatingRowKind.forgottenFavorites,
          tracks: List.unmodifiable(forgottenFavorites),
        ),
      if (onThisDay.isNotEmpty)
        HomeRotatingRow(
          kind: HomeRotatingRowKind.onThisDay,
          tracks: List.unmodifiable(onThisDay),
        ),
      if (mostPlayedThisMonth.isNotEmpty)
        HomeRotatingRow(
          kind: HomeRotatingRowKind.mostPlayedThisMonth,
          tracks: List.unmodifiable(mostPlayedThisMonth),
        ),
    ];
    if (candidates.isEmpty) return null;
    final days = localDaysSinceEpoch(localDate);
    final idx = ((days % candidates.length) + candidates.length) %
        candidates.length;
    return candidates[idx];
  }

  void _onDataCacheChanged() {
    if (_disposed) return;
    final nextRevision = dataCache.revision;
    if (nextRevision != _lastCacheRevision) {
      _lastCacheRevision = nextRevision;
      _syncPlaybackAndSession(notify: false);
      unawaited(refresh());
    }
  }

  void _syncPlaybackAndSession({bool notify = true}) {
    if (_disposed) return;
    final nextNowPlaying = _buildNowPlayingSummary();
    final nextResume = _buildResumeSessionSummary();
    if (nextNowPlaying != _nowPlaying || nextResume != _resumeSession) {
      _nowPlaying = nextNowPlaying;
      _resumeSession = nextResume;
      if (notify) {
        notifyListeners();
      }
    }
  }

  Track? _findCachedTrack(String uri) {
    final tracks = dataCache.tracks;
    if (tracks == null || tracks.isEmpty || uri.isEmpty) return null;
    final key = FilePathUtils.canonicalKey(uri);
    for (final t in tracks) {
      if (t.path == uri || FilePathUtils.canonicalKey(t.path) == key) {
        return t;
      }
    }
    return null;
  }

  HomeNowPlayingSummary _buildNowPlayingSummary() {
    final current = playbackController.queue.current;
    if (current == null) return HomeNowPlayingSummary.empty;
    final extras = current.extras ?? const <String, String>{};
    final cached = _findCachedTrack(current.uri);

    final rawTitle = extras['title']?.trim();
    final title = (rawTitle != null && rawTitle.isNotEmpty)
        ? rawTitle
        : (cached?.title?.trim().isNotEmpty == true
            ? cached!.title!.trim()
            : p.basenameWithoutExtension(current.uri));
    final artist = (extras['artist']?.trim().isNotEmpty == true)
        ? extras['artist']!.trim()
        : cached?.artist;
    final album = (extras['album']?.trim().isNotEmpty == true)
        ? extras['album']!.trim()
        : cached?.album;
    final coverKey = (extras['coverKey']?.trim().isNotEmpty == true)
        ? extras['coverKey']!.trim()
        : cached?.coverKey;

    return HomeNowPlayingSummary(
      uri: current.uri,
      title: title,
      artist: artist,
      album: album,
      coverKey: coverKey,
      isPlaying: playbackController.currentState == PlaybackState.playing,
    );
  }

  HomeResumeSessionSummary? _buildResumeSessionSummary() {
    final session = sessionStore?.session;
    if (session == null || session.isEmpty) return null;

    SavedSessionItem? target;
    if (session.currentEntryId != null) {
      for (final item in session.queue) {
        if (item.entryId == session.currentEntryId) {
          target = item;
          break;
        }
      }
    }
    if (target == null &&
        session.currentIndex >= 0 &&
        session.currentIndex < session.queue.length) {
      target = session.queue[session.currentIndex];
    }
    target ??= session.queue.first;

    final extras = target.extras ?? const <String, String>{};
    final cached = _findCachedTrack(target.uri);
    final rawTitle = extras['title']?.trim();
    final title = (rawTitle != null && rawTitle.isNotEmpty)
        ? rawTitle
        : (cached?.title?.trim().isNotEmpty == true
            ? cached!.title!.trim()
            : p.basenameWithoutExtension(target.uri));
    final artist = (extras['artist']?.trim().isNotEmpty == true)
        ? extras['artist']!.trim()
        : cached?.artist;
    final coverKey = (extras['coverKey']?.trim().isNotEmpty == true)
        ? extras['coverKey']!.trim()
        : cached?.coverKey;

    return HomeResumeSessionSummary(
      title: title,
      artist: artist,
      coverKey: coverKey,
      trackCount: session.queue.length,
      session: session,
    );
  }

  Future<T> _safeQuery<T>(
    String label,
    Future<T> Function() run,
    T fallback,
  ) async {
    try {
      return await run();
    } catch (e, st) {
      AppLogger.instance.warn(
        'HomeController',
        'Home query "$label" failed; hiding section',
        e,
        st,
      );
      return fallback;
    }
  }

  /// Refreshes Home data stale-while-revalidate without clearing existing items.
  Future<void> refresh() async {
    if (_disposed) return;
    if (_isRefreshing) {
      _pendingRefresh = true;
      return;
    }
    _isRefreshing = true;

    try {
      final nowRaw = clock();
      final localNow = nowRaw.isUtc ? nowRaw.toLocal() : nowRaw;

      final results = await Future.wait([
        _safeQuery(
          'recentAlbumsPlayed',
          () => repository.recentAlbumsPlayed(limit: rowLimit),
          const <AlbumSummary>[],
        ),
        _safeQuery(
          'recentlyAddedAlbums',
          () => repository.recentlyAddedAlbums(limit: rowLimit),
          const <AlbumSummary>[],
        ),
        _safeQuery(
          'forgottenFavorites',
          () => repository.forgottenFavorites(
            olderThan: forgottenOlderThan,
            limit: rowLimit,
            now: nowRaw,
          ),
          const <Track>[],
        ),
        _safeQuery(
          'onThisDay',
          () => repository.onThisDay(localNow, limit: rowLimit),
          const <Track>[],
        ),
        _safeQuery(
          'mostPlayedThisMonth',
          () => repository.mostPlayedThisMonth(
            limit: rowLimit,
            now: localNow,
          ),
          const <Track>[],
        ),
      ]);

      if (_disposed) return;

      final nextContinue =
          List<AlbumSummary>.unmodifiable(results[0] as List<AlbumSummary>);
      final nextRotating = pickRotatingRow(
        localDate: localNow,
        recentlyAdded: results[1] as List<AlbumSummary>,
        forgottenFavorites: results[2] as List<Track>,
        onThisDay: results[3] as List<Track>,
        mostPlayedThisMonth: results[4] as List<Track>,
      );

      _continueListening = nextContinue;
      _rotatingRow = nextRotating;
      _hasLoaded = true;
      _nowPlaying = _buildNowPlayingSummary();
      _resumeSession = _buildResumeSessionSummary();
      notifyListeners();
    } finally {
      _isRefreshing = false;
      if (_pendingRefresh && !_disposed) {
        _pendingRefresh = false;
        await refresh();
      } else {
        _pendingRefresh = false;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    dataCache.removeListener(_onDataCacheChanged);
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    super.dispose();
  }
}
