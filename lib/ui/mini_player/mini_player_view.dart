import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../library/cover_cache.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../now_playing/cover_palette.dart';
import '../now_playing/now_playing_view.dart';
import '../settings/app_shortcuts.dart';
import '../shell/bottom_now_playing_bar.dart';
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

  /// Creates a [MiniPlayerView].
  const MiniPlayerView({
    super.key,
    required this.controller,
    required this.playbackController,
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

  bool _isSpaceDown = false;
  bool _spaceChordUsed = false;

  @override
  void initState() {
    super.initState();
    _currentSub = widget.playbackController.currentStream.listen(_onTrackChanged);
    _stateSub = widget.playbackController.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _updatePalette(widget.playbackController.queue.current?.extras?['coverKey']);
  }

  @override
  void didUpdateWidget(covariant MiniPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // 1. Esc key exits mini mode
    if (event is KeyDownEvent && matchesShortcut(event, AppShortcutId.back)) {
      widget.controller.exit();
      return KeyEventResult.handled;
    }

    // 2. Media keys
    if (event is KeyDownEvent) {
      if (matchesShortcut(event, AppShortcutId.mediaPlayPause)) {
        widget.playbackController.togglePlayPause();
        return KeyEventResult.handled;
      }
      if (matchesShortcut(event, AppShortcutId.nextTrack) ||
          matchesShortcut(event, AppShortcutId.mediaNext)) {
        widget.playbackController.skipNext();
        return KeyEventResult.handled;
      }
      if (matchesShortcut(event, AppShortcutId.previousTrack) ||
          matchesShortcut(event, AppShortcutId.mediaPrevious)) {
        widget.playbackController.skipPrevious();
        return KeyEventResult.handled;
      }
    }

    // 3. Space tracking & chords
    if (isSpaceKey(event)) {
      if (event is KeyDownEvent) {
        _isSpaceDown = true;
        _spaceChordUsed = false;
        return KeyEventResult.handled;
      } else if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        final wasDown = _isSpaceDown;
        final chordUsed = _spaceChordUsed;
        _isSpaceDown = false;
        _spaceChordUsed = false;
        if (wasDown && !chordUsed) {
          widget.playbackController.togglePlayPause();
        }
        return KeyEventResult.handled;
      }
    }

    // 4. Space chords: Space + Right / Left
    if (_isSpaceDown && (isArrowLeftKey(event) || isArrowRightKey(event))) {
      final isRight = isArrowRightKey(event);
      if (event is KeyDownEvent) {
        if (isRight) {
          widget.playbackController.skipNext();
        } else {
          widget.playbackController.skipPrevious();
        }
        _spaceChordUsed = true;
        return KeyEventResult.handled;
      } else if (event is KeyRepeatEvent || event is KeyUpEvent) {
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
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
  }) {
    final coverSize = (constraints.maxHeight - 24).clamp(64.0, 120.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                // Top row: Title + Artist, Favorite, Pin, Expand
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
  }) {
    final coverSize = (constraints.maxHeight * 0.45).clamp(120.0, 200.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Top bar with pin and expand buttons
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
          const SizedBox(height: 12),

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
      onKeyEvent: _handleKeyEvent,
      child: Material(
        color: AppColors.base,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final isPinned =
                widget.controller.settingsStore.settings.miniPlayerAlwaysOnTop;

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
