import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/lyrics/lyrics_controller.dart';
import '../../library/cover_cache.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../lyrics/lyrics_view.dart';
import '../now_playing/cover_palette.dart';
import '../now_playing/now_playing_view.dart';
import '../settings/shortcuts_cheat_sheet_dialog.dart';
import '../shell/bottom_now_playing_bar.dart';
import '../shell/global_playback_keys.dart';
import '../shell/volume_hud.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/dither_noise.dart';
import 'mini_player_controller.dart';

/// Compact desktop player view rendered when [MiniPlayerController] is in mini mode.
///
/// Responsive to available box constraints: provides a wide layout when horizontal
/// aspect ratio is dominant (e.g. 480x170 or 480x320) and a square layout otherwise (e.g. 340x440 or 340x620).
class MiniPlayerView extends StatefulWidget {
  /// The mini player window mode controller.
  final MiniPlayerController controller;

  /// The audio playback controller coordinating queue and engine.
  final PlaybackController playbackController;

  /// Optional shared lyrics controller for mini player lyrics display.
  final LyricsController? lyricsController;

  /// Optional close callback matching the main window close flow ('tray' or 'quit').
  final Future<void> Function()? onCloseRequested;

  /// Creates a [MiniPlayerView].
  const MiniPlayerView({
    super.key,
    required this.controller,
    required this.playbackController,
    this.lyricsController,
    this.onCloseRequested,
  });

  @override
  State<MiniPlayerView> createState() => _MiniPlayerViewState();
}

class _MiniPlayerViewState extends State<MiniPlayerView> {
  final FocusNode _focusNode = FocusNode();
  StreamSubscription<AudioSource?>? _currentSub;
  StreamSubscription<PlaybackState>? _stateSub;
  CoverPalette _palette = CoverPalette.fallback;
  String? _lastCoverKey;

