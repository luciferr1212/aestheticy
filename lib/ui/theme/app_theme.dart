import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Builds the default dark Material 3 theme for Aestheticy using design tokens.
ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.dark(
    brightness: Brightness.dark,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    primary: AppColors.accent,
    onPrimary: AppColors.base,
    primaryContainer: AppColors.accentFill,
    onPrimaryContainer: AppColors.text,
    secondary: AppColors.accentSoft,
    onSecondary: AppColors.base,
    error: AppColors.danger,
    onError: AppColors.base,
    outline: AppColors.border,
    outlineVariant: AppColors.borderSubtle,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.base,
    splashFactory: NoSplash.splashFactory,
    highlightColor: const Color(0x0AFFFFFF),
    focusColor: const Color(0x33D3C9EA),
    fontFamily: 'Segoe UI Variable',
    fontFamilyFallback: AppTypography.fontFamilyFallback,
    textTheme: const TextTheme(
      displayLarge: AppTypography.display,
      titleLarge: AppTypography.title,
      bodyLarge: AppTypography.bodyStrong,
      bodyMedium: AppTypography.body,
      bodySmall: AppTypography.caption,
      labelSmall: AppTypography.micro,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll<double>(6.0),
      radius: const Radius.circular(AppSpacing.r10),
      thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.dragged)) {
          return AppColors.textSecondary;
        }
        if (states.contains(WidgetState.hovered)) {
          return AppColors.textMuted;
        }
        return AppColors.border;
      }),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xDC1D1C25),
        borderRadius: AppSpacing.br10,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      textStyle: AppTypography.caption.copyWith(color: AppColors.text),
      waitDuration: const Duration(milliseconds: 500),
    ),
  );
}
