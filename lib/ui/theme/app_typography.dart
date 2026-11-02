import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Typography scale and font configurations for Aestheticy.
abstract final class AppTypography {
  /// Preferred font family sequence for Windows desktop.
  static const List<String> fontFamilies = [
    'Segoe UI Variable',
    'Segoe UI',
  ];

  /// Fallback font list enabling seamless Arabic and symbol rendering.
  static const List<String> fontFamilyFallback = [
    'Segoe UI',
    'Tahoma',
    'Arial',
  ];

  /// Primary display style (32.0 dp / w600 / height 1.25).
  static const TextStyle display = TextStyle(
    fontFamily: 'Segoe UI Variable',
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 32.0,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: AppColors.text,
  );

  /// Section title style (20.0 dp / w600 / height 1.30).
  static const TextStyle title = TextStyle(
    fontFamily: 'Segoe UI Variable',
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 20.0,
    fontWeight: FontWeight.w600,
    height: 1.30,
    color: AppColors.text,
  );

  /// Regular body style (14.0 dp / w400 / height 1.43).
  static const TextStyle body = TextStyle(
    fontFamily: 'Segoe UI Variable',
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14.0,
    fontWeight: FontWeight.w400,
    height: 1.43,
    color: AppColors.text,
  );

  /// Emphasized body style (14.0 dp / w600 / height 1.43).
  static const TextStyle bodyStrong = TextStyle(
    fontFamily: 'Segoe UI Variable',
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
    height: 1.43,
    color: AppColors.text,
  );

  /// Secondary caption style (12.5 dp / w400 / height 1.36).
  static const TextStyle caption = TextStyle(
    fontFamily: 'Segoe UI Variable',
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.36,
    color: AppColors.textSecondary,
  );

  /// Compact uppercase label style (11.0 dp / w500 / letterSpacing 0.8 / height 1.36).
  static const TextStyle micro = TextStyle(
    fontFamily: 'Segoe UI Variable',
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 11.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
    height: 1.36,
    color: AppColors.textMuted,
  );
}
