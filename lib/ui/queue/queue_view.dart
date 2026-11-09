import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/collections/user_collections.dart';
import '../../library/cover_cache.dart';
import '../../library/models.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../library/track_actions_menu.dart';
import '../settings/app_shortcuts.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Full-page interactive playback queue view.
///
/// Features active playback order, history / current / upcoming visual groups,
/// drag reordering, track jumping, track deletion, clear actions, and playlist export.
class QueueView extends StatefulWidget {
  /// The audio playback controller coordinating queue and engine.
  final PlaybackController controller;

  /// Application navigator.
  final AppNavigator navigator;

  /// User settings store.
  final SettingsStore settingsStore;

  /// User collections for favorites and playlist management.
  final UserCollections? userCollections;

  /// Creates a [QueueView].
  const QueueView({
    super.key,
    required this.controller,
    required this.navigator,
    required this.settingsStore,
    this.userCollections,
  });

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  StreamSubscription<void>? _queueSub;
  StreamSubscription<AudioSource?>? _currentSub;

  int _selectedIndex = -1;
  bool _userScrolled = false;

  int _nextKeyId = 0;
  final List<int> _keyIds = [];

  @override
  void initState() {
    super.initState();
    _syncKeyIds();
    _selectedIndex = widget.controller.queue.currentIndex;

    _queueSub = widget.controller.queueChangeStream.listen((_) {
      if (mounted) {
        setState(() {
          _syncKeyIds();
        });
      }
    });

    _currentSub = widget.controller.currentStream.listen((_) {
      if (mounted) {
        setState(() {});
        final cur = widget.controller.queue.currentIndex;
        if (!_userScrolled && cur >= 0) {
          _scrollToIndex(cur, smooth: !widget.settingsStore.settings.reduceMotion);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cur = widget.controller.queue.currentIndex;
      if (cur >= 0) {
        _scrollToIndex(cur, smooth: false);
      }
    });
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _currentSub?.cancel();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _syncKeyIds() {
    final len = widget.controller.queue.length;
    if (_keyIds.length < len) {
      while (_keyIds.length < len) {
        _keyIds.add(_nextKeyId++);
      }
    } else if (_keyIds.length > len) {
      _keyIds.length = len;
    }
  }

  void _scrollToIndex(int index, {required bool smooth}) {
    if (!_scrollController.hasClients || index < 0) return;
    const itemExtent = 56.0;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final targetOffset = (index * itemExtent - 120.0).clamp(0.0, maxScroll);
    if (smooth) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(targetOffset);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (isDeleteKey(event)) {
      final primaryFocus = FocusManager.instance.primaryFocus;
      final focusCtx = primaryFocus?.context;
      final isTextFieldFocused = focusCtx != null &&
          (focusCtx.widget is EditableText ||
              focusCtx.findAncestorWidgetOfExactType<EditableText>() != null);

      if (!isTextFieldFocused &&
          _selectedIndex >= 0 &&
          _selectedIndex < widget.controller.queue.length) {
        final toRemove = _selectedIndex;
        widget.controller.removeFromQueue(toRemove);
        setState(() {
          if (widget.controller.queue.length <= 1) {
            _selectedIndex = -1;
          } else if (_selectedIndex >= widget.controller.queue.length - 1) {
            _selectedIndex = widget.controller.queue.length - 2;
          }
        });
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  Duration _calculateUpcomingDuration(List<AudioSource> items, int currentIndex) {
    var totalMs = 0;
    if (currentIndex >= 0 && currentIndex < items.length) {
      for (var i = currentIndex + 1; i < items.length; i++) {
        final ms = int.tryParse(items[i].extras?['durationMs'] ?? '');
        if (ms != null && ms > 0) totalMs += ms;
      }
    }
    return Duration(milliseconds: totalMs);
  }

  Future<void> _showClearAllDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.r16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          dialogCtx.t('queue.clearAllTitle'),
          style: AppTypography.title.copyWith(color: AppColors.text),
        ),
        content: Text(
          dialogCtx.t('queue.clearAllConfirm'),
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            key: const Key('queue_clear_all_cancel_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(dialogCtx.t('common.cancel')),
          ),
          ElevatedButton(
            key: const Key('queue_clear_all_confirm_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(dialogCtx.t('common.delete')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.controller.stop();
      widget.controller.queue.clear();
      widget.controller.notifyQueueChanged();
      setState(() {
        _selectedIndex = -1;
      });
    }
  }

  Future<void> _showSavePlaylistDialog() async {
    final now = DateTime.now();
    final datePart =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final defaultName =
        '${context.t('queue.defaultPlaylistPrefix')} ${context.localizeDigitsText(datePart)}';

    final collections = widget.userCollections ?? UserCollectionsScope.maybeOf(context);
    if (collections == null) return;

    final textCtrl = TextEditingController(text: defaultName);
    String? errorMessage;

    final created = await showDialog<PlaylistSummary>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (innerCtx, setDialogState) {
            void validateAndSubmit() async {
              final trimmed = textCtrl.text.trim();
              if (trimmed.isEmpty) {
                setDialogState(() => errorMessage = innerCtx.t('playlist.nameEmpty'));
                return;
              }
              if (trimmed.length > 60) {
                setDialogState(() => errorMessage = innerCtx.t('playlist.nameTooLong'));
                return;
              }
              final duplicate = collections.playlists.any(
                (p) => p.name.trim().toLowerCase() == trimmed.toLowerCase(),
              );
              if (duplicate) {
                setDialogState(() => errorMessage = innerCtx.t('playlist.nameDuplicate'));
                return;
              }

              try {
                final pl = await collections.createPlaylist(trimmed);
                if (innerCtx.mounted) {
                  Navigator.of(innerCtx).pop(pl);
                }
              } catch (e) {
                setDialogState(() => errorMessage = e.toString());
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.r16),
                side: const BorderSide(color: AppColors.border),
              ),
              title: Text(
                innerCtx.t('queue.savePlaylistTitle'),
                style: AppTypography.title.copyWith(color: AppColors.text),
              ),
              content: SizedBox(
                width: 360,
                child: TextField(
                  key: const Key('save_queue_playlist_text_field'),
                  controller: textCtrl,
                  autofocus: true,
                  style: AppTypography.body.copyWith(color: AppColors.text),
                  decoration: InputDecoration(
                    hintText: innerCtx.t('queue.savePlaylistHint'),
                    errorText: errorMessage,
                    isDense: true,
                  ),
                  onChanged: (_) {
                    if (errorMessage != null) {
                      setDialogState(() => errorMessage = null);
                    }
                  },
                  onSubmitted: (_) => validateAndSubmit(),
                ),
              ),
              actions: [
                TextButton(
                  key: const Key('save_queue_playlist_cancel_button'),
                  onPressed: () => Navigator.of(innerCtx).pop(null),
                  child: Text(innerCtx.t('common.cancel')),
                ),
                ElevatedButton(
                  key: const Key('save_queue_playlist_submit_button'),
                  onPressed: validateAndSubmit,
                  child: Text(innerCtx.t('common.create')),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != null && mounted) {
      final items = widget.controller.queue.items;
      final validPaths = <String>[];
      var skippedCount = 0;
      for (final item in items) {
        final uri = item.uri.trim();
        if (uri.isNotEmpty && !uri.startsWith('http://') && !uri.startsWith('https://')) {
          validPaths.add(uri);
        } else {
          skippedCount++;
        }
      }

      if (validPaths.isNotEmpty) {
        await collections.addToPlaylist(created.id, validPaths);
      }

      if (mounted) {
        final message = skippedCount > 0
            ? context.t('queue.playlistSavedWithSkipped', args: {
                'name': created.name,
                'skipped': context.formatCountLocalized(skippedCount),
              })
            : context.t('queue.playlistSaved', args: {'name': created.name});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            action: SnackBarAction(
              label: context.t('queue.viewPlaylist'),
              onPressed: () => widget.navigator.openPlaylistDetail(created.id, playlist: created),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.controller.queue.items;
    final currentIndex = widget.controller.queue.currentIndex;
    final hasUpcoming = currentIndex >= 0 && currentIndex < items.length - 1;
    final upcomingDuration = _calculateUpcomingDuration(items, currentIndex);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.t('queue.title'),
                      style: AppTypography.display.copyWith(color: AppColors.text),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      context.t('queue.itemCount', args: {
                        'count': context.formatCountLocalized(items.length),
                      }),
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                    ),
                    if (upcomingDuration > Duration.zero) ...[
                      const SizedBox(width: 8),
                      Text(
                        '•',
                        style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.t('queue.upcomingDuration', args: {
                          'duration': context.formatDurationLocalized(upcomingDuration),
                        }),
                        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlassPillButton(
                      key: const Key('queue_clear_upcoming_button'),
                      label: context.t('queue.clearUpcoming'),
                      onPressed: hasUpcoming ? () => widget.controller.clearUpcoming() : null,
                    ),
                    const SizedBox(width: 8),
                    GlassPillButton(
                      key: const Key('queue_clear_all_button'),
                      label: context.t('queue.clearAll'),
                      onPressed: items.isNotEmpty ? _showClearAllDialog : null,
                    ),
                    const SizedBox(width: 8),
                    GlassPillButton(
                      key: const Key('queue_save_playlist_button'),
                      variant: GlassButtonVariant.primary,
                      label: context.t('queue.saveAsPlaylist'),
                      onPressed: items.isNotEmpty ? _showSavePlaylistDialog : null,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Content body
            Expanded(
              child: items.isEmpty
                  ? _buildEmptyState(context)
                  : NotificationListener<ScrollUpdateNotification>(
                      onNotification: (notif) {
                        if (notif.dragDetails != null) {
                          _userScrolled = true;
                        }
                        return false;
                      },
                      child: ReorderableListView.builder(
                        scrollController: _scrollController,
                        itemExtent: 56.0,
                        buildDefaultDragHandles: false,
                        onReorderItem: (oldIndex, newIndex) {
                          if (oldIndex < _keyIds.length && newIndex < _keyIds.length) {
                            final k = _keyIds.removeAt(oldIndex);
                            _keyIds.insert(newIndex, k);
                          }
                          widget.controller.moveInQueue(oldIndex, newIndex);
                        },
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final source = items[index];
                          final keyId = index < _keyIds.length ? _keyIds[index] : index;
                          return _QueueRow(
                            key: ValueKey('queue_row_$keyId'),
                            index: index,
                            source: source,
                            currentIndex: currentIndex,
                            isSelected: _selectedIndex == index,
                            controller: widget.controller,
                            navigator: widget.navigator,
                            userCollections: widget.userCollections,
                            totalCount: items.length,
                            onSelect: () {
                              setState(() => _selectedIndex = index);
                              _focusNode.requestFocus();
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.queue_music, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            context.t('queue.emptyTitle'),
            style: AppTypography.title.copyWith(color: AppColors.text),
          ),
          const SizedBox(height: 4),
          Text(
            context.t('queue.emptyHint'),
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final int index;
  final AudioSource source;
  final int currentIndex;
  final bool isSelected;
  final PlaybackController controller;
  final AppNavigator navigator;
  final UserCollections? userCollections;
  final int totalCount;
  final VoidCallback onSelect;

  const _QueueRow({
    super.key,
    required this.index,
    required this.source,
    required this.currentIndex,
    required this.isSelected,
    required this.controller,
    required this.navigator,
    required this.userCollections,
    required this.totalCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isHistory = currentIndex >= 0 && index < currentIndex;
    final isCurrent = currentIndex >= 0 && index == currentIndex;

    final extras = source.extras;
    final title = extras?['title'] ?? context.t('library.unknownTitle');
    final rawArtist = extras?['artist'];
    final artist = (rawArtist != null && rawArtist.isNotEmpty)
        ? context.displayArtist(rawArtist)
        : '—';
    final album = extras?['album'] ?? '';
    final durationMsStr = extras?['durationMs'];
    final durationMs = int.tryParse(durationMsStr ?? '');
    final durationText = durationMs != null
        ? context.formatDurationLocalized(Duration(milliseconds: durationMs))
        : '—';
    final coverKey = extras?['coverKey'];

    return Opacity(
      opacity: isHistory ? 0.50 : 1.0,
      child: Container(
        height: 56.0,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentFill
              : (isCurrent ? AppColors.fillControl : Colors.transparent),
          borderRadius: BorderRadius.circular(AppSpacing.r10),
          border: Border.all(
            color: isSelected
                ? AppColors.accent
                : (isCurrent ? AppColors.accent.withValues(alpha: 0.3) : Colors.transparent),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.r10),
            onTap: () {
              onSelect();
              controller.playTrack(index);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  // Drag handle
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.drag_indicator, size: 18, color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Cover thumbnail (36x36)
                  _buildCover(coverKey),
                  const SizedBox(width: 12),

                  // Current playing/paused indicator
                  if (isCurrent)
                    _PlayingIndicator(controller: controller),

                  // Title & Artist
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: textDirectionFor(title),
                          style: isCurrent
                              ? AppTypography.bodyStrong.copyWith(color: AppColors.accent)
                              : AppTypography.bodyStrong.copyWith(color: AppColors.text),
                        ),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: textDirectionFor(artist),
                          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Album
                  Expanded(
                    flex: 3,
                    child: Text(
                      album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: textDirectionFor(album),
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Duration
                  SizedBox(
                    width: 48,
                    child: Text(
                      durationText,
                      textAlign: TextAlign.end,
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Favorite button
                  _QueueFavoriteButton(path: source.uri),
                  const SizedBox(width: 4),

                  // More actions menu
                  _QueueRowMenu(
                    index: index,
                    source: source,
                    controller: controller,
                    navigator: navigator,
                    userCollections: userCollections,
                    totalCount: totalCount,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(String? coverKey) {
    Widget imageWidget;
    if (coverKey != null && CoverCache.hasCover(coverKey)) {
      final file = File(CoverCache.pathFor(coverKey));
      imageWidget = Image.file(
        file,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        cacheWidth: 72,
        cacheHeight: 72,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else {
      imageWidget = _buildPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.r10),
      child: SizedBox(
        width: 36,
        height: 36,
        child: imageWidget,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF22212C),
        borderRadius: BorderRadius.circular(AppSpacing.r10),
      ),
      child: const Center(
        child: Icon(
          Icons.music_note,
          color: Colors.white24,
          size: 18,
        ),
      ),
    );
  }
}

class _QueueFavoriteButton extends StatelessWidget {
  final String path;

  const _QueueFavoriteButton({required this.path});

  @override
  Widget build(BuildContext context) {
    final collections = UserCollectionsScope.maybeOf(context);
    if (collections == null || path.isEmpty) return const SizedBox(width: 24);

    return ListenableBuilder(
      listenable: collections,
      builder: (context, _) {
        final isFav = collections.isFavorite(path);
        return Tooltip(
          message: isFav ? context.t('track.unfavorite') : context.t('track.favorite'),
          child: InkResponse(
            radius: 12,
            onTap: () => collections.toggleFavorite(path),
            child: SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  size: 16,
                  color: isFav ? AppColors.accent : AppColors.textMuted,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QueueRowMenu extends StatelessWidget {
  final int index;
  final AudioSource source;
  final PlaybackController controller;
  final AppNavigator navigator;
  final UserCollections? userCollections;
  final int totalCount;

  const _QueueRowMenu({
    required this.index,
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

    return MenuAnchor(
      builder: (context, controller, child) {
        return IconButton(
          key: Key('queue_row_menu_$index'),
          icon: const Icon(Icons.more_horiz, size: 18, color: AppColors.textMuted),
          splashRadius: 14,
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
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

        // 2. Remove
        MenuItemButton(
          key: const Key('queue_menu_remove'),
          leadingIcon: const Icon(Icons.delete_outline, size: 16),
          onPressed: () => controller.removeFromQueue(index),
          child: Text(context.t('queue.remove')),
        ),

        // 3. Add to playlist
        if (collections != null && path.isNotEmpty)
          SubmenuButton(
            key: const Key('queue_menu_add_to_playlist'),
            leadingIcon: const Icon(Icons.playlist_add, size: 16),
            menuChildren: [
              for (final pl in collections.playlists)
                MenuItemButton(
                  key: Key('queue_menu_playlist_${pl.id}'),
                  leadingIcon:
                      const Icon(Icons.queue_music, size: 16, color: AppColors.textSecondary),
                  onPressed: () => collections.addToPlaylist(pl.id, [path]),
                  child: Text(pl.name),
                ),
              MenuItemButton(
                key: const Key('queue_menu_new_playlist'),
                leadingIcon: const Icon(Icons.add, size: 16, color: AppColors.accent),
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

        // 4. Move up
        MenuItemButton(
          key: const Key('queue_menu_move_up'),
          leadingIcon: const Icon(Icons.arrow_upward, size: 16),
          onPressed: index > 0 ? () => controller.moveInQueue(index, index - 1) : null,
          child: Text(context.t('queue.moveUp')),
        ),

        // 5. Move down
        MenuItemButton(
          key: const Key('queue_menu_move_down'),
          leadingIcon: const Icon(Icons.arrow_downward, size: 16),
          onPressed:
              index < totalCount - 1 ? () => controller.moveInQueue(index, index + 1) : null,
          child: Text(context.t('queue.moveDown')),
        ),

        // 6. Go to album
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

        // 7. Go to artist
        if (rawArtist != null && rawArtist.isNotEmpty)
          MenuItemButton(
            key: const Key('queue_menu_go_to_artist'),
            leadingIcon: const Icon(Icons.person_outline, size: 16),
            onPressed: () => navigator.openArtistDetail(
              rawArtist,
              artist: ArtistSummary(name: rawArtist, albumCount: 0, trackCount: 0),
            ),
            child: Text(context.t('queue.goToArtist')),
          ),
      ],
    );
  }
}

class _PlayingIndicator extends StatefulWidget {
  final PlaybackController controller;

  const _PlayingIndicator({required this.controller});

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator> {
  StreamSubscription<PlaybackState>? _sub;
  late PlaybackState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.controller.currentState;
    _sub = widget.controller.stateStream.listen((s) {
      if (mounted) {
        setState(() {
          _state = s;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _state == PlaybackState.playing;
    return Container(
      key: const Key('queue_playing_indicator'),
      margin: const EdgeInsetsDirectional.only(end: 8),
      child: Icon(
        isPlaying ? Icons.play_arrow : Icons.pause,
        size: 16,
        color: AppColors.accent,
      ),
    );
  }
}
