import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../library/album_identity.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/text_normalizer.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_scope.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'album_year_grouping.dart';
import 'albums_artist_chips.dart';
import 'library_data_cache.dart';
import 'library_header.dart';
import 'library_placeholders.dart';
import 'library_view_controls.dart';
import 'sort_direction_button.dart';
import 'widgets/album_tiles.dart';

export 'album_year_grouping.dart';

/// Albums library screen supporting square, wide, and list layout modes.
class AlbumsView extends StatefulWidget {
  /// The library data repository.
  final LibraryRepository repository;

  /// The settings store for persisting view and sort options.
  final SettingsStore settingsStore;

  /// The application navigation coordinator.
  final AppNavigator navigator;

  /// Optional in-memory library data cache.
  final LibraryDataCache? dataCache;

  /// Creates an [AlbumsView].
  const AlbumsView({
    super.key,
    required this.repository,
    required this.settingsStore,
    required this.navigator,
    this.dataCache,
  });

  @override
  State<AlbumsView> createState() => _AlbumsViewState();
}

class _AlbumsViewState extends State<AlbumsView> {
  List<AlbumSummary> _albums = [];
  List<AlbumSummary> _artistAlbums = [];
  List<AlbumSummary> _searchResults = [];
  List<ArtistSummary> _rawArtists = [];
  Set<String> _selectedArtistKeys = const {};
  int _artistFilterRequestId = 0;
  int _searchRequestId = 0;
  String _searchQuery = '';
  bool _isLoading = true;
  LibraryDataCache? _activeCache;

  @override
  void initState() {
    super.initState();
    if (widget.dataCache?.albums != null) {
      _albums = widget.dataCache!.albums!;
      _rawArtists = widget.dataCache!.artists ?? [];
      _isLoading = false;
    }
    _loadAlbums();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cache = widget.dataCache ?? LibraryDataCacheScope.maybeOf(context);
    if (cache != _activeCache) {
      _activeCache?.removeListener(_onCacheChanged);
      _activeCache = cache;
      _activeCache?.addListener(_onCacheChanged);
      if (_isLoading && cache != null && cache.albums != null) {
        _albums = cache.albums!;
        _rawArtists = cache.artists ?? [];
        _isLoading = false;
      }
    }
  }

