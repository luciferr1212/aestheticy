import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/lyrics/lyrics_controller.dart';
import '../../features/lyrics/lyrics_models.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'lyrics_view_helpers.dart';
import 'widgets/lyrics_header.dart';
import 'widgets/lyrics_state_views.dart';
import 'widgets/lyrics_user_scrollbar.dart';
import 'widgets/plain_lyrics_view.dart';
import 'widgets/synced_line_item.dart';

export 'lyrics_view_helpers.dart';

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

  /// Optional density override (defaults from [isFullScreen] when omitted).
  final LyricsViewDensity? density;

  /// Whether mini density renders inside the wide horizontal layout.
  final bool isWideMini;

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
    this.density,
    this.isWideMini = false,
    this.onLineBuild,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _plainScrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  final ValueNotifier<double> _wordProgressNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<int> _activeWordNotifier = ValueNotifier<int>(-1);

  StreamSubscription<PlaybackState>? _playbackStateSub;
  StreamSubscription<AudioSource?>? _currentTrackSub;
  StreamSubscription<Duration>? _seekSub;
  Ticker? _ticker;
  Timer? _autoFollowTimer;
  bool _isAutoFollowPaused = false;
  bool _handlingSeek = false;
  bool _isHovered = false;
  int _lastScrolledLine = -1;
  String? _currentTrackUri;
  Duration? _lastObservedPosition;
  LyricsControllerState? _lastStructuralState;
  String? _lastHighlightMode;
  bool? _lastReduceMotion;
  String? _lastLanguage;
  bool _needsInitialJump = false;
  int _scrollToken = 0;
  int? _inFlightTargetLine;
  int _lastOffsetMs = 0;

  LyricsViewDensity get _effectiveDensity =>
      widget.density ??
      (widget.isFullScreen
          ? LyricsViewDensity.fullScreen
          : LyricsViewDensity.page);

  double _defaultLineExtent() => switch (_effectiveDensity) {
        LyricsViewDensity.mini => widget.isWideMini ? 36.0 : 40.0,
        LyricsViewDensity.sidePanel => 48.0,
        LyricsViewDensity.fullScreen => 84.0,
        LyricsViewDensity.page => 68.0,
      };

  double _syncedVerticalPadding() => switch (_effectiveDensity) {
        LyricsViewDensity.mini => 24.0,
        LyricsViewDensity.sidePanel => 40.0,
        LyricsViewDensity.fullScreen => 140.0,
        LyricsViewDensity.page => 100.0,
      };

  double _scrollAlignment() =>
      _effectiveDensity == LyricsViewDensity.mini ? 0.40 : 0.38;

  static Alignment _resolveDirectionAlignment(TextDirection direction) =>
      direction == TextDirection.rtl
          ? Alignment.centerRight
          : Alignment.centerLeft;

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
    if (widget.controller.hasRecordedPosition) {
      _lastObservedPosition = widget.controller.lastPlaybackPosition;
    }

    widget.controller.addListener(_onControllerChange);
    widget.settingsStore.addListener(_onSettingsChange);
    _playbackStateSub =
        widget.playbackController.stateStream.listen(_onPlaybackStateChange);
    _currentTrackSub =
        widget.playbackController.currentStream.listen(_onCurrentTrackChange);
    _seekSub = widget.playbackController.seekStream.listen(_onSeek);

    _ticker = createTicker(_onTick);
    _updateTicker();

    if (_lastStructuralState is LyricsStateFound) {
      _needsInitialJump = true;
      _scrollToLine(
        widget.controller.currentLineIndex,
        force: true,
        immediate: true,
      );
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
      _lastObservedPosition = widget.controller.hasRecordedPosition
          ? widget.controller.lastPlaybackPosition
          : null;
      _lastScrolledLine = -1;
      _inFlightTargetLine = null;
      if (_lastStructuralState is LyricsStateFound) {
        _needsInitialJump = true;
        _scrollToLine(
          widget.controller.currentLineIndex,
          force: true,
          immediate: true,
        );
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
      _seekSub?.cancel();
      _playbackStateSub =
          widget.playbackController.stateStream.listen(_onPlaybackStateChange);
      _currentTrackSub =
          widget.playbackController.currentStream.listen(_onCurrentTrackChange);
      _seekSub = widget.playbackController.seekStream.listen(_onSeek);
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

  void _cancelAutoFollowPause() {
    _isAutoFollowPaused = false;
    _autoFollowTimer?.cancel();
    _autoFollowTimer = null;
  }

  void _onSeek(Duration position) {
    if (!mounted) return;
    _cancelAutoFollowPause();
    _lastObservedPosition = position;
    _inFlightTargetLine = null;

    _handlingSeek = true;
    try {
      widget.controller.updatePosition(position, forceNotify: true);
    } finally {
      _handlingSeek = false;
    }

    _activeWordNotifier.value = widget.controller.currentWordIndex;
    _wordProgressNotifier.value = widget.controller.wordProgress;

    final doc = widget.controller.document;
    if (doc != null && doc.kind == LyricsKind.synced && doc.lines.isNotEmpty) {
      final currentLine = widget.controller.currentLineIndex;
      final targetLine = currentLine >= 0 ? currentLine : 0;
      _lastScrolledLine = targetLine;
      _scrollToLine(targetLine, force: true);
    }
  }

  void _onCurrentTrackChange(AudioSource? source) {
    final newUri = source?.uri;
    if (newUri != _currentTrackUri) {
      _currentTrackUri = newUri;
      _lastObservedPosition = null;
      _lastScrolledLine = -1;
      _inFlightTargetLine = null;
      _needsInitialJump = true;
      _cancelAutoFollowPause();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
      if (_plainScrollController.hasClients) {
        _plainScrollController.jumpTo(0.0);
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

    if (_handlingSeek) {
      _lastStructuralState = widget.controller.state;
      _lastOffsetMs = widget.controller.offsetMs;
      return;
    }

    var jumpDetected = false;
    if (widget.controller.hasRecordedPosition) {
      final pos = widget.controller.lastPlaybackPosition;
      final prev = _lastObservedPosition;
      if (prev != null &&
          (pos - prev).abs() > const Duration(milliseconds: 1500)) {
        jumpDetected = true;
        _cancelAutoFollowPause();
        _inFlightTargetLine = null;
      }
      _lastObservedPosition = pos;
    }

    final newState = widget.controller.state;
    final newOffsetMs = widget.controller.offsetMs;
    final structuralChanged =
        !_isSameStructuralState(_lastStructuralState, newState);
    final offsetChanged = newOffsetMs != _lastOffsetMs;
    final currentLine = widget.controller.currentLineIndex;

    if (structuralChanged || offsetChanged) {
      _lastStructuralState = newState;
      _lastOffsetMs = newOffsetMs;
      if (structuralChanged) {
        _lineKeys.clear();
        _lastScrolledLine = -1;
        _inFlightTargetLine = null;
        if (newState is LyricsStateFound) {
          _needsInitialJump = true;
          _scrollToLine(currentLine, force: true, immediate: true);
        } else {
          _needsInitialJump = false;
        }
      } else if (newState is LyricsStateFound) {
        final targetLine = currentLine >= 0 ? currentLine : 0;
        if (jumpDetected ||
            (currentLine != _lastScrolledLine && currentLine >= 0)) {
          _lastScrolledLine = targetLine;
          _scrollToLine(targetLine, force: jumpDetected);
        }
      }
      setState(() {});
      return;
    }

    if (newState is LyricsStateFound) {
      if (_needsInitialJump) {
        _scrollToLine(currentLine, force: true, immediate: true);
      } else if (jumpDetected) {
        final targetLine = currentLine >= 0 ? currentLine : 0;
        _lastScrolledLine = targetLine;
        _scrollToLine(targetLine, force: true);
      } else if (currentLine != _lastScrolledLine && currentLine >= 0) {
        _lastScrolledLine = currentLine;
        _scrollToLine(currentLine);
      }
    }
  }

  double _measureAverageLineExtent(
    LyricsDocument doc,
    ScrollPosition position,
    double verticalPadding,
  ) {
    var totalHeight = 0.0;
    var count = 0;
    for (final key in _lineKeys.values) {
      final ro = key.currentContext?.findRenderObject();
      if (ro is RenderBox && ro.hasSize && ro.size.height > 0) {
        totalHeight += ro.size.height;
        count++;
      }
    }
    if (count > 0) {
      return totalHeight / count;
    }
    if (doc.lines.length > 1 && position.maxScrollExtent > 0) {
      final contentExtent = position.maxScrollExtent +
          position.viewportDimension -
          (verticalPadding * 2);
      if (contentExtent > 0) {
        return contentExtent / doc.lines.length;
      }
      return position.maxScrollExtent / (doc.lines.length - 1);
    }
    return _defaultLineExtent();
  }

  void _scrollToLine(
    int lineIndex, {
    bool force = false,
    bool immediate = false,
  }) {
    if (!force && _isAutoFollowPaused) return;
    final doc = widget.controller.document;
    if (doc == null || doc.kind != LyricsKind.synced || doc.lines.isEmpty) {
      _needsInitialJump = false;
      return;
    }
    final targetIndex = lineIndex < 0
        ? 0
        : (lineIndex >= doc.lines.length ? doc.lines.length - 1 : lineIndex);

    if (!immediate && _inFlightTargetLine == targetIndex) {
      return;
    }

    _inFlightTargetLine = targetIndex;
    final token = ++_scrollToken;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _scrollToken) return;
      if (!force && _isAutoFollowPaused) {
        if (_inFlightTargetLine == targetIndex) {
          _inFlightTargetLine = null;
        }
        return;
      }
      final currentDoc = widget.controller.document;
      if (currentDoc == null ||
          currentDoc.kind != LyricsKind.synced ||
          currentDoc.lines.isEmpty) {
        _needsInitialJump = false;
        _inFlightTargetLine = null;
        return;
      }
      if (!_scrollController.hasClients) {
        _inFlightTargetLine = null;
        return;
      }

      final clampedIndex = targetIndex.clamp(0, currentDoc.lines.length - 1);
      _needsInitialJump = false;
      _lastScrolledLine = clampedIndex;

      if (immediate && lineIndex <= 0) {
        _scrollController.jumpTo(0.0);
        _inFlightTargetLine = null;
        return;
      }

      final reduceMotion = widget.settingsStore.settings.reduceMotion;
      final directContext = _lineKeys[clampedIndex]?.currentContext;
      if (directContext != null) {
        final duration = (reduceMotion || immediate)
            ? Duration.zero
            : const Duration(milliseconds: 650);
        final alignment = _scrollAlignment();
        Scrollable.ensureVisible(
          directContext,
          alignment: alignment,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
        _inFlightTargetLine = null;
        return;
      }

      // Off-screen target: estimate scroll offset using measured line extent
      // so the target line is built, then refine to alignment next frame.
      final position = _scrollController.position;
      final verticalPadding = _syncedVerticalPadding();
      final alignment = _scrollAlignment();
      final estExtent = _measureAverageLineExtent(
        currentDoc,
        position,
        verticalPadding,
      );
      final estY = verticalPadding + (clampedIndex * estExtent);
      final targetOffset = (estY - position.viewportDimension * alignment)
          .clamp(0.0, position.maxScrollExtent);
      _scrollController.jumpTo(targetOffset);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != _scrollToken) return;
        final refinedContext = _lineKeys[clampedIndex]?.currentContext;
        if (refinedContext != null) {
          final refineDuration = (reduceMotion || immediate)
              ? Duration.zero
              : const Duration(milliseconds: 350);
          Scrollable.ensureVisible(
            refinedContext,
            alignment: alignment,
            duration: refineDuration,
            curve: Curves.easeOutCubic,
          );
        }
        if (_inFlightTargetLine == targetIndex) {
          _inFlightTargetLine = null;
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

  void _pauseAutoFollow() {
    _isAutoFollowPaused = true;
    _inFlightTargetLine = null;
    _autoFollowTimer?.cancel();
    _autoFollowTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _isAutoFollowPaused = false;
      final line = widget.controller.currentLineIndex;
      if (line >= 0) {
        _lastScrolledLine = line;
        _scrollToLine(line, force: true);
      }
    });
  }

  @override
  void dispose() {
    _scrollToken++;
    _autoFollowTimer?.cancel();
    _autoFollowTimer = null;
    widget.controller.removeListener(_onControllerChange);
    widget.settingsStore.removeListener(_onSettingsChange);
    _playbackStateSub?.cancel();
    _currentTrackSub?.cancel();
    _seekSub?.cancel();
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _activeWordNotifier.dispose();
    _wordProgressNotifier.dispose();
    _scrollController.dispose();
    _plainScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = widget.playbackController.queue.current;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_effectiveDensity == LyricsViewDensity.sidePanel)
            LyricsSidePanelToolbar(
              currentTrack: currentTrack,
              controller: widget.controller,
            )
          else if (widget.showHeader &&
              _effectiveDensity != LyricsViewDensity.mini)
            LyricsHeader(
              currentTrack: currentTrack,
              controller: widget.controller,
              navigator: widget.navigator,
            ),
          Expanded(
            child: _buildBody(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final state = widget.controller.state;
    final reduceMotion = widget.settingsStore.settings.reduceMotion;
    final density = _effectiveDensity;
    final isMini = density == LyricsViewDensity.mini;

    final Widget content;
    final Key contentKey;

    switch (state) {
      case LyricsStateLoading():
        contentKey = const ValueKey('lyrics_state_loading');
        content = LyricsLoadingView(density: density);
      case LyricsStateOff():
        contentKey = const ValueKey('lyrics_state_off');
        content = isMini
            ? const LyricsMiniUnavailable()
            : LyricsStatusMessageView(
                icon: Icons.lyrics_outlined,
                message: context.t('lyrics.state.off'),
                messageStyle:
                    AppTypography.body.copyWith(color: AppColors.textMuted),
              );
      case LyricsStateNotFound():
        contentKey = const ValueKey('lyrics_state_notFound');
        content = isMini
            ? const LyricsMiniUnavailable()
            : LyricsStatusMessageView(
                icon: Icons.music_off,
                message: context.t('lyrics.state.notFound'),
                messageStyle:
                    AppTypography.body.copyWith(color: AppColors.textMuted),
              );
      case LyricsStateError(reason: final r):
        contentKey = ValueKey('lyrics_state_error_${r.name}');
        content = isMini
            ? const LyricsMiniUnavailable()
            : LyricsStatusMessageView(
                icon: Icons.error_outline,
                message: context.t('lyrics.state.error'),
                messageStyle:
                    AppTypography.body.copyWith(color: AppColors.textMuted),
                onRetry: () => widget.controller.retry(),
              );
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

  Widget _buildFound(BuildContext context, LyricsDocument doc) {
    if (doc.kind == LyricsKind.instrumental) {
      return LyricsStatusMessageView(
        icon: Icons.music_note,
        iconSize: 56,
        message: context.t('lyrics.state.instrumental'),
        messageStyle: AppTypography.title.copyWith(color: AppColors.textMuted),
      );
    }

    if (doc.kind == LyricsKind.plain) {
      return PlainLyricsView(
        document: doc,
        scrollController: _plainScrollController,
        density: _effectiveDensity,
        isWideMini: widget.isWideMini,
        isFullScreen: widget.isFullScreen,
        reduceMotion: widget.settingsStore.settings.reduceMotion,
        isHovered: _isHovered,
        onUserScroll: _pauseAutoFollow,
      );
    }

    return _buildSyncedList(context, doc);
  }

  Widget _buildSyncedList(BuildContext context, LyricsDocument doc) {
    final density = _effectiveDensity;
    if (density == LyricsViewDensity.mini && doc.lines.isEmpty) {
      return const LyricsMiniUnavailable();
    }
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
      child: LyricsUserScrollbar(
        controller: _scrollController,
        reduceMotion: reduceMotion,
        onUserScroll: _pauseAutoFollow,
        child: ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(
            horizontal: (density == LyricsViewDensity.mini ||
                    density == LyricsViewDensity.sidePanel)
                ? 12
                : 24,
            vertical: _syncedVerticalPadding(),
          ),
          itemCount: doc.lines.length,
          itemBuilder: (context, index) {
            final line = doc.lines[index];
            final key = _lineKeys.putIfAbsent(index, GlobalKey.new);
            final mappedRanges = (hasWordTiming && line.words != null)
                ? mapWordsToLineRanges(line.text, line.words!)
                : null;

            final canSweep = !reduceMotion &&
                hasWordTiming &&
                highlightMode == 'word';

            return RepaintBoundary(
              child: SyncedLineItem(
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
                density: density,
                isWideMini: widget.isWideMini,
                canSweep: canSweep,
                resolveDirectionAlignment: _resolveDirectionAlignment,
                onBuildProbe: widget.onLineBuild,
                onTap: () {
                  _cancelAutoFollowPause();
                  _inFlightTargetLine = null;
                  _lastScrolledLine = index;
                  final targetPos = Duration(milliseconds: line.startMs);
                  widget.playbackController.seek(targetPos);
                  widget.controller.updatePosition(targetPos, forceNotify: true);
                  _activeWordNotifier.value = widget.controller.currentWordIndex;
                  _wordProgressNotifier.value = widget.controller.wordProgress;
                  _scrollToLine(index, force: true);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
