import 'package:flutter/painting.dart';

/// Design color tokens for the Aestheticy dark theme.
///
/// Calm, muted color palette with strict contrast compliance and
/// no neon or saturated colors.
abstract final class AppColors {
  /// Base background color (#0F1115).
  static const Color base = Color(0xFF0F1115);

  /// Elevated surface color (#1D1C25).
  static const Color surface = Color(0xFF1D1C25);

  /// Primary high-contrast text color (#E9E7F0).
  static const Color text = Color(0xFFE9E7F0);

  /// Secondary text color (#A9A7B3) meeting 4.5:1 contrast on [base].
  static const Color textSecondary = Color(0xFFA9A7B3);

  /// Muted caption and placeholder text color (#8E8C99) meeting 3.0:1 contrast on [base].
  static const Color textMuted = Color(0xFF8E8C99);

  /// Primary accent color (#D3C9EA), calm lavender.
  static const Color accent = Color(0xFFD3C9EA);

  /// Soft accent variant (#C9BEE4).
  static const Color accentSoft = Color(0xFFC9BEE4);

  /// Accent fill at 26% alpha (0x42) for translucent indicators and primary buttons.
  static const Color accentFill = Color(0x42D3C9EA);

  /// Standard subtle border (white at 12% alpha).
  static const Color border = Color(0x1FFFFFFF);

  /// Very subtle border (white at 8% alpha).
  static const Color borderSubtle = Color(0x14FFFFFF);

  /// Translucent glass fill for full-tier glass (white at 4.5% alpha).
  static const Color fillGlass = Color(0x0CFFFFFF);

  /// Translucent control fill for interactive buttons (white at 7% alpha).
  static const Color fillControl = Color(0x12FFFFFF);

  /// Danger/error color (#D9908F), muted soft coral.
  static const Color danger = Color(0xFFD9908F);

  /// Success color (#A9C4AE), muted sage green.
  static const Color success = Color(0xFFA9C4AE);
}
