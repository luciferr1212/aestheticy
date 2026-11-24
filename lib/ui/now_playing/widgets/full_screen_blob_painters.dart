import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../cover_palette.dart';

/// Creates the animated drifting color blob painter for full glass quality.
CustomPainter createFullScreenBlobPainter({
  required CoverPalette palette,
  required ValueListenable<double> phaseListenable,
}) =>
    _BlobPainter(palette: palette, phaseListenable: phaseListenable);

/// Creates the static gradient blob painter for light glass quality.
CustomPainter createFullScreenStaticBlobPainter({
  required CoverPalette palette,
}) =>
    _StaticBlobPainter(palette: palette);

/// Single CustomPainter rendering 3 large drifting color blobs.
class _BlobPainter extends CustomPainter {
  final CoverPalette palette;
  final ValueListenable<double> phaseListenable;

  _BlobPainter({
    required this.palette,
    required this.phaseListenable,
  }) : super(repaint: phaseListenable);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final phase = phaseListenable.value;

    // Blob 1: primary color
    final p1 = Offset(
      w * (0.32 + 0.10 * math.sin(phase * 0.3)),
      h * (0.38 + 0.10 * math.cos(phase * 0.2)),
    );
    final r1 = w * 0.35;
    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.primary.withValues(alpha: 0.20),
          palette.primary.withValues(alpha: 0.14),
          palette.primary.withValues(alpha: 0.07),
          palette.primary.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: p1, radius: r1));
    canvas.drawCircle(p1, r1, paint1);

    // Blob 2: secondary color
    final p2 = Offset(
      w * (0.68 + 0.12 * math.cos(phase * 0.25)),
      h * (0.55 + 0.08 * math.sin(phase * 0.35)),
    );
    final r2 = w * 0.38;
    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.secondary.withValues(alpha: 0.20),
          palette.secondary.withValues(alpha: 0.14),
          palette.secondary.withValues(alpha: 0.07),
          palette.secondary.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: p2, radius: r2));
    canvas.drawCircle(p2, r2, paint2);

    // Blob 3: tertiary color
    final p3 = Offset(
      w * (0.48 + 0.10 * math.sin(phase * 0.18)),
      h * (0.75 + 0.08 * math.cos(phase * 0.22)),
    );
    final r3 = w * 0.34;
    final paint3 = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.tertiary.withValues(alpha: 0.20),
          palette.tertiary.withValues(alpha: 0.14),
          palette.tertiary.withValues(alpha: 0.07),
          palette.tertiary.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: p3, radius: r3));
    canvas.drawCircle(p3, r3, paint3);
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) {
    return oldDelegate.palette != palette ||
        oldDelegate.phaseListenable != phaseListenable;
  }
}

/// Static cheap gradient blob painter for light glass quality with zero per-frame animation.
class _StaticBlobPainter extends CustomPainter {
  final CoverPalette palette;

  const _StaticBlobPainter({required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.primary.withValues(alpha: 0.20),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(center: Offset(w * 0.35, h * 0.4), radius: w * 0.35),
      );
    canvas.drawCircle(Offset(w * 0.35, h * 0.4), w * 0.35, paint1);

    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.secondary.withValues(alpha: 0.20),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(center: Offset(w * 0.65, h * 0.6), radius: w * 0.38),
      );
    canvas.drawCircle(Offset(w * 0.65, h * 0.6), w * 0.38, paint2);
  }

  @override
  bool shouldRepaint(_StaticBlobPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
