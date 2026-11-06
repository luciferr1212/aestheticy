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
import 'track_actions_menu.dart';

/// Screen displaying all user-created playlists with grid cards, creation,
/// and management actions.
class PlaylistsView extends StatelessWidget {
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
  });

  @override
  Widget build(BuildContext context) {
    final doImport = onImportM3u ??
        (ctx) => M3u.importPlaylist(
              ctx,
              repository: repository,
              collections: collections,
            );
    final doExport = onExportM3u ??
        (ctx, pl) => M3u.exportPlaylist(
              ctx,
              repository: repository,
              playlist: pl,
            );

    return ListenableBuilder(
      listenable: collections,
      builder: (context, _) {
        final playlists = collections.playlists;

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
                      collections: collections,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Playlist Grid or Empty State
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
                            GlassPillButton(
                              key: const Key('empty_new_playlist_button'),
                              label: context.t('playlists.new'),
                              leadingIcon: Icons.add,
                              variant: GlassButtonVariant.primary,
                              size: GlassButtonSize.medium,
                              onPressed: () => showCreatePlaylistDialog(
                                context,
                                collections: collections,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        key: const Key('playlists_grid_view'),
                        padding: const EdgeInsets.only(bottom: 120),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
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
                            onTap: () => navigator.openPlaylistDetail(
                              playlist.id,
                              playlist: playlist,
                            ),
                            onRename: () => showRenamePlaylistDialog(
                              context,
                              collections: collections,
                              playlist: playlist,
                            ),
                            onDelete: () => showDeletePlaylistDialog(
                              context,
                              collections: collections,
                              playlist: playlist,
                            ),
                            onExport: () => doExport(context, playlist),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
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
