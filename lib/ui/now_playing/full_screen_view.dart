import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../audio/audio_engine.dart';
import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/lyrics/lyrics_controller.dart';
import '../../features/lyrics/lyrics_repository.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_quality.dart';
import '../glass/glass_scope.dart';
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
import '../theme/dither_noise.dart';
import 'cover_palette.dart';
import 'widgets/full_screen_blob_painters.dart';
import 'widgets/full_screen_chrome.dart';
import 'widgets/full_screen_seek_bar.dart';

export 'widgets/full_screen_seek_bar.dart' show FullScreenSeekDragState;

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final GlobalKey _seekBarKey = GlobalKey();
  final GlobalKey _lyricsKey = GlobalKey();
  final GlobalKey _topBarKey = GlobalKey();
  final GlobalKey _controlsColumnKey = GlobalKey();
  Offset? _lastDoubleTapPosition;
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
  FullScreenSeekDragState? _dragTooltipState;

  /// Exposes whether the animation ticker is active.
  bool get isTickerActive => _ticker.isActive;

  static Alignment _resolveFillAlignment(bool isRtl) =>
      isRtl ? Alignment.centerRight : Alignment.centerLeft;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTickerWithSettings();
  }

  void _syncTickerWithSettings() {
    final reduceMotion = widget.settingsStore.settings.reduceMotion;
    final isVisible = TickerMode.valuesOf(context).enabled;
    if (reduceMotion || !_isAppResumed || !isVisible) {
      if (_ticker.isActive) {
        _ticker.stop();
      }
      if (reduceMotion && _phaseNotifier.value != 0.0) {
        _phaseNotifier.value = 0.0;
      }
    } else if (_isAppResumed && isVisible && !_ticker.isActive) {
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

  bool _isInteractiveArea(Offset globalPosition) {
    bool hits(GlobalKey key) {
      final ctx = key.currentContext;
      if (ctx == null) return false;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return false;
      final origin = box.localToGlobal(Offset.zero);
      final rect = origin & box.size;
      return rect.contains(globalPosition);
    }

    // 1. Seek bar
    if (hits(_seekBarKey)) return true;
    final size = MediaQuery.sizeOf(context);
    if (globalPosition.dy >= size.height - 32.0) return true;

    // 2. Top bar controls
    if (hits(_topBarKey)) return true;
    if (globalPosition.dy <= MediaQuery.paddingOf(context).top + 64.0) return true;

    // 3. Lyrics view
    if (hits(_lyricsKey)) return true;

    // 4. Metadata controls
    if (hits(_controlsColumnKey)) return true;

    return false;
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _lastDoubleTapPosition = details.globalPosition;
  }

  void _handleDoubleTap() {
    _resetControlsTimer();
    final pos = _lastDoubleTapPosition;
    if (pos != null && _isInteractiveArea(pos)) {
      return;
    }

    final isPlaying = widget.controller.currentState == PlaybackState.playing;
    if (isPlaying) {
      widget.controller.pause();
    } else {
      widget.controller.play();
    }
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
    widget.settingsStore
        .update((s) => s.copyWith(fullScreenGlassShapes: !current));
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

    final storeQuality = widget.settingsStore.settings.glassQuality;
    final quality = (storeQuality != GlassQuality.full)
        ? storeQuality
        : GlassScope.qualityOf(context);

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
              // 1. Drifting color blobs (controlled by GlassQuality tier)
              if (quality == GlassQuality.full) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: createFullScreenBlobPainter(
                          palette: _palette,
                          phaseListenable: _phaseNotifier,
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DitherOverlay(),
                  ),
                ),
              ] else if (quality == GlassQuality.light) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: createFullScreenStaticBlobPainter(
                          palette: _palette,
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DitherOverlay(),
                  ),
                ),
              ],

              // 2. Dark contrast scrim overlay
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: const Color(0xB30F1115),
                  ),
                ),
              ),

              // 3. Optional decorative static glass shapes (consume 2 blur slots)
              if (showGlassShapes) ...const [
                Positioned(
                  left: 80.0,
                  top: 140.0,
                  child: IgnorePointer(
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
                ),
                Positioned(
                  right: 90.0,
                  bottom: 120.0,
                  child: IgnorePointer(
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
                ),
              ],

              // Background double click detector for play/pause toggle
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('fullscreen_background_gesture_detector'),
                  behavior: HitTestBehavior.opaque,
                  onDoubleTapDown: _onDoubleTapDown,
                  onDoubleTap: _handleDoubleTap,
                  child: const SizedBox.expand(),
                ),
              ),

              // 4. Main directional layout
              Positioned.fill(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 32,
                    ),
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
                              child: FullScreenArtworkColumn(
                                coverKey: coverKey,
                                artworkSize: artworkSize,
                                controlsColumnKey: _controlsColumnKey,
                                hasTrack: hasTrack,
                                trackUri: current?.uri,
                                title: title,
                                artist: artist,
                                rawArtist: rawArtist,
                                album: album,
                                reduceMotion:
                                    widget.settingsStore.settings.reduceMotion,
                                navigator: widget.navigator,
                              ),
                            ),
                            if (widget.settingsStore.settings.showLyricsInFullScreen) ...[
                              const SizedBox(width: 48),
                              Expanded(
                                flex: 5,
                                child: KeyedSubtree(
                                  key: _lyricsKey,
                                  child: LyricsView(
                                    controller: _lyricsController,
                                    playbackController: widget.controller,
                                    settingsStore: widget.settingsStore,
                                    navigator: widget.navigator,
                                    showHeader: false,
                                    isFullScreen: true,
                                  ),
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
                  key: _topBarKey,
                  child: FullScreenTopBar(
                    showControls: _showControls,
                    showGlassShapes: showGlassShapes,
                    navigator: widget.navigator,
                    miniPlayerController: widget.miniPlayerController,
                    onToggleGlassShapes: _toggleGlassShapes,
                  ),
                ),
              ),

              // 6. Bottom seek bar spanning window width (fixed 28 dp strip, track at bottom: 0)
              Positioned(
                key: const ValueKey('fullscreen_seek_bar_slot'),
                bottom: 0,
                left: 0,
                right: 0,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: RepaintBoundary(
                    key: _seekBarKey,
                    child: FullScreenSeekBar(
                      key: const ValueKey('fullscreen_seek_bar_line'),
                      engine: widget.engine,
                      controller: widget.controller,
                      reduceMotion: widget.settingsStore.settings.reduceMotion,
                      resolveFillAlignment: _resolveFillAlignment,
                      onInteractionChanged: _onScrubberInteractionChanged,
                      onDragStateChanged: (state) {
                        if (mounted) {
                          setState(() => _dragTooltipState = state);
                        }
                      },
                    ),
                  ),
                ),
              ),

              // 7. Tooltip overlay while dragging (floats above pointer in page Stack)
              if (_dragTooltipState != null)
                Positioned(
                  key: const ValueKey('fullscreen_seek_tooltip_slot'),
                  left: (_dragTooltipState!.pointerDx - 32.0).clamp(
                    8.0,
                    math.max(8.0, MediaQuery.sizeOf(context).width - 72.0),
                  ),
                  bottom: 36.0,
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
                        context.formatDurationLocalized(
                          _dragTooltipState!.position,
                        ),
                        style: AppTypography.micro.copyWith(
                          color: AppColors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
}
