import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/library/cover_cache.dart';
import 'package:aestheticy/ui/now_playing/cover_palette.dart';

void main() {
  group('CoverPalette Tests', () {
    late Directory tempCoversDir;

    setUp(() async {
      clearPaletteCacheForTesting();
      tempCoversDir = await Directory.systemTemp.createTemp('palette_test_covers_');
      CoverCache.setCustomDirectory(tempCoversDir.path);
    });

    tearDown(() async {
      CoverCache.setCustomDirectory(null);
      if (tempCoversDir.existsSync()) {
        try {
          await tempCoversDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('extractPalette clamps pure saturated red to sat <= 0.55 and light 0.25..0.60', () {
      // 10x10 pure red (255, 0, 0, 255)
      final buffer = Uint8List(10 * 10 * 4);
      for (int i = 0; i < buffer.length; i += 4) {
        buffer[i] = 255; // R
        buffer[i + 1] = 0; // G
        buffer[i + 2] = 0; // B
        buffer[i + 3] = 255; // A
      }

      final palette = extractPalette(buffer, 10, 10);
      final primaryHsl = HSLColor.fromColor(palette.primary);
      final secondaryHsl = HSLColor.fromColor(palette.secondary);
      final tertiaryHsl = HSLColor.fromColor(palette.tertiary);

      expect(primaryHsl.saturation, lessThanOrEqualTo(0.55 + 0.001));
      expect(primaryHsl.lightness, greaterThanOrEqualTo(0.25 - 0.001));
      expect(primaryHsl.lightness, lessThanOrEqualTo(0.60 + 0.001));

      expect(secondaryHsl.saturation, lessThanOrEqualTo(0.55 + 0.001));
      expect(secondaryHsl.lightness, greaterThanOrEqualTo(0.25 - 0.001));
      expect(secondaryHsl.lightness, lessThanOrEqualTo(0.60 + 0.001));

      expect(tertiaryHsl.saturation, lessThanOrEqualTo(0.55 + 0.001));
      expect(tertiaryHsl.lightness, greaterThanOrEqualTo(0.25 - 0.001));
      expect(tertiaryHsl.lightness, lessThanOrEqualTo(0.60 + 0.001));
    });

    test('extractPalette filters near-black, near-white, and near-gray pixels', () {
      // Buffer containing only near-black (L < 0.12), near-white (L > 0.88), and gray (S < 0.12)
      final buffer = Uint8List(4 * 4 * 4);
      for (int i = 0; i < buffer.length; i += 4) {
        if (i < 16) {
          // Black (0, 0, 0) -> L = 0
          buffer[i] = 10;
          buffer[i + 1] = 10;
          buffer[i + 2] = 10;
          buffer[i + 3] = 255;
        } else if (i < 32) {
          // White (250, 250, 250) -> L > 0.88
          buffer[i] = 250;
          buffer[i + 1] = 250;
          buffer[i + 2] = 250;
          buffer[i + 3] = 255;
        } else {
          // Gray (128, 128, 128) -> S = 0
          buffer[i] = 128;
          buffer[i + 1] = 128;
          buffer[i + 2] = 128;
          buffer[i + 3] = 255;
        }
      }

      final palette = extractPalette(buffer, 4, 4);
      // All dropped, should return fallback
      expect(palette, equals(CoverPalette.fallback));
    });

    test('extractPalette is deterministic with multi-color pixels', () {
      // 32x32 buffer: top half red, bottom half blue
      final buffer = Uint8List(32 * 32 * 4);
      for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
          final idx = (y * 32 + x) * 4;
          if (y < 16) {
            // Calm red-ish
            buffer[idx] = 180;
            buffer[idx + 1] = 60;
            buffer[idx + 2] = 60;
            buffer[idx + 3] = 255;
          } else {
            // Calm blue-ish
            buffer[idx] = 60;
            buffer[idx + 1] = 60;
            buffer[idx + 2] = 180;
            buffer[idx + 3] = 255;
          }
        }
      }

      final palette1 = extractPalette(buffer, 32, 32);
      final palette2 = extractPalette(buffer, 32, 32);

      expect(palette1, equals(palette2));
      expect(palette1.primary, isNot(equals(CoverPalette.fallback.primary)));
    });

    test('paletteForCover returns fallback when coverKey is null or file missing', () async {
      expect(await paletteForCover(null), equals(CoverPalette.fallback));
      expect(await paletteForCover('nonexistent_key_12345'), equals(CoverPalette.fallback));
    });

    test('paletteForCover caches results in LRU up to 32 entries', () async {
      final tempDir = await Directory.systemTemp.createTemp('aestheticy_palette_test_');
      CoverCache.setCustomDirectory(tempDir.path);

      try {
        // 1x1 valid PNG bytes (transparent 1x1 image or small test png)
        final pngBytes = Uint8List.fromList(<int>[
          137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1,
          0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65,
          84, 120, 156, 99, 252, 207, 192, 80, 31, 0, 5, 133, 2, 122, 106, 172, 63,
          234, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130
        ]);

        // Create 35 dummy files
        for (int i = 0; i < 35; i++) {
          final file = File(p.join(tempDir.path, 'key_$i.jpg'));
          await file.writeAsBytes(pngBytes);
        }

        // Load all 35 into palette cache
        for (int i = 0; i < 35; i++) {
          await paletteForCover('key_$i');
        }

        // Delete the first created file 'key_0.jpg' on disk
        final file0 = File(p.join(tempDir.path, 'key_0.jpg'));
        await file0.delete();

        // If 'key_0' was evicted from the 32-entry LRU cache, reading it again will see missing file and return fallback
        final result0 = await paletteForCover('key_0');
        expect(result0, equals(CoverPalette.fallback));
      } finally {
        CoverCache.setCustomDirectory(null);
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
