import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/result.dart';
import '../../diagnostics/app_logger.dart';
import '../../features/wrapped/recap.dart';
import '../../features/wrapped/recap_builder.dart';
import '../../library/album_identity.dart';
import '../../library/file_path_utils.dart';
import '../../library/history_models.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/text_normalizer.dart';
import '../library/library_data_cache.dart';
import '../now_playing/cover_palette.dart';
import '../settings/settings_store.dart';
import '../stats/stats_controller.dart';
import '../stats/stats_date_range.dart';

/// State coordinator for Monthly Wrapped and Weekly listening recaps.
///
/// Reuses [StatsController] clock/lifecycle when available alongside
/// [StatsDateRange] calendar helpers and [LibraryDataCache] SWR refreshes.
class WrappedController extends ChangeNotifier {
  /// Number of paged cards rendered when a recap is eligible.
  static const int pageCount = 8;

  /// Library repository supplying read-only history queries.
  final LibraryRepository repository;

  /// Settings store governing locale, numerals, and motion preferences.
  final SettingsStore settingsStore;

  /// Shared library data cache used for cover art resolution and SWR.
  final LibraryDataCache dataCache;

  /// Optional shared [StatsController] reused when opening from Stats.
  final StatsController? statsController;

  /// Clock returning current timestamp.
  final DateTime Function() clock;

  final RecapBuilder _builder;
  final AppLogger _logger;

  RecapPeriodKind _kind;
  int? _selectedYear;
  int? _selectedMonth;
  List<RecapMonthOption> _availableMonths = const [];
  Recap? _recap;
  CoverPalette _coverPalette = CoverPalette.fallback;
  int _currentPage = 0;
  bool _isLoading = false;
  bool _hasLoaded = false;
  AppError? _error;
  bool _disposed = false;
  int _loadGeneration = 0;
  int _lastCacheRevision = -1;
  String _lastLanguage = '';

  /// Creates a [WrappedController].
  WrappedController({
    required this.repository,
    required this.settingsStore,
    required this.dataCache,
    this.statsController,
    RecapPeriodKind initialKind = RecapPeriodKind.monthly,
    int? initialYear,
    int? initialMonth,
    DateTime Function()? clock,
    AppLogger? logger,
  }) : clock = clock ?? statsController?.clock ?? DateTime.now,
       _kind = initialKind,
       _selectedYear = initialYear,
       _selectedMonth = initialMonth,
       _logger = logger ?? AppLogger.instance,
       _builder = RecapBuilder(
         repository: repository,
         clock: clock ?? statsController?.clock ?? DateTime.now,
       ) {
    _lastCacheRevision = dataCache.revision;
    _lastLanguage = settingsStore.settings.language;
    dataCache.addListener(_onDataCacheChanged);
    settingsStore.addListener(_onSettingsChanged);
  }

  /// Active recap mode (`monthly` Wrapped or `weekly` activity recap).
  RecapPeriodKind get kind => _kind;

  /// Selected calendar year for monthly mode.
  int? get selectedYear => _selectedYear;

  /// Selected calendar month (`1..12`) for monthly mode.
  int? get selectedMonth => _selectedMonth;

  /// Calendar months containing counted listening history (newest first).
  List<RecapMonthOption> get availableMonths => _availableMonths;

  /// Most recently built [Recap], or `null` before first load.
  Recap? get recap => _recap;

  /// Muted palette sampled from the recap's top album or top track cover.
  CoverPalette get coverPalette => _coverPalette;

  /// Active page index (`0..pageCount - 1`).
  int get currentPage => _currentPage;

  /// True while fetching before any recap is ready.
  bool get isInitialLoading => !_hasLoaded && _isLoading && _recap == null;

  /// True while a load/refresh is active.
  bool get isLoading => _isLoading;

  /// True after at least one load cycle has completed cleanly.
  bool get hasLoaded => _hasLoaded;

  /// Most recent error during load, or `null`.
  AppError? get error => _error;

  void _onDataCacheChanged() {
    if (_disposed) return;
    final nextRev = dataCache.revision;
    if (nextRev != _lastCacheRevision) {
      _lastCacheRevision = nextRev;
      unawaited(refresh());
    }
  }

  void _onSettingsChanged() {
    if (_disposed) return;
    final nextLang = settingsStore.settings.language;
    if (nextLang != _lastLanguage) {
      _lastLanguage = nextLang;
      if (_kind == RecapPeriodKind.weekly) {
        unawaited(refresh());
      }
    }
  }

  /// Switches between monthly Wrapped and weekly listening recap.
  Future<void> setKind(RecapPeriodKind next) async {
    if (_disposed || (_kind == next && _recap != null && _error == null)) {
      return;
    }
    _kind = next;
    _currentPage = 0;
    notifyListeners();
    await refresh();
  }

  /// Selects a month from [availableMonths] and reloads its monthly Wrapped.
  Future<void> selectMonth(int year, int month) async {
    if (_disposed) return;
    if (_kind == RecapPeriodKind.monthly &&
        _selectedYear == year &&
        _selectedMonth == month &&
        _recap != null &&
        _error == null) {
      return;
    }
    _kind = RecapPeriodKind.monthly;
    _selectedYear = year;
    _selectedMonth = month;
    _currentPage = 0;
    notifyListeners();
    await refresh();
  }

