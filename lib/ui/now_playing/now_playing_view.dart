import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/audio_engine.dart';
import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/lyrics/lyrics_controller.dart';
import '../../features/lyrics/lyrics_repository.dart';
import '../../library/cover_cache.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../glass/glass_quality.dart';
import '../glass/glass_scope.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../lyrics/lyrics_view.dart';
import '../settings/app_shortcuts.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/dither_noise.dart';
import 'cover_palette.dart';
import 'widgets/now_playing_controls.dart';
import 'widgets/now_playing_metadata_area.dart';
import 'widgets/now_playing_seek_bar.dart';
import 'widgets/now_playing_up_next_list.dart';

export 'widgets/now_playing_seek_bar.dart';

/// Full-window Now Playing screen with two-column responsive layout,
/// artwork, transport controls, isolated seekbar, up next queue, and stream info.
class NowPlayingView extends StatefulWidget {
  /// The audio playback controller.
  final PlaybackController controller;

  /// The underlying audio engine.
  final AudioEngine engine;

  /// App navigation coordinator.
  final AppNavigator navigator;

  /// User settings store.
  final SettingsStore settingsStore;

  /// Optional lyrics controller.
  final LyricsController? lyricsController;

  /// Optional callback invoked when track metadata is built (for test counters).
  final VoidCallback? onMetadataBuild;

  /// Creates a [NowPlayingView].
  const NowPlayingView({
    super.key,
    required this.controller,
    required this.engine,
    required this.navigator,
    required this.settingsStore,
    this.lyricsController,
    this.onMetadataBuild,
  });

  @override
  State<NowPlayingView> createState() => _NowPlayingViewState();
}

class _NowPlayingViewState extends State<NowPlayingView> {
  final FocusNode _focusNode = FocusNode();
  late final LyricsController _lyricsController;
  bool _createdLyricsControllerLocally = false;
  StreamSubscription<AudioSource?>? _currentSub;
  StreamSubscription<void>? _queueSub;
  CoverPalette _palette = CoverPalette.fallback;
  int _activeTabIndex = 0; // 0: Up next, 1: Lyrics

