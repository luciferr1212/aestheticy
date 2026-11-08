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
      expect(store.settings.fullScreenGlassShapes, isTrue);
      expect(store.settings.arabicNumerals, isFalse);
      expect(store.settings.textScale, equals('normal'));
      expect(store.settings.uiFont, equals('system'));
      expect(store.settings.artistNameMode, equals('followLanguage'));
      expect(store.settings.outputDeviceId, equals('auto'));
      expect(store.settings.exclusiveMode, isFalse);
      expect(store.settings.replayGainMode, equals('off'));
      expect(store.settings.replayGainPreampDb, equals(0.0));
      expect(store.settings.mediaControls, isTrue);
      expect(store.settings.preventSleepWhilePlaying, isTrue);
      expect(store.settings.closeBehavior, equals('quit'));
      expect(store.settings.lyricsSource, equals('localThenOnline'));
      expect(store.settings.lyricsHighlight, equals('word'));
      expect(store.settings.showLyricsInFullScreen, isTrue);
      expect(store.settings.seekStepSeconds, equals(2));

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
            fullScreenGlassShapes: false,
            arabicNumerals: true,
            textScale: 'large',
            uiFont: 'Cairo',
            artistNameMode: 'alwaysArabic',
            outputDeviceId: 'device-123',
            exclusiveMode: true,
            replayGainMode: 'track',
            replayGainPreampDb: 4.5,
            mediaControls: false,
            preventSleepWhilePlaying: false,
            closeBehavior: 'tray',
            lyricsSource: 'onlineThenLocal',
            lyricsHighlight: 'line',
            showLyricsInFullScreen: false,
            seekStepSeconds: 5,
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
      expect(store2.settings.fullScreenGlassShapes, isFalse);
      expect(store2.settings.arabicNumerals, isTrue);
      expect(store2.settings.textScale, equals('large'));
      expect(store2.settings.uiFont, equals('Cairo'));
      expect(store2.settings.artistNameMode, equals('alwaysArabic'));
      expect(store2.settings.outputDeviceId, equals('device-123'));
      expect(store2.settings.exclusiveMode, isTrue);
      expect(store2.settings.replayGainMode, equals('track'));
      expect(store2.settings.replayGainPreampDb, equals(4.5));
      expect(store2.settings.mediaControls, isFalse);
      expect(store2.settings.preventSleepWhilePlaying, isFalse);
      expect(store2.settings.closeBehavior, equals('tray'));
      expect(store2.settings.lyricsSource, equals('onlineThenLocal'));
      expect(store2.settings.lyricsHighlight, equals('line'));
      expect(store2.settings.showLyricsInFullScreen, isFalse);
      expect(store2.settings.seekStepSeconds, equals(5));
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
        'textScale': 'huge',
        'artistNameMode': 'invalid_artist_mode',
        'replayGainMode': 'super_boost',
        'replayGainPreampDb': 99.9,
        'userName': 'Hani',
        'mediaControls': 'invalid_bool',
        'preventSleepWhilePlaying': 123,
        'closeBehavior': 'hibernate',
        'lyricsSource': 'invalid_source',
        'lyricsHighlight': 'paragraph',
        'showLyricsInFullScreen': 'not_a_bool',
        'seekStepSeconds': 42,
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
      expect(store.settings.fullScreenGlassShapes, isTrue);
      expect(store.settings.arabicNumerals, isFalse);
      expect(store.settings.textScale, equals('normal'));
      expect(store.settings.uiFont, equals('system'));
      expect(store.settings.artistNameMode, equals('followLanguage'));
      expect(store.settings.outputDeviceId, equals('auto'));
      expect(store.settings.exclusiveMode, isFalse);
      expect(store.settings.replayGainMode, equals('off'));
      expect(store.settings.replayGainPreampDb, equals(15.0)); // clamped to 15.0
      expect(store.settings.mediaControls, isTrue);
      expect(store.settings.preventSleepWhilePlaying, isTrue);
      expect(store.settings.closeBehavior, equals('quit'));
      expect(store.settings.lyricsSource, equals('localThenOnline'));
      expect(store.settings.lyricsHighlight, equals('word'));
      expect(store.settings.showLyricsInFullScreen, isTrue);
      expect(store.settings.seekStepSeconds, equals(2));
      store.dispose();
    });

    test('replayGainPreampDb clamps values to [-15.0, 15.0]', () {
      const lower = AppSettings(replayGainPreampDb: -30.0);
      expect(lower.replayGainPreampDb, equals(-15.0));

      const upper = AppSettings(replayGainPreampDb: 30.0);
      expect(upper.replayGainPreampDb, equals(15.0));

      final copiedLower = const AppSettings().copyWith(replayGainPreampDb: -20.0);
      expect(copiedLower.replayGainPreampDb, equals(-15.0));

      final copiedUpper = const AppSettings().copyWith(replayGainPreampDb: 25.0);
      expect(copiedUpper.replayGainPreampDb, equals(15.0));
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