  /// Updates the active page index cleanly within `[0, pageCount - 1]`.
  void setPage(int page) {
    final clamped = page.clamp(0, pageCount - 1);
    if (clamped == _currentPage) return;
    _currentPage = clamped;
    notifyListeners();
  }

  /// Moves to the next recap card if available. Returns true if changed.
  bool nextPage() {
    if (_currentPage >= pageCount - 1) return false;
    _currentPage += 1;
    notifyListeners();
    return true;
  }

  /// Moves to the previous recap card if available. Returns true if changed.
  bool previousPage() {
    if (_currentPage <= 0) return false;
    _currentPage -= 1;
    notifyListeners();
    return true;
  }

  /// Loads available months and rebuilds the active [Recap] and palette.
  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final months = await _builder.availableMonths();
      if (_disposed || generation != _loadGeneration) return;
      _availableMonths = months;

      final localNow = StatsDateRange.toLocal(clock());
      if (_selectedYear == null || _selectedMonth == null) {
        if (months.isNotEmpty) {
          final preferred = months.firstWhere(
            (m) => m.isEligible,
            orElse: () => months.first,
          );
          _selectedYear = preferred.year;
          _selectedMonth = preferred.month;
        } else {
          _selectedYear = localNow.year;
          _selectedMonth = localNow.month;
        }
      }

      final Recap built;
      if (_kind == RecapPeriodKind.weekly) {
        built = await _builder.buildWeek(
          languageCode: settingsStore.settings.language,
        );
      } else {
        built = await _builder.buildMonth(
          year: _selectedYear!,
          month: _selectedMonth!,
        );
      }

      if (_disposed || generation != _loadGeneration) return;
      _recap = built;
      _hasLoaded = true;
      _error = null;

      final coverKey = resolveRecapHeroCoverKey(built);
      if (coverKey != null && coverKey.isNotEmpty) {
        final palette = await paletteForCover(coverKey);
        if (!_disposed && generation == _loadGeneration) {
          _coverPalette = palette;
        }
      } else {
        _coverPalette = CoverPalette.fallback;
      }
    } catch (e, st) {
      if (_disposed || generation != _loadGeneration) return;
      _logger.error(
        'WrappedController',
        'Failed loading ${_kind.name} recap',
        e,
        st,
      );
      _error = AppError.fromException(e, st, 'wrapped.error.loadFailed');
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Resolves the best CoverCache key for the recap's top album or top track.
  String? resolveRecapHeroCoverKey(Recap recap) {
    final albumKey = resolveAlbumCoverKey(recap.topAlbum);
    if (albumKey != null && albumKey.isNotEmpty) return albumKey;
    for (final t in recap.topTracks) {
      final k = resolveTrackCoverKey(t);
      if (k != null && k.isNotEmpty) return k;
    }
    return resolveArtistCoverKey(recap.topArtist?.artist);
  }

  /// Resolves a [CoverCache] key for a ranked track via [dataCache].
  String? resolveTrackCoverKey(RankedTrackStat stat) {
    final targetKey = FilePathUtils.canonicalKey(stat.uri);
    for (final t in dataCache.tracks ?? const <Track>[]) {
      if (FilePathUtils.canonicalKey(t.path) == targetKey) {
        return t.coverKey;
      }
    }
    return null;
  }

  /// Resolves a [CoverCache] key for a ranked album via [dataCache].
  String? resolveAlbumCoverKey(RankedAlbumStat? stat) {
    if (stat == null) return null;
    final key = AlbumIdentity.key(album: stat.album, artist: stat.artist);
    final normTitle = TextNormalizer.normalize(stat.album);
    for (final album in dataCache.albums ?? const <AlbumSummary>[]) {
      if (AlbumIdentity.forSummary(album) == key &&
          album.coverKey != null &&
          album.coverKey!.isNotEmpty) {
        return album.coverKey;
      }
    }
    for (final album in dataCache.albums ?? const <AlbumSummary>[]) {
      if (TextNormalizer.normalize(album.album) == normTitle &&
          album.coverKey != null &&
          album.coverKey!.isNotEmpty) {
        return album.coverKey;
      }
    }
    return null;
  }

  /// Resolves a [CoverCache] key for a ranked artist via their cached albums.
  String? resolveArtistCoverKey(String? artistName) {
    if (artistName == null || artistName.trim().isEmpty) return null;
    final target = TextNormalizer.normalize(artistName);
    for (final album in dataCache.albums ?? const <AlbumSummary>[]) {
      final candidate = TextNormalizer.normalize(
        album.displayArtist ?? album.albumArtist ?? '',
      );
      if (candidate == target &&
          album.coverKey != null &&
          album.coverKey!.isNotEmpty) {
        return album.coverKey;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    dataCache.removeListener(_onDataCacheChanged);
    settingsStore.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
