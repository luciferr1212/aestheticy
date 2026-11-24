import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyRepeatEvent;

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
import '../theme/interactive_cursor.dart';

/// Shared interactive playback queue list reused by the full [QueueView] page
/// and the compact docked [SidePanel].
class QueueContent extends StatefulWidget {
  /// The audio playback controller coordinating queue and engine.
  final PlaybackController controller;

  /// Application navigator for album/artist/playlist destinations.
  final AppNavigator navigator;

  /// Persistent user settings store.
  final SettingsStore settingsStore;

  /// User collections for favorites and playlist management.
  final UserCollections? userCollections;

  /// Whether to use compact styling suitable for the 360 px docked side panel.
  final bool compact;

  /// Whether the internal keyboard-navigation [Focus] node should autofocus.
  final bool autofocus;

  /// Optional padding applied to the scrollable list.
  final EdgeInsets? padding;

  /// Creates a [QueueContent].
  const QueueContent({
    super.key,
    required this.controller,
    required this.navigator,
    required this.settingsStore,
    this.userCollections,
    this.compact = false,
    this.autofocus = true,
    this.padding,
  });

  @override
  State<QueueContent> createState() => _QueueContentState();
}

class _QueueContentState extends State<QueueContent> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  StreamSubscription<void>? _queueSub;
  StreamSubscription<AudioSource?>? _currentSub;

  int? _selectedEntryId;
  int? _selectionAnchorEntryId;
  final Set<int> _selectedEntryIds = <int>{};
  bool _userScrolled = false;

  int get _resolvedSelectedIndex {
    final id = _selectedEntryId;
    if (id == null) return -1;
    return widget.controller.queue.indexOfEntryId(id);
  }

  @override
  void initState() {
    super.initState();
    final initialId = widget.controller.queue.currentEntry?.id;
    _selectedEntryId = initialId;
    _selectionAnchorEntryId = initialId;
    if (initialId != null) {
      _selectedEntryIds.add(initialId);
    }

    _queueSub = widget.controller.queueChangeStream.listen((_) {
      if (!mounted) return;
      final existingIds =
          widget.controller.queue.entries.map((e) => e.id).toSet();
      setState(() {
        _selectedEntryIds.removeWhere((id) => !existingIds.contains(id));
        if (_selectedEntryId != null && !existingIds.contains(_selectedEntryId)) {
          _selectedEntryId =
              _selectedEntryIds.isNotEmpty ? _selectedEntryIds.first : null;
        }
        if (_selectedEntryIds.isEmpty) {
          final fallbackCur = widget.controller.queue.currentEntry?.id;
          if (fallbackCur != null && existingIds.contains(fallbackCur)) {
            _selectedEntryId = fallbackCur;
            _selectedEntryIds.add(fallbackCur);
          }
        }
        if (_selectionAnchorEntryId != null &&
            !existingIds.contains(_selectionAnchorEntryId)) {
          _selectionAnchorEntryId = _selectedEntryId;
        }
      });
    });

    _currentSub = widget.controller.currentStream.listen((_) {
      if (!mounted) return;
      setState(() {});
      final cur = widget.controller.queue.currentIndex;
      if (!_userScrolled && cur >= 0) {
        _scrollToIndex(cur, smooth: !widget.settingsStore.settings.reduceMotion);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
    if (smooth && !widget.settingsStore.settings.reduceMotion) {
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
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final primaryFocus = FocusManager.instance.primaryFocus;
    final focusCtx = primaryFocus?.context;
    final isTextFieldFocused = focusCtx != null &&
        (focusCtx.widget is EditableText ||
            focusCtx.findAncestorWidgetOfExactType<EditableText>() != null);

    if (isTextFieldFocused) return KeyEventResult.ignored;

    final entries = widget.controller.queue.entries;

    if (isDeleteKey(event)) {
      final targetIds = _selectedEntryIds.isNotEmpty
          ? _selectedEntryIds.toSet()
          : (_selectedEntryId != null ? <int>{_selectedEntryId!} : <int>{});
      if (targetIds.isNotEmpty) {
        var earliestRemovedIdx = -1;
        for (var i = 0; i < entries.length; i++) {
          if (targetIds.contains(entries[i].id)) {
            earliestRemovedIdx = i;
            break;
          }
        }
        if (earliestRemovedIdx >= 0) {
          int? nextSelectedId;
          for (var i = earliestRemovedIdx; i < entries.length; i++) {
            if (!targetIds.contains(entries[i].id)) {
              nextSelectedId = entries[i].id;
              break;
            }
          }
          if (nextSelectedId == null) {
            for (var i = earliestRemovedIdx - 1; i >= 0; i--) {
              if (!targetIds.contains(entries[i].id)) {
                nextSelectedId = entries[i].id;
                break;
              }
            }
          }

          setState(() {
            _selectedEntryId = nextSelectedId;
            _selectionAnchorEntryId = nextSelectedId;
            _selectedEntryIds
              ..clear()
              ..addAll(nextSelectedId != null ? [nextSelectedId] : const []);
          });
          widget.controller.removeEntriesFromQueue(targetIds);
          return KeyEventResult.handled;
        }
      }
    }

    // Alt+Up and Alt+Down shortcuts to move selected upcoming row
    final isAlt = isAltModifierPressed();
    final isShift = isShiftModifierPressed();
    final selectedIdx = _resolvedSelectedIndex;

    if (isAlt && isArrowUpKey(event)) {
      final curIdx = widget.controller.queue.currentIndex;
      if (selectedIdx > curIdx + 1 && selectedIdx < entries.length) {
        final to = selectedIdx - 1;
        widget.controller.moveInQueue(selectedIdx, to);
        return KeyEventResult.handled;
      }
    } else if (isAlt && isArrowDownKey(event)) {
      final curIdx = widget.controller.queue.currentIndex;
      if (selectedIdx > curIdx && selectedIdx < entries.length - 1) {
        final to = selectedIdx + 1;
        widget.controller.moveInQueue(selectedIdx, to);
        return KeyEventResult.handled;
      }
    } else if (!isAlt && isArrowDownKey(event)) {
      if (entries.isEmpty) return KeyEventResult.ignored;
      final nextIdx = selectedIdx < 0
          ? 0
          : (selectedIdx < entries.length - 1 ? selectedIdx + 1 : selectedIdx);
      if (selectedIdx < entries.length - 1) {
        final nextEntry = entries[nextIdx];
        setState(() {
          _selectedEntryId = nextEntry.id;
          if (isShift && _selectionAnchorEntryId != null) {
            final anchorIdx =
                widget.controller.queue.indexOfEntryId(_selectionAnchorEntryId!);
            if (anchorIdx >= 0) {
              final lo = anchorIdx < nextIdx ? anchorIdx : nextIdx;
              final hi = anchorIdx > nextIdx ? anchorIdx : nextIdx;
              _selectedEntryIds
                ..clear()
                ..addAll([for (var i = lo; i <= hi; i++) entries[i].id]);
            }
          } else {
            _selectionAnchorEntryId = nextEntry.id;
            _selectedEntryIds
              ..clear()
              ..add(nextEntry.id);
          }
        });
        _scrollToIndex(nextIdx, smooth: true);
        return KeyEventResult.handled;
      }
    } else if (!isAlt && isArrowUpKey(event)) {
      if (entries.isEmpty) return KeyEventResult.ignored;
      final prevIdx = selectedIdx < 0
          ? entries.length - 1
          : (selectedIdx > 0 ? selectedIdx - 1 : 0);
      if (selectedIdx > 0 || selectedIdx < 0) {
        final prevEntry = entries[prevIdx];
        setState(() {
          _selectedEntryId = prevEntry.id;
          if (isShift && _selectionAnchorEntryId != null) {
            final anchorIdx =
                widget.controller.queue.indexOfEntryId(_selectionAnchorEntryId!);
            if (anchorIdx >= 0) {
              final lo = anchorIdx < prevIdx ? anchorIdx : prevIdx;
              final hi = anchorIdx > prevIdx ? anchorIdx : prevIdx;
              _selectedEntryIds
                ..clear()
                ..addAll([for (var i = lo; i <= hi; i++) entries[i].id]);
            }
          } else {
            _selectionAnchorEntryId = prevEntry.id;
            _selectedEntryIds
              ..clear()
              ..add(prevEntry.id);
          }
        });
        _scrollToIndex(prevIdx, smooth: true);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _handleRowSelection(QueueEntry entry, int index, List<QueueEntry> entries) {
    final isCtrl = isCtrlModifierPressed();
    final isShift = isShiftModifierPressed();

    setState(() {
      if (isShift && _selectionAnchorEntryId != null) {
        final anchorIdx =
            widget.controller.queue.indexOfEntryId(_selectionAnchorEntryId!);
        if (anchorIdx >= 0) {
          final lo = anchorIdx < index ? anchorIdx : index;
          final hi = anchorIdx > index ? anchorIdx : index;
          _selectedEntryIds
            ..clear()
            ..addAll([for (var i = lo; i <= hi; i++) entries[i].id]);
          _selectedEntryId = entry.id;
          return;
        }
      }
      if (isCtrl) {
        if (!_selectedEntryIds.remove(entry.id)) {
          _selectedEntryIds.add(entry.id);
        }
        _selectedEntryId = entry.id;
        _selectionAnchorEntryId = entry.id;
        return;
      }
      _selectedEntryId = entry.id;
      _selectionAnchorEntryId = entry.id;
      _selectedEntryIds
        ..clear()
        ..add(entry.id);
    });
  }

  Widget _buildProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
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
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.compact && entries.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 12,
                end: 12,
                bottom: 6,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.t(
                        'queue.itemCount',
                        args: {
                          'count': context.formatCountLocalized(entries.length),
                        },
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (hasUpcoming) ...[
                    const SizedBox(width: 8),
                    GlassPillButton(
                      key: const Key('side_panel_queue_clear_upcoming'),
                      label: context.t('queue.clearUpcoming'),
                      size: GlassButtonSize.small,
                      onPressed: () => widget.controller.clearUpcoming(),
                    ),
                  ],
                ],
              ),
            ),
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
                      padding: widget.padding ??
                          (widget.compact
                              ? const EdgeInsets.symmetric(horizontal: 6)
                              : null),
                      buildDefaultDragHandles: false,
                      proxyDecorator: _buildProxyDecorator,
                      onReorderItem: (oldIndex, newIndex) {
                        widget.controller.moveInQueue(oldIndex, newIndex);
                      },
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final showUserHeader = showUpcomingHeaders &&
                            index == firstUpcomingUserQueuedIndex;
                        final showContextHeader = showUpcomingHeaders &&
                            index == firstUpcomingContextIndex;

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
                          headerKey =
                              const Key('queue_section_next_from_context');
                        }

                        final rowWidget = _QueueRow(
                          key: ValueKey('queue_row_${entry.id}'),
                          index: index,
                          entry: entry,
                          currentIndex: currentIndex,
                          currentEntry: currentEntry,
                          isSelected: _selectedEntryIds.contains(entry.id),
                          compact: widget.compact,
                          controller: widget.controller,
                          navigator: widget.navigator,
                          userCollections: widget.userCollections,
                          totalCount: entries.length,
                          onSelect: ({bool playIfPlain = false}) {
                            final isModified =
                                isCtrlModifierPressed() || isShiftModifierPressed();
                            _handleRowSelection(entry, index, entries);
                            _focusNode.requestFocus();
                            if (playIfPlain && !isModified) {
                              widget.controller.playTrack(index);
                            }
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
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.compact ? 20 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.queue_music,
              size: widget.compact ? 40 : 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              context.t('queue.emptyTitle'),
              textAlign: TextAlign.center,
              style: AppTypography.title.copyWith(color: AppColors.text),
            ),
            const SizedBox(height: 4),
            Text(
              context.t('queue.emptyHint'),
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
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
  final bool compact;
  final PlaybackController controller;
  final AppNavigator navigator;
  final UserCollections? userCollections;
  final int totalCount;
  final void Function({bool playIfPlain}) onSelect;

  const _QueueRow({
    super.key,
    required this.index,
    required this.entry,
    required this.currentIndex,
    required this.currentEntry,
    required this.isSelected,
    required this.compact,
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
    final isHistory =
        widget.currentIndex >= 0 && widget.index < widget.currentIndex;
    final isCurrent = widget.currentEntry != null &&
        widget.entry.id == widget.currentEntry!.id;

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
      cursor: isHistory ? SystemMouseCursors.basic : SystemMouseCursors.click,
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
                    : (isCurrent
                        ? AppColors.accent.withValues(alpha: 0.3)
                        : Colors.transparent),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                mouseCursor: isHistory
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                hoverColor: const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(AppSpacing.r10),
                onTap: () {
                  widget.onSelect(playIfPlain: true);
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? 6 : 8,
                  ),
                  child: Row(
                    children: [
                      // Drag handle
                      ReorderableDragStartListener(
                        index: widget.index,
                        child: DragHandleCursor(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: widget.compact ? 2 : 4,
                            ),
                            child: const Icon(
                              Icons.drag_indicator,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Cover thumbnail (36x36)
                      _buildCover(coverKey),
                      SizedBox(width: widget.compact ? 10 : 12),

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
                                  ? AppTypography.bodyStrong
                                      .copyWith(color: AppColors.accent)
                                  : AppTypography.bodyStrong
                                      .copyWith(color: AppColors.text),
                            ),
                            Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: textDirectionFor(artist),
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!widget.compact) ...[
                        const SizedBox(width: 8),

                        // Album
                        Expanded(
                          flex: 3,
                          child: Text(
                            album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: textDirectionFor(album),
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textMuted),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Duration
                        SizedBox(
                          width: 48,
                          child: Text(
                            durationText,
                            textAlign: TextAlign.end,
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textMuted),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Favorite button
                        _QueueFavoriteButton(path: source.uri),
                      ],
                      const SizedBox(width: 4),

                      if (widget.compact)
                        IconButton(
                          key: Key('queue_row_remove_${widget.index}'),
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            color: _isHovered
                                ? AppColors.text
                                : AppColors.textMuted,
                          ),
                          tooltip: context.t('queue.remove'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          onPressed: () =>
                              widget.controller.removeEntryFromQueue(widget.entry.id),
                        ),

                      // More actions menu
                      _QueueRowMenu(
                        menuController: _menuController,
                        isHovered: _isHovered,
                        compact: widget.compact,
                        index: widget.index,
                        entryId: widget.entry.id,
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
    File? coverFile;
    if (coverKey != null && coverKey.isNotEmpty) {
      try {
        if (CoverCache.hasCover(coverKey)) {
          coverFile = File(CoverCache.pathFor(coverKey));
        }
      } on StateError {
        coverFile = null;
      }
    }
    if (coverFile != null) {
      imageWidget = Image.file(
        coverFile,
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
          message:
              isFav ? context.t('track.unfavorite') : context.t('track.favorite'),
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
  final bool compact;
  final int index;
  final int entryId;
  final AudioSource source;
  final PlaybackController controller;
  final AppNavigator navigator;
  final UserCollections? userCollections;
  final int totalCount;

  const _QueueRowMenu({
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
