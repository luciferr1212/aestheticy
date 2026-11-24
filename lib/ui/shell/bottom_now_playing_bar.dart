import 'package:flutter/material.dart';

import '../../audio/playback_controller.dart';
import '../glass/glass_surface.dart';
import '../mini_player/mini_player_controller.dart';
import '../settings/settings_store.dart';
import 'app_navigator.dart';
import 'side_panel_controller.dart';
import 'widgets/bottom_bar_end_controls.dart';
import 'widgets/bottom_bar_track_info.dart';
import 'widgets/bottom_bar_transport.dart';

export 'widgets/bottom_bar_end_controls.dart' show PlayerFavoriteButton;

/// Floating bottom player bar providing transport controls, track metadata,
/// seeking, and auxiliary controls.
class BottomNowPlayingBar extends StatelessWidget {
  /// The audio playback controller coordinating queue and engine.
  final PlaybackController controller;

  /// Optional navigation coordinator.
  final AppNavigator? navigator;

  /// Optional mini player window mode controller.
  final MiniPlayerController? miniPlayerController;

  /// Optional callback invoked when the track info area is built (for test counters).
  final VoidCallback? onTrackInfoBuild;

  /// Optional settings store for inspecting glass quality.
  final SettingsStore? settingsStore;

  /// Optional docked side panel controller for toggling Queue and Lyrics tabs.
  final SidePanelController? sidePanelController;

  /// Creates a [BottomNowPlayingBar].
  const BottomNowPlayingBar({
    super.key,
    required this.controller,
    this.navigator,
    this.miniPlayerController,
    this.onTrackInfoBuild,
    this.settingsStore,
    this.sidePanelController,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: 24.0,
      height: 84.0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTight = constraints.maxWidth < 500;
          final gap = isTight ? 4.0 : 8.0;

          return Row(
            children: [
              // Start side: Cover + Title + Artist + Expand chevron (button)
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: isTight ? 56 : 120,
                  maxWidth: isTight ? 88 : 170,
                ),
                child: BottomBarTrackInfo(
                  controller: controller,
                  navigator: navigator,
                  onTrackInfoBuild: onTrackInfoBuild,
                  compact: isTight,
                ),
              ),
              SizedBox(width: gap),

              // Center side: Transport controls + Seekbar (Always LTR)
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: BottomBarTransportArea(controller: controller),
                ),
              ),
              SizedBox(width: gap),

              // End side: Auxiliary icon buttons (volume, lyrics, queue, etc.)
              if (isTight)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (constraints.maxWidth * 0.36).clamp(80.0, 220.0),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerEnd,
                    child: BottomBarEndControls(
                      controller: controller,
                      navigator: navigator,
                      miniPlayerController: miniPlayerController,
                      sidePanelController: sidePanelController,
                    ),
                  ),
                )
              else
                BottomBarEndControls(
                  controller: controller,
                  navigator: navigator,
                  miniPlayerController: miniPlayerController,
                  sidePanelController: sidePanelController,
                ),
            ],
          );
        },
      ),
    );
  }
}
