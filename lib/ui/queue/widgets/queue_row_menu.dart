import 'package:flutter/material.dart';

import '../../../audio/audio_models.dart';
import '../../../audio/playback_controller.dart';
import '../../../features/collections/user_collections.dart';
import '../../../library/models.dart';
import '../../l10n/app_strings.dart';
import '../../library/track_actions_menu.dart';
import '../../shell/app_navigator.dart';
import '../../theme/app_colors.dart';

/// Overflow and context menu for a single row in [QueueContent].
class QueueRowMenu extends StatelessWidget {
  /// Menu controller shared with right-click gesture handling.
  final MenuController menuController;

  /// Whether the row is currently hovered.
  final bool isHovered;

  /// Whether the queue is in compact side-panel mode.
  final bool compact;

  /// Zero-based queue index.
  final int index;

  /// Unique queue entry identifier.
  final int entryId;

  /// Track audio source.
  final AudioSource source;

  /// Playback controller.
  final PlaybackController controller;

  /// Application navigator.
  final AppNavigator navigator;

  /// Optional explicit user collections store.
  final UserCollections? userCollections;

  /// Total entries in the queue.
  final int totalCount;

  /// Creates a [QueueRowMenu].
  const QueueRowMenu({
    super.key,
    required this.menuController,
    required this.isHovered,
    required this.compact,
    required this.index,
    required this.entryId,
    required this.source,
    required this.controller,
    required this.navigator,
    required this.userCollections,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final collections = userCollections ?? UserCollectionsScope.maybeOf(context);
    final extras = source.extras;
    final album = extras?['album'] ?? '';
    final rawArtist = extras?['artist'];
    final path = source.uri;
    final curIdx = controller.queue.currentIndex;

    return MenuAnchor(
      controller: menuController,
      builder: (context, ctrl, child) {
        return IconButton(
          key: Key('queue_row_menu_$index'),
          icon: Icon(
            Icons.more_horiz,
            size: 18,
            color:
                isHovered || ctrl.isOpen ? AppColors.text : AppColors.textMuted,
          ),
          tooltip: context.t('tracks.moreOptions'),
          padding: compact ? EdgeInsets.zero : null,
          constraints: compact
              ? const BoxConstraints.tightFor(width: 28, height: 28)
              : null,
          splashRadius: 14,
          onPressed: () {
            if (ctrl.isOpen) {
              ctrl.close();
            } else {
              ctrl.open();
            }
          },
        );
      },
      menuChildren: [
        // 1. Play next
        MenuItemButton(
          key: const Key('queue_menu_play_next'),
          leadingIcon: const Icon(Icons.playlist_play, size: 16),
          onPressed: () => controller.playNextFromQueue(index),
          child: Text(context.t('queue.playNext')),
        ),

        // 2. Add to queue
        MenuItemButton(
          key: const Key('queue_menu_add_to_queue'),
          leadingIcon: const Icon(Icons.queue, size: 16),
          onPressed: () => controller.addToQueue([source]),
          child: Text(context.t('queue.addToQueue')),
        ),

        // 3. Move to top of Up next
        MenuItemButton(
          key: const Key('queue_menu_move_to_top'),
          leadingIcon: const Icon(Icons.vertical_align_top, size: 16),
          onPressed: (curIdx >= 0 && index != curIdx + 1)
              ? () => controller.moveInQueue(index, curIdx + 1)
              : null,
          child: Text(context.t('queue.moveToTop')),
        ),

        // 4. Move to bottom
        MenuItemButton(
          key: const Key('queue_menu_move_to_bottom'),
          leadingIcon: const Icon(Icons.vertical_align_bottom, size: 16),
          onPressed: index < totalCount - 1
              ? () => controller.moveInQueue(index, totalCount - 1)
              : null,
          child: Text(context.t('queue.moveToBottom')),
        ),

        // 5. Remove
        MenuItemButton(
          key: const Key('queue_menu_remove'),
          leadingIcon: const Icon(Icons.delete_outline, size: 16),
          onPressed: () => controller.removeEntryFromQueue(entryId),
          child: Text(context.t('queue.remove')),
        ),

        // 6. Add to playlist
        if (collections != null && path.isNotEmpty)
          SubmenuButton(
            key: const Key('queue_menu_add_to_playlist'),
            leadingIcon: const Icon(Icons.playlist_add, size: 16),
            menuChildren: [
              for (final pl in collections.playlists)
                MenuItemButton(
                  key: Key('queue_menu_playlist_${pl.id}'),
                  leadingIcon: const Icon(
                    Icons.queue_music,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () => collections.addToPlaylist(pl.id, [path]),
                  child: Text(pl.name),
                ),
              MenuItemButton(
                key: const Key('queue_menu_new_playlist'),
                leadingIcon:
                    const Icon(Icons.add, size: 16, color: AppColors.accent),
                onPressed: () {
                  showCreatePlaylistDialog(
                    context,
                    collections: collections,
                    initialTrackPath: path,
                  );
                },
                child: Text(
                  context.t('playlist.newPlaylist'),
                  style: const TextStyle(color: AppColors.accent),
                ),
              ),
            ],
            child: Text(context.t('menu.addToPlaylist')),
          ),

        // 7. Move up
        MenuItemButton(
          key: const Key('queue_menu_move_up'),
          leadingIcon: const Icon(Icons.arrow_upward, size: 16),
          onPressed:
              index > 0 ? () => controller.moveInQueue(index, index - 1) : null,
          child: Text(context.t('queue.moveUp')),
        ),

        // 8. Move down
        MenuItemButton(
          key: const Key('queue_menu_move_down'),
          leadingIcon: const Icon(Icons.arrow_downward, size: 16),
          onPressed: index < totalCount - 1
              ? () => controller.moveInQueue(index, index + 1)
              : null,
          child: Text(context.t('queue.moveDown')),
        ),

        // 9. Go to album
        if (album.isNotEmpty)
          MenuItemButton(
            key: const Key('queue_menu_go_to_album'),
            leadingIcon: const Icon(Icons.album_outlined, size: 16),
            onPressed: () => navigator.openAlbumDetail(
              album,
              album: AlbumSummary(album: album, trackCount: 0),
            ),
            child: Text(context.t('queue.goToAlbum')),
          ),

        // 10. Go to artist
        if (rawArtist != null && rawArtist.isNotEmpty)
          MenuItemButton(
            key: const Key('queue_menu_go_to_artist'),
            leadingIcon: const Icon(Icons.person_outline, size: 16),
            onPressed: () => navigator.openArtistDetail(
              rawArtist,
              artist: ArtistSummary(
                name: rawArtist,
                albumCount: 0,
                trackCount: 0,
              ),
            ),
            child: Text(context.t('queue.goToArtist')),
          ),
      ],
    );
  }
}
