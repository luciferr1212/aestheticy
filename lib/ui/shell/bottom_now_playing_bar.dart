import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide RepeatMode;

import '../../audio/audio_engine.dart';
import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../audio/playback_queue.dart';
import '../../features/collections/user_collections.dart';
import '../../library/cover_cache.dart';
import '../mini_player/mini_player_controller.dart';
import 'app_navigator.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../now_playing/metadata_link.dart';
import '../settings/settings_scope.dart';
import '../settings/settings_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'side_panel_controller.dart';
import 'volume_hud.dart';
import 'volume_wheel_region.dart';

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
                child: _TrackInfoArea(
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
                  child: _CenterTransportArea(controller: controller),
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
                    child: _EndControlsArea(
                      controller: controller,
                      navigator: navigator,
                      miniPlayerController: miniPlayerController,
                      sidePanelController: sidePanelController,
                    ),
                  ),
                )
              else
                _EndControlsArea(
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

/// Metadata and cover artwork area on the start side.
///
/// Isolated so seek position ticks do NOT trigger rebuilds here.
class _TrackInfoArea extends StatelessWidget {
  final PlaybackController controller;
  final AppNavigator? navigator;
  final VoidCallback? onTrackInfoBuild;
  final bool compact;

  const _TrackInfoArea({
    required this.controller,
    this.navigator,
    this.onTrackInfoBuild,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    onTrackInfoBuild?.call();

    return StreamBuilder<AudioSource?>(
      stream: controller.currentStream,
      initialData: controller.queue.current,
      builder: (context, snapshot) {
        final current = snapshot.data;
        final hasTrack = current != null;

        final title = hasTrack
            ? (current.extras?['title'] ?? context.t('library.unknownTitle'))
            : context.t('player.noTrack');
        final rawArtist = current?.extras?['artist'];
        final artist = hasTrack
            ? context.displayArtist(rawArtist)
            : '—';
        final coverKey = current?.extras?['coverKey'];

        return Semantics(
          button: true,
          label: context.t('player.openNowPlaying'),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.r12),
            onTap: () {
              if (navigator != null) {
                navigator!.openNowPlaying();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.t('common.soon')),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 2 : 6,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    // Cover thumbnail
                    _buildCover(coverKey),
                    SizedBox(width: compact ? 6 : 12),

                    // Title and Artist
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textDirection: textDirectionFor(title),
                                  style: AppTypography.bodyStrong.copyWith(
                                    color: hasTrack
                                        ? AppColors.text
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ),
                              if (hasTrack && !compact) ...[
                                const SizedBox(width: 4),
                                _PlayerFavoriteButton(path: current.uri),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Builder(
                            builder: (context) {
                              final canLink = hasTrack &&
                                  rawArtist != null &&
                                  rawArtist.trim().isNotEmpty &&
                                  navigator != null;
                              return MetadataLink(
                                text: artist,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                                reduceMotion: SettingsScope.maybeOf(context)
                                        ?.settings
                                        .reduceMotion ??
                                    false,
                                semanticLabel: canLink
                                    ? context.t(
                                        'common.goToArtist',
                                        args: {'name': artist},
                                      )
                                    : null,
                                onTap: canLink
                                    ? () => MetadataNavHelper.openArtist(
                                          context: context,
                                          navigator: navigator!,
                                          rawArtist: rawArtist,
                                        )
                                    : null,
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // Directional chevron
                    if (!compact)
                      const Icon(
                        Icons.keyboard_arrow_up,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                  ],
                ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCover(String? coverKey) {
    final dim = compact ? 36.0 : 52.0;
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
        width: dim,
        height: dim,
        fit: BoxFit.cover,
        cacheWidth: 104,
        cacheHeight: 104,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else {
      imageWidget = _buildPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.r10),
      child: SizedBox(
        width: dim,
        height: dim,
        child: imageWidget,
      ),
    );
  }

  Widget _buildPlaceholder() {
    final dim = compact ? 36.0 : 52.0;
    return Container(
      width: dim,
      height: dim,
      decoration: BoxDecoration(
        color: const Color(0xFF22212C),
        borderRadius: BorderRadius.circular(AppSpacing.r10),
      ),
      child: Center(
        child: Icon(
          Icons.music_note,
          color: Colors.white24,
          size: compact ? 18 : 24,
        ),
      ),
    );
  }
}

/// Center transport controls and isolated seekbar.
class _CenterTransportArea extends StatelessWidget {
  final PlaybackController controller;

  const _CenterTransportArea({required this.controller});

  Widget _buildRepeatButton(BuildContext context, RepeatMode mode) {
    final (variant, tooltip) = switch (mode) {
      RepeatMode.off => (GlassButtonVariant.normal, context.t('player.repeatOff')),
      RepeatMode.all => (GlassButtonVariant.selected, context.t('player.repeatAll')),
      RepeatMode.one => (GlassButtonVariant.selected, context.t('player.repeatOne')),
    };

    if (mode == RepeatMode.one) {
      return Stack(
        alignment: Alignment.center,
        children: [
          GlassIconButton(
            key: const Key('bottom_bar_repeat_button'),
            icon: Icons.repeat_one,
            tooltip: tooltip,
            semanticLabel: tooltip,
            size: GlassButtonSize.small,
            variant: variant,
            onPressed: () => unawaited(controller.cycleRepeatMode()),
          ),
          PositionedDirectional(
            end: 2,
            top: 2,
            child: IgnorePointer(
              child: Container(
                key: const Key('bottom_bar_repeat_one_badge'),
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '1',
                  style: TextStyle(
                    color: AppColors.base,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return GlassIconButton(
      key: const Key('bottom_bar_repeat_button'),
      icon: Icons.repeat,
      tooltip: tooltip,
      semanticLabel: tooltip,
      size: GlassButtonSize.small,
      variant: variant,
      onPressed: () => unawaited(controller.cycleRepeatMode()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: controller.queueChangeStream,
      builder: (context, _) {
        final isShuffled = controller.queue.isShuffled;
        final repeatMode = controller.queue.repeatMode;

        return StreamBuilder<PlaybackState>(
          stream: controller.stateStream,
          initialData: controller.currentState,
          builder: (context, snapshot) {
            final state = snapshot.data ?? PlaybackState.idle;
            final isPlaying = state == PlaybackState.playing;
            final hasTrack = controller.queue.current != null;

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Transport buttons row: [shuffle] [prev] [play/pause] [next] [repeat]
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlassIconButton(
                        key: const Key('bottom_bar_shuffle_button'),
                        icon: Icons.shuffle,
                        tooltip: context.t('player.shuffle'),
                        semanticLabel: context.t('player.shuffle'),
                        size: GlassButtonSize.small,
                        variant: isShuffled
                            ? GlassButtonVariant.selected
                            : GlassButtonVariant.normal,
                        onPressed: () =>
                            unawaited(controller.setShuffle(!isShuffled)),
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        key: const Key('bottom_bar_prev_button'),
                        icon: Icons.skip_previous,
                        tooltip: context.t('common.previous'),
                        semanticLabel: context.t('common.previous'),
                        size: GlassButtonSize.small,
                        onPressed:
                            hasTrack ? () => controller.skipPrevious() : null,
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        key: const Key('bottom_bar_play_pause_button'),
                        icon: isPlaying ? Icons.pause : Icons.play_arrow,
                        tooltip: isPlaying
                            ? context.t('common.pause')
                            : context.t('common.play'),
                        semanticLabel: isPlaying
                            ? context.t('common.pause')
                            : context.t('common.play'),
                        size: GlassButtonSize.medium,
                        variant: GlassButtonVariant.primary,
                        onPressed:
                            hasTrack ? () => controller.togglePlayPause() : null,
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        key: const Key('bottom_bar_next_button'),
                        icon: Icons.skip_next,
                        tooltip: context.t('common.next'),
                        semanticLabel: context.t('common.next'),
                        size: GlassButtonSize.small,
                        onPressed:
                            hasTrack ? () => controller.skipNext() : null,
                      ),
                      const SizedBox(width: 8),
                      _buildRepeatButton(context, repeatMode),
                    ],
                  ),
                ),
                const SizedBox(height: 2),

                // Isolated Seek Bar Leaf (rebuilds on its own)
                _NowPlayingSeekBarLeaf(
                  engine: controller.engine,
                  hasTrack: hasTrack,
                  controller: controller,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Leaf seek bar widget that rebuilds independently on position updates.
class _NowPlayingSeekBarLeaf extends StatefulWidget {
  final AudioEngine engine;
  final bool hasTrack;
  final PlaybackController? controller;

  const _NowPlayingSeekBarLeaf({
    required this.engine,
    required this.hasTrack,
    this.controller,
  });

  @override
  State<_NowPlayingSeekBarLeaf> createState() => _NowPlayingSeekBarLeafState();
}

class _NowPlayingSeekBarLeafState extends State<_NowPlayingSeekBarLeaf> {
  StreamSubscription<Duration>? _seekSub;

  @override
  void initState() {
    super.initState();
    _seekSub = widget.controller?.seekStream.listen((_) {
      if (mounted && widget.controller?.currentState == PlaybackState.idle) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant _NowPlayingSeekBarLeaf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _seekSub?.cancel();
      _seekSub = widget.controller?.seekStream.listen((_) {
        if (mounted && widget.controller?.currentState == PlaybackState.idle) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _seekSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasTrack) {
      return SizedBox(
        height: 18,
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  context.formatDurationLocalized(Duration.zero),
                  style: AppTypography.micro.copyWith(color: AppColors.textMuted),
                ),
              ),
            ),
            const Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 0),
                  trackHeight: 3.0,
                  activeTrackColor: AppColors.fillControl,
                  inactiveTrackColor: AppColors.fillGlass,
                ),
                child: Slider(
                  value: 0.0,
                  onChanged: null,
                ),
              ),
            ),
            SizedBox(
              width: 32,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.formatDurationLocalized(Duration.zero),
                  style: AppTypography.micro.copyWith(color: AppColors.textMuted),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final controller = widget.controller;
    final engine = widget.engine;

    return StreamBuilder<Duration>(
      stream: engine.durationStream,
      initialData: controller?.currentDuration ?? engine.currentDuration,
      builder: (context, durSnapshot) {
        final totalDuration = (controller != null && controller.currentState == PlaybackState.idle)
            ? controller.currentDuration
            : (durSnapshot.data != null && durSnapshot.data! > Duration.zero
                ? durSnapshot.data!
                : (controller?.currentDuration ?? Duration.zero));

        return StreamBuilder<Duration>(
          stream: engine.positionStream,
          initialData: controller?.currentPosition ?? engine.currentPosition,
          builder: (context, posSnapshot) {
            final position = (controller != null && controller.currentState == PlaybackState.idle)
                ? controller.currentPosition
                : (posSnapshot.data ?? controller?.currentPosition ?? Duration.zero);
            final maxMs = totalDuration.inMilliseconds.toDouble();
            final currentMs =
                position.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

            return SizedBox(
              height: 18,
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        context.formatDurationLocalized(position),
                        textAlign: TextAlign.end,
                        style: AppTypography.micro.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.0),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 8.0),
                        trackHeight: 3.0,
                        activeTrackColor: AppColors.accent,
                        inactiveTrackColor: AppColors.border,
                        thumbColor: AppColors.accent,
                        mouseCursor: WidgetStateProperty.resolveWith<MouseCursor>((states) =>
                            states.contains(WidgetState.disabled)
                                ? SystemMouseCursors.basic
                                : SystemMouseCursors.click),
                      ),
                      child: Slider(
                        value: maxMs > 0 ? currentMs : 0.0,
                        max: maxMs > 0 ? maxMs : 1.0,
                        onChanged: (val) {
                          final target = Duration(milliseconds: val.toInt());
                          if (controller != null) {
                            controller.seek(target);
                          } else {
                            engine.seek(target);
                          }
                          if (controller?.currentState == PlaybackState.idle) {
                            setState(() {});
                          }
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        context.formatDurationLocalized(totalDuration),
                        textAlign: TextAlign.start,
                        style: AppTypography.micro.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// End side auxiliary controls (volume, lyrics, queue, equalizer, fullscreen).
class _EndControlsArea extends StatelessWidget {
  final PlaybackController controller;
  final AppNavigator? navigator;
  final MiniPlayerController? miniPlayerController;
  final SidePanelController? sidePanelController;

  const _EndControlsArea({
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                thumbShape:
                                    const RoundSliderThumbShape(enabledThumbRadius: 5.0),
                                trackHeight: 3.0,
                                activeTrackColor: AppColors.accent,
                                inactiveTrackColor: AppColors.border,
                                thumbColor: AppColors.accent,
                                mouseCursor: WidgetStateProperty.resolveWith<MouseCursor>((states) =>
                                    states.contains(WidgetState.disabled)
                                        ? SystemMouseCursors.basic
                                        : SystemMouseCursors.click),
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

class PlayerFavoriteButton extends StatelessWidget {
  final String path;
  final Key? buttonKey;

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
          message: isFav
              ? context.t('track.unfavorite')
              : context.t('track.favorite'),
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

typedef _PlayerFavoriteButton = PlayerFavoriteButton;
