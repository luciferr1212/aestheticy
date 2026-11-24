import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../audio/playback_controller.dart';
import '../../features/collections/m3u.dart';
import '../../features/collections/user_collections.dart';
import '../../library/cover_cache.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'library_data_cache.dart';
import 'library_view_controls.dart';
import 'sort_direction_button.dart';
import 'track_actions_menu.dart';

/// Screen displaying all user-created playlists with grid cards, creation,
/// and management actions.
class PlaylistsView extends StatefulWidget {
  /// User collections store.
  final UserCollections collections;

  /// Library repository.
  final LibraryRepository repository;

  /// Audio playback controller.
  final PlaybackController controller;

  /// Settings store.
  final SettingsStore settingsStore;

  /// App navigator.
  final AppNavigator navigator;

  /// Optional export callback for M3U testing or injection.
  final Future<void> Function(BuildContext context, PlaylistSummary playlist)?
      onExportM3u;

  /// Optional import callback for M3U testing or injection.
  final Future<void> Function(BuildContext context)? onImportM3u;

  /// Optional in-memory library data cache for automatic refresh after scans.
  final LibraryDataCache? dataCache;

  /// Creates a [PlaylistsView].
  const PlaylistsView({
    super.key,
    required this.collections,
    required this.repository,
    required this.controller,
    required this.settingsStore,
    required this.navigator,
    this.onExportM3u,
    this.onImportM3u,
    this.dataCache,
  });

  @override
  State<PlaylistsView> createState() => _PlaylistsViewState();
}

