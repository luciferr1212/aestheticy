import 'package:flutter/material.dart';

import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'sort_direction_button.dart';

/// Unified control bar providing shape switcher (where applicable), sort dropdown,
/// and sort direction toggle button across all library list views.
class LibraryViewControls extends StatelessWidget {
  /// Allowed visual shapes for this view (e.g. ['square', 'wide', 'list'],
  /// ['circle', 'square', 'list'], or empty/single-item for table-only).
  final List<String> allowedShapes;

  /// Current active shape mode.
  final String? currentShape;

  /// Callback when user selects a different shape.
  final ValueChanged<String>? onShapeChanged;

  /// List of sort keys available for this view.
  final List<String> sortOptions;

  /// Current active sort key.
  final String currentSort;

  /// Callback when user picks a sort key from the dropdown menu.
  final ValueChanged<String> onSortChanged;

  /// Current sort direction (ascending or descending).
  final SortDirection sortDirection;

  /// Callback when sort direction is toggled.
  final ValueChanged<SortDirection> onSortDirectionChanged;

  /// Whether animations are disabled.
  final bool reduceMotion;

  /// Optional custom key for the sort direction button.
  final Key? sortDirectionButtonKey;

  /// Creates a [LibraryViewControls].
  const LibraryViewControls({
    super.key,
    this.allowedShapes = const [],
    this.currentShape,
    this.onShapeChanged,
    required this.sortOptions,
    required this.currentSort,
    required this.onSortChanged,
    required this.sortDirection,
    required this.onSortDirectionChanged,
    this.reduceMotion = false,
    this.sortDirectionButtonKey,
  });

  IconData _iconForShape(String shape) {
    return switch (shape) {
      'circle' => Icons.circle_outlined,
      'wide' => Icons.view_agenda_outlined,
      'list' => Icons.view_list,
      'square' => Icons.grid_view,
      _ => Icons.grid_view,
    };
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
      items: sortOptions.map((opt) {
        final isSelected = opt == currentSort;
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
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((selected) {
      if (selected != null && selected != currentSort) {
        onSortChanged(selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasShapes = allowedShapes.length > 1;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: GlassSurface(
        density: GlassDensity.regular,
        borderRadius: AppSpacing.r12,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Shape switcher segmented control (when allowed shapes > 1)
            if (hasShapes) ...[
              _ShapeSwitcher(
                shapes: allowedShapes,
                currentShape: currentShape ?? allowedShapes.first,
                onShapeChanged: (s) => onShapeChanged?.call(s),
                iconForShape: _iconForShape,
                reduceMotion: reduceMotion,
              ),
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 20,
                color: AppColors.borderSubtle,
              ),
              const SizedBox(width: 8),
            ],

            // 2. Sort dropdown menu trigger
            Flexible(
              fit: FlexFit.loose,
              child: Builder(
                builder: (sortCtx) {
                  return InkWell(
                    key: const Key('sort_button'),
                    borderRadius: BorderRadius.circular(AppSpacing.r10),
                    onTap: () {
                      final box = sortCtx.findRenderObject() as RenderBox?;
                      final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
                      _showSortMenu(
                        context,
                        pos + Offset(0, box?.size.height ?? 32),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.sort,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            fit: FlexFit.loose,
                            child: Text(
                              '${context.t('common.sort')}: ${context.t('sort.$currentSort')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.text,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_drop_down,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(width: 4),

            // 3. Sort direction button
            SortDirectionButton(
              buttonKey: sortDirectionButtonKey,
              direction: sortDirection,
              onChanged: onSortDirectionChanged,
              reduceMotion: reduceMotion,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShapeSwitcher extends StatelessWidget {
  final List<String> shapes;
  final String currentShape;
  final ValueChanged<String> onShapeChanged;
  final IconData Function(String) iconForShape;
  final bool reduceMotion;

  const _ShapeSwitcher({
    required this.shapes,
    required this.currentShape,
    required this.onShapeChanged,
    required this.iconForShape,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    final activeIndex = shapes.indexOf(currentShape).clamp(0, shapes.length - 1);
    const itemWidth = 32.0;
    const itemHeight = 28.0;
    final totalWidth = itemWidth * shapes.length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.fillGlass,
        borderRadius: BorderRadius.circular(AppSpacing.r10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: SizedBox(
        width: totalWidth,
        height: itemHeight,
        child: Stack(
          children: [
            // Sliding indicator
            AnimatedPositionedDirectional(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              start: activeIndex * itemWidth,
              top: 0,
              bottom: 0,
              width: itemWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.accentFill,
                  borderRadius: BorderRadius.circular(AppSpacing.r10 - 2),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                ),
              ),
            ),

            // Shape buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: shapes.map((shape) {
              final isSelected = shape == currentShape;
              final tooltip = context.t('viewControls.$shape');

              return SizedBox(
                width: itemWidth,
                height: itemHeight,
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label: tooltip,
                  child: IconButton(
                    key: Key('view_mode_$shape'),
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    tooltip: tooltip,
                    icon: Icon(
                      iconForShape(shape),
                      color: isSelected ? AppColors.accent : AppColors.textMuted,
                    ),
                    onPressed: () => onShapeChanged(shape),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ),
  );
}
}
