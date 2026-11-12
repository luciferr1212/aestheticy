import 'dart:io';

import 'package:flutter/material.dart';

import '../../library/cover_cache.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../artist_names/artist_name_scope.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'library_header.dart';

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
  List<AlbumSummary> _searchResults = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    final albums = await widget.repository.listAlbums();
    if (mounted) {
      setState(() {
        _albums = albums;
        _isLoading = false;
      });
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

  List<AlbumSummary> _getSortedAlbums() {
    final list = List<AlbumSummary>.from(
      _searchQuery.isNotEmpty ? _searchResults : _albums,
    );
    final sortKey = widget.settingsStore.settings.albumSort;
    final isReversed = widget.settingsStore.settings.albumsSortReversed;

    switch (sortKey) {
      case 'title':
        list.sort((a, b) => a.album.toLowerCase().compareTo(b.album.toLowerCase()));
      case 'artist':
        list.sort((a, b) =>
            (a.albumArtist ?? '').toLowerCase().compareTo((b.albumArtist ?? '').toLowerCase()));
      case 'year':
        list.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
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
      albumsSortReversed: false,
    ));
    setState(() {});
  }

  void _onSortDirectionToggle() {
    final current = widget.settingsStore.settings.albumsSortReversed;
    widget.settingsStore.update((s) => s.copyWith(albumsSortReversed: !current));
    setState(() {});
  }

  void _onViewModeChanged(String newMode) {
    widget.settingsStore.update((s) => s.copyWith(libraryViewMode: newMode));
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

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LibraryHeader(
            title: context.t('nav.albums'),
            settingsStore: widget.settingsStore,
            itemCount: sortedAlbums.length,
            itemCountLabel: context.t('albums.count'),
            searchQuery: _searchQuery,
            onSearchChanged: _onSearchChanged,
            sortOptions: const ['recentlyAdded', 'title', 'artist', 'year'],
            currentSort: currentSort,
            onSortChanged: _onSortChanged,
            viewMode: viewMode,
            onViewModeChanged: _onViewModeChanged,
            isSortReversed: widget.settingsStore.settings.albumsSortReversed,
            onSortDirectionToggle: _onSortDirectionToggle,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _buildAlbumContent(sortedAlbums, viewMode, currentSort),
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
      return Center(
        child: Text(
          _searchQuery.isNotEmpty ? 'No albums match "$_searchQuery"' : 'No albums in library',
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
        cacheWidth: cacheSize * 2,
        cacheHeight: cacheSize * 2,
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
