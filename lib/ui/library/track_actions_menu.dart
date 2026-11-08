import 'package:flutter/material.dart';

import '../../audio/playback_controller.dart';
import '../../features/collections/user_collections.dart';
import '../../library/models.dart';
import '../../library/track_audio_source_mapper.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Shows the dialog to create a new playlist, validate its name, and optionally
/// add [initialTrackPath] to it.
Future<PlaylistSummary?> showCreatePlaylistDialog(
  BuildContext context, {
  required UserCollections collections,
  String? initialTrackPath,
}) async {
  final controller = TextEditingController();
  String? errorMessage;

  final created = await showDialog<PlaylistSummary>(
    context: context,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (innerCtx, setState) {
          void validateAndSubmit() async {
            final trimmed = controller.text.trim();
            if (trimmed.isEmpty) {
              setState(() => errorMessage = innerCtx.t('playlist.nameEmpty'));
              return;
            }
            if (trimmed.length > 60) {
              setState(() => errorMessage = innerCtx.t('playlist.nameTooLong'));
              return;
            }
            final duplicate = collections.playlists.any(
              (p) => p.name.trim().toLowerCase() == trimmed.toLowerCase(),
            );
            if (duplicate) {
              setState(
                  () => errorMessage = innerCtx.t('playlist.nameDuplicate'));
              return;
            }

            try {
              final pl = await collections.createPlaylist(trimmed);
              if (initialTrackPath != null) {
                await collections.addToPlaylist(pl.id, [initialTrackPath]);
              }
              if (innerCtx.mounted) {
                Navigator.of(innerCtx).pop(pl);
              }
            } catch (e) {
              setState(() => errorMessage = e.toString());
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.r16),
              side: const BorderSide(color: AppColors.border),
            ),
            title: Text(
              innerCtx.t('playlist.createTitle'),
              style: AppTypography.title.copyWith(color: AppColors.text),
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('create_playlist_text_field'),
                    controller: controller,
                    autofocus: true,
                    style: AppTypography.body.copyWith(color: AppColors.text),
                    decoration: InputDecoration(
                      hintText: innerCtx.t('playlist.nameHint'),
                      errorText: errorMessage,
                      isDense: true,
                    ),
                    onChanged: (_) {
                      if (errorMessage != null) {
                        setState(() => errorMessage = null);
                      }
                    },
                    onSubmitted: (_) => validateAndSubmit(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const Key('create_playlist_cancel_button'),
                onPressed: () => Navigator.of(innerCtx).pop(null),
                child: Text(innerCtx.t('common.cancel')),
              ),
              ElevatedButton(
                key: const Key('create_playlist_submit_button'),
                onPressed: validateAndSubmit,
                child: Text(innerCtx.t('common.create')),
              ),
            ],
          );
        },
      );
    },
  );

  return created;
}

/// Shows the dialog to rename an existing playlist.
Future<bool> showRenamePlaylistDialog(
  BuildContext context, {
  required UserCollections collections,
  required PlaylistSummary playlist,
}) async {
  final controller = TextEditingController(text: playlist.name);
  String? errorMessage;

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (innerCtx, setState) {
          void validateAndSubmit() async {
            final trimmed = controller.text.trim();
            if (trimmed.isEmpty) {
              setState(() => errorMessage = innerCtx.t('playlist.nameEmpty'));
              return;
            }
            if (trimmed.length > 60) {
              setState(() => errorMessage = innerCtx.t('playlist.nameTooLong'));
              return;
            }
            final duplicate = collections.playlists.any(
              (p) =>
                  p.id != playlist.id &&
                  p.name.trim().toLowerCase() == trimmed.toLowerCase(),
            );
            if (duplicate) {
              setState(
                  () => errorMessage = innerCtx.t('playlist.nameDuplicate'));
              return;
            }

            try {
              await collections.renamePlaylist(playlist.id, trimmed);
              if (innerCtx.mounted) {
                Navigator.of(innerCtx).pop(true);
              }
            } catch (e) {
              setState(() => errorMessage = e.toString());
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.r16),
              side: const BorderSide(color: AppColors.border),
            ),
            title: Text(
              innerCtx.t('playlist.renameTitle'),
              style: AppTypography.title.copyWith(color: AppColors.text),
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('rename_playlist_text_field'),
                    controller: controller,
                    autofocus: true,
                    style: AppTypography.body.copyWith(color: AppColors.text),
                    decoration: InputDecoration(
                      hintText: innerCtx.t('playlist.nameHint'),
                      errorText: errorMessage,
                      isDense: true,
                    ),
                    onChanged: (_) {
                      if (errorMessage != null) {
                        setState(() => errorMessage = null);
                      }
                    },
                    onSubmitted: (_) => validateAndSubmit(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const Key('rename_playlist_cancel_button'),
                onPressed: () => Navigator.of(innerCtx).pop(false),
                child: Text(innerCtx.t('common.cancel')),
              ),
              ElevatedButton(
                key: const Key('rename_playlist_submit_button'),
                onPressed: validateAndSubmit,
                child: Text(innerCtx.t('playlist.rename')),
              ),
            ],
          );
        },
      );
    },
  );

  return result ?? false;
}

