import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  group('SettingsStore & AppSettings Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_settings_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('defaults on missing file', () async {
      final store = SettingsStore(directory: tempDir);
      await store.init();

      expect(store.settings.language, equals('en'));
      expect(store.settings.userName, isEmpty);
      expect(store.settings.glassQuality, equals(GlassQuality.full));
      expect(store.settings.reduceMotion, isFalse);
      expect(store.settings.sidebarCompact, isFalse);
      expect(store.settings.libraryViewMode, equals('square'));
      expect(store.settings.albumSort, equals('recentlyAdded'));
      expect(store.settings.trackSort, equals('title'));

      final file = File(p.join(tempDir.path, 'ui_settings.json'));
      expect(file.existsSync(), isFalse);
      store.dispose();
    });

    test('round trip serialization preserves values', () async {
      final store1 = SettingsStore(directory: tempDir);
      await store1.init();

      store1.update((s) => s.copyWith(
            language: 'ar',
            userName: 'mido',
            glassQuality: GlassQuality.full,
            reduceMotion: true,
            sidebarCompact: true,
            libraryViewMode: 'wide',
            albumSort: 'title',
            trackSort: 'artist',
          ));
      await store1.flush();
      store1.dispose();

      // Read back in new store instance
      final store2 = SettingsStore(directory: tempDir);
      await store2.init();

      expect(store2.settings.language, equals('ar'));
      expect(store2.settings.userName, equals('mido'));
      expect(store2.settings.glassQuality, equals(GlassQuality.full));
      expect(store2.settings.reduceMotion, isTrue);
      expect(store2.settings.sidebarCompact, isTrue);
      expect(store2.settings.libraryViewMode, equals('wide'));
      expect(store2.settings.albumSort, equals('title'));
      expect(store2.settings.trackSort, equals('artist'));
      store2.dispose();
    });

    test('corrupt JSON falls back to defaults and creates .bad file', () async {
      final file = File(p.join(tempDir.path, 'ui_settings.json'));
      await file.writeAsString('{ "language": "ar", INVALID_JSON_BODY ...');

      final store = SettingsStore(directory: tempDir);
      await store.init();

      // Returns defaults
      expect(store.settings.language, equals('en'));
      expect(store.settings.glassQuality, equals(GlassQuality.full));

      // Bad file was created and original replaced
      final badFile = File(p.join(tempDir.path, 'ui_settings.json.bad'));
      expect(badFile.existsSync(), isTrue);
      store.dispose();
    });

    test('invalid enum value falls back to default for that field only', () async {
      final file = File(p.join(tempDir.path, 'ui_settings.json'));
      await file.writeAsString(jsonEncode({
        'language': 'ar',
        'glassQuality': 'ultra_neon_4k', // invalid enum
        'libraryViewMode': 'invalid_mode', // invalid mode
        'albumSort': 'invalid_album_sort',
        'trackSort': 'invalid_track_sort',
        'userName': 'Hani',
      }));

      final store = SettingsStore(directory: tempDir);
      await store.init();

      expect(store.settings.language, equals('ar'));
      expect(store.settings.userName, equals('Hani'));
      // Invalid fields fell back to default
      expect(store.settings.glassQuality, equals(GlassQuality.full));
      expect(store.settings.libraryViewMode, equals('square'));
      expect(store.settings.albumSort, equals('recentlyAdded'));
      expect(store.settings.trackSort, equals('title'));
      store.dispose();
    });

    test('debounce collapses rapid updates and atomic write leaves no .tmp file', () async {
      final store = SettingsStore(directory: tempDir);
      await store.init();

      // Fire 5 updates rapidly
      for (int i = 0; i < 5; i++) {
        store.update((s) => s.copyWith(userName: 'user_$i'));
      }

      // Wait 100ms (less than 400ms debounce)
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final file = File(p.join(tempDir.path, 'ui_settings.json'));
      // File not written yet
      expect(file.existsSync(), isFalse);

      // Now flush
      await store.flush();
      expect(file.existsSync(), isTrue);

      final content = await file.readAsString();
      expect(content, contains('user_4'));

      // Verify no .tmp file remains
      final tmpFile = File(p.join(tempDir.path, 'ui_settings.json.tmp'));
      expect(tmpFile.existsSync(), isFalse);

      store.dispose();
    });

    test('bindGlassController synchronizes quality and reduceMotion', () async {
      final store = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(
          glassQuality: GlassQuality.off,
          reduceMotion: true,
        ),
      );
      final controller = GlassController();

      store.bindGlassController(controller);
      expect(controller.quality, equals(GlassQuality.off));
      expect(controller.reduceMotion, isTrue);

      store.update((s) => s.copyWith(
            glassQuality: GlassQuality.full,
            reduceMotion: false,
          ));
      expect(controller.quality, equals(GlassQuality.full));
      expect(controller.reduceMotion, isFalse);

      store.dispose();
    });
  });
}