  late GlobalPlaybackKeysHandler _playbackKeysHandler;
  bool _shortcutsDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _playbackKeysHandler = _createPlaybackKeysHandler();
    _currentSub = widget.playbackController.currentStream.listen(_onTrackChanged);
    _stateSub = widget.playbackController.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _updatePalette(widget.playbackController.queue.current?.extras?['coverKey']);
  }

  GlobalPlaybackKeysHandler _createPlaybackKeysHandler() {
    return GlobalPlaybackKeysHandler(
      controller: widget.playbackController,
      engine: widget.playbackController.engine,
      settingsStore: widget.controller.settingsStore,
      volumeHudProvider: () => VolumeHudScope.maybeOf(context),
      isInFullScreenOrMini: () => true,
      onEscape: () {
        if (_shortcutsDialogOpen) return false;
        widget.controller.exit();
        return true;
      },
      onShowShortcutsCheatSheet: _openShortcutsCheatSheet,
      isShortcutsCheatSheetOpen: () => _shortcutsDialogOpen,
    );
  }

  void _openShortcutsCheatSheet() {
    if (_shortcutsDialogOpen || !mounted) return;
    _shortcutsDialogOpen = true;
    showShortcutsCheatSheetDialog(context).whenComplete(() {
      _shortcutsDialogOpen = false;
    });
  }

  @override
  void didUpdateWidget(covariant MiniPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.playbackController != widget.playbackController) {
      _playbackKeysHandler.dispose();
      _playbackKeysHandler = _createPlaybackKeysHandler();
    }
    if (oldWidget.playbackController != widget.playbackController) {
      _currentSub?.cancel();
      _stateSub?.cancel();
      _currentSub =
          widget.playbackController.currentStream.listen(_onTrackChanged);
      _stateSub = widget.playbackController.stateStream.listen((_) {
        if (mounted) setState(() {});
      });
      _updatePalette(widget.playbackController.queue.current?.extras?['coverKey']);
    }
  }

  @override
  void dispose() {
    _playbackKeysHandler.dispose();
    _currentSub?.cancel();
    _stateSub?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTrackChanged(AudioSource? source) {
    if (!mounted) return;
    setState(() {});
    _updatePalette(source?.extras?['coverKey']);
  }

  Future<void> _updatePalette(String? coverKey) async {
    if (coverKey == _lastCoverKey) return;
    _lastCoverKey = coverKey;
    final palette = await paletteForCover(coverKey);
    if (mounted) {
      setState(() => _palette = palette);
    }
  }

  Widget _buildCover(String? coverKey, double size) {
    final hasCover = coverKey != null && CoverCache.hasCover(coverKey);
    Widget image;
    if (hasCover) {
      final file = File(CoverCache.pathFor(coverKey));
      image = Image.file(
        file,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildFallbackCover(size),
      );
    } else {
      image = _buildFallbackCover(size);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: image,
      ),
    );
  }

  Widget _buildFallbackCover(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Icon(
        Icons.music_note,
        size: size * 0.45,
        color: AppColors.textMuted,
      ),
    );
  }

  Widget _buildLyricsToggleButton(BuildContext context, bool showLyrics) {
    return GlassIconButton(
      key: const Key('mini_lyrics_toggle'),
      icon: Icons.lyrics_outlined,
      tooltip: context.t('miniPlayer.lyricsTooltip'),
      semanticLabel: context.t('miniPlayer.lyricsTooltip'),
      size: GlassButtonSize.small,
      variant:
          showLyrics ? GlassButtonVariant.selected : GlassButtonVariant.normal,
      onPressed: widget.controller.toggleShowLyrics,
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    return GlassIconButton(
      key: const Key('mini_player_close'),
      icon: Icons.close,
      tooltip: context.t('miniPlayer.close'),
      semanticLabel: context.t('miniPlayer.close'),
      size: GlassButtonSize.small,
      onPressed: () {
        if (widget.onCloseRequested != null) {
          widget.onCloseRequested!();
        } else {
          widget.controller.restoreFrameForClose();
        }
      },
    );
  }

  Widget _buildMiniLyricsPanel(BuildContext context, {required bool isWide}) {
    final lyricsCtrl = widget.lyricsController;
    if (lyricsCtrl == null) {
      return Center(
        key: const Key('mini_player_no_lyrics'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            context.t('miniPlayer.noSyncedLyrics'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body.copyWith(color: AppColors.textMuted),
          ),
        ),
      );
    }
    return LyricsView(
      key: const Key('mini_player_lyrics_view'),
      controller: lyricsCtrl,
      playbackController: widget.playbackController,
      settingsStore: widget.controller.settingsStore,
      showHeader: false,
      density: LyricsViewDensity.mini,
      isWideMini: isWide,
    );
  }

  Widget _buildWideLayout({
    required BuildContext context,
    required BoxConstraints constraints,
    required bool hasTrack,
    required bool isPlaying,
    required String title,
    required String artist,
    required String? coverKey,
    required String? trackPath,
    required bool isPinned,
    required bool showLyrics,
    required bool reduceMotion,
  }) {
    final showExpandedLyrics = showLyrics && constraints.maxHeight >= 220;
    final topHeight = showExpandedLyrics
        ? (constraints.maxHeight * 0.45).clamp(118.0, 144.0)
        : constraints.maxHeight;
    final coverSize = showExpandedLyrics
        ? (topHeight - 24.0).clamp(56.0, 96.0)
        : (constraints.maxHeight - 24.0).clamp(48.0, 120.0);

    final playerContent = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Cover artwork on start side
        _buildCover(coverKey, coverSize),
        const SizedBox(width: 12),

        // Controls, text, and seek bar beside cover
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top row: Title + Artist, Favorite, Lyrics, Pin, Expand, Close
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: textDirectionFor(title),
                          style: AppTypography.title.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: textDirectionFor(artist),
                          style: AppTypography.caption.copyWith(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (hasTrack && trackPath != null) ...[
                    PlayerFavoriteButton(
                      path: trackPath,
                      buttonKey: const Key('mini_player_favorite_button'),
                    ),
                    const SizedBox(width: 2),
                  ],
                  _buildLyricsToggleButton(context, showLyrics),
                  const SizedBox(width: 2),
                  GlassIconButton(
                    key: const Key('mini_player_pin_button'),
                    icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    tooltip: isPinned
                        ? context.t('miniPlayer.unpin')
                        : context.t('miniPlayer.pin'),
                    semanticLabel: isPinned
                        ? context.t('miniPlayer.unpin')
                        : context.t('miniPlayer.pin'),
                    size: GlassButtonSize.small,
                    variant: isPinned
                        ? GlassButtonVariant.selected
                        : GlassButtonVariant.normal,
                    onPressed: widget.controller.toggleAlwaysOnTop,
                  ),
                  const SizedBox(width: 2),
                  GlassIconButton(
                    key: const Key('mini_player_expand_button'),
                    icon: Icons.open_in_full,
                    tooltip: context.t('miniPlayer.exit'),
                    semanticLabel: context.t('miniPlayer.exit'),
                    size: GlassButtonSize.small,
                    onPressed: widget.controller.exit,
                  ),
                  const SizedBox(width: 2),
                  _buildCloseButton(context),
                ],
              ),
              SizedBox(height: showLyrics ? 2 : 4),

              // Seek bar (existing widget)
              NowPlayingSeekBar(
                key: const Key('mini_player_seek_bar'),
                engine: widget.playbackController.engine,
                controller: widget.playbackController,
              ),
              const SizedBox(height: 2),

              // Transport buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlassIconButton(
                    key: const Key('mini_player_prev_button'),
                    icon: Icons.skip_previous,
                    tooltip: context.t('common.previous'),
                    semanticLabel: context.t('common.previous'),
                    size: GlassButtonSize.small,
                    onPressed: hasTrack
                        ? widget.playbackController.skipPrevious
                        : null,
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    key: const Key('mini_player_play_pause_button'),
                    icon: isPlaying ? Icons.pause : Icons.play_arrow,
                    tooltip: isPlaying
                        ? context.t('common.pause')
                        : context.t('common.play'),
                    semanticLabel: isPlaying
                        ? context.t('common.pause')
                        : context.t('common.play'),
                    size: GlassButtonSize.medium,
                    onPressed: hasTrack
                        ? widget.playbackController.togglePlayPause
                        : null,
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    key: const Key('mini_player_next_button'),
                    icon: Icons.skip_next,
                    tooltip: context.t('common.next'),
                    semanticLabel: context.t('common.next'),
                    size: GlassButtonSize.small,
                    onPressed:
                        hasTrack ? widget.playbackController.skipNext : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      child: showExpandedLyrics
          ? Column(
              children: [
                SizedBox(
                  height: topHeight - 16,
                  child: playerContent,
                ),
                const SizedBox(height: 6),
                Container(
                  height: 1,
                  color: AppColors.borderSubtle,
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: _buildMiniLyricsPanel(context, isWide: true),
                ),
              ],
            )
          : playerContent,
    );
  }

  Widget _buildSquareLayout({
    required BuildContext context,
    required BoxConstraints constraints,
    required bool hasTrack,
    required bool isPlaying,
    required String title,
    required String artist,
    required String? coverKey,
    required String? trackPath,
    required bool isPinned,
    required bool showLyrics,
    required bool reduceMotion,
  }) {
    final coverSize = showLyrics
        ? (constraints.maxHeight * 0.22).clamp(64.0, 128.0)
        : (constraints.maxHeight * 0.45).clamp(120.0, 200.0);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: showLyrics ? 10 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Top bar with lyrics, pin, expand, and close buttons
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t('miniPlayer.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
              _buildLyricsToggleButton(context, showLyrics),
              const SizedBox(width: 4),
              GlassIconButton(
                key: const Key('mini_player_pin_button'),
                icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                tooltip: isPinned
                    ? context.t('miniPlayer.unpin')
                    : context.t('miniPlayer.pin'),
                semanticLabel: isPinned
                    ? context.t('miniPlayer.unpin')
                    : context.t('miniPlayer.pin'),
                size: GlassButtonSize.small,
                variant: isPinned
                    ? GlassButtonVariant.selected
                    : GlassButtonVariant.normal,
                onPressed: widget.controller.toggleAlwaysOnTop,
              ),
              const SizedBox(width: 4),
              GlassIconButton(
                key: const Key('mini_player_expand_button'),
                icon: Icons.open_in_full,
                tooltip: context.t('miniPlayer.exit'),
                semanticLabel: context.t('miniPlayer.exit'),
                size: GlassButtonSize.small,
                onPressed: widget.controller.exit,
              ),
              const SizedBox(width: 4),
              _buildCloseButton(context),
            ],
          ),
          SizedBox(height: showLyrics ? 6 : 8),

          // Centered cover
          _buildCover(coverKey, coverSize),
          SizedBox(height: showLyrics ? 6 : 10),

          // Title & Artist row with Favorite button
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: textDirectionFor(title),
                      style: AppTypography.title.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: textDirectionFor(artist),
                      style: AppTypography.caption.copyWith(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasTrack && trackPath != null) ...[
                const SizedBox(width: 8),
                PlayerFavoriteButton(
                  path: trackPath,
                  buttonKey: const Key('mini_player_favorite_button'),
                ),
              ],
            ],
          ),
          if (!showLyrics) const Spacer() else const SizedBox(height: 6),

          // Seek bar
          NowPlayingSeekBar(
            key: const Key('mini_player_seek_bar'),
            engine: widget.playbackController.engine,
            controller: widget.playbackController,
          ),
          SizedBox(height: showLyrics ? 4 : 8),

          // Transport controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlassIconButton(
                key: const Key('mini_player_prev_button'),
                icon: Icons.skip_previous,
                tooltip: context.t('common.previous'),
                semanticLabel: context.t('common.previous'),
                size: GlassButtonSize.small,
                onPressed:
                    hasTrack ? widget.playbackController.skipPrevious : null,
              ),
              const SizedBox(width: 16),
              GlassIconButton(
                key: const Key('mini_player_play_pause_button'),
                icon: isPlaying ? Icons.pause : Icons.play_arrow,
                tooltip: isPlaying
                    ? context.t('common.pause')
                    : context.t('common.play'),
                semanticLabel: isPlaying
                    ? context.t('common.pause')
                    : context.t('common.play'),
                size: showLyrics ? GlassButtonSize.medium : GlassButtonSize.large,
                onPressed:
                    hasTrack ? widget.playbackController.togglePlayPause : null,
              ),
              const SizedBox(width: 16),
              GlassIconButton(
                key: const Key('mini_player_next_button'),
                icon: Icons.skip_next,
                tooltip: context.t('common.next'),
                semanticLabel: context.t('common.next'),
                size: GlassButtonSize.small,
                onPressed: hasTrack ? widget.playbackController.skipNext : null,
              ),
            ],
          ),
          if (showLyrics) ...[
            const SizedBox(height: 8),
            Container(
              height: 1,
              color: AppColors.borderSubtle,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _buildMiniLyricsPanel(context, isWide: false),
            ),
          ] else
            const SizedBox(height: 4),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.playbackController.queue.current;
    final hasTrack = current != null;
    final isPlaying =
        widget.playbackController.currentState == PlaybackState.playing;

    final title = hasTrack
        ? (current.extras?['title'] ?? context.t('library.unknownTitle'))
        : context.t('miniPlayer.noTrack');
    final rawArtist = current?.extras?['artist'];
    final artist = hasTrack ? context.displayArtist(rawArtist) : '—';
    final coverKey = current?.extras?['coverKey'];
    final trackPath = current?.extras?['path'];

    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: _playbackKeysHandler.handleKeyEvent,
      onFocusChange: (hasFocus) {
        if (!hasFocus) _playbackKeysHandler.reset();
      },
      child: Material(
        color: AppColors.base,
        child: GestureDetector(
          key: const Key('mini_player_drag_surface'),
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) {
            widget.controller.windowService.startDragging();
          },
          child: ListenableBuilder(
            listenable: Listenable.merge([
              widget.controller,
              widget.controller.settingsStore,
            ]),
            builder: (context, _) {
              final settings = widget.controller.settingsStore.settings;
              final isPinned = settings.miniPlayerAlwaysOnTop;
              final showLyrics = settings.miniPlayerShowLyrics;
              final reduceMotion = settings.reduceMotion;

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isWide =
                      constraints.maxWidth / constraints.maxHeight >= 1.4;

                  return GlassSurface(
                    borderRadius: 0,
                    padding: EdgeInsets.zero,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _palette.secondary.withValues(alpha: 0.35),
                                  AppColors.surface,
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Positioned.fill(
                          child: DitherOverlay(),
                        ),
                        Positioned.fill(
                          child: isWide
                              ? _buildWideLayout(
                                  context: context,
                                  constraints: constraints,
                                  hasTrack: hasTrack,
                                  isPlaying: isPlaying,
                                  title: title,
                                  artist: artist,
                                  coverKey: coverKey,
                                  trackPath: trackPath,
                                  isPinned: isPinned,
                                  showLyrics: showLyrics,
                                  reduceMotion: reduceMotion,
                                )
                              : _buildSquareLayout(
                                  context: context,
                                  constraints: constraints,
                                  hasTrack: hasTrack,
                                  isPlaying: isPlaying,
                                  title: title,
                                  artist: artist,
                                  coverKey: coverKey,
                                  trackPath: trackPath,
                                  isPinned: isPinned,
                                  showLyrics: showLyrics,
                                  reduceMotion: reduceMotion,
                                ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