/// Shows confirmation dialog to delete a playlist.
Future<bool> showDeletePlaylistDialog(
  BuildContext context, {
  required UserCollections collections,
  required PlaylistSummary playlist,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.r16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          dialogCtx.t('playlist.deleteTitle'),
          style: AppTypography.title.copyWith(color: AppColors.text),
        ),
        content: Text(
          dialogCtx.t('playlist.deleteConfirm', args: {'name': playlist.name}),
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            key: const Key('delete_playlist_cancel_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(dialogCtx.t('common.cancel')),
          ),
          ElevatedButton(
            key: const Key('delete_playlist_confirm_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await collections.deletePlaylist(playlist.id);
              if (dialogCtx.mounted) {
                Navigator.of(dialogCtx).pop(true);
              }
            },
            child: Text(dialogCtx.t('common.delete')),
          ),
        ],
      );
    },
  );

  return confirmed ?? false;
}

/// Shared track actions menu items builder and widget wrappers.
abstract final class TrackActionsMenu {
  /// Builds the list of menu children for [MenuAnchor].
  static List<Widget> buildMenuItems({
    required BuildContext context,
    required Track track,
    bool isMissing = false,
    PlaybackController? controller,
    UserCollections? userCollections,
    int? playlistId,
    int? playlistEntryId,
    int? position,
    int? totalCount,
    VoidCallback? onPlay,
    VoidCallback? onPlayNext,
    VoidCallback? onAddToQueue,
    VoidCallback? onRemoveFromPlaylist,
    VoidCallback? onMoveUp,
    VoidCallback? onMoveDown,
  }) {
    final collections = userCollections ?? UserCollectionsScope.maybeOf(context);
    final isFav = collections?.isFavorite(track.path) ?? false;
    final currentRating = collections?.ratingOf(track.path) ?? 0;

    return [
      // 1. Play
      MenuItemButton(
        key: const Key('track_action_play'),
        leadingIcon: const Icon(Icons.play_arrow, size: 16),
        onPressed: isMissing
            ? null
            : () {
                if (onPlay != null) {
                  onPlay();
                } else if (controller != null) {
                  controller.playQueue([track.toAudioSource()], startIndex: 0);
                }
              },
        child: Text(context.t('menu.play')),
      ),

      // 2. Play next
      MenuItemButton(
        key: const Key('track_action_play_next'),
        leadingIcon: const Icon(Icons.playlist_play, size: 16),
        onPressed: isMissing
            ? null
            : () {
                if (onPlayNext != null) {
                  onPlayNext();
                } else if (controller != null) {
                  controller.playNext([track.toAudioSource()]);
                }
              },
        child: Text(context.t('menu.playNext')),
      ),

      // 3. Add to queue
      MenuItemButton(
        key: const Key('track_action_add_to_queue'),
        leadingIcon: const Icon(Icons.queue_music, size: 16),
        onPressed: isMissing
            ? null
            : () {
                if (onAddToQueue != null) {
                  onAddToQueue();
                } else if (controller != null) {
                  controller.addToQueue([track.toAudioSource()]);
                }
              },
        child: Text(context.t('menu.addToQueue')),
      ),

      // 4. Add to playlist (hidden if missing or no collections)
      if (!isMissing && collections != null)
        SubmenuButton(
          key: const Key('track_action_add_to_playlist'),
          leadingIcon: const Icon(Icons.playlist_add, size: 16),
          menuChildren: [
            for (final pl in collections.playlists)
              MenuItemButton(
                key: Key('track_add_to_playlist_${pl.id}'),
                leadingIcon:
                    const Icon(Icons.queue_music, size: 16, color: AppColors.textSecondary),
                onPressed: () {
                  collections.addToPlaylist(pl.id, [track.path]);
                },
                child: Text(pl.name),
              ),
            MenuItemButton(
              key: const Key('track_action_new_playlist'),
              leadingIcon: const Icon(Icons.add, size: 16, color: AppColors.accent),
              onPressed: () {
                showCreatePlaylistDialog(
                  context,
                  collections: collections,
                  initialTrackPath: track.path,
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

      // 5. Favorite / Remove from favorites
      if (collections != null)
        MenuItemButton(
          key: const Key('track_action_favorite'),
          leadingIcon: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            size: 16,
            color: isFav ? AppColors.accent : null,
          ),
          onPressed: () {
            collections.toggleFavorite(track.path, track: track);
          },
          child: Text(
            isFav
                ? context.t('menu.removeFromFavorites')
                : context.t('menu.addToFavorites'),
          ),
        ),

      // 6. Rate (submenu 1..5 stars, clear)
      if (!isMissing && collections != null)
        SubmenuButton(
          key: const Key('track_action_rate'),
          leadingIcon: Icon(
            currentRating > 0 ? Icons.star : Icons.star_border,
            size: 16,
            color: currentRating > 0 ? AppColors.accent : null,
          ),
          menuChildren: [
            for (var s = 1; s <= 5; s++)
              MenuItemButton(
                key: Key('track_rate_$s'),
                leadingIcon: Icon(
                  currentRating >= s ? Icons.star : Icons.star_border,
                  size: 16,
                  color: currentRating >= s ? AppColors.accent : null,
                ),
                onPressed: () {
                  collections.setRating(track.path, s);
                },
                child: Text(
                  context.t('rating.stars',
                      args: {'stars': context.localizeDigitsText('$s')}),
                ),
              ),
            if (currentRating > 0)
              MenuItemButton(
                key: const Key('track_rate_clear'),
                leadingIcon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  collections.setRating(track.path, 0);
                },
                child: Text(context.t('rating.clear')),
              ),
          ],
          child: Text(context.t('menu.rate')),
        ),

      // 7. Playlist specific actions
      if (playlistId != null) ...[
        MenuItemButton(
          key: const Key('track_action_remove_from_playlist'),
          leadingIcon: const Icon(Icons.delete_outline, size: 16),
          onPressed: () {
            if (onRemoveFromPlaylist != null) {
              onRemoveFromPlaylist();
            } else if (playlistEntryId != null) {
              collections?.removeFromPlaylist(playlistId, [playlistEntryId]);
            }
          },
          child: Text(context.t('menu.removeFromPlaylist')),
        ),
        if (position != null && position > 0)
          MenuItemButton(
            key: const Key('track_action_move_up'),
            leadingIcon: const Icon(Icons.arrow_upward, size: 16),
            onPressed: () {
              if (onMoveUp != null) {
                onMoveUp();
              } else if (playlistEntryId != null) {
                collections?.moveEntry(playlistId, playlistEntryId, position - 1);
              }
            },
            child: Text(context.t('menu.moveUp')),
          ),
        if (position != null && totalCount != null && position < totalCount - 1)
          MenuItemButton(
            key: const Key('track_action_move_down'),
            leadingIcon: const Icon(Icons.arrow_downward, size: 16),
            onPressed: () {
              if (onMoveDown != null) {
                onMoveDown();
              } else if (playlistEntryId != null) {
                collections?.moveEntry(playlistId, playlistEntryId, position + 1);
              }
            },
            child: Text(context.t('menu.moveDown')),
          ),
      ],
    ];
  }

  /// Default menu style for TrackActionsMenu anchors.
  static MenuStyle get defaultMenuStyle => MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Color(0xFF1D1C25)),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.r12),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
      );
}

