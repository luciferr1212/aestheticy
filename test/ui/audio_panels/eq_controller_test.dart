import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/ui/audio_panels/eq_controller.dart';
import 'package:aestheticy/ui/audio_panels/eq_store.dart';
import 'package:aestheticy/ui/settings/audio_settings_applier.dart';

class _NoEqEngine extends FakeAudioEngine {
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        exclusiveMode: false,
        gapless: false,
        equalizer: false,
        replayGain: false,
      );
}

class _FailingEqEngine extends FakeAudioEngine {
  bool failNext = true;

  @override
  Future<void> setEqGains(List<double> gains) async {
    if (failNext) {
      throw StateError('Engine setEqGains failure simulation');
    }
    await super.setEqGains(gains);
  }

  @override
  Future<void> setPreamp(double preampDb) async {
    if (failNext) {
      throw StateError('Engine setPreamp failure simulation');
    }
    await super.setPreamp(preampDb);
  }

  @override
  Future<void> setEqEnabled(bool enabled) async {
    if (failNext) {
      throw StateError('Engine setEqEnabled failure simulation');
    }
    await super.setEqEnabled(enabled);
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('eq_controller_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('EqController Unit Tests', () {
    test('applyAll pushes store values to engine on startup', () async {
      final engine = FakeAudioEngine();
      final store = EqStore(directoryProvider: () async => tempDir);
      await store.init();

      store.update((s) => s.copyWith(
            enabled: true,
            gains: [3.0, 0, 0, 0, 0, 0, 0, 0, 0, -2.0],
            preampDb: 1.5,
          ));

      final controller = EqController(engine: engine, store: store);
      await controller.applyAll();

      expect(engine.isEqEnabled, isTrue);
      expect(engine.eqGains[0], 3.0);
      expect(engine.eqGains[9], -2.0);
      expect(engine.preamp, 1.5);
    });

    test('capability false returns unsupported and does not call engine', () async {
      final engine = _NoEqEngine();
      final store = EqStore(directoryProvider: () async => tempDir);
      await store.init();

      final controller = EqController(engine: engine, store: store);
      await controller.applyAll();

      expect(engine.isEqEnabled, isFalse);

      final err1 = await controller.setEnabled(true);
      expect(err1, AudioSettingsError.unsupported);

      final err2 = await controller.setBand(0, 5.0);
      expect(err2, AudioSettingsError.unsupported);

      final err3 = await controller.setPreamp(2.0);
      expect(err3, AudioSettingsError.unsupported);

      final err4 = await controller.applyPreset('warm');
      expect(err4, AudioSettingsError.unsupported);

      final err5 = await controller.reset();
      expect(err5, AudioSettingsError.unsupported);
    });

    test('band dragging throttles to engine and ensures last value is applied', () async {
      final engine = FakeAudioEngine();
      final store = EqStore(directoryProvider: () async => tempDir);
      await store.init();

      final controller = EqController(engine: engine, store: store);
      await controller.applyAll();

      // Rapid slider movements
      await controller.setBand(3, 1.0);
      await controller.setBand(3, 2.0);
      await controller.setBand(3, 4.0);
      await controller.setBand(3, 6.0);

      expect(controller.gains[3], 6.0);

      // Wait for trailing 50ms throttle
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(engine.eqGains[3], 6.0);
    });

    test('presets apply predefined gains and preamp', () async {
      final engine = FakeAudioEngine();
      final store = EqStore(directoryProvider: () async => tempDir);
      await store.init();

      final controller = EqController(engine: engine, store: store);
      await controller.applyAll();

      final err = await controller.applyPreset('warm');
      expect(err, isNull);
      expect(controller.presetId, 'warm');
      expect(controller.preampDb, -3.0);
      expect(controller.gains[0], 3.0);
      expect(controller.gains[9], -2.0);

      // Wait for trailing throttle
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(engine.eqGains[0], 3.0);
      expect(engine.preamp, -3.0);
    });

    test('modifying band or preamp after preset switches presetId to custom', () async {
      final engine = FakeAudioEngine();
      final store = EqStore(directoryProvider: () async => tempDir);
      await store.init();

      final controller = EqController(engine: engine, store: store);
      await controller.applyAll();
      await controller.applyPreset('flat');
      expect(controller.presetId, 'flat');

      await controller.setBand(2, 3.0);
      expect(controller.presetId, 'custom');

      await controller.applyPreset('bright');
      expect(controller.presetId, 'bright');

      await controller.setPreamp(1.0);
      expect(controller.presetId, 'custom');
    });

    test('reset clears gains and preamp to 0, keeping enabled', () async {
      final engine = FakeAudioEngine();
      final store = EqStore(directoryProvider: () async => tempDir);
      await store.init();

      final controller = EqController(engine: engine, store: store);
      await controller.setEnabled(true);
      await controller.applyPreset('bassBoost');

      final err = await controller.reset();
      expect(err, isNull);
      expect(controller.enabled, isTrue);
      expect(controller.gains, everyElement(0.0));
      expect(controller.preampDb, 0.0);
      expect(controller.presetId, 'flat');
    });

    test('custom preset validation and management works', () async {
      final engine = FakeAudioEngine();
      final store = EqStore(directoryProvider: () async => tempDir);
      await store.init();

      final controller = EqController(engine: engine, store: store);
      await controller.setBand(0, 4.0);
      await controller.setPreamp(-1.0);

      // Name validation
      expect(controller.saveCustomPreset('   '), 'audioPanels.presetNameEmpty');
      expect(controller.saveCustomPreset('A' * 25), 'audioPanels.presetNameTooLong');
      expect(controller.saveCustomPreset('flat'), 'audioPanels.presetNameExists');
      expect(controller.saveCustomPreset('custom'), 'audioPanels.presetNameExists');

      final err = controller.saveCustomPreset('My Rock');
      expect(err, isNull);
      expect(controller.customPresets.length, 1);
      expect(controller.presetId, 'My Rock');

      controller.deleteCustomPreset('My Rock');
      expect(controller.customPresets, isEmpty);
      expect(controller.presetId, 'custom');
    });

    test('engine failure reverts in-memory gains and preamp, nothing persisted', () async {
      final engine = _FailingEqEngine();
      final store = EqStore(directoryProvider: () async => tempDir);
      await store.init();

      final controller = EqController(engine: engine, store: store);

      // Initially zero
      expect(controller.gains[0], 0.0);
      expect(controller.preampDb, 0.0);

      // Apply preset fails
      engine.failNext = true;
      final errPreset = await controller.applyPreset('warm');
      expect(errPreset, AudioSettingsError.failed);
      expect(controller.gains[0], 0.0); // Reverted
      expect(controller.presetId, 'flat');

      // Set enabled fails
      engine.failNext = true;
      final errEnabled = await controller.setEnabled(true);
      expect(errEnabled, AudioSettingsError.failed);
      expect(controller.enabled, isFalse); // Reverted

      // Throttled band drag fails in engine dispatch -> reverts to last good
      engine.failNext = true;
      await controller.setBand(0, 5.0);
      expect(controller.gains[0], 5.0); // Immediately responsive in memory
      await Future<void>.delayed(const Duration(milliseconds: 100)); // Dispatches and fails
      expect(controller.gains[0], 0.0); // Reverted to last good values
    });
  });
}
