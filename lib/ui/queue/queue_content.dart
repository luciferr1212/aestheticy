import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyRepeatEvent;

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/collections/user_collections.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/app_shortcuts.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'widgets/queue_row.dart';

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

  /// Whether to use compact styling suitable for the docked side panel (280–320 px).
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
                    Flexible(
                      fit: FlexFit.loose,
                      child: GlassPillButton(
                        key: const Key('side_panel_queue_clear_upcoming'),
                        label: context.t('queue.clearUpcoming'),
                        size: GlassButtonSize.small,
                        onPressed: () => widget.controller.clearUpcoming(),
                      ),
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

                        final rowWidget = QueueRow(
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
