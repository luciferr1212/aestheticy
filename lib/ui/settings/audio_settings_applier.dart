import '../../audio/audio_engine.dart';
import '../../audio/audio_models.dart';
import 'settings_store.dart';

/// Error categories surfaced when applying audio settings mutations.
enum AudioSettingsError {
  /// The audio engine does not support this capability.
  unsupported,

  /// Applying the setting to the audio engine failed.
  failed,
}

/// Applies persistent audio settings to the underlying [AudioEngine]
/// and exposes transactional mutations that persist only on success.
class AudioSettingsApplier {
  /// The audio engine instance being configured.
  final AudioEngine engine;

  /// The persistent settings store.
  final SettingsStore settingsStore;

  /// Creates an [AudioSettingsApplier].
  AudioSettingsApplier({
    required this.engine,
    required this.settingsStore,
  });

  /// Applies all saved audio settings to [engine] once after startup initialization.
  Future<void> applyAll() async {
    try {
      await engine.refreshDevices();
    } catch (_) {
      // Non-fatal if device discovery fails during startup
    }

    final settings = settingsStore.settings;

    // 1. Output device: only select if it exists in detected devices list
    final savedDeviceId = settings.outputDeviceId;
    if (savedDeviceId != 'auto') {
      final exists = engine.devices.any((d) => d.id == savedDeviceId);
      if (exists) {
        try {
          await engine.selectDevice(savedDeviceId);
        } catch (_) {
          // Keep active device, do not overwrite saved id
        }
      }
    }

    // 2. Exclusive mode (only if capabilities permit)
    if (engine.capabilities.exclusiveMode) {
      try {
        await engine.setExclusiveMode(settings.exclusiveMode);
      } catch (_) {}
    }

    // 3. ReplayGain mode
    final rgMode = switch (settings.replayGainMode) {
      'track' => ReplayGainMode.track,
      'album' => ReplayGainMode.album,
      _ => ReplayGainMode.off,
    };
    try {
      await engine.setReplayGainMode(rgMode);
    } catch (_) {}

    // 4. ReplayGain preamp (clamped -15.0 to 15.0 dB)
    final clampedPreamp = settings.replayGainPreampDb.clamp(-15.0, 15.0);
    try {
      await engine.setReplayGainPreamp(clampedPreamp);
    } catch (_) {}
  }

  /// Selects the audio output device by [id].
  ///
  /// On success, persists [id] to [settingsStore] and returns `null`.
  /// On failure, leaves settings unchanged and returns [AudioSettingsError.failed].
  Future<AudioSettingsError?> setDevice(String id) async {
    try {
      await engine.selectDevice(id);
      settingsStore.update((s) => s.copyWith(outputDeviceId: id));
      return null;
    } catch (_) {
      return AudioSettingsError.failed;
    }
  }

  /// Sets WASAPI exclusive mode.
  ///
  /// Returns [AudioSettingsError.unsupported] if [EngineCapabilities.exclusiveMode] is false.
  /// On success, persists to [settingsStore] and returns `null`.
  Future<AudioSettingsError?> setExclusive(bool enabled) async {
    if (!engine.capabilities.exclusiveMode) {
      return AudioSettingsError.unsupported;
    }
    try {
      await engine.setExclusiveMode(enabled);
      settingsStore.update((s) => s.copyWith(exclusiveMode: enabled));
      return null;
    } catch (_) {
      return AudioSettingsError.failed;
    }
  }

  /// Sets the ReplayGain normalization [mode].
  ///
  /// On success, persists to [settingsStore] and returns `null`.
  Future<AudioSettingsError?> setReplayGainMode(ReplayGainMode mode) async {
    try {
      await engine.setReplayGainMode(mode);
      settingsStore.update((s) => s.copyWith(replayGainMode: mode.name));
      return null;
    } catch (_) {
      return AudioSettingsError.failed;
    }
  }

  /// Sets the ReplayGain pre-amplification in dB, clamped to [-15.0, 15.0].
  ///
  /// On success, persists the clamped value to [settingsStore] and returns `null`.
  Future<AudioSettingsError?> setReplayGainPreamp(double preampDb) async {
    final clamped = preampDb.clamp(-15.0, 15.0);
    try {
      await engine.setReplayGainPreamp(clamped);
      settingsStore.update((s) => s.copyWith(replayGainPreampDb: clamped));
      return null;
    } catch (_) {
      return AudioSettingsError.failed;
    }
  }
}
