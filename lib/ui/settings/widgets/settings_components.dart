import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Card container grouping related settings rows under a section title.
class SettingsCard extends StatelessWidget {
  /// Section heading text.
  final String title;

  /// Optional descriptive subtitle beneath [title].
  final String? description;

  /// Child rows and dividers.
  final List<Widget> children;

  /// Creates a [SettingsCard].
  const SettingsCard({
    super.key,
    required this.title,
    this.description,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.fillGlass,
        borderRadius: BorderRadius.circular(AppSpacing.r16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTypography.title),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: AppTypography.caption),
          ],
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

/// Horizontal row pairing a setting label/description with a trailing control.
class SettingsRow extends StatelessWidget {
  /// Primary setting label.
  final String title;

  /// Optional secondary hint text.
  final String? description;

  /// Trailing control widget.
  final Widget control;

  /// Creates a [SettingsRow].
  const SettingsRow({
    super.key,
    required this.title,
    this.description,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.bodyStrong),
              if (description != null) ...[
                const SizedBox(height: 2),
                Text(
                  description!,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        control,
      ],
    );
  }
}

/// Option entry for [SettingsSegmentedControl].
class SettingsSegmentedOption<T> {
  /// Underlying option value.
  final T value;

  /// Localized display label.
  final String label;

  /// Creates a [SettingsSegmentedOption].
  const SettingsSegmentedOption({required this.value, required this.label});
}

/// Glass pill segmented control used across settings sections.
class SettingsSegmentedControl<T> extends StatelessWidget {
  /// Currently selected value.
  final T value;

  /// Available options.
  final List<SettingsSegmentedOption<T>> options;

  /// Called when the user selects an option.
  final ValueChanged<T> onChanged;

  /// Creates a [SettingsSegmentedControl].
  const SettingsSegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.fillControl,
        borderRadius: BorderRadius.circular(AppSpacing.r10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final isSelected = opt.value == value;
          return InkWell(
            mouseCursor: SystemMouseCursors.click,
            hoverColor: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(AppSpacing.r10 - 2),
            onTap: () => onChanged(opt.value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accentFill : Colors.transparent,
                borderRadius: BorderRadius.circular(AppSpacing.r10 - 2),
                border: Border.all(
                  color: isSelected ? AppColors.accent : Colors.transparent,
                ),
              ),
              child: Text(
                opt.label,
                style: AppTypography.caption.copyWith(
                  color: isSelected ? AppColors.text : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
