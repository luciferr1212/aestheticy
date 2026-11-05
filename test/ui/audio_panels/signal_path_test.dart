import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/ui/audio_panels/signal_path_model.dart';

void main() {
  group('SignalPathModel Pure Logic Tests', () {
    const defaultCapabilities = EngineCapabilities(
      exclusiveMode: true,
      gapless: true,
      equalizer: true,
      replayGain: true,
    );

    test('idle state when nothing is playing', () {
      final model = buildSignalPathModel(
        streamInfo: null,
        eqEnabled: false,
        eqPresetId: 'flat',
        eqPreampDb: 0.0,
        replayGainMode: ReplayGainMode.off,
        replayGainPreamp: 0.0,
        currentDevice: const AudioDevice(id: 'auto', name: 'Default Audio Device'),
        isExclusiveMode: false,
        capabilities: defaultCapabilities,
      );

      expect(model.isPlaying, isFalse);
      expect(model.sourceCodec, '—');
      expect(model.sourceContainer, '—');
      expect(model.sourceSampleRate, '—');
      expect(model.sourceBitDepth, '—');
      expect(model.sourceChannels, '—');
      expect(model.sourceBitrate, '—');
      expect(model.sourceBadge, AudioLosslessBadge.unknown);
      expect(model.hasProcessing, isFalse);
      expect(model.outputMode, 'Shared');

      // Strict requirement: never claim bit-perfect or unaltered
      expect(model.verdict.toLowerCase(), isNot(contains('bit-perfect')));
      expect(model.verdict.toLowerCase(), isNot(contains('unaltered')));
    });

    test('lossless FLAC stream info properly mapped', () {
      const flacInfo = AudioStreamInfo(
        codec: 'flac',
        container: 'flac',
        sampleRate: 44100,
        bitDepth: 16,
        channels: 2,
        bitrateKbps: 850.5,
        isLossless: true,
      );

      final model = buildSignalPathModel(
        streamInfo: flacInfo,
        eqEnabled: false,
        eqPresetId: 'flat',
        eqPreampDb: 0.0,
        replayGainMode: ReplayGainMode.off,
        replayGainPreamp: 0.0,
        currentDevice: const AudioDevice(id: 'dac1', name: 'External USB DAC'),
        isExclusiveMode: true,
        capabilities: defaultCapabilities,
      );

      expect(model.isPlaying, isTrue);
      expect(model.sourceCodec, 'FLAC');
      expect(model.sourceContainer, 'FLAC');
      expect(model.sourceSampleRate, '44.1 kHz');
      expect(model.sourceBitDepth, '16-bit');
      expect(model.sourceChannels, 'Stereo');
      expect(model.sourceBitrate, '851 kbps');
      expect(model.sourceBadge, AudioLosslessBadge.lossless);
      expect(model.decoderEngine, 'libmpv');
      expect(model.hasProcessing, isFalse);
      expect(model.outputDevice, 'External USB DAC');
      expect(model.outputMode, 'Exclusive');

      expect(model.verdict.toLowerCase(), isNot(contains('bit-perfect')));
      expect(model.verdict.toLowerCase(), isNot(contains('unaltered')));
    });

    test('lossy MP3 stream info with null bitDepth', () {
      const mp3Info = AudioStreamInfo(
        codec: 'mp3',
        container: 'mp3',
        sampleRate: 48000,
        bitDepth: null,
        channels: 1,
        bitrateKbps: 320.0,
        isLossless: false,
      );

      final model = buildSignalPathModel(
        streamInfo: mp3Info,
        eqEnabled: false,
        eqPresetId: 'flat',
        eqPreampDb: 0.0,
        replayGainMode: ReplayGainMode.off,
        replayGainPreamp: 0.0,
        currentDevice: AudioDevice.auto,
        isExclusiveMode: false,
        capabilities: defaultCapabilities,
      );

      expect(model.isPlaying, isTrue);
      expect(model.sourceCodec, 'MP3');
      expect(model.sourceSampleRate, '48.0 kHz');
      expect(model.sourceBitDepth, '—');
      expect(model.sourceChannels, 'Mono');
      expect(model.sourceBitrate, '320 kbps');
      expect(model.sourceBadge, AudioLosslessBadge.lossy);

      expect(model.verdict.toLowerCase(), isNot(contains('bit-perfect')));
      expect(model.verdict.toLowerCase(), isNot(contains('unaltered')));
    });

    test('active processing: equalizer enabled with preset and preamp', () {
      const flacInfo = AudioStreamInfo(
        codec: 'flac',
        sampleRate: 96000,
        bitDepth: 24,
        channels: 2,
        isLossless: true,
      );

      final model = buildSignalPathModel(
        streamInfo: flacInfo,
        eqEnabled: true,
        eqPresetId: 'warm',
        eqPreampDb: -3.0,
        replayGainMode: ReplayGainMode.off,
        replayGainPreamp: 0.0,
        currentDevice: AudioDevice.auto,
        isExclusiveMode: false,
        capabilities: defaultCapabilities,
      );

      expect(model.hasProcessing, isTrue);
      expect(model.activeProcessingItems.first, contains('warm'));
      expect(model.eqStatus, contains('warm'));
      expect(model.eqStatus, contains('-3.0 dB'));
      expect(model.verdict, contains('Equalizer'));

      expect(model.verdict.toLowerCase(), isNot(contains('bit-perfect')));
      expect(model.verdict.toLowerCase(), isNot(contains('unaltered')));
    });

    test('active processing: ReplayGain active', () {
      const flacInfo = AudioStreamInfo(codec: 'flac', isLossless: true);

      final model = buildSignalPathModel(
        streamInfo: flacInfo,
        eqEnabled: false,
        eqPresetId: 'flat',
        eqPreampDb: 0.0,
        replayGainMode: ReplayGainMode.album,
        replayGainPreamp: 2.0,
        currentDevice: AudioDevice.auto,
        isExclusiveMode: false,
        capabilities: defaultCapabilities,
      );

      expect(model.hasProcessing, isTrue);
      expect(model.activeProcessingItems, contains('ReplayGain (album)'));
      expect(model.replayGainStatus, contains('album'));
      expect(model.replayGainStatus, contains('+2.0 dB'));

      expect(model.verdict.toLowerCase(), isNot(contains('bit-perfect')));
      expect(model.verdict.toLowerCase(), isNot(contains('unaltered')));
    });

    test('plain text export toPlainText formats cleanly', () {
      const flacInfo = AudioStreamInfo(
        codec: 'flac',
        container: 'flac',
        sampleRate: 44100,
        bitDepth: 16,
        channels: 2,
        bitrateKbps: 900.0,
        isLossless: true,
      );

      final model = buildSignalPathModel(
        streamInfo: flacInfo,
        eqEnabled: true,
        eqPresetId: 'vocal',
        eqPreampDb: -3.0,
        replayGainMode: ReplayGainMode.track,
        replayGainPreamp: 0.0,
        currentDevice: const AudioDevice(id: 'dev1', name: 'Speakers'),
        isExclusiveMode: false,
        capabilities: defaultCapabilities,
      );

      final text = model.toPlainText();
      expect(text, contains('--- Signal Path Report ---'));
      expect(text, contains('Codec: FLAC'));
      expect(text, contains('Engine: libmpv'));
      expect(text, contains('Equalizer: On (vocal'));
      expect(text, contains('ReplayGain: track'));
      expect(text, contains('Device: Speakers'));
      expect(text, contains('Mode: Shared'));
      expect(text, contains('Verdict:'));
      expect(text, contains('Note:'));

      expect(text.toLowerCase(), isNot(contains('bit-perfect')));
      expect(text.toLowerCase(), isNot(contains('unaltered')));
    });
  });
}
