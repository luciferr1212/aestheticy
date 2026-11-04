import 'dart:convert';

import 'package:flutter/services.dart';

/// Descriptor for a selectable UI font option.
class FontOption {
  /// Font family identifier stored in settings ('system' or bundled family name).
  final String id;

  /// User-visible display name.
  final String displayName;

  /// Creates an immutable [FontOption].
  const FontOption({required this.id, required this.displayName});

  /// Default system font stack option ('Segoe UI Variable').
  static const system =
      FontOption(id: 'system', displayName: 'System default');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FontOption &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          displayName == other.displayName;

  @override
  int get hashCode => Object.hash(id, displayName);

  @override
  String toString() => 'FontOption($id, "$displayName")';
}

/// Font loader discovering registered bundled families via `FontManifest.json`.
abstract final class FontManager {
  static const Map<String, String> _knownFamilyDisplayNames = {
    'Inter': 'Inter',
    'IBMPlexSansArabic': 'IBM Plex Sans Arabic',
    'NotoSansArabic': 'Noto Sans Arabic',
    'Cairo': 'Cairo',
  };

  /// Fixed specimen string showing mixed English, Arabic, and digits.
  static const String previewSample = 'Golden Hour · فيروز · 1:24';

  /// Reads registered font families from `FontManifest.json` via [bundle].
  ///
  /// Always includes [FontOption.system]. Never includes families not in the manifest.
  /// Falls back to system option on missing or unparseable manifest.
  static Future<List<FontOption>> loadAvailableFonts({
    AssetBundle? bundle,
  }) async {
    final effectiveBundle = bundle ?? rootBundle;
    final options = <FontOption>[FontOption.system];

    try {
      final manifestJson =
          await effectiveBundle.loadString('FontManifest.json');
      final decoded = jsonDecode(manifestJson);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map && item['family'] is String) {
            final family = item['family'] as String;
            if (family == 'MaterialIcons' || family.isEmpty) continue;
            final displayName = _knownFamilyDisplayNames[family] ?? family;
            options.add(FontOption(id: family, displayName: displayName));
          }
        }
      }
    } catch (_) {
      // Missing or corrupt manifest falls back to system only
    }

    return options;
  }
}
