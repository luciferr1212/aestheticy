import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/lyrics/lyrics_controller.dart';
import '../../features/lyrics/lyrics_models.dart';
import '../../features/lyrics/lyrics_repository.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Computes the visual opacity for a lyrics line based on its distance from the active line.
///
/// Falloff table:
/// - Current active line: 1.0
/// - Distance 1 upcoming: 0.55 (next line)
/// - Distance 2 upcoming: 0.38
/// - Distance 3 upcoming: 0.26
/// - Distance 4+ upcoming: 0.20 (floor)
/// - Past lines are dimmer than upcoming ones (distance 1: 0.44, distance 2: 0.30, distance 3: 0.21, distance 4+: 0.20)
/// - Hover raises opacity by 0.18 (clamped to 1.0)
double computeLineOpacity({
  required int index,
  required int activeIndex,
  bool isHovered = false,
}) {
  if (activeIndex < 0) {
    // Before first line starts: index 0 is distance 1
    final d = index + 1;
    final base = switch (d) {
      1 => 0.55,
      2 => 0.38,
      3 => 0.26,
      _ => 0.20,
    };
    return isHovered ? (base + 0.18).clamp(0.20, 1.0) : base;
  }

  if (index == activeIndex) {
    return 1.0;
  }

  final diff = index - activeIndex;
  final double base;
  if (diff > 0) {
    // Upcoming lines
    base = switch (diff) {
      1 => 0.55,
      2 => 0.38,
      3 => 0.26,
      _ => 0.20,
    };
  } else {
    // Past lines: dimmer than upcoming ones
    final pastDist = -diff;
    base = switch (pastDist) {
      1 => 0.44,
      2 => 0.30,
      3 => 0.21,
      _ => 0.20,
    };
  }

  if (isHovered) {
    return (base + 0.18).clamp(0.20, 1.0);
  }
  return base;
}

/// Presentation widget for time-synchronized and plain lyrics with calm motion and typography.
class LyricsView extends StatefulWidget {
  /// The lyrics state coordinator.
  final LyricsController controller;

  /// The active playback controller.
  final PlaybackController playbackController;

  /// The persistent user settings store.
  final SettingsStore settingsStore;

  /// Optional app navigation coordinator (for back button).
  final AppNavigator? navigator;

  /// Whether to render the top header with track metadata, source pill, and back button.
  final bool showHeader;

  /// Whether this view is rendered in full screen mode.
  final bool isFullScreen;

