import 'package:flutter/material.dart';

import '../../../audio/playback_controller.dart';
import '../../../features/collections/user_collections.dart';
import '../../glass/glass_button.dart';
import '../../glass/glass_surface.dart';
import '../../l10n/app_strings.dart';
import '../../mini_player/mini_player_controller.dart';
import '../../settings/settings_scope.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../app_navigator.dart';
import '../side_panel_controller.dart';
import '../volume_hud.dart';
import '../volume_wheel_region.dart';

/// End side auxiliary controls (lyrics, queue, equalizer, volume, mini player, fullscreen).
class BottomBarEndControls extends StatelessWidget {
  /// Active playback controller.
  final PlaybackController controller;

  /// Optional navigation coordinator.
  final AppNavigator? navigator;

  /// Optional mini player window controller.
  final MiniPlayerController? miniPlayerController;

  /// Optional docked side panel controller.
  final SidePanelController? sidePanelController;

  /// Creates a [BottomBarEndControls].
  const BottomBarEndControls({
    super.key,
    required this.controller,
    this.navigator,
    this.miniPlayerController,
    this.sidePanelController,
  });

  void _showVolumePopup(BuildContext context) {
    final settingsStore = SettingsScope.maybeOf(context);
    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogCtx) {
        return Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 32, bottom: 104),
            child: Material(
              color: Colors.transparent,
              child: VolumeWheelRegion(
                engine: controller.engine,
                settingsStore: settingsStore,
                behavior: HitTestBehavior.opaque,
                child: GlassSurface(
                  borderRadius: AppSpacing.r16,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  width: 200,
                  height: 52,
                  child: StreamBuilder<double>(
                    stream: controller.engine.volumeStream,
                    initialData: controller.engine.currentVolume,
                    builder: (context, snapshot) {
                      final vol = (snapshot.data ?? 1.0).clamp(0.0, 1.0);
                      return Row(
                        children: [
                          const Icon(
                            Icons.volume_down,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5.0,
                                ),
                                trackHeight: 3.0,
                                activeTrackColor: AppColors.accent,
                                inactiveTrackColor: AppColors.border,
                                thumbColor: AppColors.accent,
                                mouseCursor: WidgetStateProperty.resolveWith<
                                    MouseCursor>(
                                  (states) =>
                                      states.contains(WidgetState.disabled)
                                          ? SystemMouseCursors.basic
                                          : SystemMouseCursors.click,
                                ),
                              ),
                              child: Slider(
                                value: vol,
                                onChanged: (newVol) {
                                  final hudCtrl = VolumeHudScope.maybeOf(context);
                                  setVolumeDirect(
                                    engine: controller.engine,
                                    volume: newVol,
                                    settingsStore: settingsStore,
                                    hudController: hudCtrl,
                                  );
                                },
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.volume_up,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsStore = SettingsScope.maybeOf(context);
    final panelController = sidePanelController;

    Widget buildLyricsAndQueueButtons({
      required bool isLyricsActive,
      required bool isQueueActive,
    }) {
      final lyricsTooltip = panelController != null
          ? (isLyricsActive
              ? context.t('sidePanel.closeLyrics')
              : context.t('sidePanel.openLyrics'))
          : context.t('common.lyrics');
      final queueTooltip = panelController != null
          ? (isQueueActive
              ? context.t('sidePanel.closeQueue')
              : context.t('sidePanel.openQueue'))
          : context.t('common.queue');

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassIconButton(
            key: const Key('player_lyrics_button'),
            icon: Icons.lyrics_outlined,
            tooltip: lyricsTooltip,
            semanticLabel: lyricsTooltip,
            size: GlassButtonSize.small,
            variant: isLyricsActive
                ? GlassButtonVariant.selected
                : GlassButtonVariant.normal,
            onPressed: panelController != null
                ? () => panelController.toggleTab(SidePanelTab.lyrics)
                : (navigator != null ? () => navigator!.openLyrics() : null),
          ),
          const SizedBox(width: 4),
          GlassIconButton(
            key: const Key('player_queue_button'),
            icon: Icons.queue_music,
            tooltip: queueTooltip,
            semanticLabel: queueTooltip,
            size: GlassButtonSize.small,
            variant: isQueueActive
                ? GlassButtonVariant.selected
                : GlassButtonVariant.normal,
            onPressed: panelController != null
                ? () => panelController.toggleTab(SidePanelTab.queue)
                : (navigator != null ? () => navigator!.openQueue() : null),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (panelController != null)
          ListenableBuilder(
            listenable: panelController,
            builder: (context, _) {
              final isLyricsActive = panelController.isOpen &&
                  panelController.activeTab == SidePanelTab.lyrics;
              final isQueueActive = panelController.isOpen &&
                  panelController.activeTab == SidePanelTab.queue;
              return buildLyricsAndQueueButtons(
                isLyricsActive: isLyricsActive,
                isQueueActive: isQueueActive,
              );
            },
          )
        else
          buildLyricsAndQueueButtons(
            isLyricsActive: false,
            isQueueActive: false,
          ),
        const SizedBox(width: 4),

        // Equalizer
        GlassIconButton(
          key: const Key('player_equalizer_button'),
          icon: Icons.equalizer,
          tooltip: context.t('common.equalizer'),
          semanticLabel: context.t('common.equalizer'),
          size: GlassButtonSize.small,
          onPressed:
              navigator != null ? () => navigator!.openAudioPanels() : null,
        ),
        const SizedBox(width: 4),

        // Volume (enabled, click for popup slider, scroll wheel for +/-5% step)
        VolumeWheelRegion(
          key: const Key('player_volume_wheel_listener'),
          engine: controller.engine,
          settingsStore: settingsStore,
          behavior: HitTestBehavior.opaque,
          child: GlassIconButton(
            key: const Key('player_volume_button'),
            icon: Icons.volume_up,
            tooltip: context.t('common.volume'),
            semanticLabel: context.t('common.volume'),
            size: GlassButtonSize.small,
            onPressed: () => _showVolumePopup(context),
          ),
        ),
        const SizedBox(width: 4),

        // Mini player
        GlassIconButton(
          key: const Key('player_mini_player_button'),
          icon: Icons.picture_in_picture_alt,
          tooltip: context.t('player.miniPlayer'),
          semanticLabel: context.t('player.miniPlayer'),
          size: GlassButtonSize.small,
          onPressed: miniPlayerController != null
              ? () => miniPlayerController!.enter()
              : null,
        ),
        const SizedBox(width: 4),

        // Full Screen
        GlassIconButton(
          key: const Key('player_fullscreen_button'),
          icon: Icons.fullscreen,
          tooltip: context.t('common.fullScreen'),
          semanticLabel: context.t('common.fullScreen'),
          size: GlassButtonSize.small,
          onPressed:
              navigator != null ? () => navigator!.openFullScreen() : null,
        ),
      ],
    );
  }
}

/// Favorite heart toggle shared by the bottom player bar and mini player.
class PlayerFavoriteButton extends StatelessWidget {
  /// Track path/URI.
  final String path;

  /// Optional test key override.
  final Key? buttonKey;

  /// Creates a [PlayerFavoriteButton].
  const PlayerFavoriteButton({
    super.key,
    required this.path,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final collections = UserCollectionsScope.maybeOf(context);
    if (collections == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: collections,
      builder: (context, _) {
        final isFav = collections.isFavorite(path);

        return Tooltip(
          message:
              isFav ? context.t('track.unfavorite') : context.t('track.favorite'),
          child: InkResponse(
            key: buttonKey ?? const Key('bottom_bar_favorite_button'),
            radius: 12,
            onTap: () => collections.toggleFavorite(path),
            child: SizedBox(
              width: 18,
              height: 18,
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