class _PlaylistsViewState extends State<PlaylistsView> {
  LibraryDataCache? _activeCache;
  int _lastCacheRevision = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cache = widget.dataCache ?? LibraryDataCacheScope.maybeOf(context);
    if (cache != _activeCache) {
      _activeCache?.removeListener(_onCacheChanged);
      _activeCache = cache;
      _activeCache?.addListener(_onCacheChanged);
      _lastCacheRevision = _activeCache?.revision ?? -1;
    }
  }

  @override
  void didUpdateWidget(PlaylistsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataCache != widget.dataCache) {
      final cache = widget.dataCache ?? LibraryDataCacheScope.maybeOf(context);
      if (cache != _activeCache) {
        _activeCache?.removeListener(_onCacheChanged);
        _activeCache = cache;
        _activeCache?.addListener(_onCacheChanged);
        _lastCacheRevision = _activeCache?.revision ?? -1;
      }
    }
  }

  @override
  void dispose() {
    _activeCache?.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() {
    final cache = _activeCache;
    if (!mounted || cache == null) return;
    if (cache.revision != _lastCacheRevision) {
      _lastCacheRevision = cache.revision;
      unawaited(widget.collections.refresh());
    }
  }

  List<PlaylistSummary> _sortPlaylists(
    List<PlaylistSummary> list,
    String sortKey,
    bool reversed,
  ) {
    final sorted = List<PlaylistSummary>.from(list);
    sorted.sort((a, b) {
      int cmp;
      switch (sortKey) {
        case 'trackCount':
          cmp = b.trackCount.compareTo(a.trackCount);
          if (cmp == 0) cmp = compareLocaleAware(a.name, b.name);
          break;
        case 'recentlyAdded':
          cmp = b.createdAt.compareTo(a.createdAt);
          if (cmp == 0) cmp = compareLocaleAware(a.name, b.name);
          break;
        case 'name':
        default:
          cmp = compareLocaleAware(a.name, b.name);
          break;
      }
      return reversed ? -cmp : cmp;
    });
    return sorted;
  }

  Widget _buildShapeContent(
    BuildContext context,
    List<PlaylistSummary> playlists,
    String shape,
    Future<void> Function(BuildContext, PlaylistSummary) doExport,
  ) {
    if (shape == 'list') {
      return ListView.builder(
        key: const Key('playlists_list_view'),
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: playlists.length,
        itemBuilder: (context, index) {
          final playlist = playlists[index];
          return _PlaylistListRow(
            key: Key('playlist_list_row_${playlist.id}'),
            playlist: playlist,
            onTap: () => widget.navigator.openPlaylistDetail(
              playlist.id,
              playlist: playlist,
            ),
            onRename: () => showRenamePlaylistDialog(
              context,
              collections: widget.collections,
              playlist: playlist,
            ),
            onDelete: () => showDeletePlaylistDialog(
              context,
              collections: widget.collections,
              playlist: playlist,
            ),
            onExport: () => doExport(context, playlist),
          );
        },
      );
    }

    if (shape == 'wide') {
      return ListView.builder(
        key: const Key('playlists_wide_view'),
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: playlists.length,
        itemBuilder: (context, index) {
          final playlist = playlists[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PlaylistWideCard(
              key: Key('playlist_wide_card_${playlist.id}'),
              playlist: playlist,
              onTap: () => widget.navigator.openPlaylistDetail(
                playlist.id,
                playlist: playlist,
              ),
              onRename: () => showRenamePlaylistDialog(
                context,
                collections: widget.collections,
                playlist: playlist,
              ),
              onDelete: () => showDeletePlaylistDialog(
                context,
                collections: widget.collections,
                playlist: playlist,
              ),
              onExport: () => doExport(context, playlist),
            ),
          );
        },
      );
    }

    return GridView.builder(
      key: const Key('playlists_grid_view'),
      padding: const EdgeInsets.only(bottom: 120),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: 0.78,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _PlaylistCard(
          key: Key('playlist_card_${playlist.id}'),
          playlist: playlist,
          onTap: () => widget.navigator.openPlaylistDetail(
            playlist.id,
            playlist: playlist,
          ),
          onRename: () => showRenamePlaylistDialog(
            context,
            collections: widget.collections,
            playlist: playlist,
          ),
          onDelete: () => showDeletePlaylistDialog(
            context,
            collections: widget.collections,
            playlist: playlist,
          ),
          onExport: () => doExport(context, playlist),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final doImport = widget.onImportM3u ??
        (ctx) => M3u.importPlaylist(
              ctx,
              repository: widget.repository,
              collections: widget.collections,
            );
    final doExport = widget.onExportM3u ??
        (ctx, pl) => M3u.exportPlaylist(
              ctx,
              repository: widget.repository,
              playlist: pl,
            );

    return ListenableBuilder(
      listenable: widget.collections,
      builder: (context, _) {
        final rawPlaylists = widget.collections.playlists;
        final settings = widget.settingsStore.settings;
        final playlists = _sortPlaylists(
          rawPlaylists,
          settings.playlistsSort,
          settings.playlistsSortReversed,
        );
        final currentShape = settings.playlistsViewMode;
        final reduceMotion = settings.reduceMotion;

        return Padding(
          padding:
              const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.t('nav.playlists'),
                      style: AppTypography.display
                          .copyWith(letterSpacing: -0.5),
                    ),
                  ),
                  GlassPillButton(
                    key: const Key('import_m3u_button'),
                    label: context.t('playlist.importM3u'),
                    leadingIcon: Icons.file_upload_outlined,
                    size: GlassButtonSize.medium,
                    onPressed: () => doImport(context),
                  ),
                  const SizedBox(width: 12),
                  GlassPillButton(
                    key: const Key('new_playlist_button'),
                    label: context.t('playlists.new'),
                    leadingIcon: Icons.add,
                    variant: GlassButtonVariant.primary,
                    size: GlassButtonSize.medium,
                    onPressed: () => showCreatePlaylistDialog(
                      context,
                      collections: widget.collections,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              LibraryViewControls(
                allowedShapes: const ['square', 'wide', 'list'],
                currentShape: currentShape,
                onShapeChanged: (newShape) {
                  widget.settingsStore.update((s) => s.copyWith(playlistsViewMode: newShape));
                },
                sortOptions: const ['name', 'trackCount', 'recentlyAdded'],
                currentSort: settings.playlistsSort,
                onSortChanged: (newSort) {
                  widget.settingsStore.update((s) => s.copyWith(playlistsSort: newSort));
                },
                sortDirection: SortDirection.fromReversed(settings.playlistsSortReversed),
                onSortDirectionChanged: (newDir) {
                  widget.settingsStore.update((s) => s.copyWith(playlistsSortReversed: newDir.isReversed));
                },
                reduceMotion: reduceMotion,
              ),
              const SizedBox(height: 16),

              // Playlist Content or Empty State
              Expanded(
                child: playlists.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.queue_music_outlined,
                              size: 64,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.t('playlists.empty'),
                              style: AppTypography.title
                                  .copyWith(color: AppColors.text),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              context.t('playlists.emptyDescription'),
                              style: AppTypography.body
                                  .copyWith(color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GlassPillButton(
                                  key: const Key('empty_new_playlist_button'),
                                  label: context.t('playlists.new'),
                                  leadingIcon: Icons.add,
                                  variant: GlassButtonVariant.primary,
                                  size: GlassButtonSize.medium,
                                  onPressed: () => showCreatePlaylistDialog(
                                    context,
                                    collections: widget.collections,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                GlassPillButton(
                                  key: const Key('empty_import_m3u_button'),
                                  label: context.t('playlist.importM3u'),
                                  leadingIcon: Icons.file_upload_outlined,
                                  size: GlassButtonSize.medium,
                                  onPressed: () => doImport(context),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeOut,
                        child: KeyedSubtree(
                          key: ValueKey('playlists_view_mode_$currentShape'),
                          child: _buildShapeContent(
                            context,
                            playlists,
                            currentShape,
                            doExport,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlaylistWideCard extends StatelessWidget {
  final PlaylistSummary playlist;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onExport;

  const _PlaylistWideCard({
    super.key,
    required this.playlist,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      hoverColor: const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(AppSpacing.r12),
      onTap: onTap,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.fillGlass,
          borderRadius: BorderRadius.circular(AppSpacing.r12),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.r10),
                child: _buildCover(playlist.coverKey),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDirectionFor(playlist.name),
                    style: AppTypography.bodyStrong.copyWith(color: AppColors.text),
                  ),
                  const SizedBox(height: 4),
                  Builder(
                    builder: (context) {
                      final countStr = context.t('playlist.trackCount', args: {
                        'count': context.formatCountLocalized(playlist.trackCount),
                      });
                      final durStr = playlist.totalDurationMs > 0
                          ? ' • ${context.formatDurationLocalized(Duration(milliseconds: playlist.totalDurationMs))}'
                          : '';
                      return Text(
                        '$countStr$durStr',
                        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                      );
                    },
                  ),
                ],
              ),
            ),
            _PlaylistCardMenuButton(
              playlist: playlist,
              onRename: onRename,
              onDelete: onDelete,
              onExport: onExport,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistListRow extends StatelessWidget {
  final PlaylistSummary playlist;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onExport;

  const _PlaylistListRow({
    super.key,
    required this.playlist,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      hoverColor: const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(AppSpacing.r10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.r10),
                child: _buildCover(playlist.coverKey),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDirectionFor(playlist.name),
                    style: AppTypography.bodyStrong.copyWith(color: AppColors.text),
                  ),
                  const SizedBox(height: 2),
                  Builder(
                    builder: (context) {
                      final countStr = context.t('playlist.trackCount', args: {
                        'count': context.formatCountLocalized(playlist.trackCount),
                      });
                      final durStr = playlist.totalDurationMs > 0
                          ? ' • ${context.formatDurationLocalized(Duration(milliseconds: playlist.totalDurationMs))}'
                          : '';
                      return Text(
                        '$countStr$durStr',
                        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                      );
                    },
                  ),
                ],
              ),
            ),
            _PlaylistCardMenuButton(
              playlist: playlist,
              onRename: onRename,
              onDelete: onDelete,
              onExport: onExport,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final PlaylistSummary playlist;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onExport;

  const _PlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      hoverColor: const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(AppSpacing.r12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.r12),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Artwork
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.r10),
                      child: _buildCover(playlist.coverKey),
                    ),
                  ),
                  PositionedDirectional(
                    top: 6,
                    end: 6,
                    child: _PlaylistCardMenuButton(
                      playlist: playlist,
                      onRename: onRename,
                      onDelete: onDelete,
                      onExport: onExport,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Title
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: textDirectionFor(playlist.name),
              style: AppTypography.bodyStrong.copyWith(color: AppColors.text),
            ),
            const SizedBox(height: 4),

            // Track count & duration
            Builder(
              builder: (context) {
                final countStr = context.t('playlist.trackCount', args: {
                  'count': context.formatCountLocalized(playlist.trackCount),
                });
                final durStr = playlist.totalDurationMs > 0
                    ? ' • ${context.formatDurationLocalized(Duration(milliseconds: playlist.totalDurationMs))}'
                    : '';
                return Text(
                  '$countStr$durStr',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textMuted),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildCover(String? coverKey) {
  if (coverKey != null && CoverCache.hasCover(coverKey)) {
    final file = File(CoverCache.pathFor(coverKey));
    return Image.file(
      file,
      fit: BoxFit.cover,
      cacheWidth: 320,
      cacheHeight: 320,
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }
  return _placeholder();
}

Widget _placeholder() {
  return Container(
    color: const Color(0xFF22212C),
    child: const Center(
      child: Icon(
        Icons.queue_music,
        size: 48,
        color: Colors.white24,
      ),
    ),
  );
}

class _PlaylistCardMenuButton extends StatelessWidget {
  final PlaylistSummary playlist;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onExport;

  const _PlaylistCardMenuButton({
    required this.playlist,
    required this.onRename,
    required this.onDelete,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      style: TrackActionsMenu.defaultMenuStyle,
      menuChildren: [
        MenuItemButton(
          key: Key('playlist_rename_${playlist.id}'),
          leadingIcon: const Icon(Icons.edit_outlined, size: 16),
          onPressed: onRename,
          child: Text(context.t('playlist.rename')),
        ),
        if (onExport != null)
          MenuItemButton(
            key: Key('playlist_export_${playlist.id}'),
            leadingIcon: const Icon(Icons.file_download_outlined, size: 16),
            onPressed: onExport,
            child: Text(context.t('playlist.exportM3u')),
          ),
        MenuItemButton(
          key: Key('playlist_delete_${playlist.id}'),
          leadingIcon: const Icon(Icons.delete_outline,
              size: 16, color: Colors.redAccent),
          onPressed: onDelete,
          child: Text(
            context.t('common.delete'),
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
      builder: (context, controller, child) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            key: Key('playlist_menu_button_${playlist.id}'),
            icon: const Icon(Icons.more_vert, size: 18, color: Colors.white),
            tooltip: context.t('tracks.moreOptions'),
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
          ),
        );
      },
    );
  }
}