  @override
  void initState() {
    super.initState();
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
    widget.settingsStore.addListener(_onSettingsChanged);
    _updatePalette(widget.controller.queue.current?.extras?['coverKey']);
    _currentSub = widget.controller.currentStream.listen((source) {
      if (!mounted) return;
      _updatePalette(source?.extras?['coverKey']);
      setState(() {});
    });
    _queueSub = widget.controller.queueChangeStream.listen((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(NowPlayingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settingsStore != widget.settingsStore) {
      oldWidget.settingsStore.removeListener(_onSettingsChanged);
      widget.settingsStore.addListener(_onSettingsChanged);
    }
    if (oldWidget.controller != widget.controller) {
      _currentSub?.cancel();
      _queueSub?.cancel();
      _currentSub = widget.controller.currentStream.listen((source) {
        if (!mounted) return;
        _updatePalette(source?.extras?['coverKey']);
        setState(() {});
      });
      _queueSub = widget.controller.queueChangeStream.listen((_) {
        if (!mounted) return;
        setState(() {});
      });
    }
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _updatePalette(String? coverKey) async {
    final palette = await paletteForCover(coverKey);
    if (!mounted) return;
    setState(() {
      _palette = palette;
    });
  }

  @override
  void dispose() {
    widget.settingsStore.removeListener(_onSettingsChanged);
    if (_createdLyricsControllerLocally) {
      _lyricsController.dispose();
    }
    _currentSub?.cancel();
    _queueSub?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _cycleRepeat() {
    unawaited(widget.controller.cycleRepeatMode());
  }

  void _toggleShuffle() {
    unawaited(widget.controller.setShuffle(!widget.controller.queue.isShuffled));
  }

  Future<void> _clearUpcoming() async {
    await widget.controller.clearUpcoming();
    setState(() {});
  }

  Future<void> _playUpcoming(int index) async {
    await widget.controller.playTrack(index);
    setState(() {});
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (matchesShortcut(event, AppShortcutId.back)) {
      widget.navigator.goBack();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
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

    final storeQuality = widget.settingsStore.settings.glassQuality;
    final quality = (storeQuality != GlassQuality.full)
        ? storeQuality
        : GlassScope.qualityOf(context);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppColors.base,
        body: Stack(
          children: [
            // 1. Ambient radial glow from CoverPalette (adapting to GlassQuality)
            if (quality == GlassQuality.full) ...[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.5, 0.0),
                      radius: 0.9,
                      colors: [
                        _palette.primary.withValues(alpha: 0.24),
                        _palette.secondary.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: DitherOverlay(),
              ),
            ] else if (quality == GlassQuality.light) ...[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.5, 0.0),
                      radius: 0.9,
                      colors: [
                        _palette.primary.withValues(alpha: 0.15),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: DitherOverlay(),
              ),
            ],

            // 2. Dark scrim ensuring text contrast >= 4.5:1
            Positioned.fill(
              child: Container(
                color: const Color(0xB30F1115),
              ),
            ),

            // 3. Main content
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Column(
                    children: [
                      // Top Bar: Back button & Full-screen button
                      _buildTopBar(context),
                      const SizedBox(height: 16),

                      // Two-column layout
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final artworkSize = math.min(
                              math.max(260.0, constraints.maxHeight * 0.44),
                              380.0,
                            );

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Start column: Artwork + Metadata + Seekbar + Transport
                                Expanded(
                                  flex: 5,
                                  child: SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        const SizedBox(height: 8),
                                        _buildArtwork(coverKey, artworkSize),
                                        const SizedBox(height: 20),
                                        NowPlayingMetadataArea(
                                          title: title,
                                          artist: artist,
                                          album: album,
                                          rawArtist: rawArtist,
                                          navigator: widget.navigator,
                                          reduceMotion: widget.settingsStore
                                              .settings.reduceMotion,
                                          trackPath: current?.uri,
                                          onBuild: widget.onMetadataBuild,
                                        ),
                                        const SizedBox(height: 16),
                                        // Isolated seekbar leaf widget (zero rebuilds on ticks)
                                        Directionality(
                                          textDirection: TextDirection.ltr,
                                          child: NowPlayingSeekBar(
                                            engine: widget.engine,
                                            controller: widget.controller,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        // Transport row (strictly LTR)
                                        Directionality(
                                          textDirection: TextDirection.ltr,
                                          child: NowPlayingTransportRow(
                                            controller: widget.controller,
                                            onToggleShuffle: _toggleShuffle,
                                            onCycleRepeat: _cycleRepeat,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 24),

                                // End column: GlassSurface card with Up Next / Lyrics tabs
                                Expanded(
                                  flex: 6,
                                  child: _buildEndCard(context),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        // Back to Library button
        GlassPillButton(
          leadingIcon: Icons.chevron_left,
          matchTextDirection: true,
          label: context.t('nav.library'),
          tooltip: context.t('nav.library'),
          semanticLabel: context.t('nav.library'),
          onPressed: () => widget.navigator.goBack(),
        ),
        const Spacer(),
        // Lyrics button
        GlassIconButton(
          key: const Key('now_playing_lyrics_button'),
          icon: Icons.lyrics_outlined,
          tooltip: context.t('common.lyrics'),
          semanticLabel: context.t('common.lyrics'),
          onPressed: () => widget.navigator.openLyrics(),
        ),
        const SizedBox(width: 8),
        // Full screen button
        GlassIconButton(
          key: const Key('now_playing_fullscreen_button'),
          icon: Icons.fullscreen,
          tooltip: context.t('common.fullScreen'),
          semanticLabel: context.t('common.fullScreen'),
          onPressed: () => widget.navigator.openFullScreen(),
        ),
      ],
    );
  }

  Widget _buildArtwork(String? coverKey, double size) {
    final hasCover = coverKey != null && CoverCache.hasCover(coverKey);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26.0),
        border: Border.all(color: AppColors.border, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20.0,
            offset: Offset(0, 8.0),
          ),
        ],
        color: AppColors.surface,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25.0),
        child: hasCover
            ? Image.file(
                File(CoverCache.pathFor(coverKey)),
                fit: BoxFit.cover,
                cacheWidth: 1024,
                gaplessPlayback: true,
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
        size: 64,
        color: AppColors.textMuted,
      ),
    );
  }

  Widget _buildEndCard(BuildContext context) {
    return GlassSurface(
      density: GlassDensity.clear,
      borderRadius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header tabs row: "Up next" & "Lyrics" + "Clear upcoming"
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Up next tab
                InkWell(
                  borderRadius: BorderRadius.circular(AppSpacing.r12),
                  onTap: () => setState(() => _activeTabIndex = 0),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      context.t('nowPlaying.upNext'),
                      style: AppTypography.bodyStrong.copyWith(
                        color: _activeTabIndex == 0
                            ? AppColors.text
                            : AppColors.textMuted,
                        fontWeight: _activeTabIndex == 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Lyrics tab
                InkWell(
                  borderRadius: BorderRadius.circular(AppSpacing.r12),
                  onTap: () => setState(() => _activeTabIndex = 1),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      context.t('nowPlaying.lyrics'),
                      style: AppTypography.bodyStrong.copyWith(
                        color: _activeTabIndex == 1
                            ? AppColors.text
                            : AppColors.textMuted,
                        fontWeight: _activeTabIndex == 1
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Open queue & Clear upcoming buttons (visible only in Up next tab)
                if (_activeTabIndex == 0) ...[
                  TextButton(
                    key: const Key('now_playing_open_queue_button'),
                    onPressed: () => widget.navigator.openQueue(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                    child: Text(
                      context.t('nowPlaying.openQueue'),
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _clearUpcoming,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                    child: Text(
                      context.t('nowPlaying.clearUpcoming'),
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tab content area
          Expanded(
            child: _activeTabIndex == 0
                ? NowPlayingUpNextList(
                    controller: widget.controller,
                    onPlayUpcoming: _playUpcoming,
                  )
                : _buildLyricsView(context),
          ),
          const SizedBox(height: 12),

          // Bottom card accessories: Stream info & Volume slider
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Isolated stream info pill
                InkWell(
                  key: const Key('now_playing_stream_info_pill'),
                  borderRadius: BorderRadius.circular(AppSpacing.pill),
                  onTap: () => widget.navigator.openAudioPanels(),
                  child: NowPlayingStreamInfoPill(engine: widget.engine),
                ),
                const SizedBox(width: 8),
                GlassIconButton(
                  key: const Key('now_playing_eq_button'),
                  icon: Icons.equalizer,
                  tooltip: context.t('nowPlaying.equalizer'),
                  semanticLabel: context.t('nowPlaying.equalizer'),
                  onPressed: () => widget.navigator.openAudioPanels(),
                ),
                const SizedBox(width: 8),
                GlassIconButton(
                  key: const Key('now_playing_signal_path_button'),
                  icon: Icons.alt_route,
                  tooltip: context.t('nowPlaying.signalPath'),
                  semanticLabel: context.t('nowPlaying.signalPath'),
                  onPressed: () => widget.navigator.openAudioPanels(),
                ),
                const SizedBox(width: 16),
                // Volume slider
                NowPlayingVolumeControl(engine: widget.engine),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsView(BuildContext context) {
    return LyricsView(
      controller: _lyricsController,
      playbackController: widget.controller,
      settingsStore: widget.settingsStore,
      navigator: widget.navigator,
      showHeader: false,
    );
  }
}
