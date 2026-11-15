import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Item model for artist chips in the Albums screen.
class ArtistChipItem {
  /// Unique key for the artist (canonical key).
  final String key;

  /// Display name of the artist.
  final String name;

  /// Song/track count for ordering and display.
  final int songCount;

  /// Creates an [ArtistChipItem].
  const ArtistChipItem({
    required this.key,
    required this.name,
    required this.songCount,
  });
}

/// Horizontal scrollable, reorderable row of artist chips with custom scrollbar
/// and mouse-wheel translation.
class AlbumsArtistChips extends StatefulWidget {
  /// Ordered list of artists to display after the fixed "All" chip.
  final List<ArtistChipItem> artists;

  /// Currently selected artist key (null means "All").
  final String? selectedArtistKey;

  /// Callback when user taps a chip. Null key corresponds to "All".
  final ValueChanged<String?> onArtistSelected;

  /// Callback when user reorders the chips.
  final ValueChanged<List<String>> onOrderChanged;

  /// Callback when user triggers "Reset order".
  final VoidCallback onResetOrder;

  /// Whether reduce motion is enabled.
  final bool reduceMotion;

  /// Creates [AlbumsArtistChips].
  const AlbumsArtistChips({
    super.key,
    required this.artists,
    required this.selectedArtistKey,
    required this.onArtistSelected,
    required this.onOrderChanged,
    required this.onResetOrder,
    this.reduceMotion = false,
  });

  @override
  State<AlbumsArtistChips> createState() => _AlbumsArtistChipsState();
}

class _AlbumsArtistChipsState extends State<AlbumsArtistChips> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _scrollController.hasClients) {
      final delta =
          event.scrollDelta.dy != 0 ? event.scrollDelta.dy : event.scrollDelta.dx;
      final target = (_scrollController.offset + delta).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(target);
    }
  }

  void _handleReorder(int oldIndex, int newIndex) {
    final keys = widget.artists.map((a) => a.key).toList();
    final item = keys.removeAt(oldIndex);
    keys.insert(newIndex, item);
    widget.onOrderChanged(keys);
  }

  @override
  Widget build(BuildContext context) {
    final isAllSelected = widget.selectedArtistKey == null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            // Fixed "All" chip
            GlassPillButton(
              key: const Key('albums_artist_chip_all'),
              label: context.t('albums.allArtists'),
              variant: isAllSelected
                  ? GlassButtonVariant.selected
                  : GlassButtonVariant.normal,
              size: GlassButtonSize.small,
              onPressed: () => widget.onArtistSelected(null),
            ),

            const SizedBox(width: 8),

            // Horizontal Reorderable list with custom scrollbar
            Expanded(
              child: Listener(
                onPointerSignal: _onPointerSignal,
                child: ScrollbarTheme(
                  data: ScrollbarThemeData(
                    thickness: const WidgetStatePropertyAll<double>(4.0),
                    radius: const Radius.circular(AppSpacing.r10),
                    thumbColor:
                        WidgetStateProperty.resolveWith<Color>((states) {
                      if (states.contains(WidgetState.dragged) ||
                          states.contains(WidgetState.hovered)) {
                        return AppColors.textMuted;
                      }
                      return AppColors.border;
                    }),
                  ),
                  child: RawScrollbar(
                    controller: _scrollController,
                    thumbVisibility: false,
                    child: ReorderableListView.builder(
                      scrollController: _scrollController,
                      scrollDirection: Axis.horizontal,
                      buildDefaultDragHandles: false,
                      itemCount: widget.artists.length,
                      onReorderItem: _handleReorder,
                      proxyDecorator: (child, index, animation) {
                        return Material(
                          color: Colors.transparent,
                          child: child,
                        );
                      },
                      itemBuilder: (context, index) {
                        final artist = widget.artists[index];
                        final isSelected =
                            widget.selectedArtistKey == artist.key;

                        return ReorderableDragStartListener(
                          key: ValueKey('artist_chip_${artist.key}'),
                          index: index,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8.0),
                            child: GlassPillButton(
                              key: Key('artist_chip_button_${artist.key}'),
                              label: artist.name,
                              variant: isSelected
                                  ? GlassButtonVariant.selected
                                  : GlassButtonVariant.normal,
                              size: GlassButtonSize.small,
                              onPressed: () =>
                                  widget.onArtistSelected(artist.key),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 4),

            // Reset order action in chip row menu
            PopupMenuButton<String>(
              key: const Key('albums_artist_chips_menu'),
              tooltip: context.t('albums.resetArtistOrder'),
              icon: const Icon(Icons.more_horiz, size: 18, color: AppColors.textMuted),
              color: const Color(0xFF1D1C25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.r12),
                side: const BorderSide(color: AppColors.border),
              ),
              onSelected: (val) {
                if (val == 'reset') {
                  widget.onResetOrder();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  key: const Key('albums_artist_chips_reset_order'),
                  value: 'reset',
                  child: Text(
                    context.t('albums.resetArtistOrder'),
                    style: AppTypography.body.copyWith(color: AppColors.text),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
