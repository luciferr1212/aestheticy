import 'dart:async';

import 'package:flutter/material.dart';

import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Shared top header displayed on Albums, Artists, and Tracks list screens.
///
/// Encapsulates greeting line, display title, debounced search field with Ctrl+K chip,
/// sort popup selector, item count, and optional view-mode switcher.
class LibraryHeader extends StatefulWidget {
  /// Screen display title (e.g. Albums, Artists, Tracks).
  final String title;

  /// Settings store for resolving userName and persisting sort/view preferences.
  final SettingsStore settingsStore;

  /// Total count of items currently displayed.
  final int itemCount;

  /// Label for the item count (e.g. albums, artists, tracks).
  final String itemCountLabel;

  /// Callback when debounced search query changes.
  final ValueChanged<String> onSearchChanged;

  /// Active search query for populating the controller.
  final String searchQuery;

  /// List of sort keys allowed for this screen.
  final List<String> sortOptions;

  /// Current active sort key.
  final String currentSort;

  /// Callback when a new sort option is selected.
  final ValueChanged<String> onSortChanged;

  /// Optional active view mode for Albums ('square', 'wide', 'list').
  final String? viewMode;

  /// Optional callback when view mode changes.
  final ValueChanged<String>? onViewModeChanged;

  /// Creates a [LibraryHeader].
  const LibraryHeader({
    super.key,
    required this.title,
    required this.settingsStore,
    required this.itemCount,
    required this.itemCountLabel,
    required this.onSearchChanged,
    this.searchQuery = '',
    required this.sortOptions,
    required this.currentSort,
    required this.onSortChanged,
    this.viewMode,
    this.onViewModeChanged,
  });

  @override
  State<LibraryHeader> createState() => _LibraryHeaderState();
}

class _LibraryHeaderState extends State<LibraryHeader> {
  late final TextEditingController _controller;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchQuery);
  }

  @override
  void didUpdateWidget(covariant LibraryHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != _controller.text) {
      _controller.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChange(String text) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      widget.onSearchChanged(text);
    });
  }

  String _formatGreeting(BuildContext context) {
    final key = greetingKey(DateTime.now());
    final baseGreeting = context.t(key);
    final userName = widget.settingsStore.settings.userName.trim();
    if (userName.isNotEmpty) {
      return '$baseGreeting, $userName';
    }
    return baseGreeting;
  }

  void _showSortMenu(BuildContext context, Offset position) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: const Color(0xFF1D1C25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.r12),
        side: const BorderSide(color: AppColors.border),
      ),
      items: widget.sortOptions.map((opt) {
        final isSelected = opt == widget.currentSort;
        return PopupMenuItem<String>(
          value: opt,
          child: Row(
            children: [
              if (isSelected)
                const Icon(Icons.check, size: 16, color: AppColors.accent)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              Text(
                context.t('sort.$opt'),
                style: AppTypography.body.copyWith(
                  color: isSelected ? AppColors.accent : AppColors.text,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((selected) {
      if (selected != null) {
        widget.onSortChanged(selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final greeting = _formatGreeting(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top row: Greeting + Title and Search
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Left: Greeting + Title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    greeting,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.title,
                    style: AppTypography.display.copyWith(
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            // Right: Glass Search Field
            SizedBox(
              width: 260,
              height: 40,
              child: GlassSurface(
                borderRadius: AppSpacing.r12,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search,
                      color: AppColors.textMuted,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('library_search_field'),
                        controller: _controller,
                        onChanged: _onTextChange,
                        style: AppTypography.body.copyWith(color: AppColors.text),
                        decoration: InputDecoration(
                          hintText: context.t('common.search'),
                          hintStyle: AppTypography.body.copyWith(
                            color: AppColors.textMuted,
                          ),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_controller.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        color: AppColors.textMuted,
                        onPressed: () {
                          _controller.clear();
                          widget.onSearchChanged('');
                        },
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x1AFFFFFF),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Text(
                          context.t('common.searchShortcut'),
                          style: AppTypography.micro.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Toolbar row: Sort chip, Item count, and optional View-mode toggle
        Row(
          children: [
            // Sort chip
            Builder(
              builder: (sortCtx) {
                return GlassPillButton(
                  key: const Key('sort_button'),
                  label: '${context.t('common.sort')}: ${context.t('sort.${widget.currentSort}')}',
                  leadingIcon: Icons.sort,
                  size: GlassButtonSize.small,
                  onPressed: () {
                    final box = sortCtx.findRenderObject() as RenderBox?;
                    final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
                    _showSortMenu(context, pos + Offset(0, box?.size.height ?? 32));
                  },
                );
              },
            ),
            const SizedBox(width: 16),

            // Item count label
            Text(
              '${widget.itemCount} ${widget.itemCountLabel}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textMuted,
              ),
            ),

            const Spacer(),

            // Optional view-mode toggle for Albums
            if (widget.viewMode != null && widget.onViewModeChanged != null)
              Container(
                decoration: BoxDecoration(
                  color: AppColors.fillControl,
                  borderRadius: BorderRadius.circular(AppSpacing.r10),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ViewModeIconButton(
                      key: const Key('view_mode_square'),
                      icon: Icons.grid_view_rounded,
                      tooltip: context.t('view.square'),
                      isSelected: widget.viewMode == 'square',
                      onPressed: () => widget.onViewModeChanged!('square'),
                    ),
                    _ViewModeIconButton(
                      key: const Key('view_mode_wide'),
                      icon: Icons.view_agenda_outlined,
                      tooltip: context.t('view.wide'),
                      isSelected: widget.viewMode == 'wide',
                      onPressed: () => widget.onViewModeChanged!('wide'),
                    ),
                    _ViewModeIconButton(
                      key: const Key('view_mode_list'),
                      icon: Icons.view_headline_rounded,
                      tooltip: context.t('view.list'),
                      isSelected: widget.viewMode == 'list',
                      onPressed: () => widget.onViewModeChanged!('list'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ViewModeIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onPressed;

  const _ViewModeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.r10 - 2),
        onTap: onPressed,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0x3DD3C9EA) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.r10 - 2),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isSelected ? AppColors.accent : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