/// A wrapper widget that embeds a [MenuAnchor] for both right-click and "more" button actions.
class TrackActionsMenuAnchor extends StatefulWidget {
  /// Track data.
  final Track track;

  /// Whether file is missing.
  final bool isMissing;

  /// Audio controller.
  final PlaybackController? controller;

  /// User collections store.
  final UserCollections? userCollections;

  /// Playlist context.
  final int? playlistId;

  /// Playlist item entry ID.
  final int? playlistEntryId;

  /// Zero-based position in playlist.
  final int? position;

  /// Total count in playlist.
  final int? totalCount;

  /// Action callbacks.
  final VoidCallback? onPlay;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onRemoveFromPlaylist;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// Builder for child receiving the menu controller.
  final Widget Function(BuildContext context, MenuController controller) builder;

  /// Creates a [TrackActionsMenuAnchor].
  const TrackActionsMenuAnchor({
    super.key,
    required this.track,
    this.isMissing = false,
    this.controller,
    this.userCollections,
    this.playlistId,
    this.playlistEntryId,
    this.position,
    this.totalCount,
    this.onPlay,
    this.onPlayNext,
    this.onAddToQueue,
    this.onRemoveFromPlaylist,
    this.onMoveUp,
    this.onMoveDown,
    required this.builder,
  });

  @override
  State<TrackActionsMenuAnchor> createState() => _TrackActionsMenuAnchorState();
}

class _TrackActionsMenuAnchorState extends State<TrackActionsMenuAnchor> {
  final MenuController _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final collections =
        widget.userCollections ?? UserCollectionsScope.maybeOf(context);

    Widget buildMenu(BuildContext context) {
      return MenuAnchor(
        controller: _controller,
        style: TrackActionsMenu.defaultMenuStyle,
        menuChildren: TrackActionsMenu.buildMenuItems(
          context: context,
          track: widget.track,
          isMissing: widget.isMissing,
          controller: widget.controller,
          userCollections: collections,
          playlistId: widget.playlistId,
          playlistEntryId: widget.playlistEntryId,
          position: widget.position,
          totalCount: widget.totalCount,
          onPlay: widget.onPlay,
          onPlayNext: widget.onPlayNext,
          onAddToQueue: widget.onAddToQueue,
          onRemoveFromPlaylist: widget.onRemoveFromPlaylist,
          onMoveUp: widget.onMoveUp,
          onMoveDown: widget.onMoveDown,
        ),
        builder: (context, controller, child) {
          return widget.builder(context, controller);
        },
      );
    }

    if (collections != null) {
      return ListenableBuilder(
        listenable: collections,
        builder: (context, _) => buildMenu(context),
      );
    }
    return buildMenu(context);
  }
}
