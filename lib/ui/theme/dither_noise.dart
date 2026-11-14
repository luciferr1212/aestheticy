import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../glass/glass_quality.dart';
import '../glass/glass_scope.dart';
import '../settings/settings_scope.dart';

/// Generates deterministic grayscale premultiplied RGBA noise bytes (~3% average opacity).
///
/// In premultiplied RGBA, color channels must never exceed alpha.
/// Alpha is capped at 10 (max ~3.9% opacity), with an average alpha under 6 of 255.
Uint8List generateDitherNoiseBytes({
  int width = 128,
  int height = 128,
  int seed = 42,
}) {
  final random = math.Random(seed);
  final totalBytes = width * height * 4;
  final bytes = Uint8List(totalBytes);
  for (var i = 0; i < totalBytes; i += 4) {
    // Valid premultiplied alpha: max alpha <= 10, average under 6
    final a = random.nextInt(11); // 0..10 (average ~5.0)
    // Premultiplied grayscale: 0 <= v <= a (white when v == a, black when v == 0)
    final v = a == 0 ? 0 : random.nextInt(a + 1);
    bytes[i] = v; // Red <= a
    bytes[i + 1] = v; // Green <= a
    bytes[i + 2] = v; // Blue <= a
    bytes[i + 3] = a; // Alpha <= 10
  }
  return bytes;
}

/// Asynchronously decodes deterministic dither noise bytes into a [ui.Image] tile.
Future<ui.Image> createDitherNoiseImage({
  int width = 128,
  int height = 128,
  int seed = 42,
}) {
  final completer = Completer<ui.Image>();
  final bytes = generateDitherNoiseBytes(
    width: width,
    height: height,
    seed: seed,
  );
  ui.decodeImageFromPixels(
    bytes,
    width,
    height,
    ui.PixelFormat.rgba8888,
    (ui.Image image) {
      completer.complete(image);
    },
  );
  return completer.future;
}

/// Singleton cache for the shared deterministic dither noise texture.
abstract final class DitherNoise {
  static ui.Image? _cachedImage;
  static Future<ui.Image>? _pendingFuture;

  /// Returns the cached [ui.Image] tile, loading it once if not already initialized.
  static Future<ui.Image> get image async {
    if (_cachedImage != null) return _cachedImage!;
    _pendingFuture ??= createDitherNoiseImage().then((img) {
      _cachedImage = img;
      return img;
    });
    return _pendingFuture!;
  }

  /// Synchronous accessor returning the cached tile if decoded, or `null`.
  static ui.Image? get currentImage => _cachedImage;

  /// Disposes the cached noise image.
  static void dispose() {
    _cachedImage?.dispose();
    _cachedImage = null;
    _pendingFuture = null;
  }

  /// Resets image cache for testing.
  @visibleForTesting
  static void resetForTest() {
    dispose();
  }
}

/// Helper function to paint the repeated dither noise tile over [rect].
void paintDitherNoise(
  Canvas canvas,
  Rect rect, {
  ui.Image? noiseImage,
}) {
  final img = noiseImage ?? DitherNoise.currentImage;
  if (img == null) return;
  final shader = ImageShader(
    img,
    TileMode.repeated,
    TileMode.repeated,
    Matrix4.identity().storage,
  );
  canvas.drawRect(
    rect,
    Paint()
      ..shader = shader
      ..blendMode = BlendMode.srcOver,
  );
}

/// CustomPainter rendering the cached dither noise texture repeatedly over its canvas.
class DitherPainter extends CustomPainter {
  /// The image tile to repeat.
  final ui.Image? image;

  /// Creates a [DitherPainter].
  const DitherPainter({this.image});

  @override
  void paint(Canvas canvas, Size size) {
    paintDitherNoise(canvas, Offset.zero & size, noiseImage: image);
  }

  @override
  bool shouldRepaint(covariant DitherPainter oldDelegate) =>
      oldDelegate.image != image;
}

/// A static overlay widget painting repeated deterministic dither noise.
///
/// It is wrapped in [IgnorePointer] and [RepaintBoundary] so it never absorbs pointer
/// events and does not repaint when underlying animated backgrounds change.
/// Skipped entirely when [GlassQuality] is [GlassQuality.off].
class DitherOverlay extends StatefulWidget {
  /// Creates a [DitherOverlay].
  const DitherOverlay({super.key});

  @override
  State<DitherOverlay> createState() => _DitherOverlayState();
}

class _DitherOverlayState extends State<DitherOverlay> {
  @override
  void initState() {
    super.initState();
    if (DitherNoise.currentImage == null) {
      DitherNoise.image.then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsStore = SettingsScope.maybeOf(context);
    final isOff = (settingsStore?.settings.glassQuality == GlassQuality.off) ||
        (GlassScope.qualityOf(context) == GlassQuality.off);
    if (isOff) {
      return const SizedBox.shrink();
    }

    final image = DitherNoise.currentImage;
    if (image == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: DitherPainter(image: image),
        ),
      ),
    );
  }
}
