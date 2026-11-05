import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/ui/settings/audio_settings_applier.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

class FailingAudioEngine extends FakeAudioEngine {
  bool failDevice = false;
  bool failExclusive = false;
  bool failReplayGain = false;
  bool failPreamp = false;

  @override
  Future<void> selectDevice(String id) async {
    if (failDevice) throw Exception('Device failed');
    return super.selectDevice(id);
  }

  @override
  Future<void> setExclusiveMode(bool enabled) async {
    if (failExclusive) throw Exception('Exclusive failed');
    return super.setExclusiveMode(enabled);
  }

  @override
  Future<void> setReplayGainMode(ReplayGainMode mode) async {
    if (failReplayGain) throw Exception('ReplayGain failed');
    return super.setReplayGainMode(mode);
  }

  @override
  Future<void> setReplayGainPreamp(double preampDb) async {
    if (failPreamp) throw Exception('Preamp failed');
    return super.setReplayGainPreamp(preampDb);
  }
}

class CapabilitiesAudioEngine extends FakeAudioEngine {
  final bool canExclusive;

  CapabilitiesAudioEngine({this.canExclusive = false});

  @override
  EngineCapabilities get capabilities => EngineCapabilities(
        exclusiveMode: canExclusive,
        gapless: false,
        equalizer: true,
        replayGain: true,
      );
}

void main() {
  group('AudioSettingsApplier Tests', () {
    late Directory tempDir;
    late FakeAudioEngine engine;
    late SettingsStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audio_applier_test_');
      engine = FakeAudioEngine();
      await engine.init();
      store = SettingsStore(directory: tempDir);
      await store.init();
    });

    tearDown(() async {
      await engine.dispose();
      store.dispose();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('applyAll applies saved values to engine', () async {
      engine.fakeDevices = [
        AudioDevice.auto,
        const AudioDevice(id: 'dev_headphones', name: 'Headphones'),
      ];

      final capEngine = CapabilitiesAudioEngine(canExclusive: true);
      await capEngine.init();
      capEngine.fakeDevices = [
        AudioDevice.auto,
        const AudioDevice(id: 'dev_headphones', name: 'Headphones'),
      ];

      store.update((s) => s.copyWith(
            outputDeviceId: 'dev_headphones',
            exclusiveMode: true,
            replayGainMode: 'track',
            replayGainPreampDb: 6.0,
          ));

      final applier = AudioSettingsApplier(
        engine: capEngine,
        settingsStore: store,
      );
      await applier.applyAll();

      expect(capEngine.currentDevice.id, equals('dev_headphones'));
      expect(capEngine.isExclusiveMode, isTrue);
      expect(capEngine.replayGainMode, equals(ReplayGainMode.track));
      expect(capEngine.replayGainPreamp, equals(6.0));

      await capEngine.dispose();
    });

    test('saved device id not present is ignored without overwriting setting', () async {
      engine.fakeDevices = [AudioDevice.auto];

      store.update((s) => s.copyWith(outputDeviceId: 'ghost_dac'));

      final applier = AudioSettingsApplier(
        engine: engine,
        settingsStore: store,
      );
      await applier.applyAll();

      // Engine remains on auto because ghost_dac is not in engine.devices
      expect(engine.currentDevice.id, equals(AudioDevice.auto.id));
      // Store setting is preserved, NOT overwritten
      expect(store.settings.outputDeviceId, equals('ghost_dac'));
    });

    test('failure does not persist to settings store', () async {
      final failingEngine = FailingAudioEngine();
      await failingEngine.init();

      final applier = AudioSettingsApplier(
        engine: failingEngine,
        settingsStore: store,
      );

      // 1. Device failure
      failingEngine.failDevice = true;
      final devErr = await applier.setDevice('new_device');
      expect(devErr, equals(AudioSettingsError.failed));
      expect(store.settings.outputDeviceId, equals('auto'));

      // 2. Exclusive unsupported
      final exclErr = await applier.setExclusive(true);
      expect(exclErr, equals(AudioSettingsError.unsupported));
      expect(store.settings.exclusiveMode, isFalse);

      // 3. ReplayGain failure
      failingEngine.failReplayGain = true;
      final rgErr = await applier.setReplayGainMode(ReplayGainMode.album);
      expect(rgErr, equals(AudioSettingsError.failed));
      expect(store.settings.replayGainMode, equals('off'));

      // 4. Preamp failure
      failingEngine.failPreamp = true;
      final preErr = await applier.setReplayGainPreamp(8.0);
      expect(preErr, equals(AudioSettingsError.failed));
      expect(store.settings.replayGainPreampDb, equals(0.0));

      await failingEngine.dispose();
    });

    test('preamp is clamped on applyAll and setReplayGainPreamp', () async {
      store.update((s) => s.copyWith(replayGainPreampDb: 25.0));

      final applier = AudioSettingsApplier(
        engine: engine,
        settingsStore: store,
      );
      await applier.applyAll();
      expect(engine.replayGainPreamp, equals(15.0));

      await applier.setReplayGainPreamp(-25.0);
      expect(engine.replayGainPreamp, equals(-15.0));
      expect(store.settings.replayGainPreampDb, equals(-15.0));
    });

    test('successful calls persist new values', () async {
      engine.fakeDevices = [
        AudioDevice.auto,
        const AudioDevice(id: 'usb_dac', name: 'USB DAC'),
      ];

      final capEngine = CapabilitiesAudioEngine(canExclusive: true);
      await capEngine.init();
      final applier = AudioSettingsApplier(
        engine: capEngine,
        settingsStore: store,
      );

      final devErr = await applier.setDevice('usb_dac');
      expect(devErr, isNull);
      expect(store.settings.outputDeviceId, equals('usb_dac'));

      final exclErr = await applier.setExclusive(true);
      expect(exclErr, isNull);
      expect(store.settings.exclusiveMode, isTrue);

      final rgErr = await applier.setReplayGainMode(ReplayGainMode.album);
      expect(rgErr, isNull);
      expect(store.settings.replayGainMode, equals('album'));

      final preErr = await applier.setReplayGainPreamp(5.0);
      expect(preErr, isNull);
      expect(store.settings.replayGainPreampDb, equals(5.0));

      await capEngine.dispose();
    });
  });
}
