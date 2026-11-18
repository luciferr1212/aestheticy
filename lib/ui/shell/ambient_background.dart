import 'package:flutter/widgets.dart';

import '../glass/glass_quality.dart';
import '../glass/glass_scope.dart';
import '../settings/settings_store.dart';
import '../theme/app_colors.dart';
import '../theme/dither_noise.dart';

/// Calm, static ambient background rendered with radial gradients on a dark base.
///
/// Adapts live to active [GlassQuality] tier:
/// * [GlassQuality.full]: static radial gradient + dither noise overlay.
/// * [GlassQuality.light]: cheap static radial gradient + dither noise overlay.
/// * [GlassQuality.off]: flat opaque surface, no gradients, no dither, no blur.
class AmbientBackground extends StatelessWidget {
  /// Optional settings store for direct quality inspection in tests or shell.
  final SettingsStore? settingsStore;

  /// Whether to include the dither noise overlay (defaults to true).
  final bool enableDither;

  /// Creates an [AmbientBackground].
  const AmbientBackground({
    super.key,
    this.settingsStore,
    this.enableDither = true,
  });

  @override
  Widget build(BuildContext context) {
    final quality = GlassScope.qualityOf(context);
    final effectiveQuality = settingsStore?.settings.glassQuality ?? quality;

    if (effectiveQuality == GlassQuality.off) {
      return const ColoredBox(color: AppColors.base);
    }

    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(
          child: CustomPaint(
            painter: _AmbientBackgroundPainter(),
            size: Size.infinite,
          ),
        ),
        if (enableDither) const DitherOverlay(),
      ],
    );
  }
}

class _AmbientBackgroundPainter extends CustomPainter {
  const _AmbientBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Solid base color #0F1115
    final basePaint = Paint()..color = AppColors.base;
    canvas.drawRect(Offset.zero & size, basePaint);

    // Muted purple #6B5B7B at 45% alpha (0x736B5B7B) at top-start
    final purplePaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.8, -0.8),
        radius: 1.2,
        colors: [
          Color(0x736B5B7B),
          Color(0x006B5B7B),
        ],
        stops: [0.0, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, purplePaint);

    // Muted teal #3F6C7A at 30% alpha (0x4D3F6C7A) at bottom-end
    final tealPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0.8, 0.8),
        radius: 1.2,
        colors: [
          Color(0x4D3F6C7A),
          Color(0x003F6C7A),
        ],
        stops: [0.0, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, tealPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
