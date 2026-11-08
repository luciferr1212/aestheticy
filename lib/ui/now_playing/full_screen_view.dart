import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../audio/audio_engine.dart';
import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/collections/user_collections.dart';
import '../../library/cover_cache.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/app_shortcuts.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'cover_palette.dart';

/// Immersive full-screen playback view featuring drifting ambient color blobs,
/// optional floating glass shapes, responsive typography, and slender timeline.
class FullScreenView extends StatefulWidget {
  /// The audio playback controller.
  final PlaybackController controller;

  /// The audio engine.
  final AudioEngine engine;

  /// Navigation coordinator.
  final AppNavigator navigator;

  /// Application settings store.
  final SettingsStore settingsStore;

  /// Optional callback invoked on ticker frame (for test verification).
  final VoidCallback? onTickerFrame;

  /// Creates a [FullScreenView].
  const FullScreenView({
    super.key,
    required this.controller,
    required this.engine,
    required this.navigator,
    required this.settingsStore,
    this.onTickerFrame,
  });

  @override
  State<FullScreenView> createState() => FullScreenViewState();
}

/// Exposed state for testing ticker and lifecycle behaviors.
class FullScreenViewState extends State<FullScreenView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();
  StreamSubscription<AudioSource?>? _currentSub;
  StreamSubscription<Duration>? _posSub;
  Duration _currentPos = Duration.zero;
  Timer? _controlsTimer;

  CoverPalette _palette = CoverPalette.fallback;
  double _animationPhase = 0.0;
  Duration _lastTickElapsed = Duration.zero;
  bool _showControls = true;
  bool _isHoveringProgress = false;

  /// Exposes whether the animation ticker is active.
  bool get isTickerActive => _ticker.isActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });

    _updatePalette(widget.controller.queue.current?.extras?['coverKey']);
    _posSub = widget.engine.positionStream.listen((pos) {
      _currentPos = pos;
    });
    _currentSub = widget.controller.currentStream.listen((source) {
      if (!mounted) return;
      _updatePalette(source?.extras?['coverKey']);
      setState(() {});
    });

    _ticker = createTicker(_onTick);

    final reduceMotion = widget.settingsStore.settings.reduceMotion;
    if (!reduceMotion) {
      _ticker.start();
    }

    _resetControlsTimer();
  }

  Future<void> _updatePalette(String? coverKey) async {
    final palette = await paletteForCover(coverKey);
    if (!mounted) return;
    setState(() {
      _palette = palette;
    });
  }

  void _onTick(Duration elapsed) {
    widget.onTickerFrame?.call();

    // 30 fps cap: only update state if >= 33ms have passed
    if (elapsed - _lastTickElapsed < const Duration(milliseconds: 33)) {
      return;
    }
    _lastTickElapsed = elapsed;

    if (!mounted) return;
    setState(() {
      _animationPhase = elapsed.inMilliseconds / 1000.0;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final reduceMotion = widget.settingsStore.settings.reduceMotion;
    if (reduceMotion) return;

    if (state == AppLifecycleState.resumed) {
      if (!_ticker.isActive) {
        _ticker.start();
      }
    } else {
      if (_ticker.isActive) {
        _ticker.stop();
      }
    }
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controlsTimer?.cancel();
    _ticker.dispose();
    _posSub?.cancel();
    _currentSub?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    _resetControlsTimer();

    if (matchesShortcut(event, AppShortcutId.back)) {
      widget.navigator.goBack();
      return KeyEventResult.handled;
    }
    if (matchesShortcut(event, AppShortcutId.playPause)) {
      widget.controller.togglePlayPause();
      return KeyEventResult.handled;
    }
    if (matchesShortcut(event, AppShortcutId.seekBackward)) {
      _seekRelative(-const Duration(seconds: 5));
      return KeyEventResult.handled;
    }
    if (matchesShortcut(event, AppShortcutId.seekForward)) {
      _seekRelative(const Duration(seconds: 5));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _seekRelative(Duration delta) {
    final target = _currentPos + delta;
    widget.engine.seek(target < Duration.zero ? Duration.zero : target);
  }

  void _toggleGlassShapes() {
    final current = widget.settingsStore.settings.fullScreenGlassShapes;
    widget.settingsStore.update((s) => s.copyWith(fullScreenGlassShapes: !current));
    _resetControlsTimer();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.controller.queue.current;
    final hasTrack = current != null;

    final title = hasTrack
        ? (current.extras?['title'] ?? context.t('library.unknownTitle'))
        : context.t('player.noTrack');
    final rawArtist = current?.extras?['artist'];
    final artist = hasTrack
        ? (rawArtist != null && rawArtist.isNotEmpty
            ? context.displayArtist(rawArtist)
            : context.t('library.unknownArtist'))
        : '—';
    final album = hasTrack ? (current.extras?['album'] ?? '') : '';
    final coverKey = current?.extras?['coverKey'];

    final settings = widget.settingsStore.settings;
    final showGlassShapes = settings.fullScreenGlassShapes;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        onHover: (_) => _resetControlsTimer(),
        onEnter: (_) => _resetControlsTimer(),
        child: Scaffold(
          backgroundColor: AppColors.base,
          body: Stack(
            children: [
              // 1. Drifting color blobs (painted via RepaintBoundary)
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _BlobPainter(
                      palette: _palette,
                      phase: settings.reduceMotion ? 0.0 : _animationPhase,
                    ),
                  ),
                ),
              ),

              // 2. Dark contrast scrim overlay
              Positioned.fill(
                child: Container(
                  color: const Color(0xB30F1115),
                ),
              ),

              // 3. Optional decorative floating glass shapes (consume 2 blur slots)
              if (showGlassShapes) ...[
                Positioned(
                  left: 80.0 + (settings.reduceMotion ? 0.0 : math.sin(_animationPhase * 0.25) * 24.0),
                  top: 140.0 + (settings.reduceMotion ? 0.0 : math.cos(_animationPhase * 0.2) * 18.0),
                  child: const GlassSurface(
                    density: GlassDensity.clear,
                    borderRadius: 28,
                    width: 320,
                    height: 200,
                    child: SizedBox.shrink(),
                  ),
                ),
                Positioned(
                  right: 90.0 + (settings.reduceMotion ? 0.0 : math.cos(_animationPhase * 0.22) * 20.0),
                  bottom: 120.0 + (settings.reduceMotion ? 0.0 : math.sin(_animationPhase * 0.28) * 16.0),
                  child: const GlassSurface(
                    density: GlassDensity.clear,
                    borderRadius: 28,
                    width: 300,
                    height: 180,
                    child: SizedBox.shrink(),
                  ),
                ),
              ],

              // 4. Main directional layout
              Positioned.fill(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final artworkSize = math.min(
                          math.max(320.0, constraints.maxHeight * 0.52),
                          520.0,
                        );

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Start side: Artwork + Metadata
                            Expanded(
                              flex: 5,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _buildArtwork(coverKey, artworkSize),
                                  const SizedBox(height: 28),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          textDirection:
                                              textDirectionFor(title),
                                          style: AppTypography.title.copyWith(
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.text,
                                          ),
                                        ),
                                      ),
                                      if (hasTrack) ...[
                                        const SizedBox(width: 10),
                                        _FullScreenFavoriteButton(
                                            path: current.uri),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    textDirection: textDirectionFor(artist),
                                    style: AppTypography.title.copyWith(
                                      fontSize: 20,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  if (album.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      album,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      textDirection: textDirectionFor(album),
                                      style: AppTypography.bodyStrong.copyWith(
                                        fontSize: 16,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 48),

                            // End side: Lyrics placeholder area
                            Expanded(
                              flex: 5,
                              child: Container(
                                padding: const EdgeInsets.all(32),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(color: AppColors.borderSubtle),
                                  color: AppColors.fillControl,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.lyrics_outlined,
                                        size: 64,
                                        color: AppColors.textMuted,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        context.t('fullScreen.lyricsPlaceholder'),
                                        style: AppTypography.title.copyWith(
                                          color: AppColors.textMuted,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),

              // 5. Top Controls bar (fades on inactivity)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(
                        children: [
                          // Credit text "by mido"
                          Text(
                            context.t('app.credit'),
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textMuted,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),

                          // Glass shapes toggle button
                          GlassIconButton(
                            key: const Key('fullscreen_toggle_glass_shapes'),
                            icon: showGlassShapes ? Icons.grain : Icons.blur_off,
                            tooltip: context.t('fullScreen.glassShapesTooltip'),
                            semanticLabel: context.t('fullScreen.glassShapesTooltip'),
                            variant: showGlassShapes
                                ? GlassButtonVariant.selected
                                : GlassButtonVariant.normal,
                            onPressed: _toggleGlassShapes,
                          ),
                          const SizedBox(width: 12),

                          // Exit full screen button
                          GlassIconButton(
                            key: const Key('fullscreen_exit_button'),
                            icon: Icons.fullscreen_exit,
                            tooltip: context.t('fullScreen.exitTooltip'),
                            semanticLabel: context.t('fullScreen.exitTooltip'),
                            onPressed: () => widget.navigator.goBack(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 6. Bottom Slender progress line (2dp high) spanning window width
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _isHoveringProgress = true),
                  onExit: (_) => setState(() => _isHoveringProgress = false),
                  child: _SlenderProgressLine(
                    engine: widget.engine,
                    controller: widget.controller,
                    isHovered: _isHoveringProgress,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArtwork(String? coverKey, double size) {
    final hasCover = coverKey != null && CoverCache.hasCover(coverKey);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32.0),
        border: Border.all(color: AppColors.border, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 36.0,
            offset: Offset(0, 14.0),
          ),
        ],
        color: AppColors.surface,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(31.0),
        child: hasCover
            ? Image.file(
                File(CoverCache.pathFor(coverKey)),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholderIcon(),
              )
            : _placeholderIcon(),
      ),
    );
  }

  Widget _placeholderIcon() {
    return const Center(
      child: Icon(
        Icons.music_note,
        size: 80,
        color: AppColors.textMuted,
      ),
    );
  }
}

/// Single CustomPainter rendering 3 large drifting color blobs.
class _BlobPainter extends CustomPainter {
  final CoverPalette palette;
  final double phase;

  _BlobPainter({required this.palette, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // Blob 1: primary color
    final p1 = Offset(
      w * (0.32 + 0.10 * math.sin(phase * 0.3)),
      h * (0.38 + 0.10 * math.cos(phase * 0.2)),
    );
    final paint1 = Paint()
      ..color = palette.primary.withValues(alpha: 0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 120.0);
    canvas.drawCircle(p1, w * 0.35, paint1);

    // Blob 2: secondary color
    final p2 = Offset(
      w * (0.68 + 0.12 * math.cos(phase * 0.25)),
      h * (0.55 + 0.08 * math.sin(phase * 0.35)),
    );
    final paint2 = Paint()
      ..color = palette.secondary.withValues(alpha: 0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 130.0);
    canvas.drawCircle(p2, w * 0.38, paint2);

    // Blob 3: tertiary color
    final p3 = Offset(
      w * (0.48 + 0.10 * math.sin(phase * 0.18)),
      h * (0.75 + 0.08 * math.cos(phase * 0.22)),
    );
    final paint3 = Paint()
      ..color = palette.tertiary.withValues(alpha: 0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 120.0);
    canvas.drawCircle(p3, w * 0.34, paint3);
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.palette != palette;
  }
}

/// Slender 2dp progress line spanning the bottom edge of the screen.
class _SlenderProgressLine extends StatelessWidget {
  final AudioEngine engine;
  final PlaybackController? controller;
  final bool isHovered;

  const _SlenderProgressLine({
    required this.engine,
    this.controller,
    required this.isHovered,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: engine.durationStream,
      initialData: controller?.currentDuration ?? engine.currentDuration,
      builder: (context, durSnapshot) {
        final total = (controller != null && controller!.currentState == PlaybackState.idle)
            ? controller!.currentDuration
            : (durSnapshot.data != null && durSnapshot.data! > Duration.zero
                ? durSnapshot.data!
                : (controller?.currentDuration ?? Duration.zero));

        return StreamBuilder<Duration>(
          stream: engine.positionStream,
          initialData: controller?.currentPosition ?? engine.currentPosition,
          builder: (context, posSnapshot) {
            final pos = (controller != null && controller!.currentState == PlaybackState.idle)
                ? controller!.currentPosition
                : (posSnapshot.data ?? controller?.currentPosition ?? Duration.zero);
            final progress = total.inMilliseconds > 0
                ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                : 0.0;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isHovered)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          context.formatDurationLocalized(pos),
                          style: AppTypography.micro.copyWith(color: AppColors.textMuted),
                        ),
                        Text(
                          context.formatDurationLocalized(total),
                          style: AppTypography.micro.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                // 2dp slender progress bar
                Container(
                  height: 2.0,
                  width: double.infinity,
                  color: AppColors.borderSubtle,
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: progress,
                    child: Container(
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _FullScreenFavoriteButton extends StatelessWidget {
  final String path;

  const _FullScreenFavoriteButton({required this.path});

  @override
  Widget build(BuildContext context) {
    final collections = UserCollectionsScope.maybeOf(context);
    if (collections == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: collections,
      builder: (context, _) {
        final isFav = collections.isFavorite(path);

        return IconButton(
          key: const Key('fullscreen_favorite_button'),
          icon: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            size: 24,
            color: isFav ? AppColors.accent : AppColors.textMuted,
          ),
          tooltip: isFav
              ? context.t('track.unfavorite')
              : context.t('track.favorite'),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => collections.toggleFavorite(path),
        );
      },
    );
  }
}
