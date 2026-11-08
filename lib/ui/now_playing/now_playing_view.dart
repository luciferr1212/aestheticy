import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';

import '../../audio/audio_engine.dart';
import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../audio/playback_queue.dart';
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
import '../settings/app_shortcuts.dart';
import '../settings/settings_scope.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'cover_palette.dart';

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
    _updatePalette(widget.controller.queue.current?.extras?['coverKey']);
    _currentSub = widget.controller.currentStream.listen((source) {
      if (!mounted) return;
      _updatePalette(source?.extras?['coverKey']);
      setState(() {});
    });
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
    if (_createdLyricsControllerLocally) {
      _lyricsController.dispose();
    }
    _currentSub?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _cycleRepeat() {
    final next = switch (widget.controller.queue.repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    widget.controller.queue.repeatMode = next;
    setState(() {});
  }

  void _toggleShuffle() {
    widget.controller.queue.setShuffle(!widget.controller.queue.isShuffled);
    setState(() {});
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

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppColors.base,
        body: Stack(
          children: [
            // 1. Ambient radial glow from CoverPalette
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
                                        _MetadataArea(
                                          title: title,
                                          artist: artist,
                                          album: album,
                                          trackPath: current?.uri,
                                          onBuild: widget.onMetadataBuild,
                                        ),
                                        const SizedBox(height: 16),
                                        // Isolated seekbar leaf widget (zero rebuilds on ticks)
                                        _IsolatedSeekBar(
                                          engine: widget.engine,
                                          controller: widget.controller,
                                        ),
                                        const SizedBox(height: 16),
                                        // Transport row (strictly LTR)
                                        Directionality(
                                          textDirection: TextDirection.ltr,
                                          child: _buildTransportRow(context),
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
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Row(
      children: [
        // Back to Library button
        GlassPillButton(
          leadingIcon: isRtl ? Icons.chevron_right : Icons.chevron_left,
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

  Widget _buildTransportRow(BuildContext context) {
    final isShuffled = widget.controller.queue.isShuffled;
    final repeatMode = widget.controller.queue.repeatMode;

    return StreamBuilder<PlaybackState>(
      stream: widget.controller.stateStream,
      initialData: widget.controller.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? PlaybackState.idle;
        final isPlaying = state == PlaybackState.playing;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Shuffle
            GlassIconButton(
              icon: Icons.shuffle,
              tooltip: context.t('player.shuffle'),
              semanticLabel: context.t('player.shuffle'),
              variant: isShuffled
                  ? GlassButtonVariant.selected
                  : GlassButtonVariant.normal,
              onPressed: _toggleShuffle,
            ),
            const SizedBox(width: 12),

            // Previous
            GlassIconButton(
              icon: Icons.skip_previous,
              tooltip: context.t('common.previous'),
              semanticLabel: context.t('common.previous'),
              onPressed: () => widget.controller.skipPrevious(),
            ),
            const SizedBox(width: 16),

            // Play / Pause (Large 60dp)
            SizedBox(
              width: 60,
              height: 60,
              child: GlassIconButton(
                key: const Key('now_playing_play_pause_button'),
                icon: isPlaying ? Icons.pause : Icons.play_arrow,
                tooltip: isPlaying
                    ? context.t('common.pause')
                    : context.t('common.play'),
                semanticLabel: isPlaying
                    ? context.t('common.pause')
                    : context.t('common.play'),
                variant: GlassButtonVariant.primary,
                size: GlassButtonSize.large,
                onPressed: () => widget.controller.togglePlayPause(),
              ),
            ),
            const SizedBox(width: 16),

            // Next
            GlassIconButton(
              icon: Icons.skip_next,
              tooltip: context.t('common.next'),
              semanticLabel: context.t('common.next'),
              onPressed: () => widget.controller.skipNext(),
            ),
            const SizedBox(width: 12),

            // Repeat (off -> all -> one -> off)
            _buildRepeatButton(context, repeatMode),
          ],
        );
      },
    );
  }

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
            icon: Icons.repeat_one,
            tooltip: tooltip,
            semanticLabel: tooltip,
            variant: variant,
            onPressed: _cycleRepeat,
          ),
          Positioned(
            right: 4,
            top: 4,
            child: Container(
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
        ],
      );
    }

    return GlassIconButton(
      icon: Icons.repeat,
      tooltip: tooltip,
      semanticLabel: tooltip,
      variant: variant,
      onPressed: _cycleRepeat,
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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

                // Clear upcoming button (visible only in Up next tab)
                if (_activeTabIndex == 0)
                  TextButton(
                    onPressed: _clearUpcoming,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    child: Text(
                      context.t('nowPlaying.clearUpcoming'),
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tab content area
          Expanded(
            child: _activeTabIndex == 0
                ? _buildUpcomingList(context)
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
                  child: _StreamInfoPill(engine: widget.engine),
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
                _VolumeControl(engine: widget.engine),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingList(BuildContext context) {
    final queue = widget.controller.queue;
    final items = queue.items;
    final currentIndex = queue.currentIndex;

    final upcomingIndices = <int>[];
    for (int i = currentIndex + 1; i < items.length; i++) {
      upcomingIndices.add(i);
    }

    if (upcomingIndices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.queue_music, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 8),
            Text(
              context.t('nowPlaying.nothingQueued'),
              style: AppTypography.body.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: upcomingIndices.length,
      itemBuilder: (context, index) {
        final queueIndex = upcomingIndices[index];
        final source = items[queueIndex];
        final trackTitle =
            source.extras?['title'] ?? context.t('library.unknownTitle');
        final rawTrackArtist = source.extras?['artist'];
        final trackArtist = rawTrackArtist != null && rawTrackArtist.isNotEmpty
            ? context.displayArtist(rawTrackArtist)
            : '—';
        final durationMsStr = source.extras?['durationMs'];
        final durationMs = int.tryParse(durationMsStr ?? '');
        final durationText = durationMs != null
            ? context.formatDurationLocalized(Duration(milliseconds: durationMs))
            : '—';

        return RepaintBoundary(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.r12),
              onTap: () => _playUpcoming(queueIndex),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${index + 1}',
                        style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trackTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: textDirectionFor(trackTitle),
                            style: AppTypography.bodyStrong.copyWith(color: AppColors.text),
                          ),
                          Text(
                            trackArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: textDirectionFor(trackArtist),
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      durationText,
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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

/// Metadata area isolated from seek ticks.
class _MetadataArea extends StatelessWidget {
  final String title;
  final String artist;
  final String album;
  final String? trackPath;
  final VoidCallback? onBuild;

  const _MetadataArea({
    required this.title,
    required this.artist,
    required this.album,
    this.trackPath,
    this.onBuild,
  });

  @override
  Widget build(BuildContext context) {
    onBuild?.call();

    return Column(
      children: [
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
                textDirection: textDirectionFor(title),
                style: AppTypography.title
                    .copyWith(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            if (trackPath != null) ...[
              const SizedBox(width: 8),
              _NowPlayingFavoriteButton(path: trackPath!),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          textDirection: textDirectionFor(artist),
          style: AppTypography.bodyStrong.copyWith(
            color: AppColors.textSecondary,
            fontSize: 16,
          ),
        ),
        if (album.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textDirection: textDirectionFor(album),
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
              fontSize: 14,
            ),
          ),
        ],
        if (trackPath != null) ...[
          const SizedBox(height: 10),
          _TrackStarRatingControl(trackPath: trackPath!),
        ],
      ],
    );
  }
}

class _NowPlayingFavoriteButton extends StatelessWidget {
  final String path;

  const _NowPlayingFavoriteButton({required this.path});

  @override
  Widget build(BuildContext context) {
    final collections = UserCollectionsScope.maybeOf(context);
    if (collections == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: collections,
      builder: (context, _) {
        final isFav = collections.isFavorite(path);

        return IconButton(
          key: const Key('now_playing_favorite_button'),
          icon: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            size: 22,
            color: isFav ? AppColors.accent : AppColors.textMuted,
          ),
          tooltip: isFav
              ? context.t('track.unfavorite')
              : context.t('track.favorite'),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () => collections.toggleFavorite(path),
        );
      },
    );
  }
}

class _TrackStarRatingControl extends StatelessWidget {
  final String trackPath;

  const _TrackStarRatingControl({required this.trackPath});

  @override
  Widget build(BuildContext context) {
    final collections = UserCollectionsScope.maybeOf(context);
    if (collections == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: collections,
      builder: (context, _) {
        final currentRating = collections.ratingOf(trackPath);

        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var s = 1; s <= 5; s++)
              IconButton(
                key: Key('rating_star_$s'),
                icon: Icon(
                  currentRating >= s ? Icons.star : Icons.star_border,
                  size: 20,
                  color: currentRating >= s
                      ? AppColors.accent
                      : AppColors.textMuted,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: currentRating == s
                    ? context.t('track.clearRating')
                    : context.t('track.rateStars', args: {
                        'stars': context.localizeDigitsText('$s'),
                      }),
                onPressed: () {
                  if (currentRating == s) {
                    collections.setRating(trackPath, 0);
                  } else {
                    collections.setRating(trackPath, s);
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

/// Isolated seekbar leaf listening to position and duration streams.
class _IsolatedSeekBar extends StatefulWidget {
  final AudioEngine engine;
  final PlaybackController? controller;

  const _IsolatedSeekBar({required this.engine, this.controller});

  @override
  State<_IsolatedSeekBar> createState() => _IsolatedSeekBarState();
}

class _IsolatedSeekBarState extends State<_IsolatedSeekBar> {
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
  void didUpdateWidget(covariant _IsolatedSeekBar oldWidget) {
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

            return Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox(
                height: 24,
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        context.formatDurationLocalized(position),
                        textAlign: TextAlign.end,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SliderTheme(
                        data: const SliderThemeData(
                          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5.0),
                          overlayShape: RoundSliderOverlayShape(overlayRadius: 10.0),
                          trackHeight: 3.5,
                          activeTrackColor: AppColors.accent,
                          inactiveTrackColor: AppColors.border,
                          thumbColor: AppColors.accent,
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
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 36,
                      child: Text(
                        context.formatDurationLocalized(totalDuration),
                        textAlign: TextAlign.start,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Isolated audio stream info pill leaf widget.
class _StreamInfoPill extends StatelessWidget {
  final AudioEngine engine;

  const _StreamInfoPill({required this.engine});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AudioStreamInfo?>(
      stream: engine.streamInfoStream,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null ||
            ((info.codec == null || info.codec!.isEmpty) &&
                (info.sampleRate == null || info.sampleRate! <= 0) &&
                (info.bitDepth == null || info.bitDepth! <= 0) &&
                (info.channels == null || info.channels! <= 0) &&
                (info.bitrateKbps == null || info.bitrateKbps! <= 0))) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.fillControl,
              borderRadius: BorderRadius.circular(AppSpacing.r12),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Text(
              context.t('nowPlaying.standardAudio'),
              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            ),
          );
        }

        final parts = <String>[];
        if (info.codec != null && info.codec!.isNotEmpty) {
          parts.add(info.codec!.toUpperCase());
        }
        if (info.sampleRate != null && info.sampleRate! > 0) {
          final khz = (info.sampleRate! / 1000.0)
              .toStringAsFixed(1)
              .replaceAll('.0', '');
          parts.add('$khz kHz');
        }
        if (info.bitDepth != null && info.bitDepth! > 0) {
          parts.add('${info.bitDepth}-bit');
        }
        if (info.channels != null && info.channels! > 0) {
          parts.add(info.channels == 2
              ? 'Stereo'
              : (info.channels == 1 ? 'Mono' : '${info.channels} ch'));
        }
        if (info.bitrateKbps != null && info.bitrateKbps! > 0) {
          parts.add('${info.bitrateKbps!.round()} kbps');
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.fillControl,
            borderRadius: BorderRadius.circular(AppSpacing.r12),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (info.isLossless == true) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accentFill,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    context.t('nowPlaying.lossless'),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
              Text(
                parts.isEmpty
                    ? context.t('nowPlaying.standardAudio')
                    : parts.join(' · '),
                style: AppTypography.caption.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Compact volume slider control.
class _VolumeControl extends StatelessWidget {
  final AudioEngine engine;

  const _VolumeControl({required this.engine});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: engine.volumeStream,
      initialData: engine.currentVolume,
      builder: (context, snapshot) {
        final vol = (snapshot.data ?? 1.0).clamp(0.0, 1.0);
        return SizedBox(
          width: 140,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.volume_down,
                size: 16,
                color: AppColors.textMuted,
              ),
              Expanded(
                child: SliderTheme(
                  data: const SliderThemeData(
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 4.0),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 8.0),
                    trackHeight: 2.5,
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: AppColors.border,
                    thumbColor: AppColors.accent,
                  ),
                  child: Slider(
                    value: vol,
                    onChanged: (newVol) {
                      engine.setVolume(newVol);
                      SettingsScope.maybeOf(context)?.update((s) => s.copyWith(volume: newVol));
                    },
                  ),
                ),
              ),
              const Icon(
                Icons.volume_up,
                size: 16,
                color: AppColors.textMuted,
              ),
            ],
          ),
        );
      },
    );
  }
}
