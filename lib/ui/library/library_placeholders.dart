import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../settings/settings_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'library_header.dart';
import 'library_view_controls.dart';
import 'sort_direction_button.dart';
import 'track_table.dart';

/// Loading layout placeholder for [AlbumsView] matching its final content structure.
class AlbumsViewPlaceholder extends StatelessWidget {
  /// The settings store for reading current view configuration.
  final SettingsStore settingsStore;

  /// Creates an [AlbumsViewPlaceholder].
  const AlbumsViewPlaceholder({
    super.key,
    required this.settingsStore,
  });

  @override
  Widget build(BuildContext context) {
    final viewMode = settingsStore.settings.libraryViewMode;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LibraryHeader(
            title: context.t('nav.albums'),
            settingsStore: settingsStore,
            itemCount: 0,
            itemCountLabel: context.t('albums.count'),
            onSearchChanged: (_) {},
            showControls: false,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: LibraryViewControls(
              allowedShapes: const ['square', 'wide', 'list'],
              currentShape: viewMode,
              onShapeChanged: (_) {},
              sortOptions: const ['album', 'artist', 'year', 'trackCount', 'recentlyAdded'],
              currentSort: settingsStore.settings.albumSort,
              onSortChanged: (_) {},
              sortDirection: SortDirection.fromReversed(settingsStore.settings.albumsSortReversed),
              onSortDirectionChanged: (_) {},
              reduceMotion: true,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _buildShapeGrid(viewMode),
          ),
        ],
      ),
    );
  }

  Widget _buildShapeGrid(String shape) {
    if (shape == 'list') {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 120),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 12,
        itemBuilder: (context, index) {
          return Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.fillControl,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 13,
                        width: 130,
                        decoration: BoxDecoration(
                          color: AppColors.fillControl,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 11,
                        width: 80,
                        decoration: BoxDecoration(
                          color: AppColors.fillGlass,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    if (shape == 'wide') {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 120),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 8,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              height: 80,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.fillGlass,
                borderRadius: BorderRadius.circular(AppSpacing.r12),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.fillControl,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 14,
                          width: 140,
                          decoration: BoxDecoration(
                            color: AppColors.fillControl,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 12,
                          width: 90,
                          decoration: BoxDecoration(
                            color: AppColors.fillGlass,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: 0.78,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.r12),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.fillControl,
                    borderRadius: BorderRadius.circular(AppSpacing.r10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 14,
                width: 120,
                decoration: BoxDecoration(
                  color: AppColors.fillControl,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 12,
                width: 80,
                decoration: BoxDecoration(
                  color: AppColors.fillGlass,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Loading layout placeholder for [ArtistsView] matching its final content structure.
class ArtistsViewPlaceholder extends StatelessWidget {
  /// The settings store for reading current view configuration.
  final SettingsStore settingsStore;

  /// Creates an [ArtistsViewPlaceholder].
  const ArtistsViewPlaceholder({
    super.key,
    required this.settingsStore,
  });

  @override
  Widget build(BuildContext context) {
    final settings = settingsStore.settings;
    final currentShape = settings.artistsViewMode;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LibraryHeader(
            title: context.t('nav.artists'),
            settingsStore: settingsStore,
            itemCount: 0,
            itemCountLabel: context.t('artists.count'),
            onSearchChanged: (_) {},
            showControls: false,
          ),
          const SizedBox(height: 12),
          LibraryViewControls(
            allowedShapes: const ['circle', 'square', 'list'],
            currentShape: currentShape,
            onShapeChanged: (_) {},
            sortOptions: const ['name', 'mostSongs', 'mostAlbums', 'recentlyAdded'],
            currentSort: settings.artistsSort,
            onSortChanged: (_) {},
            sortDirection: SortDirection.fromReversed(settings.artistsSortReversed),
            onSortDirectionChanged: (_) {},
            reduceMotion: true,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _buildShapeGrid(currentShape),
          ),
        ],
      ),
    );
  }

  Widget _buildShapeGrid(String shape) {
    if (shape == 'list') {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 120),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 12,
        itemBuilder: (context, index) {
          return Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: AppColors.fillControl,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 14,
                        width: 120,
                        decoration: BoxDecoration(
                          color: AppColors.fillControl,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 11,
                        width: 70,
                        decoration: BoxDecoration(
                          color: AppColors.fillGlass,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    if (shape == 'square') {
      return GridView.builder(
        padding: const EdgeInsets.only(bottom: 120),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisSpacing: 20,
          crossAxisSpacing: 20,
          childAspectRatio: 0.85,
        ),
        itemCount: 12,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.r12),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.fillControl,
                      borderRadius: BorderRadius.circular(AppSpacing.r10),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 14,
                  width: 110,
                  decoration: BoxDecoration(
                    color: AppColors.fillControl,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 11,
                  width: 60,
                  decoration: BoxDecoration(
                    color: AppColors.fillGlass,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    // Default 'circle'
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: 0.82,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.fillControl,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 14,
                width: 90,
                decoration: BoxDecoration(
                  color: AppColors.fillControl,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 11,
                width: 60,
                decoration: BoxDecoration(
                  color: AppColors.fillGlass,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Loading layout placeholder for [TracksView] matching its final content structure.
class TracksViewPlaceholder extends StatelessWidget {
  /// The settings store for reading current view configuration.
  final SettingsStore settingsStore;

  /// Creates a [TracksViewPlaceholder].
  const TracksViewPlaceholder({
    super.key,
    required this.settingsStore,
  });

  @override
  Widget build(BuildContext context) {
    final settings = settingsStore.settings;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LibraryHeader(
            title: context.t('nav.tracks'),
            settingsStore: settingsStore,
            itemCount: 0,
            itemCountLabel: context.t('tracks.count'),
            onSearchChanged: (_) {},
            showControls: false,
          ),
          const SizedBox(height: 12),
          LibraryViewControls(
            sortOptions: const ['title', 'artist', 'album', 'duration', 'recentlyAdded'],
            currentSort: settings.trackSort,
            onSortChanged: (_) {},
            sortDirection: SortDirection.fromReversed(settings.tracksSortReversed),
            onSortDirectionChanged: (_) {},
            reduceMotion: true,
          ),
          const SizedBox(height: 16),
          const TrackTableHeader(
            showTrackNumber: true,
            showCover: true,
            showAlbum: true,
            showArtist: true,
            hasActions: true,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 120),
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 12,
              itemExtent: 52.0,
              itemBuilder: (context, index) {
                return Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.fillGlass,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.fillControl,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 4,
                        child: Container(
                          height: 13,
                          margin: const EdgeInsetsDirectional.only(end: 24),
                          decoration: BoxDecoration(
                            color: AppColors.fillControl,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Container(
                          height: 13,
                          margin: const EdgeInsetsDirectional.only(end: 24),
                          decoration: BoxDecoration(
                            color: AppColors.fillGlass,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Container(
                          height: 13,
                          margin: const EdgeInsetsDirectional.only(end: 24),
                          decoration: BoxDecoration(
                            color: AppColors.fillGlass,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Container(
                        width: 40,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.fillGlass,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading layout placeholder for [RecentlyPlayedView] matching its final content structure.
class RecentlyPlayedViewPlaceholder extends StatelessWidget {
  /// The settings store for reading current view configuration.
  final SettingsStore settingsStore;

  /// Creates a [RecentlyPlayedViewPlaceholder].
  const RecentlyPlayedViewPlaceholder({
    super.key,
    required this.settingsStore,
  });

  @override
  Widget build(BuildContext context) {
    final settings = settingsStore.settings;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('nav.recent'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '0 ${context.t('tracks.count')}',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LibraryViewControls(
            sortOptions: const ['playedAt', 'title', 'artist', 'duration'],
            currentSort: settings.recentlyPlayedSort,
            onSortChanged: (_) {},
            sortDirection: SortDirection.fromReversed(settings.recentlyPlayedSortReversed),
            onSortDirectionChanged: (_) {},
            reduceMotion: true,
          ),
          const SizedBox(height: 16),
          const TrackTableHeader(
            showTrackNumber: true,
            showCover: true,
            showAlbum: true,
            showArtist: true,
            hasActions: true,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 120),
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 12,
              itemExtent: 52.0,
              itemBuilder: (context, index) {
                return Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.fillGlass,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.fillControl,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 4,
                        child: Container(
                          height: 13,
                          margin: const EdgeInsetsDirectional.only(end: 24),
                          decoration: BoxDecoration(
                            color: AppColors.fillControl,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Container(
                          height: 13,
                          margin: const EdgeInsetsDirectional.only(end: 24),
                          decoration: BoxDecoration(
                            color: AppColors.fillGlass,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Container(
                          height: 13,
                          margin: const EdgeInsetsDirectional.only(end: 24),
                          decoration: BoxDecoration(
                            color: AppColors.fillGlass,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Container(
                        width: 40,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.fillGlass,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
