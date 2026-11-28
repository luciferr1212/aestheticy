import 'package:flutter/material.dart';

import '../../../features/lyrics/lyrics_models.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../lyrics_view_helpers.dart';
import 'lyrics_state_views.dart';
import 'lyrics_user_scrollbar.dart';

/// Displays unsynced plain lyrics with edge fade masking and hover notice.
class PlainLyricsView extends StatelessWidget {
  /// Plain lyrics document.
  final LyricsDocument document;

  /// Scroll controller for plain lyrics scrolling.
  final ScrollController scrollController;

  /// Effective view density.
  final LyricsViewDensity density;

  /// Whether mini density renders inside the wide horizontal layout.
  final bool isWideMini;

  /// Whether the view is rendered in full screen mode.
  final bool isFullScreen;

  /// Whether animations should be reduced to zero duration.
  final bool reduceMotion;

  /// Whether the parent lyrics surface is currently hovered.
  final bool isHovered;

  /// Invoked when the user manually scrolls.
  final VoidCallback onUserScroll;

  /// Creates a [PlainLyricsView].
  const PlainLyricsView({
    super.key,
    required this.document,
    required this.scrollController,
    required this.density,
    required this.isWideMini,
    required this.isFullScreen,
    required this.reduceMotion,
    required this.isHovered,
    required this.onUserScroll,
  });

  @override
  Widget build(BuildContext context) {
    if (density == LyricsViewDensity.mini &&
        document.lines.every((l) => l.text.trim().isEmpty)) {
      return const LyricsMiniUnavailable();
    }
    final plainFontSize = switch (density) {
      LyricsViewDensity.mini => isWideMini ? 14.0 : 15.0,
      LyricsViewDensity.sidePanel => 15.5,
      LyricsViewDensity.fullScreen => 26.0,
      LyricsViewDensity.page => 20.0,
    };

    final plainView = ShaderMask(
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
        child: LyricsUserScrollbar(
          controller: scrollController,
          reduceMotion: reduceMotion,
          onUserScroll: onUserScroll,
          child: SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.symmetric(
              horizontal: (density == LyricsViewDensity.mini ||
                      density == LyricsViewDensity.sidePanel)
                  ? 16
                  : 32,
              vertical: switch (density) {
                LyricsViewDensity.mini => 24,
                LyricsViewDensity.sidePanel => 28,
                LyricsViewDensity.fullScreen => 80,
                LyricsViewDensity.page => 48,
              },
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final line in document.lines)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: density == LyricsViewDensity.mini
                              ? 4
                              : (density == LyricsViewDensity.sidePanel
                                  ? 5
                                  : 6),
                        ),
                        child: Text(
                          line.text,
                          textAlign: TextAlign.center,
                          textDirection: textDirectionFor(line.text),
                          style: AppTypography.title.copyWith(
                            fontSize: plainFontSize,
                            fontWeight: FontWeight.normal,
                            color: AppColors.textSecondary,
                            height: density == LyricsViewDensity.mini
                                ? 1.45
                                : (density == LyricsViewDensity.sidePanel
                                    ? 1.5
                                    : 1.6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final showNotice =
        (density == LyricsViewDensity.page ||
                density == LyricsViewDensity.sidePanel) &&
            !isFullScreen;
    if (!showNotice) {
      return plainView;
    }

    final noticeText = context.t('lyrics.notSynced');

    return Stack(
      children: [
        Positioned.fill(child: plainView),
        Positioned(
          top: 12.0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Semantics(
                label: noticeText,
                child: AnimatedOpacity(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  opacity: isHovered ? 1.0 : 0.0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      noticeText,
                      key: const Key('lyrics_unsynced_notice'),
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