  @override
  void dispose() {
    _activeCache?.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() {
    if (!mounted) return;
    final cache = _activeCache;
    if (cache == null) return;
    if (_selectedArtistKeys.isEmpty && cache.albums != null) {
      if (!listEquals(_albums, cache.albums) ||
          !listEquals(_rawArtists, cache.artists) ||
          _isLoading) {
        setState(() {
          _albums = cache.albums!;
          _rawArtists = cache.artists ?? _rawArtists;
          _isLoading = false;
        });
      }
      if (_searchQuery.isNotEmpty) {
        _refreshSearch();
      }
    } else {
      _loadAlbums();
    }
  }

  Future<void> _refreshSearch() async {
    final query = _searchQuery;
    if (query.isEmpty) return;
    final reqId = ++_searchRequestId;
    await _executeAlbumSearch(query, reqId);
  }

  Future<void> _executeAlbumSearch(String query, int reqId) async {
    final nameStore = ArtistNameScope.maybeOf(context);
    final settings =
        SettingsScope.maybeOf(context)?.settings ?? widget.settingsStore.settings;
    final expandedQueries =
        (nameStore != null && settings.artistNameMode != 'asTagged')
            ? nameStore.expandedSearchQueries(query)
            : const <String>[];

    final futures = <Future<List<AlbumSummary>>>[
      widget.repository.searchAlbums(query),
      for (final extra in expandedQueries) widget.repository.searchAlbums(extra),
    ];

    final resultLists = await Future.wait(futures);
    if (!mounted || _searchRequestId != reqId || _searchQuery != query) {
      return;
    }

    final merged = <AlbumSummary>[];
    final seen = <String>{};
    for (final list in resultLists) {
      for (final album in list) {
        if (seen.add(AlbumIdentity.forSummary(album))) {
          merged.add(album);
        }
      }
    }

    if (nameStore != null && settings.artistNameMode != 'asTagged') {
      final normQuery = TextNormalizer.normalize(query);
      final terms = normQuery.split(' ').where((t) => t.isNotEmpty).toList();
      if (terms.isNotEmpty) {
        for (final album in _albums) {
          final key = AlbumIdentity.forSummary(album);
          if (seen.contains(key)) continue;
          final rawArtist = album.displayArtist ?? album.albumArtist ?? '';
          if (rawArtist.isEmpty) continue;
          final displayed =
              nameStore.displayArtist(rawArtist, settings: settings);
          final entry = nameStore.getEntry(rawArtist);
          if (displayed == rawArtist && entry == null) continue;
          final normCombined = TextNormalizer.normalize(
            '${album.album} $rawArtist $displayed ${entry?.ar ?? ''} ${entry?.en ?? ''}',
          );
          if (terms.every((t) => normCombined.contains(t))) {
            seen.add(key);
            merged.add(album);
          }
        }
      }
    }

    if (!listEquals(_searchResults, merged)) {
      setState(() {
        _searchResults = merged;
      });
    }
  }

  Future<void> _loadAlbums() async {
    final selectedSnapshot = Set<String>.from(_selectedArtistKeys);
    final reqId = ++_artistFilterRequestId;
    final albums = await widget.repository.listAlbums();
    final artists = await widget.repository.listArtists();
    List<AlbumSummary> artistAlbums = [];
    if (selectedSnapshot.isNotEmpty) {
      artistAlbums = await widget.repository.listAlbumsByArtistKeys(
        selectedSnapshot.toList(),
      );
    }
    if (mounted) {
      final selectionMatches =
          _artistFilterRequestId == reqId &&
          setEquals(_selectedArtistKeys, selectedSnapshot);
      final changed = !listEquals(_albums, albums) ||
          !listEquals(_rawArtists, artists) ||
          (selectionMatches && !listEquals(_artistAlbums, artistAlbums)) ||
          _isLoading;
      if (changed) {
        setState(() {
          _albums = albums;
          _rawArtists = artists;
          if (selectionMatches) {
            _artistAlbums = artistAlbums;
          }
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onArtistSelectionChanged(Set<String> keys) async {
    final nextKeys = Set<String>.unmodifiable(keys);
    if (setEquals(_selectedArtistKeys, nextKeys)) return;
    final reqId = ++_artistFilterRequestId;
    setState(() {
      _selectedArtistKeys = nextKeys;
    });
    if (nextKeys.isEmpty) {
      setState(() {
        _artistAlbums = [];
      });
    } else {
      final albums = await widget.repository.listAlbumsByArtistKeys(
        nextKeys.toList(),
      );
      if (mounted &&
          _artistFilterRequestId == reqId &&
          setEquals(_selectedArtistKeys, nextKeys)) {
        setState(() {
          _artistAlbums = albums;
        });
      }
    }
  }

  Future<void> _onSearchChanged(String query) async {
    final trimmed = query.trim();
    final reqId = ++_searchRequestId;
    setState(() {
      _searchQuery = trimmed;
      if (trimmed.isEmpty) {
        _searchResults = [];
      }
    });

    if (trimmed.isEmpty) {
      return;
    }

    await _executeAlbumSearch(trimmed, reqId);
  }

  List<ArtistChipItem> _getArtistChips(BuildContext context) {
    final Map<String, ({String name, int songCount})> map = {};
    for (final a in _rawArtists) {
      if (a.albumCount <= 0) continue;
      final displayName = context.displayArtist(a.name);
      final key = a.key;
      final existing = map[key];
      if (existing == null) {
        map[key] = (name: displayName, songCount: a.trackCount);
      } else {
        map[key] =
            (name: displayName, songCount: existing.songCount + a.trackCount);
      }
    }

    final items = map.entries
        .map((e) => ArtistChipItem(
              key: e.key,
              name: e.value.name,
              songCount: e.value.songCount,
            ))
        .toList();

    // Default order: songCount descending, then stable locale-aware name
    items.sort((a, b) {
      final cmp = b.songCount.compareTo(a.songCount);
      if (cmp != 0) return cmp;
      return compareLocaleAware(a.name, b.name);
    });

    final customOrder = widget.settingsStore.settings.albumsArtistChipsOrder;
    if (customOrder.isEmpty) {
      return items;
    }

    final Map<String, ArtistChipItem> byKey = {
      for (final it in items) it.key: it,
    };
    final ordered = <ArtistChipItem>[];
    for (final k in customOrder) {
      final it = byKey.remove(k);
      if (it != null) {
        ordered.add(it);
      }
    }
    ordered.addAll(byKey.values);
    return ordered;
  }

  List<ArtistChipItem> _getAllArtists(BuildContext context) {
    final Map<String, ({String name, int songCount})> map = {};
    for (final a in _rawArtists) {
      final displayName = context.displayArtist(a.name);
      final key = a.key;
      final existing = map[key];
      if (existing == null) {
        map[key] = (name: displayName, songCount: a.trackCount);
      } else {
        map[key] =
            (name: displayName, songCount: existing.songCount + a.trackCount);
      }
    }

    final items = map.entries
        .map((e) => ArtistChipItem(
              key: e.key,
              name: e.value.name,
              songCount: e.value.songCount,
            ))
        .toList();

    items.sort((a, b) {
      final cmp = b.songCount.compareTo(a.songCount);
      if (cmp != 0) return cmp;
      return compareLocaleAware(a.name, b.name);
    });

    return items;
  }

  List<AlbumSummary> _getSortedAlbums(BuildContext context) {
    List<AlbumSummary> base;
    if (_selectedArtistKeys.isNotEmpty) {
      base = _artistAlbums;
      if (_searchQuery.isNotEmpty) {
        final normQuery = TextNormalizer.normalize(_searchQuery);
        final terms =
            normQuery.split(' ').where((t) => t.isNotEmpty).toList();
        base = base.where((a) {
          final displayedArtist =
              context.displayArtist(a.displayArtist ?? a.albumArtist);
          final rawArtist = a.displayArtist ?? a.albumArtist ?? '';
          final nameStore = ArtistNameScope.maybeOf(context);
          final entry =
              rawArtist.isNotEmpty ? nameStore?.getEntry(rawArtist) : null;
          final normCombined = TextNormalizer.normalize(
            '${a.album} $displayedArtist $rawArtist ${a.albumArtist ?? ''} ${entry?.ar ?? ''} ${entry?.en ?? ''}',
          );
          return terms.every((t) => normCombined.contains(t));
        }).toList();
      }
    } else {
      base = _searchQuery.isNotEmpty ? _searchResults : _albums;
    }

    final list = List<AlbumSummary>.from(base);

    final sortKey = widget.settingsStore.settings.albumSort;
    final isReversed = widget.settingsStore.settings.albumsSortReversed;

    switch (sortKey) {
      case 'title':
        list.sort((a, b) => compareLocaleAware(a.album, b.album));
      case 'artist':
        list.sort((a, b) {
          final artistA =
              context.displayArtist(a.displayArtist ?? a.albumArtist);
          final artistB =
              context.displayArtist(b.displayArtist ?? b.albumArtist);
          final cmp = compareLocaleAware(artistA, artistB);
          if (cmp != 0) return cmp;
          return compareLocaleAware(a.album, b.album);
        });
      case 'year':
        list.sort((a, b) => isReversed
            ? (b.year ?? 0).compareTo(a.year ?? 0)
            : (a.year ?? 0).compareTo(b.year ?? 0));
      case 'recentlyAdded':
      default:
        list.sort((a, b) {
          final aMs = a.addedAt?.millisecondsSinceEpoch ?? 0;
          final bMs = b.addedAt?.millisecondsSinceEpoch ?? 0;
          final cmp = isReversed ? bMs.compareTo(aMs) : aMs.compareTo(bMs);
          if (cmp != 0) return cmp;
          return compareLocaleAware(a.album, b.album);
        });
    }

    if (isReversed && sortKey != 'year' && sortKey != 'recentlyAdded') {
      return list.reversed.toList();
    }

    return list;
  }

  void _onSortChanged(String newSort) {
    widget.settingsStore.update((s) => s.copyWith(
          albumSort: newSort,
          albumsSortReversed: SortDirection.defaultReversedFor(newSort),
        ));
    setState(() {});
  }

  void _onSortDirectionChanged(SortDirection dir) {
    widget.settingsStore.update((s) => s.copyWith(
          albumsSortReversed: dir.isDescending,
        ));
    setState(() {});
  }

  void _onViewModeChanged(String newMode) {
    widget.settingsStore.update((s) => s.copyWith(libraryViewMode: newMode));
    setState(() {});
  }

  void _onChipsOrderChanged(List<String> newOrder) {
    widget.settingsStore
        .update((s) => s.copyWith(albumsArtistChipsOrder: newOrder));
    setState(() {});
  }

  void _onChipsResetOrder() {
    widget.settingsStore
        .update((s) => s.copyWith(albumsArtistChipsOrder: const []));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return AlbumsViewPlaceholder(settingsStore: widget.settingsStore);
    }

    final sortedAlbums = _getSortedAlbums(context);
    final viewMode = widget.settingsStore.settings.libraryViewMode;
    final currentSort = widget.settingsStore.settings.albumSort;
    final isReversed = widget.settingsStore.settings.albumsSortReversed;
    final reduceMotion = widget.settingsStore.settings.reduceMotion;
    final artistChips = _getArtistChips(context);
    final allArtists = _getAllArtists(context);

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Page Header
          LibraryHeader(
            title: context.t('nav.albums'),
            settingsStore: widget.settingsStore,
            itemCount: sortedAlbums.length,
            itemCountLabel: context.t('albums.count'),
            searchQuery: _searchQuery,
            onSearchChanged: _onSearchChanged,
            showControls: false,
          ),
          const SizedBox(height: 10),

          // 2. LibraryViewControls (shape + sort dropdown + SortDirectionButton)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: LibraryViewControls(
              allowedShapes: const ['square', 'wide', 'list'],
              currentShape: viewMode,
              onShapeChanged: _onViewModeChanged,
              sortOptions: const ['recentlyAdded', 'title', 'artist', 'year'],
              currentSort: currentSort,
              onSortChanged: _onSortChanged,
              sortDirection: SortDirection.fromReversed(isReversed),
              onSortDirectionChanged: _onSortDirectionChanged,
              sortDirectionButtonKey: const Key('albums_sort_direction'),
              reduceMotion: reduceMotion,
            ),
          ),
          const SizedBox(height: 6),

          // 3. Horizontal artist chips row
          if (artistChips.isNotEmpty)
            AlbumsArtistChips(
              artists: artistChips,
              allArtists: allArtists,
              selectedArtistKeys: _selectedArtistKeys,
              onSelectionChanged: _onArtistSelectionChanged,
              onOrderChanged: _onChipsOrderChanged,
              onResetOrder: _onChipsResetOrder,
              reduceMotion: reduceMotion,
            ),
          const SizedBox(height: 12),

          // 4. Content (with cross-fade between shapes)
          Expanded(
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeOut,
              child: KeyedSubtree(
                key: ValueKey('albums_content_$viewMode'),
                child: _buildAlbumContent(sortedAlbums, viewMode, currentSort),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _wideGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 380,
    mainAxisExtent: 100,
    crossAxisSpacing: 16,
    mainAxisSpacing: 16,
  );

  static const _squareGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 180,
    mainAxisExtent: 220,
    crossAxisSpacing: 16,
    mainAxisSpacing: 20,
  );

  Widget _buildTileForMode(AlbumSummary album, String viewMode) {
    void openDetail() => widget.navigator.openAlbumDetail(album.album, album: album);
    switch (viewMode) {
      case 'wide':
        return WideAlbumTile(album: album, onTap: openDetail);
      case 'list':
        return ListAlbumTile(album: album, onTap: openDetail);
      case 'square':
      default:
        return SquareAlbumTile(album: album, onTap: openDetail);
    }
  }

  Widget _buildAlbumContent(
    List<AlbumSummary> albums,
    String viewMode,
    String currentSort,
  ) {
    if (albums.isEmpty) {
      if (_selectedArtistKeys.isNotEmpty) {
        final emptyMessage = _selectedArtistKeys.length == 1
            ? context.t('albums.noAlbumsForArtist')
            : context.t('albums.noAlbumsForArtists');
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                emptyMessage,
                style: AppTypography.body.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              GlassPillButton(
                key: const Key('albums_empty_show_all_button'),
                label: context.t('albums.showAll'),
                size: GlassButtonSize.small,
                onPressed: () => _onArtistSelectionChanged(const {}),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Text(
          _searchQuery.isNotEmpty
              ? context.t('albums.noMatches', args: {'query': _searchQuery})
              : context.t('albums.empty'),
          style: AppTypography.body.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    if (currentSort == 'year') {
      final groups = groupAlbumsByYear(
        albums,
        reversed: widget.settingsStore.settings.albumsSortReversed,
        artistResolver: (a) =>
            context.displayArtist(a.displayArtist ?? a.albumArtist),
      );
      return CustomScrollView(
        key: const Key('albums_year_grouped_scroll'),
        slivers: [
          for (var i = 0; i < groups.length; i++) ...[
            SliverPadding(
              padding: EdgeInsetsDirectional.only(
                top: i == 0 ? 0 : 24,
                bottom: 12,
              ),
              sliver: SliverToBoxAdapter(
                child: AlbumYearSectionHeader(group: groups[i]),
              ),
            ),
            if (viewMode == 'list')
              SliverFixedExtentList(
                itemExtent: 56.0,
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildTileForMode(groups[i].albums[index], viewMode),
                  childCount: groups[i].albums.length,
                ),
              )
            else
              SliverGrid(
                gridDelegate:
                    viewMode == 'wide' ? _wideGridDelegate : _squareGridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildTileForMode(groups[i].albums[index], viewMode),
                  childCount: groups[i].albums.length,
                ),
              ),
          ],
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
      );
    }

    switch (viewMode) {
      case 'wide':
        return GridView.builder(
          key: const Key('albums_wide_grid'),
          padding: const EdgeInsets.only(bottom: 120),
          gridDelegate: _wideGridDelegate,
          itemCount: albums.length,
          itemBuilder: (context, index) =>
              _buildTileForMode(albums[index], viewMode),
        );
      case 'list':
        return ListView.builder(
          key: const Key('albums_list_view'),
          padding: const EdgeInsets.only(bottom: 120),
          itemCount: albums.length,
          itemExtent: 56.0,
          itemBuilder: (context, index) =>
              _buildTileForMode(albums[index], viewMode),
        );
      case 'square':
      default:
        return GridView.builder(
          key: const Key('albums_square_grid'),
          padding: const EdgeInsets.only(bottom: 120),
          gridDelegate: _squareGridDelegate,
          itemCount: albums.length,
          itemBuilder: (context, index) =>
              _buildTileForMode(albums[index], viewMode),
        );
    }
  }
}
