import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/ui/audio_panels/eq_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('eq_store_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('EqStore Unit & Persistence Tests', () {
    test('defaults are initialized properly', () {
      final store = EqStore(directoryProvider: () async => tempDir);
      final s = store.settings;

      expect(s.enabled, isFalse);
      expect(s.gains.length, 10);
      expect(s.gains, everyElement(0.0));
      expect(s.preampDb, 0.0);
      expect(s.presetId, 'flat');
      expect(s.customPresets, isEmpty);
    });

    test('gains and preamp are clamped to [-12.0, 12.0]', () {
      final jsonMap = <String, Object?>{
        'enabled': true,
        'gains': [20.0, -25.0, 0.0, 15.0, -13.0, 5.0, 0.0, 0.0, 0.0, 0.0],
        'preampDb': -30.0,
        'presetId': 'custom',
        'customPresets': <Map<String, Object?>>[],
      };

      final settings = EqSettings.fromJson(jsonMap);
      expect(settings.gains[0], 12.0);
      expect(settings.gains[1], -12.0);
      expect(settings.gains[3], 12.0);
      expect(settings.gains[4], -12.0);
      expect(settings.preampDb, -12.0);
    });

    test('tolerant fromJson handles missing or malformed keys gracefully', () {
      final settings = EqSettings.fromJson(<String, Object?>{
        'enabled': 'not_a_bool',
        'gains': 'not_a_list',
        'preampDb': 'not_a_num',
        'presetId': null,
      });

      expect(settings.enabled, isFalse);
      expect(settings.gains.length, 10);
      expect(settings.gains, everyElement(0.0));
      expect(settings.preampDb, 0.0);
      expect(settings.presetId, 'flat');
      expect(settings.customPresets, isEmpty);
    });

    test('custom preset parsing trims up to 24 chars and clamps gains', () {
      final preset = CustomPreset.fromJson({
        'name': '  A very long custom preset name that exceeds 24 chars  ',
        'gains': [15.0, -18.0],
        'preampDb': -20.0,
      });

      expect(preset.name.length <= 24, isTrue);
      expect(preset.name, 'A very long custom prese');
      expect(preset.gains[0], 12.0);
      expect(preset.gains[1], -12.0);
      expect(preset.preampDb, -12.0);
    });

    test('persists to eq_settings.json and reloads on new store', () async {
      final store1 = EqStore(directoryProvider: () async => tempDir);
      await store1.init();

      store1.update((s) => s.copyWith(
            enabled: true,
            presetId: 'warm',
            preampDb: 2.0,
            gains: [4.0, 0, 0, 0, 0, 0, 0, 0, 0, -3.0],
            customPresets: [
              const CustomPreset(
                name: 'Vocal Plus',
                gains: [0, 0, 0, 0, 2.0, 2.0, 0, 0, 0, 0],
                preampDb: -1.0,
              ),
            ],
          ));

      // Wait for debounce and flush
      await store1.flush();

      final file = File('${tempDir.path}/eq_settings.json');
      expect(file.existsSync(), isTrue);

      final store2 = EqStore(directoryProvider: () async => tempDir);
      await store2.init();

      expect(store2.settings.enabled, isTrue);
      expect(store2.settings.gains[0], 4.0);
      expect(store2.settings.gains[9], -3.0);
      expect(store2.settings.preampDb, 2.0);
      expect(store2.settings.presetId, 'warm');
      expect(store2.settings.customPresets.length, 1);
      expect(store2.settings.customPresets.first.name, 'Vocal Plus');
    });

    test('corrupt JSON falls back to defaults and moves file to .bad', () async {
      final targetFile = File('${tempDir.path}/eq_settings.json');
      await targetFile.writeAsString('{ invalid json syntax !!!');

      final store = EqStore(directoryProvider: () async => tempDir);
      await store.init();

      expect(store.settings.enabled, isFalse);
      expect(store.settings.gains, everyElement(0.0));

      final badFile = File('${tempDir.path}/eq_settings.json.bad');
      expect(badFile.existsSync(), isTrue);
      expect(badFile.readAsStringSync(), '{ invalid json syntax !!!');
    });

    test('atomic write leaves no .tmp file behind', () async {
      final store = EqStore(directoryProvider: () async => tempDir);
      await store.init();

      store.update((s) => s.copyWith(
            enabled: true,
            gains: [0, 0, 6.0, 0, 0, 0, 0, 0, 0, 0],
          ));
      await store.flush();

      final tmpFile = File('${tempDir.path}/eq_settings.json.tmp');
      expect(tmpFile.existsSync(), isFalse);

      final mainFile = File('${tempDir.path}/eq_settings.json');
      expect(mainFile.existsSync(), isTrue);
      final json = jsonDecode(mainFile.readAsStringSync()) as Map<String, dynamic>;
      expect(json['enabled'], isTrue);
    });
  });
}
