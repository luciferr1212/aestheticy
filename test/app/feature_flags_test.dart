import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/app/feature_flags.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  group('FeatureFlags (S3)', () {
    test('const defaults are all false', () {
      const flags = FeatureFlags.defaults;
      expect(flags.canvas, isFalse);
      expect(flags.jam, isFalse);
      expect(flags.tagEditor, isFalse);
      expect(flags.scrobbling, isFalse);
      expect(flags.videoConcerts, isFalse);
    });

    test('fromMap parses boolean overrides and ignores malformed entries', () {
      final flags = FeatureFlags.fromMap({
        'canvas': true,
        'jam': 'yes',
        'tagEditor': true,
        'scrobbling': 1,
        'videoConcerts': false,
      });
      expect(flags.canvas, isTrue);
      expect(flags.jam, isFalse);
      expect(flags.tagEditor, isTrue);
      expect(flags.scrobbling, isFalse);
      expect(flags.videoConcerts, isFalse);
    });

    test('overrides round-trip through hidden featureFlags map in SettingsStore', () async {
      final tempDir = await Directory.systemTemp.createTemp('aestheticy_ff_');
      try {
        final file = File(p.join(tempDir.path, 'ui_settings.json'));
        await file.writeAsString(jsonEncode({
          'schemaVersion': 1,
          'featureFlags': {
            'canvas': true,
            'scrobbling': true,
            'ignoredNonBool': 'nope',
          },
        }));

        final store = SettingsStore(directory: tempDir);
        await store.init();
        final resolved = FeatureFlags.fromSettings(store.settings);
        expect(resolved.canvas, isTrue);
        expect(resolved.scrobbling, isTrue);
        expect(resolved.jam, isFalse);
        expect(resolved.tagEditor, isFalse);
        expect(resolved.videoConcerts, isFalse);

        // Saving another setting preserves hidden featureFlags map
        store.update((s) => s.copyWith(volume: 0.75));
        await store.flush();
        store.dispose();

        final store2 = SettingsStore(directory: tempDir);
        await store2.init();
        final resolved2 = FeatureFlags.fromSettings(store2.settings);
        expect(resolved2.canvas, isTrue);
        expect(resolved2.scrobbling, isTrue);
        expect(store2.settings.volume, closeTo(0.75, 1e-6));
        store2.dispose();

        // Default AppSettings has empty featureFlags
        expect(FeatureFlags.fromSettings(const AppSettings()), equals(FeatureFlags.defaults));
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });
  });
}
