import 'dart:convert';

import 'package:aestheticy/ui/theme/font_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAssetBundle extends Fake implements AssetBundle {
  final Map<String, String> strings;

  _FakeAssetBundle(this.strings);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (strings.containsKey(key)) {
      return strings[key]!;
    }
    throw Exception('Asset not found: $key');
  }

  @override
  Future<ByteData> load(String key) async {
    if (strings.containsKey(key)) {
      final bytes = utf8.encode(strings[key]!);
      return ByteData.sublistView(Uint8List.fromList(bytes));
    }
    throw Exception('Asset not found: $key');
  }
}

void main() {
  group('FontManager', () {
    test('FontOption.system does not hold a display string', () {
      expect(FontOption.system.id, equals('system'));
      expect(FontOption.system.displayName, isNull);
    });

    test('returns only system default when FontManifest.json throws error', () async {
      final bundle = _FakeAssetBundle({});
      final fonts = await FontManager.loadAvailableFonts(bundle: bundle);
      expect(fonts, equals([FontOption.system]));
    });

    test('returns only system default when FontManifest.json is not a valid list', () async {
      final bundle = _FakeAssetBundle({'FontManifest.json': '{"invalid": true}'});
      final fonts = await FontManager.loadAvailableFonts(bundle: bundle);
      expect(fonts, equals([FontOption.system]));
    });

    test('parses families correctly and filters MaterialIcons', () async {
      final manifest = jsonEncode([
        {'family': 'MaterialIcons', 'fonts': [{'asset': 'fonts/MaterialIcons-Regular.otf'}]},
        {'family': 'Inter', 'fonts': [{'asset': 'assets/fonts/Inter/Inter-Regular.ttf'}]},
        {'family': 'IBMPlexSansArabic', 'fonts': [{'asset': 'assets/fonts/IBMPlexSansArabic/IBMPlexSansArabic-Regular.ttf'}]},
        {'family': 'CustomFont', 'fonts': [{'asset': 'assets/fonts/CustomFont.ttf'}]},
      ]);
      final bundle = _FakeAssetBundle({'FontManifest.json': manifest});
      final fonts = await FontManager.loadAvailableFonts(bundle: bundle);

      expect(fonts.length, equals(4));
      expect(fonts[0], equals(FontOption.system));
      expect(fonts[1].id, equals('Inter'));
      expect(fonts[1].displayName, equals('Inter'));
      expect(fonts[2].id, equals('IBMPlexSansArabic'));
      expect(fonts[2].displayName, equals('IBM Plex Sans Arabic'));
      expect(fonts[3].id, equals('CustomFont'));
      expect(fonts[3].displayName, equals('CustomFont'));
    });
  });
}
