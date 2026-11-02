import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/ui/theme/app_colors.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

/// Computes relative luminance according to WCAG 2.1 specifications.
double _relativeLuminance(Color color) {
  double transform(double channel) {
    if (channel <= 0.03928) {
      return channel / 12.92;
    } else {
      return math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
    }
  }

  final r = transform(color.r);
  final g = transform(color.g);
  final b = transform(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Computes WCAG 2.1 contrast ratio between two colors.
double _contrastRatio(Color foreground, Color background) {
  final l1 = _relativeLuminance(foreground);
  final l2 = _relativeLuminance(background);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('Design Tokens & WCAG Contrast Tests', () {
    test('WCAG contrast ratios on base (#0F1115)', () {
      final textRatio = _contrastRatio(AppColors.text, AppColors.base);
      final textSecRatio =
          _contrastRatio(AppColors.textSecondary, AppColors.base);
      final textMutedRatio = _contrastRatio(AppColors.textMuted, AppColors.base);
      final accentRatio = _contrastRatio(AppColors.accent, AppColors.base);

      expect(
        textRatio,
        greaterThanOrEqualTo(7.0),
        reason: 'Text must meet WCAG AAA normal text contrast (>= 7.0)',
      );
      expect(
        textSecRatio,
        greaterThanOrEqualTo(4.5),
        reason: 'Secondary text must meet WCAG AA normal text contrast (>= 4.5)',
      );
      expect(
        textMutedRatio,
        greaterThanOrEqualTo(3.0),
        reason: 'Muted text must meet WCAG AA large/secondary contrast (>= 3.0)',
      );
      expect(
        accentRatio,
        greaterThanOrEqualTo(4.5),
        reason: 'Accent must meet WCAG AA graphical/text contrast (>= 4.5)',
      );
    });

    test('buildAppTheme configures dark Material 3 defaults', () {
      final theme = buildAppTheme();
      expect(theme.brightness, equals(Brightness.dark));
      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, equals(AppColors.base));
      expect(theme.splashFactory, equals(NoSplash.splashFactory));
      expect(theme.colorScheme.surface, equals(AppColors.surface));
    });
  });
}
