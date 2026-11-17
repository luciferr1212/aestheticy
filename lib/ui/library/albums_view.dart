import 'dart:io';

import 'package:flutter/material.dart';

import '../../library/cover_cache.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'albums_artist_chips.dart';
import 'library_header.dart';
import 'library_view_controls.dart';
import 'sort_direction_button.dart';

/// A section of albums sharing the same release [year] (or `null` for unknown).
class AlbumYearGroup {
  /// Release year for this group, or `null` when the release year is unknown.
  final int? year;

  /// Albums belonging to this year, sorted alphabetically by artist then title.
  final List<AlbumSummary> albums;

  /// Creates an [AlbumYearGroup].
  const AlbumYearGroup({
    required this.year,
    required this.albums,
  });
}

/// Groups [albums] by release year (newest first by default, oldest first when [reversed] is true, unknown years last).
///
/// Within each year group, albums are sorted alphabetically by artist then
/// title. Null or non-positive (`<= 0`) years are placed together in a single
/// trailing group with `year == null`.
List<AlbumYearGroup> groupAlbumsByYear(
  List<AlbumSummary> albums, {
  bool reversed = false,
}) {
  final byYear = <int, List<AlbumSummary>>{};
  final unknown = <AlbumSummary>[];

  for (final album in albums) {
    final year = album.year;
    if (year != null && year > 0) {
      byYear.putIfAbsent(year, () => <AlbumSummary>[]).add(album);
    } else {
      unknown.add(album);
    }
  }

  int compareWithinGroup(AlbumSummary a, AlbumSummary b) {
    final artistA = (a.displayArtist ?? a.albumArtist ?? '').toLowerCase();
    final artistB = (b.displayArtist ?? b.albumArtist ?? '').toLowerCase();
    final artistCmp = artistA.compareTo(artistB);
    if (artistCmp != 0) return artistCmp;
    return a.album.toLowerCase().compareTo(b.album.toLowerCase());
  }

  final years = byYear.keys.toList()
    ..sort((a, b) => reversed ? a.compareTo(b) : b.compareTo(a));
  final groups = <AlbumYearGroup>[];
  for (final year in years) {
    final items = byYear[year]!..sort(compareWithinGroup);
    groups.add(AlbumYearGroup(year: year, albums: items));
  }

  if (unknown.isNotEmpty) {
    unknown.sort(compareWithinGroup);
    groups.add(AlbumYearGroup(year: null, albums: unknown));
  }

  return groups;
}

/// Albums library screen supporting square, wide, and list layout modes.
class AlbumsView extends StatefulWidget {
  /// The library data repository.
  final LibraryRepository repository;

  /// The settings store for persisting view and sort options.
  final SettingsStore settingsStore;

  /// The application navigation coordinator.
  final AppNavigator navigator;

  /// Creates an [AlbumsView].
  const AlbumsView({
    super.key,
    required this.repository,
    required this.settingsStore,
    required this.navigator,
  });

  @override
  State<AlbumsView> createState() => _AlbumsViewState();
}

