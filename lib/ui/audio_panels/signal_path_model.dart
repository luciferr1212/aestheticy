import '../../audio/audio_models.dart';

/// Quality tier badge for the source audio file.
enum AudioLosslessBadge {
  /// Lossless encoding (e.g. FLAC, ALAC, WAV).
  lossless,

  /// Lossy encoding (e.g. MP3, AAC, OGG).
  lossy,

  /// Codec quality is unknown or unverified.
  unknown,
}

/// Immutable data representation of the complete audio signal path.
class SignalPathModel {
  /// Whether an audio stream is currently active.
  final bool isPlaying;

  // ── Stage 1: Source file ──────────────────────────────────────────────────
  final String sourceCodec;
  final String sourceContainer;
  final String sourceSampleRate;
  final String sourceBitDepth;
  final String sourceChannels;
  final String sourceBitrate;
  final AudioLosslessBadge sourceBadge;

  // ── Stage 2: Decoder ──────────────────────────────────────────────────────
  final String decoderEngine;
  final String decoderCodec;

  // ── Stage 3: Processing ───────────────────────────────────────────────────
  final bool hasProcessing;
  final String eqStatus;
  final String replayGainStatus;

  // ── Stage 4: Output ───────────────────────────────────────────────────────
  final String outputDevice;
  final String outputMode;

  // ── Verdict & Notes ───────────────────────────────────────────────────────
  final String verdict;
  final List<String> activeProcessingItems;
  final String engineDisclaimer;

  /// Creates an immutable [SignalPathModel].
  const SignalPathModel({
    required this.isPlaying,
    required this.sourceCodec,
    required this.sourceContainer,
    required this.sourceSampleRate,
    required this.sourceBitDepth,
    required this.sourceChannels,
    required this.sourceBitrate,
    required this.sourceBadge,
    required this.decoderEngine,
    required this.decoderCodec,
    required this.hasProcessing,
    required this.eqStatus,
    required this.replayGainStatus,
    required this.outputDevice,
    required this.outputMode,
    required this.verdict,
    required this.activeProcessingItems,
    required this.engineDisclaimer,
  });

  /// Formats all signal path stages into a human-readable plain text export.
  String toPlainText() {
    final buffer = StringBuffer();
    buffer.writeln('--- Signal Path Report ---');
    buffer.writeln('1. Source:');
    if (!isPlaying) {
      buffer.writeln('  Nothing is playing');
    } else {
      buffer.writeln('  Codec: $sourceCodec');
      buffer.writeln('  Container: $sourceContainer');
      buffer.writeln('  Sample Rate: $sourceSampleRate');
      buffer.writeln('  Bit Depth: $sourceBitDepth');
      buffer.writeln('  Channels: $sourceChannels');
      buffer.writeln('  Bitrate: $sourceBitrate');
      buffer.writeln('  Format: ${sourceBadge.name}');
    }
    buffer.writeln('2. Decoder:');
    buffer.writeln('  Engine: $decoderEngine');
    buffer.writeln('  Codec: $decoderCodec');
    buffer.writeln('3. Processing:');
    buffer.writeln('  Equalizer: $eqStatus');
    buffer.writeln('  ReplayGain: $replayGainStatus');
    buffer.writeln('4. Output:');
    buffer.writeln('  Device: $outputDevice');
    buffer.writeln('  Mode: $outputMode');
    buffer.writeln('Verdict: $verdict');
    buffer.writeln('Note: $engineDisclaimer');
    return buffer.toString();
  }
}

/// Builds a [SignalPathModel] from live engine state, equalizer state, and persistent settings.
SignalPathModel buildSignalPathModel({
  required AudioStreamInfo? streamInfo,
  required bool eqEnabled,
  required String eqPresetId,
  required double eqPreampDb,
  required ReplayGainMode replayGainMode,
  required double replayGainPreamp,
  required AudioDevice currentDevice,
  required bool isExclusiveMode,
  required EngineCapabilities capabilities,
}) {
  final isPlaying = streamInfo != null;

  // Stage 1: Source file
  final sourceCodec = streamInfo?.codec?.toUpperCase() ?? '—';
  final sourceContainer = streamInfo?.container?.toUpperCase() ?? '—';

  final sampleRate = streamInfo?.sampleRate;
  final sourceSampleRate = sampleRate != null
      ? '${(sampleRate / 1000.0).toStringAsFixed(1)} kHz'
      : '—';

  final bitDepth = streamInfo?.bitDepth;
  final sourceBitDepth = bitDepth != null ? '$bitDepth-bit' : '—';

  final channels = streamInfo?.channels;
  final sourceChannels = channels != null
      ? (channels == 1 ? 'Mono' : (channels == 2 ? 'Stereo' : '$channels ch'))
      : '—';

  final bitrate = streamInfo?.bitrateKbps;
  final sourceBitrate =
      bitrate != null ? '${bitrate.toStringAsFixed(0)} kbps' : '—';

  final sourceBadge = streamInfo?.isLossless == true
      ? AudioLosslessBadge.lossless
      : streamInfo?.isLossless == false
          ? AudioLosslessBadge.lossy
          : AudioLosslessBadge.unknown;

  // Stage 2: Decoder
  const decoderEngine = 'libmpv';
  final decoderCodec = sourceCodec;

  // Stage 3: Processing
  final activeProcessingItems = <String>[];

  final String eqStatus;
  if (eqEnabled && capabilities.equalizer) {
    final formattedPreamp =
        '${eqPreampDb > 0 ? '+' : ''}${eqPreampDb.toStringAsFixed(1)} dB';
    eqStatus = 'On ($eqPresetId, $formattedPreamp)';
    activeProcessingItems.add('Equalizer ($eqPresetId)');
  } else {
    eqStatus = 'Off';
  }

  final String replayGainStatus;
  if (replayGainMode != ReplayGainMode.off && capabilities.replayGain) {
    final formattedPreamp =
        '${replayGainPreamp > 0 ? '+' : ''}${replayGainPreamp.toStringAsFixed(1)} dB';
    replayGainStatus = '${replayGainMode.name} ($formattedPreamp)';
    activeProcessingItems.add('ReplayGain (${replayGainMode.name})');
  } else {
    replayGainStatus = 'Off';
  }

  final hasProcessing = activeProcessingItems.isNotEmpty;

  // Stage 4: Output
  final outputDevice =
      currentDevice.id == 'auto' ? 'System default' : currentDevice.name;
  final outputMode = isExclusiveMode ? 'Exclusive' : 'Shared';

  // Disclaimer & Verdict
  const engineDisclaimer =
      'Resampling and the device format are handled by the engine and are not reported here.';

  final String verdict;
  if (!hasProcessing) {
    verdict =
        'No processing is enabled. The equalizer and ReplayGain are not changing the signal.';
  } else {
    verdict = 'Active processing: ${activeProcessingItems.join(', ')}';
  }

  return SignalPathModel(
    isPlaying: isPlaying,
    sourceCodec: sourceCodec,
    sourceContainer: sourceContainer,
    sourceSampleRate: sourceSampleRate,
    sourceBitDepth: sourceBitDepth,
    sourceChannels: sourceChannels,
    sourceBitrate: sourceBitrate,
    sourceBadge: sourceBadge,
    decoderEngine: decoderEngine,
    decoderCodec: decoderCodec,
    hasProcessing: hasProcessing,
    eqStatus: eqStatus,
    replayGainStatus: replayGainStatus,
    outputDevice: outputDevice,
    outputMode: outputMode,
    verdict: verdict,
    activeProcessingItems: activeProcessingItems,
    engineDisclaimer: engineDisclaimer,
  );
}
