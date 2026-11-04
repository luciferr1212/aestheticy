import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart';

import '../../library/cover_cache.dart';

/// Extracted calm color palette from album artwork.
class CoverPalette {
  /// Dominant clamped color.
  final Color primary;

  /// Secondary complementary clamped color.
  final Color secondary;

  /// Tertiary supporting clamped color.
  final Color tertiary;

  /// Creates a [CoverPalette].
  const CoverPalette({
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  /// Default fallback palette with calm lavender, slate, and charcoal.
  static const CoverPalette fallback = CoverPalette(
    primary: Color(0xFF6B6579),
    secondary: Color(0xFF433E4F),
    tertiary: Color(0xFF282530),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoverPalette &&
          runtimeType == other.runtimeType &&
          primary == other.primary &&
          secondary == other.secondary &&
          tertiary == other.tertiary;

  @override
  int get hashCode => Object.hash(primary, secondary, tertiary);

  @override
  String toString() =>
      'CoverPalette(primary: $primary, secondary: $secondary, tertiary: $tertiary)';
}

/// Computes the shortest angular distance in degrees between two hues (0..360).
double _hueDistance(double h1, double h2) {
  final diff = (h1 - h2).abs() % 360.0;
  return diff > 180.0 ? 360.0 - diff : diff;
}

/// Clamps HSL values to ensure visual calm.
Color _clampColor(double h, double s, double l) {
  final clampedH = (h % 360.0 + 360.0) % 360.0;
  // Clamped slightly below 0.55 so 8-bit RGB integer round-trip does not exceed 0.55
  final clampedS = s.clamp(0.0, 0.54);
  final clampedL = l.clamp(0.25, 0.60);
  return HSLColor.fromAHSL(1.0, clampedH, clampedS, clampedL).toColor();
}

class _HueBin {
  int count = 0;
  double sumH = 0.0;
  double sumS = 0.0;
  double sumL = 0.0;

  void add(double h, double s, double l) {
    count++;
    sumH += h;
    sumS += s;
    sumL += l;
  }

  double get avgH => count == 0 ? 0.0 : sumH / count;
  double get avgS => count == 0 ? 0.0 : sumS / count;
  double get avgL => count == 0 ? 0.0 : sumL / count;

  Color toClampedColor() => _clampColor(avgH, avgS, avgL);
}

/// Pure Dart palette extractor sampling at most 32x32 pixels from [rgba] bytes.
CoverPalette extractPalette(Uint8List rgba, int width, int height) {
  if (width <= 0 || height <= 0 || rgba.isEmpty) {
    return CoverPalette.fallback;
  }

  final stepX = math.max(1, width ~/ 32);
  final stepY = math.max(1, height ~/ 32);

  final bins = List<_HueBin>.generate(12, (_) => _HueBin());

  for (int y = 0; y < height; y += stepY) {
    final rowOffset = y * width * 4;
    for (int x = 0; x < width; x += stepX) {
      final offset = rowOffset + x * 4;
      if (offset + 3 >= rgba.length) break;

      final a = rgba[offset + 3];
      if (a < 128) continue; // Skip mostly transparent pixels

      final r = rgba[offset];
      final g = rgba[offset + 1];
      final b = rgba[offset + 2];

      final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
      final h = hsl.hue;
      final s = hsl.saturation;
      final l = hsl.lightness;

      // Filter near-black, near-white, and near-gray
      if (l < 0.12 || l > 0.88 || s < 0.12) {
        continue;
      }

      final binIndex = ((h % 360.0) ~/ 30).clamp(0, 11);
      bins[binIndex].add(h, s, l);
    }
  }

  final validBins = bins.where((b) => b.count > 0).toList()
    ..sort((a, b) => b.count.compareTo(a.count));

  if (validBins.isEmpty) {
    return CoverPalette.fallback;
  }

  final primaryBin = validBins[0];
  final primaryColor = primaryBin.toClampedColor();

  if (validBins.length < 3) {
    // Deterministically derive secondary and tertiary using hue shifts
    final primaryHsl = HSLColor.fromColor(primaryColor);
    final secondary = _clampColor(
      primaryHsl.hue + 40.0,
      primaryHsl.saturation,
      primaryHsl.lightness * 0.85,
    );
    final tertiary = _clampColor(
      primaryHsl.hue - 40.0,
      primaryHsl.saturation,
      primaryHsl.lightness * 0.70,
    );
    return CoverPalette(
      primary: primaryColor,
      secondary: secondary,
      tertiary: tertiary,
    );
  }

  // Secondary: next most populated bin with hue distance >= 45 deg
  _HueBin? secondaryBin;
  for (int i = 1; i < validBins.length; i++) {
    if (_hueDistance(validBins[i].avgH, primaryBin.avgH) >= 45.0) {
      secondaryBin = validBins[i];
      break;
    }
  }
  secondaryBin ??= validBins[1];

  // Tertiary: next most populated bin with hue distance >= 45 deg to both
  _HueBin? tertiaryBin;
  for (int i = 1; i < validBins.length; i++) {
    final candidate = validBins[i];
    if (identical(candidate, secondaryBin)) continue;
    if (_hueDistance(candidate.avgH, primaryBin.avgH) >= 45.0 &&
        _hueDistance(candidate.avgH, secondaryBin.avgH) >= 45.0) {
      tertiaryBin = candidate;
      break;
    }
  }
  if (tertiaryBin == null) {
    for (int i = 1; i < validBins.length; i++) {
      if (!identical(validBins[i], secondaryBin)) {
        tertiaryBin = validBins[i];
        break;
      }
    }
  }
  tertiaryBin ??= validBins.length > 2 ? validBins[2] : secondaryBin;

  return CoverPalette(
    primary: primaryColor,
    secondary: secondaryBin.toClampedColor(),
    tertiary: tertiaryBin.toClampedColor(),
  );
}

// LRU cache with maximum 32 entries
final LinkedHashMap<String, CoverPalette> _paletteLruCache =
    LinkedHashMap<String, CoverPalette>();

/// Returns the cached or extracted [CoverPalette] for the given [coverKey].
Future<CoverPalette> paletteForCover(String? coverKey) async {
  if (coverKey == null || !CoverCache.hasCover(coverKey)) {
    return CoverPalette.fallback;
  }

  final cached = _paletteLruCache.remove(coverKey);
  if (cached != null) {
    _paletteLruCache[coverKey] = cached;
    return cached;
  }

  try {
    final path = CoverCache.pathFor(coverKey);
    final file = File(path);
    if (!file.existsSync()) return CoverPalette.fallback;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return CoverPalette.fallback;

    final codec = await instantiateImageCodec(
      bytes,
      targetWidth: 32,
      targetHeight: 32,
    );
    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(
      format: ImageByteFormat.rawRgba,
    );
    if (byteData == null) return CoverPalette.fallback;

    final palette = extractPalette(
      byteData.buffer.asUint8List(),
      frame.image.width,
      frame.image.height,
    );

    if (_paletteLruCache.length >= 32) {
      _paletteLruCache.remove(_paletteLruCache.keys.first);
    }
    _paletteLruCache[coverKey] = palette;

    return palette;
  } catch (_) {
    return CoverPalette.fallback;
  }
}

/// Clears the in-memory LRU cache (for unit testing).
void clearPaletteCacheForTesting() {
  _paletteLruCache.clear();
}