class _AlbumsViewState extends State<AlbumsView> {
  List<AlbumSummary> _albums = [];
  List<AlbumSummary> _artistAlbums = [];
  List<AlbumSummary> _searchResults = [];
  List<ArtistSummary> _rawArtists = [];
  String? _selectedArtistKey;
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    final albums = await widget.repository.listAlbums();
    final artists = await widget.repository.listArtists();
    List<AlbumSummary> artistAlbums = [];
    if (_selectedArtistKey != null) {
      artistAlbums =
          await widget.repository.listAlbumsByArtistKey(_selectedArtistKey!);
    }
    if (mounted) {
      setState(() {
        _albums = albums;
        _rawArtists = artists;
        _artistAlbums = artistAlbums;
        _isLoading = false;
      });
    }
  }

  Future<void> _onArtistSelected(String? key) async {
    if (_selectedArtistKey == key) return;
    setState(() {
      _selectedArtistKey = key;
    });
    if (key == null) {
      setState(() {
        _artistAlbums = [];
      });
    } else {
      final albums = await widget.repository.listAlbumsByArtistKey(key);
      if (mounted && _selectedArtistKey == key) {
        setState(() {
          _artistAlbums = albums;
        });
      }
    }
  }

  Future<void> _onSearchChanged(String query) async {
    setState(() {
      _searchQuery = query.trim();
    });

    if (_searchQuery.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    final results = await widget.repository.searchAlbums(_searchQuery);
    if (mounted) {
      setState(() {
        _searchResults = results;
      });
    }
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

  List<AlbumSummary> _getSortedAlbums() {
    List<AlbumSummary> base;
    if (_selectedArtistKey != null) {
      base = _artistAlbums;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        base = base.where((a) {
          final titleMatch = a.album.toLowerCase().contains(q);
          final artistMatch = (a.displayArtist ?? a.albumArtist ?? '')
              .toLowerCase()
              .contains(q);
          return titleMatch || artistMatch;
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
        list.sort((a, b) => compareLocaleAware(
              a.displayArtist ?? a.albumArtist ?? '',
              b.displayArtist ?? b.albumArtist ?? '',
            ));
      case 'year':
        list.sort((a, b) => isReversed
            ? (b.year ?? 0).compareTo(a.year ?? 0)
            : (a.year ?? 0).compareTo(b.year ?? 0));
      case 'recentlyAdded':
      default:
        // Keep natural repository order
        break;
    }

    if (isReversed && sortKey != 'year') {
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
      return const Center(child: CircularProgressIndicator());
    }

    final sortedAlbums = _getSortedAlbums();
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
              selectedArtistKey: _selectedArtistKey,
              onArtistSelected: _onArtistSelected,
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
        return _WideAlbumTile(album: album, onTap: openDetail);
      case 'list':
        return _ListAlbumTile(album: album, onTap: openDetail);
      case 'square':
      default:
        return _SquareAlbumTile(album: album, onTap: openDetail);
    }
  }

  Widget _buildYearSectionHeader(BuildContext context, AlbumYearGroup group) {
    final yearLabel = group.year != null
        ? context.localizeDigitsText(group.year.toString())
        : context.t('albums.unknownYear');
    final countLabel =
        '${context.formatCountLocalized(group.albums.length)} ${context.t('albums.count')}';

    return Semantics(
      header: true,
      child: Row(
        key: ValueKey<String>(
          'album_year_header_${group.year?.toString() ?? 'unknown'}',
        ),
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              yearLabel,
              style: AppTypography.title.copyWith(color: AppColors.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            countLabel,
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumContent(
    List<AlbumSummary> albums,
    String viewMode,
    String currentSort,
  ) {
    if (albums.isEmpty) {
      if (_selectedArtistKey != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.t('albums.noAlbumsForArtist'),
                style: AppTypography.body.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              GlassPillButton(
                key: const Key('albums_empty_show_all_button'),
                label: context.t('albums.showAll'),
                size: GlassButtonSize.small,
                onPressed: () => _onArtistSelected(null),
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
                child: _buildYearSectionHeader(context, groups[i]),
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

class _SquareAlbumTile extends StatelessWidget {
  final AlbumSummary album;
  final VoidCallback onTap;

  const _SquareAlbumTile({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.r12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.0,
              child: _AlbumCoverImage(
                coverKey: album.coverKey,
                borderRadius: AppSpacing.r12,
                cacheSize: 180,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              album.album,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: textDirectionFor(album.album),
              style: AppTypography.bodyStrong.copyWith(color: AppColors.text),
            ),
            const SizedBox(height: 2),
            Builder(
              builder: (context) {
                final artist = context.displayArtist(album.displayArtist ?? album.albumArtist);
                return Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: textDirectionFor(artist),
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WideAlbumTile extends StatelessWidget {
  final AlbumSummary album;
  final VoidCallback onTap;

  const _WideAlbumTile({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.fillControl,
          borderRadius: BorderRadius.circular(AppSpacing.r12),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.r12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: _AlbumCoverImage(
                    coverKey: album.coverKey,
                    borderRadius: AppSpacing.r10,
                    cacheSize: 90,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: textDirectionFor(album.album),
                        style: AppTypography.bodyStrong.copyWith(color: AppColors.text),
                      ),
                      const SizedBox(height: 3),
                      Builder(
                        builder: (context) {
                          final artist = context.displayArtist(album.displayArtist ?? album.albumArtist);
                          return Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: textDirectionFor(artist),
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                          );
                        },
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (context) {
                          final countStr = context.formatCountLocalized(album.trackCount);
                          final yearStr = album.year != null
                              ? ' • ${context.localizeDigitsText(album.year.toString())}'
                              : '';
                          return Text(
                            '$countStr ${context.t('album.tracksCount')}$yearStr',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.micro.copyWith(color: AppColors.textMuted),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListAlbumTile extends StatelessWidget {
  final AlbumSummary album;
  final VoidCallback onTap;

  const _ListAlbumTile({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.r10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: _AlbumCoverImage(
                  coverKey: album.coverKey,
                  borderRadius: AppSpacing.r10,
                  cacheSize: 50,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text(
                  album.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: textDirectionFor(album.album),
                  style: AppTypography.bodyStrong.copyWith(color: AppColors.text),
                ),
              ),
              Expanded(
                flex: 2,
                child: Builder(
                  builder: (context) {
                    final artist = context.displayArtist(album.displayArtist ?? album.albumArtist);
                    return Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: textDirectionFor(artist),
                      style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                    );
                  },
                ),
              ),
              SizedBox(
                width: 60,
                child: Builder(
                  builder: (context) {
                    final yearStr = album.year != null
                        ? context.localizeDigitsText(album.year.toString())
                        : '—';
                    return Text(
                      yearStr,
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    );
                  },
                ),
              ),
              SizedBox(
                width: 70,
                child: Builder(
                  builder: (context) {
                    final countStr = context.formatCountLocalized(album.trackCount);
                    return Text(
                      '$countStr ${context.t('album.tracksCount')}',
                      textAlign: TextAlign.end,
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumCoverImage extends StatelessWidget {
  final String? coverKey;
  final double borderRadius;
  final int cacheSize;

  const _AlbumCoverImage({
    required this.coverKey,
    required this.borderRadius,
    required this.cacheSize,
  });

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (coverKey != null && CoverCache.hasCover(coverKey!)) {
      final file = File(CoverCache.pathFor(coverKey!));
      imageWidget = Image.file(
        file,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        cacheWidth: cacheSize * 2,
        cacheHeight: cacheSize * 2,
        frameBuilder: (context, child, frame, wasSync) {
          if (wasSync || frame != null) return child;
          return _buildPlaceholder();
        },
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else {
      imageWidget = _buildPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: imageWidget,
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF22212C),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: const Center(
        child: Icon(Icons.album_outlined, color: Colors.white24, size: 28),
      ),
    );
  }
}
