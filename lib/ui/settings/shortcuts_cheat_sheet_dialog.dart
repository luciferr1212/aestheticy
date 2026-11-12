import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_shortcuts.dart';

/// Opens the keyboard shortcuts cheat sheet dialog generated from [kAppShortcuts].
Future<void> showShortcutsCheatSheetDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => const ShortcutsCheatSheetDialog(),
  );
}

/// Modal dialog listing every active shortcut in [kAppShortcuts] grouped by scope.
class ShortcutsCheatSheetDialog extends StatelessWidget {
  /// Creates a [ShortcutsCheatSheetDialog].
  const ShortcutsCheatSheetDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final maxWidth = math.min(600.0, math.max(260.0, screenSize.width - 32));
    final maxHeight = math.min(560.0, math.max(200.0, screenSize.height - 48));

    final groups = <AppShortcutScope, List<AppShortcutItem>>{};
    for (final scope in AppShortcutScope.values) {
      final items = kAppShortcuts.where((s) => s.scope == scope).toList();
      if (items.isNotEmpty) {
        groups[scope] = items;
      }
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        shortcutById(AppShortcutId.back).activator: () {
          Navigator.of(context).maybePop();
        },
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          key: const Key('shortcuts_cheat_sheet_dialog'),
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.r16),
            side: const BorderSide(color: AppColors.border),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.t('shortcuts.cheatSheetTitle'),
                          style: AppTypography.title.copyWith(
                            color: AppColors.text,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        key: const Key('shortcuts_cheat_sheet_close'),
                        icon: Icons.close,
                        tooltip: context.t('common.close'),
                        semanticLabel: context.t('common.close'),
                        size: GlassButtonSize.small,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.t('shortcuts.cheatSheetHint'),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: AppColors.borderSubtle, height: 1),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      key: const Key('shortcuts_cheat_sheet_scroll'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final entry in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 6),
                              child: Text(
                                context.t(shortcutScopeLabelKey(entry.key)),
                                style: AppTypography.bodyStrong.copyWith(
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                            for (final shortcut in entry.value)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        context.t(shortcut.descriptionKey),
                                        style: AppTypography.body.copyWith(
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Align(
                                        alignment: AlignmentDirectional.centerEnd,
                                        child: Directionality(
                                          textDirection: TextDirection.ltr,
                                          child: Wrap(
                                            spacing: 4,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: _buildKeyChips(
                                              shortcut.keyCombination,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 6),
                          ],
                        ],
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

  List<Widget> _buildKeyChips(String keyCombination) {
    final tokens = formatShortcutKeyChips(keyCombination);
    final widgets = <Widget>[];
    for (var i = 0; i < tokens.length; i++) {
      if (i > 0) {
        widgets.add(
          Text(
            '+',
            style: AppTypography.micro.copyWith(color: AppColors.textMuted),
          ),
        );
      }
      widgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.fillControl,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Text(
            tokens[i],
            style: AppTypography.micro.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}
