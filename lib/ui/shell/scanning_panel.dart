import 'package:flutter/material.dart';

import '../../library/scan_service.dart';
import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Slim scanning progress panel rendered at the top of the content area while
/// a background directory scan is active.
class ScanningPanel extends StatelessWidget {
  /// The active scanning application service.
  final ScanService scanService;

  /// Creates a [ScanningPanel].
  const ScanningPanel({super.key, required this.scanService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scanService,
      builder: (context, _) {
        if (!scanService.isScanning) {
          return const SizedBox.shrink();
        }

        final progress = scanService.currentProgress;
        final hasTotal = progress.found > 0;
        final double? progressValue = hasTotal
            ? (progress.processed / progress.found).clamp(0.0, 1.0)
            : null;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassSurface(
            borderRadius: AppSpacing.r12,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.sync,
                      color: AppColors.accent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.t('scan.title'),
                      style: AppTypography.bodyStrong.copyWith(
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Stats: tracks found, skipped
                    Expanded(
                      child: Text(
                        '${progress.found} ${context.t('scan.tracksFound')}'
                        '${progress.errors > 0 ? ' • ${progress.errors} ${context.t('scan.skipped')}' : ''}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Cancel button
                    GlassPillButton(
                      key: const Key('scan_cancel_button'),
                      label: context.t('common.cancel'),
                      size: GlassButtonSize.small,
                      onPressed: () => scanService.cancel(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    backgroundColor: AppColors.fillControl,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                    minHeight: 3,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
