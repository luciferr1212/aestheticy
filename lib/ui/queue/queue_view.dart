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
/// Features active playback order, distinct entry identity, user-queue sections,
/// animated drag reordering, track jumping, track deletion, clear actions, and playlist export.
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

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.controller.queue.currentIndex;

    _queueSub = widget.controller.queueChangeStream.listen((_) {
      if (mounted) {
        setState(() {});
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
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    final primaryFocus = FocusManager.instance.primaryFocus;
    final focusCtx = primaryFocus?.context;
    final isTextFieldFocused = focusCtx != null &&
        (focusCtx.widget is EditableText ||
            focusCtx.findAncestorWidgetOfExactType<EditableText>() != null);

    if (isTextFieldFocused) return KeyEventResult.ignored;

    if (isDeleteKey(event)) {
      if (_selectedIndex >= 0 && _selectedIndex < widget.controller.queue.length) {
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

    // Alt+Up and Alt+Down shortcuts to move selected upcoming row
    final isAlt = isAltModifierPressed();

    if (isAlt && isArrowUpKey(event)) {
      final curIdx = widget.controller.queue.currentIndex;
      if (_selectedIndex > curIdx + 1 && _selectedIndex < widget.controller.queue.length) {
        final from = _selectedIndex;
        final to = _selectedIndex - 1;
        widget.controller.moveInQueue(from, to);
        setState(() {
          _selectedIndex = to;
        });
        return KeyEventResult.handled;
      }
    } else if (isAlt && isArrowDownKey(event)) {
      final curIdx = widget.controller.queue.currentIndex;
      if (_selectedIndex > curIdx && _selectedIndex < widget.controller.queue.length - 1) {
        final from = _selectedIndex;
        final to = _selectedIndex + 1;
        widget.controller.moveInQueue(from, to);
        setState(() {
          _selectedIndex = to;
        });
        return KeyEventResult.handled;
      }
    } else if (!isAlt && isArrowDownKey(event)) {
      if (_selectedIndex < widget.controller.queue.length - 1) {
        setState(() {
          _selectedIndex++;
        });
        _scrollToIndex(_selectedIndex, smooth: true);
        return KeyEventResult.handled;
      }
    } else if (!isAlt && isArrowUpKey(event)) {
      if (_selectedIndex > 0) {
        setState(() {
          _selectedIndex--;
        });
        _scrollToIndex(_selectedIndex, smooth: true);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  Duration _calculateUpcomingDuration(List<QueueEntry> entries, int currentIndex) {
    var totalMs = 0;
    if (currentIndex >= 0 && currentIndex < entries.length) {
      for (var i = currentIndex + 1; i < entries.length; i++) {
        final ms = int.tryParse(entries[i].source.extras?['durationMs'] ?? '');
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
                final currentItems = widget.controller.queue.items;
                final paths = <String>[];
                var skippedCount = 0;

                for (final item in currentItems) {
                  final p = item.uri;
                  if (!p.startsWith('http://') && !p.startsWith('https://')) {
                    paths.add(p);
                  } else {
                    skippedCount++;
                  }
                }

                if (paths.isNotEmpty) {
                  await collections.addToPlaylist(pl.id, paths);
                }

                if (innerCtx.mounted) {
                  Navigator.of(innerCtx).pop(pl);
                  if (mounted) {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.clearSnackBars();
                    final msg = skippedCount > 0
                        ? context.t(
                            'queue.playlistSavedWithSkipped',
                            args: {
                              'name': pl.name,
                              'skipped': context.localizeDigitsText(skippedCount.toString()),
                            },
                          )
                        : context.t('queue.playlistSaved', args: {'name': pl.name});
                    final actionLabel = context.t('queue.viewPlaylist');
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(msg),
                        action: SnackBarAction(
                          label: actionLabel,
                          onPressed: () {
                            widget.navigator.openPlaylistDetail(pl.id, playlist: pl);
                          },
                        ),
                      ),
                    );
                  }
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
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
                  ],
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
                  child: Text(innerCtx.t('common.save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != null && mounted) {
      setState(() {});
    }
  }

  Widget _buildProxyDecorator(Widget child, int index, Animation<double> animation) {
    final reduceMotion = widget.settingsStore.settings.reduceMotion;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final animValue = reduceMotion
            ? 1.0
            : CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ).value;
        final scale = reduceMotion ? 1.0 : (1.0 + 0.025 * animValue);
        final opacity = reduceMotion ? 1.0 : (0.85 + 0.15 * animValue);
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Material(
              color: Colors.transparent,
              elevation: 0,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.controller.queue.entries;
    final currentIndex = widget.controller.queue.currentIndex;
    final currentEntry = widget.controller.queue.currentEntry;
    final hasUpcoming = currentIndex >= 0 && currentIndex < entries.length - 1;
    final upcomingDuration = _calculateUpcomingDuration(entries, currentIndex);

    // Identify upcoming groups for section headers
    var hasUpcomingUserQueued = false;
    var hasUpcomingContext = false;
    int? firstUpcomingUserQueuedIndex;
    int? firstUpcomingContextIndex;

    if (currentIndex >= 0) {
      for (var i = currentIndex + 1; i < entries.length; i++) {
        if (entries[i].isUserQueued) {
          hasUpcomingUserQueued = true;
          firstUpcomingUserQueuedIndex ??= i;
        } else {
          hasUpcomingContext = true;
          firstUpcomingContextIndex ??= i;
        }
      }
    }

    final showUpcomingHeaders = hasUpcomingUserQueued && hasUpcomingContext;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header bar
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('queue.title'),
                      style: AppTypography.display,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          context.t('queue.itemCount', args: {
                            'count': context.localizeDigitsText(entries.length.toString()),
                          }),
                          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                        ),
                        if (hasUpcoming && upcomingDuration > Duration.zero) ...[
                          Text(
                            ' • ',
                            style: AppTypography.body.copyWith(color: AppColors.textMuted),
                          ),
                          Text(
                            context.t('queue.upcomingDuration', args: {
                              'duration': context.formatDurationLocalized(upcomingDuration),
                            }),
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    GlassPillButton(
                      key: const Key('queue_clear_upcoming_button'),
                      label: context.t('queue.clearUpcoming'),
                      onPressed: hasUpcoming ? () => widget.controller.clearUpcoming() : null,
                    ),
                    GlassPillButton(
                      key: const Key('queue_clear_all_button'),
                      label: context.t('queue.clearAll'),
                      onPressed: entries.isNotEmpty ? _showClearAllDialog : null,
                    ),
                    GlassPillButton(
                      key: const Key('queue_save_playlist_button'),
                      variant: GlassButtonVariant.primary,
                      label: context.t('queue.saveAsPlaylist'),
                      onPressed: entries.isNotEmpty ? _showSavePlaylistDialog : null,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Content body
            Expanded(
              child: entries.isEmpty
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
                        buildDefaultDragHandles: false,
                        proxyDecorator: _buildProxyDecorator,
                        onReorderItem: (oldIndex, newIndex) {
                          widget.controller.moveInQueue(oldIndex, newIndex);
                        },
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final showUserHeader =
                              showUpcomingHeaders && index == firstUpcomingUserQueuedIndex;
                          final showContextHeader =
                              showUpcomingHeaders && index == firstUpcomingContextIndex;

                          String? headerLabel;
                          Key? headerKey;
                          if (showUserHeader) {
                            headerLabel = context.t('queue.nextInQueue');
                            headerKey = const Key('queue_section_next_in_queue');
                          } else if (showContextHeader) {
                            final album = currentEntry?.source.extras?['album'];
                            if (album != null && album.trim().isNotEmpty) {
                              headerLabel = context.t(
                                'queue.nextFromContext',
                                args: {'context': album.trim()},
                              );
                            } else {
                              headerLabel = context.t('queue.upNext');
                            }
                            headerKey = const Key('queue_section_next_from_context');
                          }

                          final rowWidget = _QueueRow(
                            key: ValueKey('queue_row_${entry.id}'),
                            index: index,
                            entry: entry,
                            currentIndex: currentIndex,
                            currentEntry: currentEntry,
                            isSelected: _selectedIndex == index,
                            controller: widget.controller,
                            navigator: widget.navigator,
                            userCollections: widget.userCollections,
                            totalCount: entries.length,
                            onSelect: () {
                              setState(() => _selectedIndex = index);
                              _focusNode.requestFocus();
                            },
                          );

                          if (headerLabel != null) {
                            return Container(
                              key: ValueKey('queue_row_container_${entry.id}'),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      start: 8,
                                      top: 14,
                                      bottom: 6,
                                      end: 8,
                                    ),
                                    child: Text(
                                      headerLabel,
                                      key: headerKey,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  rowWidget,
                                ],
                              ),
                            );
                          }

                          return rowWidget;
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

class _QueueRow extends StatefulWidget {
  final int index;
  final QueueEntry entry;
  final int currentIndex;
  final QueueEntry? currentEntry;
  final bool isSelected;
  final PlaybackController controller;
  final AppNavigator navigator;
  final UserCollections? userCollections;
  final int totalCount;
  final VoidCallback onSelect;

  const _QueueRow({
    super.key,
    required this.index,
    required this.entry,
    required this.currentIndex,
    required this.currentEntry,
    required this.isSelected,
    required this.controller,
    required this.navigator,
    required this.userCollections,
    required this.totalCount,
    required this.onSelect,
  });

  @override
  State<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<_QueueRow> {
  final MenuController _menuController = MenuController();
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isHistory = widget.currentIndex >= 0 && widget.index < widget.currentIndex;
    final isCurrent = widget.currentEntry != null && widget.entry.id == widget.currentEntry!.id;

    final source = widget.entry.source;
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

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onSecondaryTapUp: (details) {
          widget.onSelect();
          if (!_menuController.isOpen) {
            _menuController.open(position: details.localPosition);
          }
        },
        child: Opacity(
          opacity: isHistory ? 0.50 : 1.0,
          child: Container(
            height: 56.0,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AppColors.accentFill
                  : (isCurrent ? AppColors.fillControl : Colors.transparent),
              borderRadius: BorderRadius.circular(AppSpacing.r10),
              border: Border.all(
                color: widget.isSelected
                    ? AppColors.accent
                    : (isCurrent ? AppColors.accent.withValues(alpha: 0.3) : Colors.transparent),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSpacing.r10),
                onTap: () {
                  widget.onSelect();
                  widget.controller.playTrack(widget.index);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      // Drag handle
                      ReorderableDragStartListener(
                        index: widget.index,
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
                        _PlayingIndicator(controller: widget.controller),

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
                        menuController: _menuController,
                        isHovered: _isHovered,
                        index: widget.index,
                        source: source,
                        controller: widget.controller,
                        navigator: widget.navigator,
                        userCollections: widget.userCollections,
                        totalCount: widget.totalCount,
                      ),
                    ],
                  ),
                ),
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
  final MenuController menuController;
  final bool isHovered;
  final int index;
  final AudioSource source;
  final PlaybackController controller;
  final AppNavigator navigator;
  final UserCollections? userCollections;
  final int totalCount;

  const _QueueRowMenu({
    required this.menuController,
    required this.isHovered,
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
    final curIdx = controller.queue.currentIndex;

    return MenuAnchor(
      controller: menuController,
      builder: (context, ctrl, child) {
        return IconButton(
          key: Key('queue_row_menu_$index'),
          icon: Icon(
            Icons.more_horiz,
            size: 18,
            color: isHovered || ctrl.isOpen ? AppColors.text : AppColors.textMuted,
          ),
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

        // 2. Add to queue (adds ANOTHER copy at the end of the user block)
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
          onPressed: () => controller.removeFromQueue(index),
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

        // 7. Move up
        MenuItemButton(
          key: const Key('queue_menu_move_up'),
          leadingIcon: const Icon(Icons.arrow_upward, size: 16),
          onPressed: index > 0 ? () => controller.moveInQueue(index, index - 1) : null,
          child: Text(context.t('queue.moveUp')),
        ),

        // 8. Move down
        MenuItemButton(
          key: const Key('queue_menu_move_down'),
          leadingIcon: const Icon(Icons.arrow_downward, size: 16),
          onPressed:
              index < totalCount - 1 ? () => controller.moveInQueue(index, index + 1) : null,
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
