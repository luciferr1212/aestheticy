import 'package:flutter/painting.dart';

/// Spacing and border-radius tokens for Aestheticy.
abstract final class AppSpacing {
  /// 4.0 dp spacing increment.
  static const double s4 = 4.0;

  /// 8.0 dp spacing increment.
  static const double s8 = 8.0;

  /// 12.0 dp spacing increment.
  static const double s12 = 12.0;

  /// 16.0 dp spacing increment.
  static const double s16 = 16.0;

  /// 24.0 dp spacing increment.
  static const double s24 = 24.0;

  /// 32.0 dp spacing increment.
  static const double s32 = 32.0;

  /// 10.0 dp corner radius.
  static const double r10 = 10.0;

  /// 12.0 dp corner radius.
  static const double r12 = 12.0;

  /// 16.0 dp corner radius.
  static const double r16 = 16.0;

  /// 22.0 dp standard glass surface corner radius.
  static const double r22 = 22.0;

  /// 26.0 dp large corner radius.
  static const double r26 = 26.0;

  /// 999.0 dp pill corner radius.
  static const double pill = 999.0;

  /// [BorderRadius] with 10.0 dp circular corners.
  static const BorderRadius br10 = BorderRadius.all(Radius.circular(r10));

  /// [BorderRadius] with 12.0 dp circular corners.
  static const BorderRadius br12 = BorderRadius.all(Radius.circular(r12));

  /// [BorderRadius] with 16.0 dp circular corners.
  static const BorderRadius br16 = BorderRadius.all(Radius.circular(r16));

  /// [BorderRadius] with 22.0 dp circular corners.
  static const BorderRadius br22 = BorderRadius.all(Radius.circular(r22));

  /// [BorderRadius] with 26.0 dp circular corners.
  static const BorderRadius br26 = BorderRadius.all(Radius.circular(r26));

  /// [BorderRadius] with 999.0 dp circular pill corners.
  static const BorderRadius brPill = BorderRadius.all(Radius.circular(pill));
}