  /// Creates a [LyricsView].
  const LyricsView({
    super.key,
    required this.controller,
    required this.playbackController,
    required this.settingsStore,
    this.navigator,
    this.showHeader = true,
    this.isFullScreen = false,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  final ValueNotifier<double> _wordProgressNotifier = ValueNotifier<double>(0.0);

  StreamSubscription<PlaybackState>? _playbackStateSub;
  StreamSubscription<AudioSource?>? _currentTrackSub;
  Ticker? _ticker;
  Timer? _autoFollowTimer;
  bool _isAutoFollowPaused = false;
  int _lastScrolledLine = -1;
  String? _currentTrackUri;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChange);
    _playbackStateSub = widget.playbackController.stateStream.listen(_onPlaybackStateChange);
    _currentTrackSub = widget.playbackController.currentStream.listen(_onCurrentTrackChange);
    _currentTrackUri = widget.playbackController.queue.current?.uri;

    _ticker = createTicker(_onTick);
    _updateTicker();
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
    }
    if (oldWidget.playbackController != widget.playbackController) {
      _playbackStateSub?.cancel();
      _currentTrackSub?.cancel();
      _playbackStateSub = widget.playbackController.stateStream.listen(_onPlaybackStateChange);
      _currentTrackSub = widget.playbackController.currentStream.listen(_onCurrentTrackChange);
    }
    _updateTicker();
  }

  void _onCurrentTrackChange(AudioSource? source) {
    final newUri = source?.uri;
    if (newUri != _currentTrackUri) {
      _currentTrackUri = newUri;
      _lastScrolledLine = -1;
      _isAutoFollowPaused = false;
      _autoFollowTimer?.cancel();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
      if (mounted) setState(() {});
    }
  }

  void _onPlaybackStateChange(PlaybackState _) {
    if (mounted) _updateTicker();
  }

  void _onControllerChange() {
    if (!mounted) return;
    _updateTicker();
    final currentLine = widget.controller.currentLineIndex;
    if (currentLine != _lastScrolledLine && currentLine >= 0) {
      _lastScrolledLine = currentLine;
      _scrollToCurrentLine(currentLine);
    }
    setState(() {});
  }

  void _updateTicker() {
    final isPlaying =
        widget.playbackController.currentState == PlaybackState.playing;
    final reduceMotion = widget.settingsStore.settings.reduceMotion;
    final doc = widget.controller.document;
    final hasWordTiming = doc?.hasWordTiming ?? false;
    final highlightWord =
        widget.settingsStore.settings.lyricsHighlight == 'word';

    final shouldTick =
        isPlaying && !reduceMotion && hasWordTiming && highlightWord;

    if (shouldTick) {
      if (_ticker != null && !_ticker!.isActive) {
        _ticker!.start();
      }
    } else {
      if (_ticker != null && _ticker!.isActive) {
        _ticker!.stop();
      }
    }
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    widget.controller.updatePosition(
      widget.playbackController.currentPosition,
      forceNotify: false,
    );
    _wordProgressNotifier.value = widget.controller.wordProgress;
  }

  void _scrollToCurrentLine(int lineIndex, {bool force = false}) {
    if (!force && _isAutoFollowPaused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!force && _isAutoFollowPaused) return;
      final key = _lineKeys[lineIndex];
      final targetContext = key?.currentContext;
      if (targetContext != null) {
        final reduceMotion = widget.settingsStore.settings.reduceMotion;
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.42,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 550),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _pauseAutoFollow() {
    _isAutoFollowPaused = true;
    _autoFollowTimer?.cancel();
    _autoFollowTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _isAutoFollowPaused = false;
      _scrollToCurrentLine(widget.controller.currentLineIndex, force: true);
    });
  }

  @override
  void dispose() {
    _autoFollowTimer?.cancel();
    _autoFollowTimer = null;
    widget.controller.removeListener(_onControllerChange);
    _playbackStateSub?.cancel();
    _currentTrackSub?.cancel();
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _wordProgressNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) _buildHeader(context),
        Expanded(
          child: _buildBody(context),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final current = widget.playbackController.queue.current;
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

    final doc = widget.controller.document;
    final String sourceLabel;
    if (doc != null) {
      sourceLabel = switch (doc.source) {
        LyricsSourceOrigin.local => context.t('lyrics.source.local'),
        LyricsSourceOrigin.embedded => context.t('lyrics.source.embedded'),
        LyricsSourceOrigin.lrclib => context.t('lyrics.source.lrclib'),
      };
    } else {
      sourceLabel = '';
    }

    final String timingLabel;
    if (doc != null && doc.kind == LyricsKind.synced) {
      timingLabel = doc.hasWordTiming
          ? context.t('lyrics.timing.word')
          : context.t('lyrics.timing.line');
    } else {
      timingLabel = '';
    }

    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          if (widget.navigator != null)
            GlassPillButton(
              leadingIcon: isRtl ? Icons.chevron_right : Icons.chevron_left,
              label: context.t('common.back'),
              tooltip: context.t('common.back'),
              semanticLabel: context.t('common.back'),
              onPressed: () => widget.navigator!.goBack(),
            ),
          const SizedBox(width: 16),
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
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: textDirectionFor(artist),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (sourceLabel.isNotEmpty) ...[
            const SizedBox(width: 8),
            _buildBadge(sourceLabel),
          ],
          if (timingLabel.isNotEmpty) ...[
            const SizedBox(width: 8),
            _buildBadge(timingLabel),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.fillControl,
        borderRadius: BorderRadius.circular(AppSpacing.pill),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Text(
        label,
        style: AppTypography.micro.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final state = widget.controller.state;
    final reduceMotion = widget.settingsStore.settings.reduceMotion;

    final Widget content;
    final Key contentKey;

    switch (state) {
      case LyricsStateLoading():
        contentKey = const ValueKey('lyrics_state_loading');
        content = _buildLoading(context);
      case LyricsStateOff():
        contentKey = const ValueKey('lyrics_state_off');
        content = _buildOff(context);
      case LyricsStateNotFound():
        contentKey = const ValueKey('lyrics_state_notFound');
        content = _buildNotFound(context);
      case LyricsStateError(reason: final r):
        contentKey = ValueKey('lyrics_state_error_${r.name}');
        content = _buildError(context, r);
      case LyricsStateFound(document: final doc):
        contentKey = ValueKey('lyrics_doc_${_currentTrackUri}_${doc.source}_${doc.lines.length}');
        content = _buildFound(context, doc);
    }

    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(
        key: contentKey,
        child: content,
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final widthFactor in [0.70, 0.90, 0.55, 0.80, 0.45]) ...[
              FractionallySizedBox(
                widthFactor: widthFactor,
                child: Container(
                  height: 20,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.18),
                    borderRadius: AppSpacing.br10,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              context.t('lyrics.state.loading'),
              style: AppTypography.body.copyWith(
                color: AppColors.textMuted.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOff(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lyrics_outlined, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            context.t('lyrics.state.off'),
            style: AppTypography.body.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFound(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_off, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            context.t('lyrics.state.notFound'),
            style: AppTypography.body.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, LyricsErrorReason reason) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            context.t('lyrics.state.error'),
            style: AppTypography.body.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          GlassPillButton(
            leadingIcon: Icons.refresh,
            label: context.t('lyrics.retry'),
            tooltip: context.t('lyrics.retry'),
            semanticLabel: context.t('lyrics.retry'),
            onPressed: () => widget.controller.retry(),
          ),
        ],
      ),
    );
  }

  Widget _buildFound(BuildContext context, LyricsDocument doc) {
    if (doc.kind == LyricsKind.instrumental) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note, size: 56, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              context.t('lyrics.state.instrumental'),
              style: AppTypography.title.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    if (doc.kind == LyricsKind.plain) {
      return _buildPlain(context, doc);
    }

    return _buildSyncedList(context, doc);
  }

  Widget _buildPlain(BuildContext context, LyricsDocument doc) {
    final reduceMotion = widget.settingsStore.settings.reduceMotion;
    final plainFontSize = widget.isFullScreen ? 26.0 : 20.0;

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.12, 0.88, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: AnimatedOpacity(
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
        opacity: 1.0,
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: 32,
            vertical: widget.isFullScreen ? 80 : 48,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in doc.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        line.text,
                        textAlign: TextAlign.center,
                        textDirection: textDirectionFor(line.text),
                        style: AppTypography.title.copyWith(
                          fontSize: plainFontSize,
                          fontWeight: FontWeight.normal,
                          color: AppColors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSyncedList(BuildContext context, LyricsDocument doc) {
    final activeIndex = widget.controller.currentLineIndex;
    final highlightMode = widget.settingsStore.settings.lyricsHighlight;
    final hasWordTiming = doc.hasWordTiming;
    final currentWordIdx = widget.controller.currentWordIndex;
    final reduceMotion = widget.settingsStore.settings.reduceMotion;

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.12, 0.88, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is UserScrollNotification &&
              notification.direction != ScrollDirection.idle) {
            _pauseAutoFollow();
          } else if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _pauseAutoFollow();
          }
          return false;
        },
        child: ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(
            horizontal: 24,
            vertical: widget.isFullScreen ? 140 : 100,
          ),
          itemCount: doc.lines.length,
          itemBuilder: (context, index) {
            final line = doc.lines[index];
            final key = _lineKeys.putIfAbsent(index, GlobalKey.new);

            return RepaintBoundary(
              child: _SyncedLineItem(
                key: key,
                index: index,
                line: line,
                activeIndex: activeIndex,
                activeWordIdx: currentWordIdx,
                wordProgressNotifier: _wordProgressNotifier,
                highlightMode: highlightMode,
                hasWordTiming: hasWordTiming,
                reduceMotion: reduceMotion,
                isFullScreen: widget.isFullScreen,
                onTap: () {
                  _autoFollowTimer?.cancel();
                  _isAutoFollowPaused = false;
                  widget.playbackController.seek(Duration(milliseconds: line.startMs));
                  _scrollToCurrentLine(index, force: true);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SyncedLineItem extends StatefulWidget {
  final int index;
  final LyricsLine line;
  final int activeIndex;
  final int activeWordIdx;
  final ValueNotifier<double> wordProgressNotifier;
  final String highlightMode;
  final bool hasWordTiming;
  final bool reduceMotion;
  final bool isFullScreen;
  final VoidCallback onTap;

  const _SyncedLineItem({
    super.key,
    required this.index,
    required this.line,
    required this.activeIndex,
    required this.activeWordIdx,
    required this.wordProgressNotifier,
    required this.highlightMode,
    required this.hasWordTiming,
    required this.reduceMotion,
    required this.isFullScreen,
    required this.onTap,
  });

  @override
  State<_SyncedLineItem> createState() => _SyncedLineItemState();
}

class _SyncedLineItemState extends State<_SyncedLineItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isCurrent = widget.index == widget.activeIndex;
    final lineDirection = textDirectionFor(widget.line.text);
    final lineOpacity = computeLineOpacity(
      index: widget.index,
      activeIndex: widget.activeIndex,
      isHovered: _isHovered,
    );

    final double currentFontSize = widget.isFullScreen ? 40.0 : 32.0;
    final double otherFontSize = widget.isFullScreen ? 28.0 : 24.0;
    final targetFontSize = isCurrent ? currentFontSize : otherFontSize;
    final targetFontWeight = isCurrent ? FontWeight.bold : FontWeight.w600;

    final baseStyle = AppTypography.title.copyWith(
      fontSize: targetFontSize,
      fontWeight: targetFontWeight,
      color: isCurrent ? AppColors.text : AppColors.textMuted,
      height: 1.35,
    );

    final isWordHighlightActive = isCurrent &&
        widget.highlightMode == 'word' &&
        widget.hasWordTiming &&
        widget.line.words != null &&
        widget.line.words!.isNotEmpty;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedOpacity(
          opacity: lineOpacity,
          duration: widget.reduceMotion
              ? Duration.zero
              : (_isHovered
                  ? const Duration(milliseconds: 150)
                  : const Duration(milliseconds: 350)),
          curve: Curves.easeOut,
          child: AnimatedScale(
            scale: widget.reduceMotion ? 1.0 : (isCurrent ? 1.0 : 0.92),
            alignment: (lineDirection == TextDirection.rtl)
                ? Alignment.centerRight
                : Alignment.centerLeft,
            duration: widget.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: isWordHighlightActive
                  ? _buildWordHighlightedLine(
                      baseStyle: baseStyle,
                      lineDirection: lineDirection,
                    )
                  : AnimatedDefaultTextStyle(
                      duration: widget.reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                      style: baseStyle,
                      child: Text(
                        widget.line.text,
                        textAlign: TextAlign.center,
                        textDirection: lineDirection,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWordHighlightedLine({
    required TextStyle baseStyle,
    required TextDirection lineDirection,
  }) {
    final words = widget.line.words!;
    final activeWordIdx = widget.activeWordIdx;
    final reduceMotion = widget.reduceMotion;
    final dimColor = AppColors.textMuted.withValues(alpha: 0.45);

    return ValueListenableBuilder<double>(
      valueListenable: widget.wordProgressNotifier,
      builder: (context, progress, _) {
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8.0,
          runSpacing: 4.0,
          textDirection: lineDirection,
          children: [
            for (var i = 0; i < words.length; i++) ...[
              if (i < activeWordIdx - 1)
                Text(
                  words[i].text,
                  style: baseStyle.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (i == activeWordIdx - 1)
                reduceMotion
                    ? Text(
                        words[i].text,
                        style: baseStyle.copyWith(
                          color: AppColors.text,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOut,
                        style: baseStyle.copyWith(
                          color: AppColors.text,
                          fontWeight: FontWeight.bold,
                        ),
                        child: Text(words[i].text),
                      )
              else if (i == activeWordIdx)
                reduceMotion
                    ? Text(
                        words[i].text,
                        style: baseStyle.copyWith(
                          color: AppColors.text,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : _WordSweepWidget(
                        text: words[i].text,
                        progress: progress,
                        textDirection: lineDirection,
                        style: baseStyle,
                      )
              else
                Text(
                  words[i].text,
                  style: baseStyle.copyWith(
                    color: dimColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _WordSweepWidget extends StatelessWidget {
  final String text;
  final double progress;
  final TextDirection textDirection;
  final TextStyle style;

  const _WordSweepWidget({
    required this.text,
    required this.progress,
    required this.textDirection,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final isRtl = textDirection == TextDirection.rtl;
    final begin = isRtl ? Alignment.centerRight : Alignment.centerLeft;
    final end = isRtl ? Alignment.centerLeft : Alignment.centerRight;

    // Soft gradient sweep transition zone
    const softness = 0.18;
    final x = -softness + p * (1.0 + 2 * softness);
    final stop0 = x.clamp(0.0, 1.0);
    final stop1 = (x + softness).clamp(0.0, 1.0);

    final dimColor = AppColors.textMuted.withValues(alpha: 0.45);

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: begin,
          end: end,
          colors: [
            AppColors.text,
            AppColors.text,
            dimColor,
            dimColor,
          ],
          stops: [0.0, stop0, stop1, 1.0],
        ).createShader(bounds);
      },
      child: Text(
        text,
        style: style.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
