import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/lyrics/lyrics_controller.dart';
import '../../features/lyrics/lyrics_models.dart';
import '../../features/lyrics/lyrics_offset_store.dart';
import '../../features/lyrics/lyrics_repository.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
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

/// Character range within [LyricsLine.text] mapped to a [LyricsWord] entry.
class WordCharRange {
  /// 0-based index of the word inside [LyricsLine.words].
  final int wordIndex;

  /// Inclusive start character index in [LyricsLine.text].
  final int start;

  /// Exclusive end character index in [LyricsLine.text].
  final int end;

  /// Creates a [WordCharRange].
  const WordCharRange({
    required this.wordIndex,
    required this.start,
    required this.end,
  });
}

/// Maps [words] sequentially onto character ranges in [lineText].
///
/// Returns `null` if any word is empty or cannot be found sequentially in
/// [lineText], signalling callers to fall back to line highlight without
/// estimating timings or altering layout text.
List<WordCharRange>? mapWordsToLineRanges(
  String lineText,
  List<LyricsWord> words,
) {
  if (words.isEmpty) return null;
  final ranges = <WordCharRange>[];
  var cursor = 0;
  for (var i = 0; i < words.length; i++) {
    final wordText = words[i].text;
    if (wordText.isEmpty) {
      return null;
    }
    final found = lineText.indexOf(wordText, cursor);
    if (found < 0) {
      return null;
    }
    ranges.add(
      WordCharRange(
        wordIndex: i,
        start: found,
        end: found + wordText.length,
      ),
    );
    cursor = found + wordText.length;
  }
  return ranges;
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

  /// Optional test hook invoked whenever a synced line item builds.
  @visibleForTesting
  final void Function(int index)? onLineBuild;

  /// Creates a [LyricsView].
  const LyricsView({
    super.key,
    required this.controller,
    required this.playbackController,
    required this.settingsStore,
    this.navigator,
    this.showHeader = true,
    this.isFullScreen = false,
    this.onLineBuild,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  final ValueNotifier<double> _wordProgressNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<int> _activeWordNotifier = ValueNotifier<int>(-1);

  StreamSubscription<PlaybackState>? _playbackStateSub;
  StreamSubscription<AudioSource?>? _currentTrackSub;
  Ticker? _ticker;
  Timer? _autoFollowTimer;
  bool _isAutoFollowPaused = false;
  int _lastScrolledLine = -1;
  String? _currentTrackUri;
  LyricsControllerState? _lastStructuralState;
  String? _lastHighlightMode;
  bool? _lastReduceMotion;
  String? _lastLanguage;
  bool _needsInitialJump = false;
  int _initialJumpToken = 0;
  int _lastOffsetMs = 0;

  @override
  void initState() {
    super.initState();
    _lastStructuralState = widget.controller.state;
    _lastHighlightMode = widget.settingsStore.settings.lyricsHighlight;
    _lastReduceMotion = widget.settingsStore.settings.reduceMotion;
    _lastLanguage = widget.settingsStore.settings.language;
    _lastOffsetMs = widget.controller.offsetMs;
    _activeWordNotifier.value = widget.controller.currentWordIndex;
    _wordProgressNotifier.value = widget.controller.wordProgress;
    _currentTrackUri = widget.playbackController.queue.current?.uri;

    widget.controller.addListener(_onControllerChange);
    widget.settingsStore.addListener(_onSettingsChange);
    _playbackStateSub =
        widget.playbackController.stateStream.listen(_onPlaybackStateChange);
    _currentTrackSub =
        widget.playbackController.currentStream.listen(_onCurrentTrackChange);

    _ticker = createTicker(_onTick);
    _updateTicker();

    if (_lastStructuralState is LyricsStateFound) {
      _needsInitialJump = true;
      _scheduleInitialJump();
    }
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
      _lastStructuralState = widget.controller.state;
      _lastOffsetMs = widget.controller.offsetMs;
      _activeWordNotifier.value = widget.controller.currentWordIndex;
      _wordProgressNotifier.value = widget.controller.wordProgress;
      _lastScrolledLine = -1;
      if (_lastStructuralState is LyricsStateFound) {
        _needsInitialJump = true;
        _scheduleInitialJump();
      }
    }
    if (oldWidget.settingsStore != widget.settingsStore) {
      oldWidget.settingsStore.removeListener(_onSettingsChange);
      widget.settingsStore.addListener(_onSettingsChange);
      _lastHighlightMode = widget.settingsStore.settings.lyricsHighlight;
      _lastReduceMotion = widget.settingsStore.settings.reduceMotion;
      _lastLanguage = widget.settingsStore.settings.language;
    }
    if (oldWidget.playbackController != widget.playbackController) {
      _playbackStateSub?.cancel();
      _currentTrackSub?.cancel();
      _playbackStateSub =
          widget.playbackController.stateStream.listen(_onPlaybackStateChange);
      _currentTrackSub =
          widget.playbackController.currentStream.listen(_onCurrentTrackChange);
    }
    _updateTicker();
  }

  void _onSettingsChange() {
    if (!mounted) return;
    _updateTicker();
    final settings = widget.settingsStore.settings;
    if (settings.lyricsHighlight != _lastHighlightMode ||
        settings.reduceMotion != _lastReduceMotion ||
        settings.language != _lastLanguage) {
      _lastHighlightMode = settings.lyricsHighlight;
      _lastReduceMotion = settings.reduceMotion;
      _lastLanguage = settings.language;
      setState(() {});
    }
  }

  void _onCurrentTrackChange(AudioSource? source) {
    final newUri = source?.uri;
    if (newUri != _currentTrackUri) {
      _currentTrackUri = newUri;
      _lastScrolledLine = -1;
      _needsInitialJump = true;
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

  bool _isSameStructuralState(
    LyricsControllerState? a,
    LyricsControllerState b,
  ) {
    if (a == null) return false;
    if (identical(a, b)) return true;
    if (a is LyricsStateOff && b is LyricsStateOff) return true;
    if (a is LyricsStateLoading && b is LyricsStateLoading) return true;
    if (a is LyricsStateNotFound && b is LyricsStateNotFound) return true;
    if (a is LyricsStateError && b is LyricsStateError) {
      return a.reason == b.reason;
    }
    if (a is LyricsStateFound && b is LyricsStateFound) {
      return identical(a.document, b.document);
    }
    return false;
  }

  void _onControllerChange() {
    if (!mounted) return;
    _updateTicker();
    _activeWordNotifier.value = widget.controller.currentWordIndex;
    _wordProgressNotifier.value = widget.controller.wordProgress;

    final newState = widget.controller.state;
    final newOffsetMs = widget.controller.offsetMs;
    final structuralChanged = !_isSameStructuralState(_lastStructuralState, newState);
    final offsetChanged = newOffsetMs != _lastOffsetMs;
    final currentLine = widget.controller.currentLineIndex;

    if (structuralChanged || offsetChanged) {
      _lastStructuralState = newState;
      _lastOffsetMs = newOffsetMs;
      if (structuralChanged) {
        _lineKeys.clear();
        _lastScrolledLine = -1;
        if (newState is LyricsStateFound) {
          _needsInitialJump = true;
          _scheduleInitialJump();
        } else {
          _needsInitialJump = false;
        }
      } else if (newState is LyricsStateFound &&
          currentLine != _lastScrolledLine &&
          currentLine >= 0) {
        _lastScrolledLine = currentLine;
        _scrollToCurrentLine(currentLine);
      }
      setState(() {});
      return;
    }

    if (newState is LyricsStateFound) {
      if (_needsInitialJump) {
        _scheduleInitialJump();
      } else if (currentLine != _lastScrolledLine && currentLine >= 0) {
        _lastScrolledLine = currentLine;
        _scrollToCurrentLine(currentLine);
      }
    }
  }

  void _scheduleInitialJump() {
    final token = ++_initialJumpToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _initialJumpToken) return;
      final doc = widget.controller.document;
      if (doc == null || doc.kind != LyricsKind.synced || doc.lines.isEmpty) {
        _needsInitialJump = false;
        return;
      }
      if (!_scrollController.hasClients) return;

      final activeLine = widget.controller.currentLineIndex;
      _needsInitialJump = false;
      _lastScrolledLine = activeLine;

      if (activeLine <= 0) {
        _scrollController.jumpTo(0.0);
        return;
      }

      final key = _lineKeys[activeLine];
      final directContext = key?.currentContext;
      if (directContext != null) {
        Scrollable.ensureVisible(
          directContext,
          alignment: 0.38,
          duration: Duration.zero,
        );
        return;
      }

      // Off-screen target: estimate scroll offset first so the active line is
      // built, then snap to exact 0.38 alignment with zero animation.
      final position = _scrollController.position;
      final estExtent = doc.lines.length > 1 && position.maxScrollExtent > 0
          ? position.maxScrollExtent / (doc.lines.length - 1)
          : (widget.isFullScreen ? 84.0 : 68.0);
      final targetOffset =
          (activeLine * estExtent - position.viewportDimension * 0.38)
              .clamp(0.0, position.maxScrollExtent);
      _scrollController.jumpTo(targetOffset);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != _initialJumpToken) return;
        final refinedContext = _lineKeys[activeLine]?.currentContext;
        if (refinedContext != null) {
          Scrollable.ensureVisible(
            refinedContext,
            alignment: 0.38,
            duration: Duration.zero,
          );
        }
      });
    });
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
    _activeWordNotifier.value = widget.controller.currentWordIndex;
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
          alignment: 0.38,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 650),
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
      final line = widget.controller.currentLineIndex;
      if (line >= 0) {
        _lastScrolledLine = line;
        _scrollToCurrentLine(line, force: true);
      }
    });
  }

  @override
  void dispose() {
    _initialJumpToken++;
    _autoFollowTimer?.cancel();
    _autoFollowTimer = null;
    widget.controller.removeListener(_onControllerChange);
    widget.settingsStore.removeListener(_onSettingsChange);
    _playbackStateSub?.cancel();
    _currentTrackSub?.cancel();
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _activeWordNotifier.dispose();
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasTrailing =
              sourceLabel.isNotEmpty ||
              timingLabel.isNotEmpty ||
              (doc != null && doc.kind == LyricsKind.synced);
          final trailingMaxWidth =
              (constraints.maxWidth * 0.68).clamp(160.0, 900.0);

          return Row(
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
              if (hasTrailing) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: trailingMaxWidth),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (sourceLabel.isNotEmpty) _buildBadge(sourceLabel),
                      if (timingLabel.isNotEmpty) _buildBadge(timingLabel),
                      if (doc != null && doc.kind == LyricsKind.synced)
                        _LyricsSyncControl(controller: widget.controller),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
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
        contentKey = ValueKey(
          'lyrics_doc_${_currentTrackUri}_${identityHashCode(doc)}_${doc.lines.length}',
        );
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
    final highlightMode = widget.settingsStore.settings.lyricsHighlight;
    final hasWordTiming = doc.hasWordTiming;
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
            final mappedRanges = (hasWordTiming && line.words != null)
                ? mapWordsToLineRanges(line.text, line.words!)
                : null;

            return RepaintBoundary(
              child: _SyncedLineItem(
                key: key,
                index: index,
                line: line,
                activeLineListenable: widget.controller.activeLineListenable,
                activeWordListenable: _activeWordNotifier,
                wordProgressListenable: _wordProgressNotifier,
                highlightMode: highlightMode,
                hasWordTiming: hasWordTiming,
                mappedRanges: mappedRanges,
                reduceMotion: reduceMotion,
                isFullScreen: widget.isFullScreen,
                onBuildProbe: widget.onLineBuild,
                onTap: () {
                  _autoFollowTimer?.cancel();
                  _isAutoFollowPaused = false;
                  _lastScrolledLine = index;
                  widget.playbackController
                      .seek(Duration(milliseconds: line.startMs));
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
  final ValueListenable<int> activeLineListenable;
  final ValueListenable<int> activeWordListenable;
  final ValueListenable<double> wordProgressListenable;
  final String highlightMode;
  final bool hasWordTiming;
  final List<WordCharRange>? mappedRanges;
  final bool reduceMotion;
  final bool isFullScreen;
  final void Function(int index)? onBuildProbe;
  final VoidCallback onTap;

  const _SyncedLineItem({
    super.key,
    required this.index,
    required this.line,
    required this.activeLineListenable,
    required this.activeWordListenable,
    required this.wordProgressListenable,
    required this.highlightMode,
    required this.hasWordTiming,
    required this.mappedRanges,
    required this.reduceMotion,
    required this.isFullScreen,
    this.onBuildProbe,
    required this.onTap,
  });

  @override
  State<_SyncedLineItem> createState() => _SyncedLineItemState();
}

class _SyncedLineItemState extends State<_SyncedLineItem> {
  bool _isHovered = false;
  late bool _cachedIsCurrent;
  late double _cachedOpacity;
  late double _cachedScale;
  late bool _cachedIsWordHighlightActive;

  @override
  void initState() {
    super.initState();
    _syncCachedBucket(widget.activeLineListenable.value);
    widget.activeLineListenable.addListener(_onActiveLineChanged);
  }

  @override
  void didUpdateWidget(_SyncedLineItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeLineListenable != widget.activeLineListenable) {
      oldWidget.activeLineListenable.removeListener(_onActiveLineChanged);
      widget.activeLineListenable.addListener(_onActiveLineChanged);
    }
    _syncCachedBucket(widget.activeLineListenable.value);
  }

  @override
  void dispose() {
    widget.activeLineListenable.removeListener(_onActiveLineChanged);
    super.dispose();
  }

  void _syncCachedBucket(int activeIndex) {
    _cachedIsCurrent = widget.index == activeIndex;
    _cachedOpacity = computeLineOpacity(
      index: widget.index,
      activeIndex: activeIndex,
      isHovered: _isHovered,
    );
    _cachedScale =
        widget.reduceMotion ? 1.0 : (_cachedIsCurrent ? 1.0 : 0.92);
    _cachedIsWordHighlightActive = _cachedIsCurrent &&
        widget.highlightMode == 'word' &&
        widget.hasWordTiming &&
        widget.mappedRanges != null;
  }

  void _onActiveLineChanged() {
    if (!mounted) return;
    final activeIndex = widget.activeLineListenable.value;
    final nextIsCurrent = widget.index == activeIndex;
    final nextOpacity = computeLineOpacity(
      index: widget.index,
      activeIndex: activeIndex,
      isHovered: _isHovered,
    );
    final nextScale = widget.reduceMotion ? 1.0 : (nextIsCurrent ? 1.0 : 0.92);
    final nextWordActive = nextIsCurrent &&
        widget.highlightMode == 'word' &&
        widget.hasWordTiming &&
        widget.mappedRanges != null;

    if (nextIsCurrent == _cachedIsCurrent &&
        nextOpacity == _cachedOpacity &&
        nextScale == _cachedScale &&
        nextWordActive == _cachedIsWordHighlightActive) {
      return;
    }

    setState(() {
      _cachedIsCurrent = nextIsCurrent;
      _cachedOpacity = nextOpacity;
      _cachedScale = nextScale;
      _cachedIsWordHighlightActive = nextWordActive;
    });
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuildProbe?.call(widget.index);

    final lineDirection = textDirectionFor(widget.line.text);
    final startAlign = lineDirection == TextDirection.rtl
        ? Alignment.centerRight
        : Alignment.centerLeft;

    final double constantFontSize = widget.isFullScreen ? 42.0 : 32.0;
    final baseStyle = AppTypography.title.copyWith(
      fontSize: constantFontSize,
      fontWeight: FontWeight.w700,
      color: AppColors.text,
      height: 1.3,
    );

    final Duration animDuration = widget.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 400);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() {
          _isHovered = true;
          _syncCachedBucket(widget.activeLineListenable.value);
        });
      },
      onExit: (_) {
        setState(() {
          _isHovered = false;
          _syncCachedBucket(widget.activeLineListenable.value);
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedOpacity(
          opacity: _cachedOpacity,
          duration: animDuration,
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: _cachedScale,
            alignment: startAlign,
            duration: animDuration,
            curve: Curves.easeOutCubic,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: startAlign,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: widget.isFullScreen ? 760.0 : double.infinity,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: _cachedIsWordHighlightActive
                        ? _WordHighlightedLineText(
                            lineText: widget.line.text,
                            ranges: widget.mappedRanges!,
                            lineDirection: lineDirection,
                            baseStyle: baseStyle,
                            reduceMotion: widget.reduceMotion,
                            activeWordListenable: widget.activeWordListenable,
                            wordProgressListenable:
                                widget.wordProgressListenable,
                          )
                        : Text(
                            widget.line.text,
                            textAlign: TextAlign.start,
                            textDirection: lineDirection,
                            style: baseStyle,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WordHighlightedLineText extends StatelessWidget {
  final String lineText;
  final List<WordCharRange> ranges;
  final TextDirection lineDirection;
  final TextStyle baseStyle;
  final bool reduceMotion;
  final ValueListenable<int> activeWordListenable;
  final ValueListenable<double> wordProgressListenable;

  const _WordHighlightedLineText({
    required this.lineText,
    required this.ranges,
    required this.lineDirection,
    required this.baseStyle,
    required this.reduceMotion,
    required this.activeWordListenable,
    required this.wordProgressListenable,
  });

  @override
  Widget build(BuildContext context) {
    final dimColor = AppColors.textMuted.withValues(alpha: 0.45);
    final geometryOnlyStyle = TextStyle(
      fontFamily: baseStyle.fontFamily,
      fontFamilyFallback: baseStyle.fontFamilyFallback,
      fontSize: baseStyle.fontSize,
      fontWeight: baseStyle.fontWeight,
      height: baseStyle.height,
      letterSpacing: baseStyle.letterSpacing,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final isRtl = lineDirection == TextDirection.rtl;

    return LayoutBuilder(
      builder: (context, constraints) {
        return ListenableBuilder(
          listenable: Listenable.merge(
            [activeWordListenable, wordProgressListenable],
          ),
          builder: (context, _) {
            final activeWordIdx = activeWordListenable.value;
            final progress = wordProgressListenable.value.clamp(0.0, 1.0);

            Rect? activeWordRect;
            if (!reduceMotion &&
                activeWordIdx >= 0 &&
                activeWordIdx < ranges.length &&
                progress > 0.0 &&
                progress < 1.0) {
              final r = ranges[activeWordIdx];
              final tp = TextPainter(
                text: TextSpan(text: lineText, style: geometryOnlyStyle),
                textAlign: TextAlign.start,
                textDirection: lineDirection,
                textScaler: textScaler,
              )..layout(maxWidth: constraints.maxWidth);
              final boxes = tp.getBoxesForSelection(
                TextSelection(baseOffset: r.start, extentOffset: r.end),
              );
              tp.dispose();
              if (boxes.isNotEmpty) {
                var union = boxes.first.toRect();
                for (var b = 1; b < boxes.length; b++) {
                  union = union.expandToInclude(boxes[b].toRect());
                }
                if (union.width > 0 && union.height > 0) {
                  activeWordRect = union;
                }
              }
            }

            final spans = <InlineSpan>[];
            var cursor = 0;

            for (var i = 0; i < ranges.length; i++) {
              final r = ranges[i];
              if (r.start > cursor) {
                final gapColor = (activeWordIdx >= 0 && i <= activeWordIdx)
                    ? AppColors.text
                    : dimColor;
                spans.add(
                  TextSpan(
                    text: lineText.substring(cursor, r.start),
                    style: TextStyle(color: gapColor),
                  ),
                );
              }

              final wordSlice = lineText.substring(r.start, r.end);
              final TextStyle wordStyle;
              if (activeWordIdx < 0) {
                wordStyle = TextStyle(color: dimColor);
              } else if (i < activeWordIdx) {
                wordStyle = const TextStyle(color: AppColors.text);
              } else if (i == activeWordIdx) {
                if (reduceMotion || progress >= 1.0) {
                  wordStyle = const TextStyle(color: AppColors.text);
                } else if (progress <= 0.0 || activeWordRect == null) {
                  wordStyle = TextStyle(
                    color: progress >= 0.5 ? AppColors.text : dimColor,
                  );
                } else {
                  final shader = LinearGradient(
                    begin:
                        isRtl ? Alignment.centerRight : Alignment.centerLeft,
                    end: isRtl ? Alignment.centerLeft : Alignment.centerRight,
                    colors: [
                      AppColors.text,
                      AppColors.text,
                      dimColor,
                      dimColor,
                    ],
                    stops: [0.0, progress, progress, 1.0],
                  ).createShader(activeWordRect);
                  wordStyle = TextStyle(foreground: Paint()..shader = shader);
                }
              } else {
                wordStyle = TextStyle(color: dimColor);
              }

              spans.add(TextSpan(text: wordSlice, style: wordStyle));
              cursor = r.end;
            }

            if (cursor < lineText.length) {
              final tailColor = (activeWordIdx >= ranges.length)
                  ? AppColors.text
                  : dimColor;
              spans.add(
                TextSpan(
                  text: lineText.substring(cursor),
                  style: TextStyle(color: tailColor),
                ),
              );
            }

            return DefaultTextStyle(
              style: geometryOnlyStyle,
              child: Text.rich(
                TextSpan(children: spans),
                textAlign: TextAlign.start,
                textDirection: lineDirection,
              ),
            );
          },
        );
      },
    );
  }
}

class _LyricsSyncControl extends StatelessWidget {
  final LyricsController controller;

  const _LyricsSyncControl({required this.controller});

  String _formatOffsetValue(BuildContext context, int offsetMs) {
    final String valueStr;
    if (offsetMs == 0) {
      valueStr = context.localizeDigitsText('0');
    } else {
      final sign = offsetMs > 0 ? '+' : '-';
      final formatted = (offsetMs.abs() / 1000.0).toStringAsFixed(1);
      valueStr = context.localizeDigitsText('$sign$formatted');
    }
    return context.t('lyrics.sync.secondsFormat', args: {'value': valueStr});
  }

  void _step(int deltaMs) {
    controller.setOffset(controller.offsetMs + deltaMs);
  }

  @override
  Widget build(BuildContext context) {
    final offsetMs = controller.offsetMs;
    final canDecrease = offsetMs > kMinLyricsOffsetMs;
    final canIncrease = offsetMs < kMaxLyricsOffsetMs;
    final formattedValue = _formatOffsetValue(context, offsetMs);

    return Container(
      key: const Key('lyrics_sync_control'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.fillControl,
        borderRadius: BorderRadius.circular(AppSpacing.pill),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 4,
        children: [
          Text(
            context.t('lyrics.sync.label'),
            style: AppTypography.micro.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          _HoldRepeatStepButton(
            key: const Key('lyrics_sync_minus'),
            icon: Icons.remove,
            tooltip: context.t('lyrics.sync.earlierTooltip'),
            enabled: canDecrease,
            onStep: () => _step(-kLyricsOffsetStepMs),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              formattedValue,
              key: const Key('lyrics_sync_value'),
              style: AppTypography.micro.copyWith(
                color: offsetMs == 0 ? AppColors.textMuted : AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _HoldRepeatStepButton(
            key: const Key('lyrics_sync_plus'),
            icon: Icons.add,
            tooltip: context.t('lyrics.sync.laterTooltip'),
            enabled: canIncrease,
            onStep: () => _step(kLyricsOffsetStepMs),
          ),
          const SizedBox(width: 4),
          TextButton(
            key: const Key('lyrics_sync_reset'),
            onPressed: offsetMs != 0 ? () => controller.resetOffset() : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 24),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: AppColors.text,
              disabledForegroundColor: AppColors.textMuted.withValues(alpha: 0.4),
            ),
            child: Text(
              context.t('lyrics.sync.reset'),
              style: AppTypography.micro.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldRepeatStepButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onStep;

  const _HoldRepeatStepButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onStep,
  });

  @override
  State<_HoldRepeatStepButton> createState() => _HoldRepeatStepButtonState();
}

class _HoldRepeatStepButtonState extends State<_HoldRepeatStepButton> {
  Timer? _holdDelayTimer;
  Timer? _repeatTimer;
  bool _didRepeat = false;

  void _cancelTimers() {
    _holdDelayTimer?.cancel();
    _holdDelayTimer = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _startHold() {
    _cancelTimers();
    _didRepeat = false;
    if (!widget.enabled) return;
    _holdDelayTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || !widget.enabled) return;
      _didRepeat = true;
      widget.onStep();
      _repeatTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        if (!mounted || !widget.enabled) {
          _cancelTimers();
          return;
        }
        widget.onStep();
      });
    });
  }

  void _endHold({required bool handleTap}) {
    final wasRepeat = _didRepeat;
    _cancelTimers();
    _didRepeat = false;
    if (handleTap && !wasRepeat && widget.enabled) {
      widget.onStep();
    }
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? AppColors.text
        : AppColors.textMuted.withValues(alpha: 0.4);

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: widget.tooltip,
        onTap: widget.enabled ? widget.onStep : null,
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: widget.enabled ? (_) => _startHold() : null,
            onPointerUp:
                widget.enabled ? (_) => _endHold(handleTap: true) : null,
            onPointerCancel: (_) => _endHold(handleTap: false),
            child: SizedBox(
              width: 24,
              height: 24,
              child: Icon(widget.icon, size: 15, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
