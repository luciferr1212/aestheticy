import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../audio/audio_engine.dart';
import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/collections/user_collections.dart';
import '../../features/lyrics/lyrics_controller.dart';
import '../../features/lyrics/lyrics_repository.dart';
import '../../library/cover_cache.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../lyrics/lyrics_view.dart';
import '../mini_player/mini_player_controller.dart';
import '../settings/app_shortcuts.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'cover_palette.dart';
import 'seek_bar_helper.dart';

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

  /// Optional lyrics controller.
  final LyricsController? lyricsController;

  /// Optional mini player controller.
  final MiniPlayerController? miniPlayerController;

  /// Optional callback invoked on ticker frame (for test verification).
  final VoidCallback? onTickerFrame;

  /// Optional subtree probe builder used in tests to measure rebuild counts.
  @visibleForTesting
  final WidgetBuilder? debugProbeBuilder;

  /// Creates a [FullScreenView].
  const FullScreenView({
    super.key,
    required this.controller,
    required this.engine,
    required this.navigator,
    required this.settingsStore,
    this.lyricsController,
    this.miniPlayerController,
    this.onTickerFrame,
    this.debugProbeBuilder,
  });

  @override
  State<FullScreenView> createState() => FullScreenViewState();
}

/// Exposed state for testing ticker and lifecycle behaviors.
class FullScreenViewState extends State<FullScreenView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();
  late final LyricsController _lyricsController;
  bool _createdLyricsControllerLocally = false;
  StreamSubscription<AudioSource?>? _currentSub;
  Timer? _controlsTimer;

  CoverPalette _palette = CoverPalette.fallback;
  final ValueNotifier<double> _phaseNotifier = ValueNotifier<double>(0.0);
  Duration _lastTickElapsed = Duration.zero;
  bool _showControls = true;
  bool _isScrubberActive = false;
  bool _isAppResumed = true;

  /// Exposes whether the animation ticker is active.
  bool get isTickerActive => _ticker.isActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settingsStore.addListener(_onSettingsChanged);
    if (widget.lyricsController != null) {
      _lyricsController = widget.lyricsController!;
    } else {
      _lyricsController = LyricsController(
        playbackController: widget.controller,
        repository: LyricsRepository(),
        settingsStore: widget.settingsStore,
      );
      _createdLyricsControllerLocally = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });

    _updatePalette(widget.controller.queue.current?.extras?['coverKey']);
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

  @override
  void didUpdateWidget(FullScreenView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settingsStore != widget.settingsStore) {
      oldWidget.settingsStore.removeListener(_onSettingsChanged);
      widget.settingsStore.addListener(_onSettingsChanged);
      _syncTickerWithSettings();
    }
  }

  void _onSettingsChanged() {
    _syncTickerWithSettings();
    if (mounted) {
      setState(() {});
    }
  }

  void _syncTickerWithSettings() {
    final reduceMotion = widget.settingsStore.settings.reduceMotion;
    if (reduceMotion) {
      if (_ticker.isActive) {
        _ticker.stop();
      }
      if (_phaseNotifier.value != 0.0) {
        _phaseNotifier.value = 0.0;
      }
    } else if (_isAppResumed && !_ticker.isActive) {
      _ticker.start();
    }
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

    // 30 fps cap: only advance paint phase if >= 33ms have passed.
    if (elapsed - _lastTickElapsed < const Duration(milliseconds: 33)) {
      return;
    }
    _lastTickElapsed = elapsed;

    if (!mounted || widget.settingsStore.settings.reduceMotion) return;
    _phaseNotifier.value = elapsed.inMilliseconds / 1000.0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppResumed = state == AppLifecycleState.resumed;
    final reduceMotion = widget.settingsStore.settings.reduceMotion;
    if (reduceMotion) return;

    if (_isAppResumed) {
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
    if (_isScrubberActive) {
      return;
    }
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isScrubberActive) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onScrubberInteractionChanged(bool active) {
    _isScrubberActive = active;
    if (active) {
      _controlsTimer?.cancel();
      if (!_showControls && mounted) {
        setState(() => _showControls = true);
      }
    } else {
      _resetControlsTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settingsStore.removeListener(_onSettingsChanged);
    if (_createdLyricsControllerLocally) {
      _lyricsController.dispose();
    }
    _controlsTimer?.cancel();
    _ticker.stop();
    _ticker.dispose();
    _phaseNotifier.dispose();
    _currentSub?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    _resetControlsTimer();
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (matchesShortcut(event, AppShortcutId.back)) {
      widget.navigator.goBack();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
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
              // 1. Drifting color blobs (painted via RepaintBoundary without page setState)
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _BlobPainter(
                      palette: _palette,
                      phaseListenable: _phaseNotifier,
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

              // 3. Optional decorative static glass shapes (consume 2 blur slots)
              if (showGlassShapes) ...const [
                Positioned(
                  left: 80.0,
                  top: 140.0,
                  child: RepaintBoundary(
                    child: GlassSurface(
                      density: GlassDensity.clear,
                      borderRadius: 28,
                      width: 320,
                      height: 200,
                      child: SizedBox.shrink(),
                    ),
                  ),
                ),
                Positioned(
                  right: 90.0,
                  bottom: 120.0,
                  child: RepaintBoundary(
                    child: GlassSurface(
                      density: GlassDensity.clear,
                      borderRadius: 28,
                      width: 300,
                      height: 180,
                      child: SizedBox.shrink(),
                    ),
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
                            if (widget.settingsStore.settings.showLyricsInFullScreen) ...[
                              const SizedBox(width: 48),
                              Expanded(
                                flex: 5,
                                child: LyricsView(
                                  controller: _lyricsController,
                                  playbackController: widget.controller,
                                  settingsStore: widget.settingsStore,
                                  navigator: widget.navigator,
                                  showHeader: false,
                                  isFullScreen: true,
                                ),
                              ),
                            ],
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
                          if (widget.miniPlayerController != null) ...[
                            const SizedBox(width: 12),
                            GlassIconButton(
                              key: const Key('fullscreen_mini_player_button'),
                              icon: Icons.picture_in_picture_alt_outlined,
                              tooltip: context.t('miniPlayer.enterTooltip'),
                              semanticLabel: context.t('miniPlayer.enterTooltip'),
                              onPressed: () {
                                widget.navigator.goBack();
                                widget.miniPlayerController?.enter();
                              },
                            ),
                          ],
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

              // 6. Bottom seek bar spanning window width (fixed 36 dp box)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: RepaintBoundary(
                  child: _SlenderProgressLine(
                    engine: widget.engine,
                    controller: widget.controller,
                    reduceMotion: widget.settingsStore.settings.reduceMotion,
                    onInteractionChanged: _onScrubberInteractionChanged,
                  ),
                ),
              ),
              if (widget.debugProbeBuilder != null)
                Positioned(
                  left: 0,
                  top: 0,
                  child: widget.debugProbeBuilder!(context),
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
  final ValueListenable<double> phaseListenable;

  _BlobPainter({
    required this.palette,
    required this.phaseListenable,
  }) : super(repaint: phaseListenable);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final phase = phaseListenable.value;

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
    return oldDelegate.palette != palette ||
        oldDelegate.phaseListenable != phaseListenable;
  }
}

/// Interactive progress line spanning the bottom edge of the screen.
class _SlenderProgressLine extends StatefulWidget {
  final AudioEngine engine;
  final PlaybackController? controller;
  final bool reduceMotion;
  final ValueChanged<bool>? onInteractionChanged;

  const _SlenderProgressLine({
    required this.engine,
    this.controller,
    this.reduceMotion = false,
    this.onInteractionChanged,
  });

  @override
  State<_SlenderProgressLine> createState() => _SlenderProgressLineState();
}

class _SlenderProgressLineState extends State<_SlenderProgressLine> {
  static const Duration _kDragSeekThrottle = Duration(milliseconds: 120);
  static const Duration _kSemanticsSeekStep = Duration(seconds: 5);

  bool _isHovered = false;
  bool _isDragging = false;
  double? _dragFraction;
  double _pointerDx = 0.0;
  Timer? _seekThrottleTimer;
  Duration? _pendingSeekTarget;
  Duration _activeTotalDuration = Duration.zero;
  StreamSubscription<Duration>? _seekSub;

  @override
  void initState() {
    super.initState();
    _subscribeSeekStream();
  }

  @override
  void didUpdateWidget(_SlenderProgressLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _seekSub?.cancel();
      _subscribeSeekStream();
    }
  }

  void _subscribeSeekStream() {
    _seekSub = widget.controller?.seekStream.listen((_) {
      if (mounted && widget.controller?.currentState == PlaybackState.idle) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _seekThrottleTimer?.cancel();
    _seekSub?.cancel();
    super.dispose();
  }

  void _setHover(bool hovered) {
    if (_isHovered == hovered) return;
    final wasActive = _isHovered || _isDragging;
    setState(() => _isHovered = hovered);
    final isActive = _isHovered || _isDragging;
    if (wasActive != isActive) {
      widget.onInteractionChanged?.call(isActive);
    }
  }

  void _dispatchSeekImmediate(Duration target, Duration total) {
    if (total <= Duration.zero) return;
    dispatchSeekBarSeek(
      engine: widget.engine,
      controller: widget.controller,
      target: target,
      totalDuration: total,
    );
    if (widget.controller?.currentState == PlaybackState.idle && mounted) {
      setState(() {});
    }
  }

  void _scheduleThrottledSeek(Duration target, Duration total) {
    _activeTotalDuration = total;
    if (total <= Duration.zero) return;
    if (_seekThrottleTimer == null) {
      _dispatchSeekImmediate(target, total);
      _seekThrottleTimer = Timer(_kDragSeekThrottle, _onThrottleElapsed);
    } else {
      _pendingSeekTarget = target;
    }
  }

  void _onThrottleElapsed() {
    _seekThrottleTimer = null;
    if (!_isDragging) {
      _pendingSeekTarget = null;
      return;
    }
    final pending = _pendingSeekTarget;
    _pendingSeekTarget = null;
    if (pending != null && _activeTotalDuration > Duration.zero) {
      _dispatchSeekImmediate(pending, _activeTotalDuration);
      _seekThrottleTimer = Timer(_kDragSeekThrottle, _onThrottleElapsed);
    }
  }

  void _handleTapUp(
    TapUpDetails details,
    double width,
    bool isRtl,
    Duration total,
  ) {
    if (total <= Duration.zero) return;
    final frac = seekBarFractionForDx(
      dx: details.localPosition.dx,
      width: width,
      isRtl: isRtl,
    );
    final target = seekBarDurationForFraction(
      fraction: frac,
      totalDuration: total,
    );
    _dispatchSeekImmediate(target, total);
  }

  void _handleDragStart(
    DragStartDetails details,
    double width,
    bool isRtl,
    Duration total,
  ) {
    final wasActive = _isHovered || _isDragging;
    final frac = seekBarFractionForDx(
      dx: details.localPosition.dx,
      width: width,
      isRtl: isRtl,
    );
    setState(() {
      _isDragging = true;
      _pointerDx = details.localPosition.dx.clamp(0.0, width);
      _dragFraction = total > Duration.zero ? frac : null;
    });
    if (!wasActive) {
      widget.onInteractionChanged?.call(true);
    }
    if (total > Duration.zero) {
      final target = seekBarDurationForFraction(
        fraction: frac,
        totalDuration: total,
      );
      _scheduleThrottledSeek(target, total);
    }
  }

  void _handleDragUpdate(
    DragUpdateDetails details,
    double width,
    bool isRtl,
    Duration total,
  ) {
    final frac = seekBarFractionForDx(
      dx: details.localPosition.dx,
      width: width,
      isRtl: isRtl,
    );
    setState(() {
      _pointerDx = details.localPosition.dx.clamp(0.0, width);
      _dragFraction = total > Duration.zero ? frac : null;
    });
    if (total > Duration.zero) {
      final target = seekBarDurationForFraction(
        fraction: frac,
        totalDuration: total,
      );
      _scheduleThrottledSeek(target, total);
    }
  }

  void _finishDrag(Duration total, {required bool commitSeek}) {
    _seekThrottleTimer?.cancel();
    _seekThrottleTimer = null;
    final pending = _pendingSeekTarget;
    _pendingSeekTarget = null;
    final frac = _dragFraction;
    if (commitSeek && total > Duration.zero) {
      final target = pending ??
          (frac != null
              ? seekBarDurationForFraction(fraction: frac, totalDuration: total)
              : null);
      if (target != null) {
        _dispatchSeekImmediate(target, total);
      }
    }
    final wasActive = _isHovered || _isDragging;
    setState(() {
      _isDragging = false;
      _dragFraction = null;
    });
    final isActive = _isHovered || _isDragging;
    if (wasActive != isActive) {
      widget.onInteractionChanged?.call(isActive);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return StreamBuilder<Duration>(
      stream: widget.engine.durationStream,
      initialData:
          widget.controller?.currentDuration ?? widget.engine.currentDuration,
      builder: (context, durSnapshot) {
        final total = resolveSeekBarDuration(
          engine: widget.engine,
          controller: widget.controller,
          streamDuration: durSnapshot.data,
        );

        return StreamBuilder<Duration>(
          stream: widget.engine.positionStream,
          initialData: widget.controller?.currentPosition ??
              widget.engine.currentPosition,
          builder: (context, posSnapshot) {
            final pos = resolveSeekBarPosition(
              engine: widget.engine,
              controller: widget.controller,
              streamPosition: posSnapshot.data,
            );
            final displayFraction = _dragFraction ??
                (total.inMilliseconds > 0
                    ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                    : 0.0);
            final displayPos = _dragFraction != null
                ? seekBarDurationForFraction(
                    fraction: displayFraction,
                    totalDuration: total,
                  )
                : pos;
            final active = _isHovered || _isDragging;

            return Semantics(
              slider: true,
              label: context.t('fullScreen.seekBarLabel'),
              value: context.formatDurationLocalized(displayPos),
              increasedValue: total > Duration.zero
                  ? context.formatDurationLocalized(
                      clampSeekTarget(displayPos + _kSemanticsSeekStep, total),
                    )
                  : null,
              decreasedValue: total > Duration.zero
                  ? context.formatDurationLocalized(
                      clampSeekTarget(displayPos - _kSemanticsSeekStep, total),
                    )
                  : null,
              onIncrease: total > Duration.zero
                  ? () => _dispatchSeekImmediate(
                        displayPos + _kSemanticsSeekStep,
                        total,
                      )
                  : null,
              onDecrease: total > Duration.zero
                  ? () => _dispatchSeekImmediate(
                        displayPos - _kSemanticsSeekStep,
                        total,
                      )
                  : null,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final thumbCenterX = ((isRtl
                              ? (1.0 - displayFraction)
                              : displayFraction) *
                          width)
                      .clamp(6.0, math.max(6.0, width - 6.0));
                  final tooltipLeft =
                      (_pointerDx - 32.0).clamp(8.0, math.max(8.0, width - 72.0)).toDouble();

                  final animDuration = widget.reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 140);

                  return SizedBox(
                    height: 36.0,
                    width: double.infinity,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: MouseRegion(
                            cursor: total > Duration.zero
                                ? SystemMouseCursors.click
                                : MouseCursor.defer,
                            onEnter: (_) => _setHover(true),
                            onExit: (_) => _setHover(false),
                            child: GestureDetector(
                              key: const Key('fullscreen_seek_bar'),
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) =>
                                  _handleTapUp(details, width, isRtl, total),
                              onHorizontalDragStart: (details) =>
                                  _handleDragStart(details, width, isRtl, total),
                              onHorizontalDragUpdate: (details) =>
                                  _handleDragUpdate(details, width, isRtl, total),
                              onHorizontalDragEnd: (_) =>
                                  _finishDrag(total, commitSeek: true),
                              onHorizontalDragCancel: () =>
                                  _finishDrag(total, commitSeek: false),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 16.0,
                                    child: Container(
                                      key: const Key('fullscreen_seek_track'),
                                      height: 4.0,
                                      color: AppColors.borderSubtle,
                                      child: FractionallySizedBox(
                                        alignment: isRtl
                                            ? Alignment.centerRight
                                            : Alignment.centerLeft,
                                        widthFactor: displayFraction,
                                        child: AnimatedContainer(
                                          key: const Key('fullscreen_seek_fill'),
                                          duration: animDuration,
                                          curve: Curves.easeOutCubic,
                                          color: active
                                              ? AppColors.accent
                                              : AppColors.accent
                                                  .withValues(alpha: 0.72),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: thumbCenterX - 6.0,
                                    bottom: 12.0,
                                    child: IgnorePointer(
                                      child: AnimatedScale(
                                        key: const Key(
                                          'fullscreen_seek_thumb_scale',
                                        ),
                                        scale: active ? 1.0 : 0.0,
                                        duration: animDuration,
                                        curve: Curves.easeOutCubic,
                                        child: Container(
                                          key: const Key('fullscreen_seek_thumb'),
                                          width: 12.0,
                                          height: 12.0,
                                          decoration: const BoxDecoration(
                                            color: AppColors.accent,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (active)
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 38.0,
                            child: IgnorePointer(
                              child: Row(
                                key: const Key('fullscreen_seek_times'),
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    context.formatDurationLocalized(displayPos),
                                    style: AppTypography.micro
                                        .copyWith(color: AppColors.textMuted),
                                  ),
                                  Text(
                                    context.formatDurationLocalized(total),
                                    style: AppTypography.micro
                                        .copyWith(color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_isDragging && total > Duration.zero)
                          Positioned(
                            left: tooltipLeft,
                            bottom: 62.0,
                            child: IgnorePointer(
                              child: Container(
                                key: const Key('fullscreen_seek_tooltip'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Text(
                                  context.formatDurationLocalized(displayPos),
                                  style: AppTypography.micro.copyWith(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
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
