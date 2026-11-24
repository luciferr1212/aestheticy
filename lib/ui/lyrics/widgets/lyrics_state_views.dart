import 'package:flutter/material.dart';

import '../../glass/glass_button.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../lyrics_view_helpers.dart';

/// Compact message shown in Mini Player when synced lyrics are unavailable.
class LyricsMiniUnavailable extends StatelessWidget {
  /// Creates a [LyricsMiniUnavailable].
  const LyricsMiniUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
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
}

/// Skeleton loading placeholder shown while lyrics are fetched.
class LyricsLoadingView extends StatelessWidget {
  /// Current layout density.
  final LyricsViewDensity density;

  /// Creates a [LyricsLoadingView].
  const LyricsLoadingView({super.key, required this.density});

  @override
  Widget build(BuildContext context) {
    final isMini = density == LyricsViewDensity.mini;
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isMini ? 320 : 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final widthFactor
                    in isMini ? const [0.70, 0.90, 0.55] : const [0.70, 0.90, 0.55, 0.80, 0.45]) ...[
                  FractionallySizedBox(
                    widthFactor: widthFactor,
                    child: Container(
                      height: isMini ? 14 : 20,
                      margin: EdgeInsets.symmetric(vertical: isMini ? 5 : 8),
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.18),
                        borderRadius: AppSpacing.br10,
                      ),
                    ),
                  ),
                ],
                SizedBox(height: isMini ? 10 : 24),
                Text(
                  context.t('lyrics.state.loading'),
                  style: AppTypography.body.copyWith(
                    color: AppColors.textMuted.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered empty/error/instrumental state view for lyrics.
class LyricsStatusMessageView extends StatelessWidget {
  /// Icon rendered above the message.
  final IconData icon;

  /// Icon size.
  final double iconSize;

  /// Localized message text.
  final String message;

  /// Text style for [message].
  final TextStyle messageStyle;

  /// Optional retry action callback.
  final VoidCallback? onRetry;

  /// Creates a [LyricsStatusMessageView].
  const LyricsStatusMessageView({
    super.key,
    required this.icon,
    this.iconSize = 48,
    required this.message,
    required this.messageStyle,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: messageStyle,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              GlassPillButton(
                leadingIcon: Icons.refresh,
                label: context.t('lyrics.retry'),
                tooltip: context.t('lyrics.retry'),
                semanticLabel: context.t('lyrics.retry'),
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
