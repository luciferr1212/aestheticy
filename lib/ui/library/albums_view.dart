import 'dart:io';

import 'package:flutter/material.dart';

import '../../library/cover_cache.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'library_header.dart';

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

    return list;
  }

  void _onSortChanged(String newSort) {
    widget.settingsStore.update((s) => s.copyWith(albumSort: newSort));
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
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _buildAlbumContent(sortedAlbums, viewMode),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumContent(List<AlbumSummary> albums, String viewMode) {
    if (albums.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty ? 'No albums match "$_searchQuery"' : 'No albums in library',
          style: AppTypography.body.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    switch (viewMode) {
      case 'wide':
        return GridView.builder(
          key: const Key('albums_wide_grid'),
          padding: const EdgeInsets.only(bottom: 120),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 380,
            mainAxisExtent: 100,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return _WideAlbumTile(
              album: album,
              onTap: () => widget.navigator.openAlbumDetail(album.album, album: album),
            );
          },
        );
      case 'list':
        return ListView.builder(
          key: const Key('albums_list_view'),
          padding: const EdgeInsets.only(bottom: 120),
          itemCount: albums.length,
          itemExtent: 56.0,
          itemBuilder: (context, index) {
            final album = albums[index];
            return _ListAlbumTile(
              album: album,
              onTap: () => widget.navigator.openAlbumDetail(album.album, album: album),
            );
          },
        );
      case 'square':
      default:
        return GridView.builder(
          key: const Key('albums_square_grid'),
          padding: const EdgeInsets.only(bottom: 120),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisExtent: 220,
            crossAxisSpacing: 16,
            mainAxisSpacing: 20,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return _SquareAlbumTile(
              album: album,
              onTap: () => widget.navigator.openAlbumDetail(album.album, album: album),
            );
          },
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
            Text(
              album.albumArtist ?? 'Unknown Artist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: textDirectionFor(album.albumArtist ?? ''),
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
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
                      Text(
                        album.albumArtist ?? 'Unknown Artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: textDirectionFor(album.albumArtist ?? ''),
                        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${album.trackCount} tracks${album.year != null ? ' • ${album.year}' : ''}',
                        style: AppTypography.micro.copyWith(color: AppColors.textMuted),
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
                child: Text(
                  album.albumArtist ?? 'Unknown Artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: textDirectionFor(album.albumArtist ?? ''),
                  style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  album.year != null ? '${album.year}' : '—',
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  '${album.trackCount} tracks',
                  textAlign: TextAlign.end,
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted),
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
