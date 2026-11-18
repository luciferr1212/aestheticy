import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
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

/// Horizontal scrollable, reorderable row of artist chips with custom scrollbar,
/// overflow fade masks, top 12 clipping with extra selected chip support,
/// and trailing All Artists dialog + reset order menu.
class AlbumsArtistChips extends StatefulWidget {
  /// Ordered list of artists eligible for chips (artists with at least one album).
  final List<ArtistChipItem> artists;

  /// Complete list of every artist with song counts for the "All artists" dialog.
  /// If null, defaults to [artists].
  final List<ArtistChipItem>? allArtists;

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
    this.allArtists,
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
  bool _isHovered = false;
  bool _canScrollStart = false;
  bool _canScrollEnd = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollFades);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollFades);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollFades() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset;
    final canStart = offset > 1.0;
    final canEnd = offset < max - 1.0;
    if (canStart != _canScrollStart || canEnd != _canScrollEnd) {
      setState(() {
        _canScrollStart = canStart;
        _canScrollEnd = canEnd;
      });
    }
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

  List<ArtistChipItem> get _displayedArtists {
    final top12 = widget.artists.take(12).toList();
    final selectedKey = widget.selectedArtistKey;
    if (selectedKey != null && !top12.any((a) => a.key == selectedKey)) {
      final source = widget.allArtists ?? widget.artists;
      ArtistChipItem? extraArtist;
      for (final a in source) {
        if (a.key == selectedKey) {
          extraArtist = a;
          break;
        }
      }
      if (extraArtist != null) {
        top12.insert(0, extraArtist);
      }
    }
    return top12;
  }

  void _handleReorder(int oldIndex, int newIndex) {
    final displayed = _displayedArtists;
    final keys = displayed.map((a) => a.key).toList();
    final item = keys.removeAt(oldIndex);
    keys.insert(newIndex, item);
    widget.onOrderChanged(keys);
  }

  void _showAllArtistsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return _AllArtistsDialog(
          artists: widget.allArtists ?? widget.artists,
          selectedArtistKey: widget.selectedArtistKey,
          onArtistSelected: (key) {
            Navigator.of(dialogCtx).pop();
            widget.onArtistSelected(key);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAllSelected = widget.selectedArtistKey == null;
    final displayed = _displayedArtists;

    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollFades());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            // Fixed "All" chip
            GlassPillButton(
              key: const Key('albums_artist_chip_all'),
              label: context.t('albums.allArtists'),
              variant: isAllSelected
                  ? GlassButtonVariant.selected
                  : GlassButtonVariant.normal,
              size: GlassButtonSize.medium,
              onPressed: () => widget.onArtistSelected(null),
            ),

            const SizedBox(width: AppSpacing.s8),

            // Horizontal Reorderable list with custom scrollbar and soft fade masks
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  _updateScrollFades();
                  return false;
                },
                child: Listener(
                  onPointerSignal: _onPointerSignal,
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _isHovered = true),
                    onExit: (_) => setState(() => _isHovered = false),
                    child: ShaderMask(
                      shaderCallback: (Rect bounds) {
                        final textDirection = Directionality.of(context);
                        if (!_canScrollStart && !_canScrollEnd) {
                          return const LinearGradient(
                            colors: [Colors.white, Colors.white],
                          ).createShader(bounds, textDirection: textDirection);
                        }
                        return LinearGradient(
                          begin: AlignmentDirectional.centerStart,
                          end: AlignmentDirectional.centerEnd,
                          colors: [
                            _canScrollStart ? Colors.transparent : Colors.white,
                            Colors.white,
                            Colors.white,
                            _canScrollEnd ? Colors.transparent : Colors.white,
                          ],
                          stops: const [0.0, 0.04, 0.96, 1.0],
                        ).createShader(bounds, textDirection: textDirection);
                      },
                      blendMode: BlendMode.dstIn,
                      child: RawScrollbar(
                        controller: _scrollController,
                        thumbVisibility: _isHovered,
                        thickness: 3.0,
                        radius: const Radius.circular(AppSpacing.r10),
                        thumbColor: AppColors.textMuted.withValues(alpha: 0.5),
                        child: ReorderableListView.builder(
                          scrollController: _scrollController,
                          scrollDirection: Axis.horizontal,
                          buildDefaultDragHandles: false,
                          itemCount: displayed.length,
                          onReorderItem: _handleReorder,
                          proxyDecorator: (child, index, animation) {
                            return Material(
                              color: Colors.transparent,
                              child: child,
                            );
                          },
                          itemBuilder: (context, index) {
                            final artist = displayed[index];
                            final isSelected =
                                widget.selectedArtistKey == artist.key;

                            return ReorderableDragStartListener(
                              key: ValueKey('artist_chip_${artist.key}'),
                              index: index,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(end: AppSpacing.s8),
                                child: GlassPillButton(
                                  key: Key('artist_chip_button_${artist.key}'),
                                  label: artist.name,
                                  trailing: Text(
                                    context.localizeDigitsText(
                                      artist.songCount.toString(),
                                    ),
                                    style: AppTypography.caption.copyWith(
                                      color: isSelected
                                          ? AppColors.accent.withValues(alpha: 0.8)
                                          : AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  variant: isSelected
                                      ? GlassButtonVariant.selected
                                      : GlassButtonVariant.normal,
                                  size: GlassButtonSize.medium,
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
              ),
            ),

            const SizedBox(width: AppSpacing.s8),

            // Trailing "All artists" button
            GlassPillButton(
              key: const Key('albums_artist_chips_all_artists'),
              label: context.t('albums.allArtistsButton'),
              leadingIcon: Icons.people_outline,
              variant: GlassButtonVariant.normal,
              size: GlassButtonSize.medium,
              onPressed: () => _showAllArtistsDialog(context),
            ),

            const SizedBox(width: AppSpacing.s4),

            // Reset order action in chip row trailing menu
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
                } else if (val == 'all_artists') {
                  _showAllArtistsDialog(context);
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

class _AllArtistsDialog extends StatefulWidget {
  final List<ArtistChipItem> artists;
  final String? selectedArtistKey;
  final ValueChanged<String?> onArtistSelected;

  const _AllArtistsDialog({
    required this.artists,
    required this.selectedArtistKey,
    required this.onArtistSelected,
  });

  @override
  State<_AllArtistsDialog> createState() => _AllArtistsDialogState();
}

class _AllArtistsDialogState extends State<_AllArtistsDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.artists
        : widget.artists
            .where((a) => a.name.toLowerCase().contains(query))
            .toList();

    return Dialog(
      backgroundColor: const Color(0xFF1D1C25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.r12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 440,
          maxHeight: 520,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.t('albums.allArtistsButton'),
                      style: AppTypography.title.copyWith(color: AppColors.text),
                    ),
                  ),
                  IconButton(
                    key: const Key('all_artists_dialog_close'),
                    icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              TextField(
                key: const Key('all_artists_search_input'),
                style: AppTypography.body.copyWith(color: AppColors.text),
                decoration: InputDecoration(
                  hintText: context.t('albums.searchArtists'),
                  hintStyle: AppTypography.body.copyWith(color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.fillControl,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.r10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.r10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.r10),
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                ),
                onChanged: (val) => setState(() => _search = val),
              ),
              const SizedBox(height: AppSpacing.s12),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          context.t('albums.noArtistsFound'),
                          style: AppTypography.body.copyWith(color: AppColors.textMuted),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final artist = filtered[index];
                          final isSelected = widget.selectedArtistKey == artist.key;
                          return InkWell(
                            key: Key('all_artists_item_${artist.key}'),
                            mouseCursor: SystemMouseCursors.click,
                            hoverColor: const Color(0x14FFFFFF),
                            borderRadius: BorderRadius.circular(AppSpacing.r10),
                            onTap: () => widget.onArtistSelected(artist.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(AppSpacing.r10),
                                color: isSelected ? AppColors.accentFill : Colors.transparent,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      artist.name,
                                      style: AppTypography.body.copyWith(
                                        color: isSelected ? AppColors.accent : AppColors.text,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${context.localizeDigitsText(artist.songCount.toString())} ${context.t('tracks.count')}',
                                    style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
