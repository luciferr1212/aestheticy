import 'dart:async';

import 'package:flutter/material.dart';
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

/// Presentation widget for time-synchronized and plain lyrics.
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

  /// Creates a [LyricsView].
  const LyricsView({
    super.key,
    required this.controller,
    required this.playbackController,
    required this.settingsStore,
    this.navigator,
    this.showHeader = true,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  StreamSubscription<PlaybackState>? _playbackStateSub;
  Ticker? _ticker;
  int _lastScrolledLine = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChange);
    _playbackStateSub = widget.playbackController.stateStream.listen(_onPlaybackStateChange);

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
    _updateTicker();
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
      forceNotify: true,
    );
  }

  void _scrollToCurrentLine(int lineIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _lineKeys[lineIndex];
      final targetContext = key?.currentContext;
      if (targetContext != null) {
        final reduceMotion = widget.settingsStore.settings.reduceMotion;
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.5,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    _playbackStateSub?.cancel();
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
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

    return switch (state) {
      LyricsStateLoading() => _buildLoading(context),
      LyricsStateOff() => _buildOff(context),
      LyricsStateNotFound() => _buildNotFound(context),
      LyricsStateError(reason: final r) => _buildError(context, r),
      LyricsStateFound(document: final doc) => _buildFound(context, doc),
    };
  }

  Widget _buildLoading(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          Text(
            context.t('lyrics.state.loading'),
            style: AppTypography.body.copyWith(color: AppColors.textMuted),
          ),
        ],
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
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in doc.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      line.text,
                      textDirection: textDirectionFor(line.text),
                      style: AppTypography.bodyStrong.copyWith(
                        fontSize: 18,
                        color: AppColors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Synced lyrics list
    final activeIndex = widget.controller.currentLineIndex;
    final highlightMode = widget.settingsStore.settings.lyricsHighlight;
    final hasWordTiming = doc.hasWordTiming;
    final currentWordIdx = widget.controller.currentWordIndex;
    final wordProgress = widget.controller.wordProgress;
    final reduceMotion = widget.settingsStore.settings.reduceMotion;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 120),
      itemCount: doc.lines.length,
      itemBuilder: (context, index) {
        final line = doc.lines[index];
        final isCurrent = index == activeIndex;
        final key = _lineKeys.putIfAbsent(index, GlobalKey.new);

        final lineDirection = textDirectionFor(line.text);

        return Container(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.r12),
            onTap: () {
              widget.playbackController.seek(Duration(milliseconds: line.startMs));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: isCurrent &&
                      highlightMode == 'word' &&
                      hasWordTiming &&
                      line.words != null &&
                      line.words!.isNotEmpty
                  ? _buildWordHighlightedLine(
                      line,
                      currentWordIdx,
                      wordProgress,
                      reduceMotion,
                      lineDirection,
                    )
                  : Text(
                      line.text,
                      textAlign: TextAlign.center,
                      textDirection: lineDirection,
                      style: AppTypography.title.copyWith(
                        fontSize: isCurrent ? 24 : 18,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent
                            ? AppColors.text
                            : AppColors.textMuted.withValues(alpha: 0.45),
                        height: 1.5,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWordHighlightedLine(
    LyricsLine line,
    int activeWordIdx,
    double progress,
    bool reduceMotion,
    TextDirection direction,
  ) {
    final words = line.words!;
    final spans = <InlineSpan>[];

    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final isPast = i < activeWordIdx;
      final isCurrent = i == activeWordIdx;

      final Color wordColor;
      if (isPast) {
        wordColor = AppColors.text;
      } else if (isCurrent) {
        if (reduceMotion) {
          wordColor = AppColors.text;
        } else {
          wordColor = Color.lerp(
            AppColors.textMuted.withValues(alpha: 0.5),
            AppColors.text,
            progress,
          )!;
        }
      } else {
        wordColor = AppColors.textMuted.withValues(alpha: 0.45);
      }

      spans.add(TextSpan(
        text: i < words.length - 1 ? '${w.text} ' : w.text,
        style: TextStyle(
          color: wordColor,
          fontWeight: isCurrent || isPast ? FontWeight.bold : FontWeight.w500,
        ),
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
      textDirection: direction,
      style: AppTypography.title.copyWith(
        fontSize: 24,
        height: 1.5,
      ),
    );
  }
}
