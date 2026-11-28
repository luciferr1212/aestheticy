import 'package:flutter/material.dart';

import '../../audio/playback_controller.dart';
import '../../features/collections/user_collections.dart';
import '../../features/lyrics/lyrics_controller.dart';
import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../lyrics/lyrics_view.dart';
import '../queue/queue_content.dart';
import '../settings/settings_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_navigator.dart';
import 'side_panel_controller.dart';

/// Docked right-hand (end-side) panel hosting Queue or Lyrics symmetrically
/// opposite the left [Sidebar], resizing the main content area cleanly.
class SidePanel extends StatefulWidget {
  /// Effective visibility (combining saved preference and width auto-hide).
  final bool isVisible;

  /// Controller coordinating open state and active tab.
  final SidePanelController sidePanelController;

  /// Audio playback controller driving the queue view and lyrics seek/tracking.
  final PlaybackController playbackController;

  /// Lyrics state controller for the embedded lyrics tab.
  final LyricsController lyricsController;

  /// Persistent settings store for motion and display preferences.
  final SettingsStore settingsStore;

  /// Application navigation coordinator for Expand actions.
  final AppNavigator navigator;

  /// Optional user collections scope for queue menus.
  final UserCollections? userCollections;

  /// Optional explicit panel width override (defaults from window width).
  final double? panelWidth;

  /// Creates a [SidePanel].
  const SidePanel({
    super.key,
    required this.isVisible,
    required this.sidePanelController,
    required this.playbackController,
    required this.lyricsController,
    required this.settingsStore,
    required this.navigator,
    this.userCollections,
    this.panelWidth,
  });

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _widthFactorAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: widget.isVisible ? 1.0 : 0.0,
    );
    _widthFactorAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(SidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reduceMotion = widget.settingsStore.settings.reduceMotion;
    if (oldWidget.isVisible != widget.isVisible ||
        (reduceMotion && _animController.isAnimating)) {
      if (reduceMotion) {
        _animController.value = widget.isVisible ? 1.0 : 0.0;
      } else if (widget.isVisible) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleExpand(SidePanelTab activeTab) {
    widget.sidePanelController.close();
    if (activeTab == SidePanelTab.lyrics) {
      widget.navigator.openLyrics();
    } else {
      widget.navigator.openQueue();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _animController,
        widget.sidePanelController,
        widget.settingsStore,
      ]),
      builder: (context, _) {
        if (!widget.isVisible && _animController.isDismissed) {
          return const SizedBox.shrink(key: Key('side_panel_closed'));
        }

        final reduceMotion = widget.settingsStore.settings.reduceMotion;
        final activeTab = widget.sidePanelController.activeTab;
        final resolvedWidth = widget.panelWidth ??
            SidePanelController.panelWidthFor(
              MediaQuery.sizeOf(context).width,
            );

        return ClipRect(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: _widthFactorAnimation.value,
            child: SizedBox(
              width: resolvedWidth,
              child: Semantics(
                container: true,
                label: context.t('sidePanel.panelLabel'),
                child: FocusTraversalGroup(
                  child: GlassSurface(
                    key: const Key('side_panel_surface'),
                    borderRadius: AppSpacing.r16,
                    margin: const EdgeInsetsDirectional.only(
                      end: 12,
                      top: 12,
                      bottom: 12,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(context, activeTab, reduceMotion),
                        const SizedBox(height: 8),
                        const Divider(color: AppColors.borderSubtle, height: 1),
                        const SizedBox(height: 8),
                        Expanded(
                          child: AnimatedSwitcher(
                            key: const Key('side_panel_tab_switcher'),
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 150),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeOut,
                            child: activeTab == SidePanelTab.queue
                                ? QueueContent(
                                    key: const ValueKey(
                                      'side_panel_queue_content',
                                    ),
                                    controller: widget.playbackController,
                                    navigator: widget.navigator,
                                    settingsStore: widget.settingsStore,
                                    userCollections: widget.userCollections,
                                    compact: true,
                                    autofocus: false,
                                  )
                                : LyricsView(
                                    key: const ValueKey(
                                      'side_panel_lyrics_content',
                                    ),
                                    controller: widget.lyricsController,
                                    playbackController:
                                        widget.playbackController,
                                    settingsStore: widget.settingsStore,
                                    navigator: null,
                                    showHeader: false,
                                    density: LyricsViewDensity.sidePanel,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    SidePanelTab activeTab,
    bool reduceMotion,
  ) {
    final expandLabel = activeTab == SidePanelTab.lyrics
        ? context.t('sidePanel.expandLyrics')
        : context.t('sidePanel.expandQueue');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GlassIconButton(
            key: const Key('side_panel_expand_button'),
            icon: Icons.open_in_full,
            matchTextDirection: true,
            tooltip: expandLabel,
            semanticLabel: expandLabel,
            size: GlassButtonSize.small,
            onPressed: () => _handleExpand(activeTab),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Center(
              child: _SidePanelTabBar(
                activeTab: activeTab,
                reduceMotion: reduceMotion,
                onSelectTab: widget.sidePanelController.setTab,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GlassIconButton(
            key: const Key('side_panel_close_button'),
            icon: Icons.close,
            tooltip: context.t('sidePanel.close'),
            semanticLabel: context.t('sidePanel.close'),
            size: GlassButtonSize.small,
            onPressed: widget.sidePanelController.close,
          ),
        ],
      ),
    );
  }
}

class _SidePanelTabBar extends StatelessWidget {
  final SidePanelTab activeTab;
  final bool reduceMotion;
  final ValueChanged<SidePanelTab> onSelectTab;

  const _SidePanelTabBar({
    required this.activeTab,
    required this.reduceMotion,
    required this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.fillGlass,
        borderRadius: AppSpacing.brPill,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: _SidePanelTabButton(
              key: const Key('side_panel_tab_queue'),
              label: context.t('common.queue'),
              isSelected: activeTab == SidePanelTab.queue,
              reduceMotion: reduceMotion,
              onPressed: () => onSelectTab(SidePanelTab.queue),
            ),
          ),
          const SizedBox(width: 2),
          Flexible(
            child: _SidePanelTabButton(
              key: const Key('side_panel_tab_lyrics'),
              label: context.t('common.lyrics'),
              isSelected: activeTab == SidePanelTab.lyrics,
              reduceMotion: reduceMotion,
              onPressed: () => onSelectTab(SidePanelTab.lyrics),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidePanelTabButton extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool reduceMotion;
  final VoidCallback onPressed;

  const _SidePanelTabButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.reduceMotion,
    required this.onPressed,
  });

  @override
  State<_SidePanelTabButton> createState() => _SidePanelTabButtonState();
}

class _SidePanelTabButtonState extends State<_SidePanelTabButton> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.isSelected
        ? AppColors.accentFill
        : (_isHovered ? const Color(0x14FFFFFF) : Colors.transparent);
    final textColor = widget.isSelected
        ? AppColors.accent
        : (_isHovered ? AppColors.text : AppColors.textSecondary);

    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: widget.label,
      child: Tooltip(
        message: widget.label,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (hovered) {
            if (_isHovered != hovered) {
              setState(() => _isHovered = hovered);
            }
          },
          onShowFocusHighlight: (focused) {
            if (_isFocused != focused) {
              setState(() => _isFocused = focused);
            }
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: widget.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: AppSpacing.brPill,
                border: Border.all(
                  color: _isFocused
                      ? AppColors.accent
                      : (widget.isSelected
                          ? AppColors.border
                          : Colors.transparent),
                  width: _isFocused ? 1.5 : 1.0,
                ),
              ),
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: textColor,
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
