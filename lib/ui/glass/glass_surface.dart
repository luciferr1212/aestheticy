import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'glass_blur_budget.dart';
import 'glass_quality.dart';
import 'glass_scope.dart';

/// A layered glass surface widget adapting to the active [GlassQuality] tier.
///
/// * [GlassQuality.full]: Real BackdropFilter blur with saturation boost and subtle highlight, strictly
///   budgeted to at most 6 concurrent surfaces. Falls back to light if unacquired.
/// * [GlassQuality.light]: High-performance simulated glass gradient with soft shadow.
/// * [GlassQuality.off]: Solid opaque surface with subtle border and zero shadow.
class GlassSurface extends StatefulWidget {
  /// The widget content inside the surface.
  final Widget child;

  /// Corner radius in dp (defaults to 22.0).
  final double borderRadius;

  /// Inner padding applied to [child].
  final EdgeInsetsGeometry? padding;

  /// Outer margin surrounding the surface.
  final EdgeInsetsGeometry? margin;

  /// Optional fixed width.
  final double? width;

  /// Optional fixed height.
  final double? height;

  /// Creates a [GlassSurface].
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = AppSpacing.r22,
    this.padding,
    this.margin,
    this.width,
    this.height,
  });

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  bool _hasBlurSlot = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateBlurSlot();
  }

  void _updateBlurSlot() {
    final quality = GlassScope.qualityOf(context);
    if (quality == GlassQuality.full) {
      if (!_hasBlurSlot) {
        _hasBlurSlot = GlassBlurBudget.instance.tryAcquire(this);
      }
    } else {
      if (_hasBlurSlot) {
        GlassBlurBudget.instance.release(this);
        _hasBlurSlot = false;
      }
    }
  }

  @override
  void dispose() {
    if (_hasBlurSlot) {
      GlassBlurBudget.instance.release(this);
      _hasBlurSlot = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quality = GlassScope.qualityOf(context);
    final isFullAndBudgeted = quality == GlassQuality.full && _hasBlurSlot;
    final effectiveTier = isFullAndBudgeted
        ? GlassQuality.full
        : (quality == GlassQuality.off ? GlassQuality.off : GlassQuality.light);

    final rrect = BorderRadius.circular(widget.borderRadius);

    final Widget content = widget.padding != null
        ? Padding(padding: widget.padding!, child: widget.child)
        : widget.child;

    final Widget surface;
    switch (effectiveTier) {
      case GlassQuality.full:
        surface = RepaintBoundary(
          child: Container(
            width: widget.width,
            height: widget.height,
            margin: widget.margin,
            decoration: BoxDecoration(
              borderRadius: rrect,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 20.0,
                  offset: Offset(0, 8.0),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: rrect,
              child: BackdropFilter(
                filter: ImageFilter.compose(
                  outer: const ColorFilter.matrix(<double>[
                    1.3935, -0.3575, -0.0360, 0.0, 0.0,
                    -0.1065, 1.1425, -0.0360, 0.0, 0.0,
                    -0.1065, -0.3575, 1.4640, 0.0, 0.0,
                    0.0, 0.0, 0.0, 1.0, 0.0,
                  ]),
                  inner: ImageFilter.blur(sigmaX: 30.0, sigmaY: 30.0),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: rrect,
                    border: Border.all(color: AppColors.border, width: 1.0),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x22FFFFFF), // Subtle top inner highlight
                        AppColors.fillGlass,
                        AppColors.fillGlass,
                      ],
                      stops: [0.0, 0.18, 1.0],
                    ),
                  ),
                  child: content,
                ),
              ),
            ),
          ),
        );
      case GlassQuality.light:
        surface = RepaintBoundary(
          child: Container(
            width: widget.width,
            height: widget.height,
            margin: widget.margin,
            decoration: BoxDecoration(
              borderRadius: rrect,
              border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.fromRGBO(52, 50, 62, 0.84),
                  Color.fromRGBO(32, 31, 40, 0.88),
                ],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x47000000),
                  blurRadius: 28.0,
                  offset: Offset(0, 10.0),
                ),
              ],
            ),
            child: content,
          ),
        );
      case GlassQuality.off:
        surface = RepaintBoundary(
          child: Container(
            width: widget.width,
            height: widget.height,
            margin: widget.margin,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: rrect,
              border: Border.all(color: AppColors.borderSubtle, width: 1.0),
            ),
            child: content,
          ),
        );
    }

    return surface;
  }
}
