import 'package:flutter/material.dart';

import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Persistent calm banner displayed when user data is opened in
/// `UserDataAccessMode.safeReadOnly`.
class SafeReadOnlyBanner extends StatelessWidget {
  /// Callback to open the application logs directory.
  final VoidCallback? onOpenLogsFolder;

  /// Callback to open the backups directory.
  final VoidCallback? onOpenBackupsFolder;

  /// Creates a [SafeReadOnlyBanner].
  const SafeReadOnlyBanner({
    super.key,
    this.onOpenLogsFolder,
    this.onOpenBackupsFolder,
  });

  @override
  Widget build(BuildContext context) {
    final hasActions =
        onOpenLogsFolder != null || onOpenBackupsFolder != null;
    return Padding(
      key: const Key('safe_read_only_banner'),
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassSurface(
        borderRadius: AppSpacing.r12,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 680;
            final messageRow = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.shield_outlined,
                    color: AppColors.danger,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.t('userdata.safeReadOnlyBannerTitle'),
                        style: AppTypography.bodyStrong.copyWith(
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.t('userdata.safeReadOnlyBannerBody'),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onOpenLogsFolder != null)
                  GlassPillButton(
                    key: const Key('safe_read_only_open_logs'),
                    label: context.t('userdata.openLogsFolder'),
                    leadingIcon: Icons.description_outlined,
                    size: GlassButtonSize.small,
                    onPressed: onOpenLogsFolder,
                  ),
                if (onOpenBackupsFolder != null)
                  GlassPillButton(
                    key: const Key('safe_read_only_open_backups'),
                    label: context.t('userdata.openBackupsFolder'),
                    leadingIcon: Icons.folder_open_outlined,
                    size: GlassButtonSize.small,
                    onPressed: onOpenBackupsFolder,
                  ),
              ],
            );

            if (!hasActions) return messageRow;
            if (compact) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  messageRow,
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 32),
                    child: actions,
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: messageRow),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}
