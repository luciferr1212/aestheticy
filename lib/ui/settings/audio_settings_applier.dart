import '../../audio/audio_engine.dart';
import '../../audio/audio_models.dart';
import '../../diagnostics/app_logger.dart';
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
    } catch (e, st) {
      // Non-fatal if device discovery fails during startup
      AppLogger.instance.warn(
        'AudioSettings',
        'Startup refreshDevices failed',
        e,
        st,
      );
    }

    final settings = settingsStore.settings;

    // 1. Output device: only select if it exists in detected devices list
    final savedDeviceId = settings.outputDeviceId;
    if (savedDeviceId != 'auto') {
      final exists = engine.devices.any((d) => d.id == savedDeviceId);
      if (exists) {
        try {
          await engine.selectDevice(savedDeviceId);
        } catch (e, st) {
          // Keep active device, do not overwrite saved id
          AppLogger.instance.warn(
            'AudioSettings',
            'Startup selectDevice failed',
            e,
            st,
          );
        }
      }
    }

    // 2. Exclusive mode (only if capabilities permit)
    if (engine.capabilities.exclusiveMode) {
      try {
        await engine.setExclusiveMode(settings.exclusiveMode);
      } catch (e, st) {
        AppLogger.instance.warn(
          'AudioSettings',
          'Startup setExclusiveMode failed',
          e,
          st,
        );
      }
    }

    // 3. ReplayGain mode
    final rgMode = switch (settings.replayGainMode) {
      'track' => ReplayGainMode.track,
      'album' => ReplayGainMode.album,
      _ => ReplayGainMode.off,
    };
    try {
      await engine.setReplayGainMode(rgMode);
    } catch (e, st) {
      AppLogger.instance.warn(
        'AudioSettings',
        'Startup setReplayGainMode failed',
        e,
        st,
      );
    }

    // 4. ReplayGain preamp (clamped -15.0 to 15.0 dB)
    final clampedPreamp = settings.replayGainPreampDb.clamp(-15.0, 15.0);
    try {
      await engine.setReplayGainPreamp(clampedPreamp);
    } catch (e, st) {
      AppLogger.instance.warn(
        'AudioSettings',
        'Startup setReplayGainPreamp failed',
        e,
        st,
      );
    }

    // 5. Volume (clamped 0.0 to 1.0)
    final clampedVolume = settings.volume.clamp(0.0, 1.0);
    try {
      await engine.setVolume(clampedVolume);
    } catch (e, st) {
      AppLogger.instance.warn('AudioSettings', 'Startup setVolume failed', e, st);
    }
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
    } catch (e, st) {
      AppLogger.instance.warn('AudioSettings', 'setDevice failed', e, st);
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
    } catch (e, st) {
      AppLogger.instance.warn('AudioSettings', 'setExclusive failed', e, st);
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
    } catch (e, st) {
      AppLogger.instance.warn(
        'AudioSettings',
        'setReplayGainMode failed',
        e,
        st,
      );
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
    } catch (e, st) {
      AppLogger.instance.warn(
        'AudioSettings',
        'setReplayGainPreamp failed',
        e,
        st,
      );
      return AudioSettingsError.failed;
    }
  }
}
