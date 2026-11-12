import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/lyrics/lyrics_controller.dart';
import '../../features/lyrics/lyrics_models.dart';
import '../../library/cover_cache.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../now_playing/cover_palette.dart';
import '../now_playing/now_playing_view.dart';
import '../settings/shortcuts_cheat_sheet_dialog.dart';
import '../shell/bottom_now_playing_bar.dart';
import '../shell/global_playback_keys.dart';
import '../shell/volume_hud.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'mini_player_controller.dart';

/// Compact desktop player view rendered when [MiniPlayerController] is in mini mode.
///
/// Responsive to available box constraints: provides a wide layout when horizontal
/// aspect ratio is dominant (e.g. 480x170) and a square layout otherwise (e.g. 340x440).
class MiniPlayerView extends StatefulWidget {
  /// The mini player window mode controller.
  final MiniPlayerController controller;

  /// The audio playback controller coordinating queue and engine.
  final PlaybackController playbackController;

  /// Optional shared lyrics controller for mini player lyrics display.
  final LyricsController? lyricsController;

  /// Creates a [MiniPlayerView].
  const MiniPlayerView({
    super.key,
    required this.controller,
    required this.playbackController,
    this.lyricsController,
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
    final compact = showLyrics && constraints.maxHeight < 200;
    final coverSize = (constraints.maxHeight -
            (showLyrics ? (compact ? 64.0 : 74.0) : 24.0))
        .clamp(48.0, showLyrics ? 112.0 : 120.0);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: compact ? 6 : 8,
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(
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
                      // Top row: Title + Artist, Favorite, Lyrics, Pin, Expand
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
                              buttonKey:
                                  const Key('mini_player_favorite_button'),
                            ),
                            const SizedBox(width: 2),
                          ],
                          _buildLyricsToggleButton(context, showLyrics),
                          const SizedBox(width: 2),
                          GlassIconButton(
                            key: const Key('mini_player_pin_button'),
                            icon: isPinned
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
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
                        ],
                      ),
                      const SizedBox(height: 4),

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
                            onPressed: hasTrack
                                ? widget.playbackController.skipNext
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showLyrics) ...[
            SizedBox(height: compact ? 2 : 6),
            _MiniLyricsStrip(
              lyricsController: widget.lyricsController,
              reduceMotion: reduceMotion,
              isSquare: false,
              compact: compact,
            ),
          ],
        ],
      ),
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
        ? (constraints.maxHeight * 0.32).clamp(96.0, 170.0)
        : (constraints.maxHeight * 0.45).clamp(120.0, 200.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Top bar with lyrics, pin, and expand buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.t('miniPlayer.title'),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Centered large cover
          _buildCover(coverKey, coverSize),
          const SizedBox(height: 10),

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
          if (showLyrics) ...[
            const SizedBox(height: 8),
            _MiniLyricsStrip(
              lyricsController: widget.lyricsController,
              reduceMotion: reduceMotion,
              isSquare: true,
              compact: false,
            ),
          ],
          const Spacer(),

          // Seek bar
          NowPlayingSeekBar(
            key: const Key('mini_player_seek_bar'),
            engine: widget.playbackController.engine,
            controller: widget.playbackController,
          ),
          const SizedBox(height: 8),

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
                size: GlassButtonSize.large,
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
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _MiniLyricsStrip extends StatelessWidget {
  final LyricsController? lyricsController;
  final bool reduceMotion;
  final bool isSquare;
  final bool compact;

  const _MiniLyricsStrip({
    required this.lyricsController,
    required this.reduceMotion,
    required this.isSquare,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = lyricsController;
    final body = ctrl == null
        ? _buildContent(context, null, -1)
        : ListenableBuilder(
            listenable: ctrl,
            builder: (context, _) => _buildContent(
              context,
              ctrl.document,
              ctrl.currentLineIndex,
            ),
          );

    return Container(
      key: const Key('mini_lyrics_strip'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isSquare ? 8 : 10,
        vertical: compact ? 2 : 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.base.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: body,
    );
  }

  Widget _buildContent(
    BuildContext context,
    LyricsDocument? doc,
    int activeIndex,
  ) {
    final hasSynced =
        doc != null && doc.kind == LyricsKind.synced && doc.lines.isNotEmpty;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 300);

    final Widget child;
    final Key childKey;

    if (!hasSynced) {
      childKey = const ValueKey('mini_lyrics_unavailable');
      child = Text(
        context.t('miniPlayer.noSyncedLyrics'),
        key: const Key('mini_lyrics_empty'),
        maxLines: isSquare ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: AppTypography.caption.copyWith(
          fontSize: compact ? 11 : 12,
          color: AppColors.textMuted,
        ),
      );
    } else if (!isSquare) {
      final hasActive = activeIndex >= 0 && activeIndex < doc.lines.length;
      final lineText = hasActive ? doc.lines[activeIndex].text : doc.lines.first.text;
      childKey = ValueKey('wide_${activeIndex}_$lineText');
      child = Text(
        lineText,
        key: const Key('mini_lyrics_current'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        textDirection: textDirectionFor(lineText),
        style: AppTypography.caption.copyWith(
          fontSize: compact ? 11 : 12,
          height: 1.25,
          fontWeight: hasActive ? FontWeight.w600 : FontWeight.w400,
          color: hasActive ? AppColors.text : AppColors.textMuted,
        ),
      );
    } else {
      final hasActive = activeIndex >= 0 && activeIndex < doc.lines.length;
      final currentText = hasActive ? doc.lines[activeIndex].text : null;
      final nextIndex = hasActive ? activeIndex + 1 : 0;
      final nextText =
          nextIndex < doc.lines.length ? doc.lines[nextIndex].text : null;
      childKey = ValueKey('square_${activeIndex}_${currentText}_$nextText');
      child = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (currentText != null)
            Text(
              currentText,
              key: const Key('mini_lyrics_current'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              textDirection: textDirectionFor(currentText),
              style: AppTypography.caption.copyWith(
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          if (nextText != null) ...[
            if (currentText != null) const SizedBox(height: 2),
            Text(
              nextText,
              key: const Key('mini_lyrics_next'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              textDirection: textDirectionFor(nextText),
              style: AppTypography.caption.copyWith(
                fontSize: 11.5,
                height: 1.2,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      );
    }

    return AnimatedSwitcher(
      key: ValueKey(reduceMotion),
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (c, animation) =>
          FadeTransition(opacity: animation, child: c),
      child: KeyedSubtree(
        key: childKey,
        child: child,
      ),
    );
  }
}
