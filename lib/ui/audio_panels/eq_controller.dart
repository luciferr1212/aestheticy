import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../audio/audio_engine.dart';
import '../settings/audio_settings_applier.dart';
import 'eq_store.dart';

/// Controller coordinating live equalizer state, throttling engine mutations,
/// and persisting configuration through [EqStore].
class EqController extends ChangeNotifier {
  /// The audio engine being configured.
  final AudioEngine engine;

  /// The persistent equalizer store.
  final EqStore store;

  bool _enabled;
  List<double> _gains;
  double _preampDb;
  String _presetId;

  // Last known successful values for reverting on failure
  List<double> _lastGoodGains;
  double _lastGoodPreamp;
  String _lastGoodPresetId;

  Timer? _throttleTimer;
  List<double>? _pendingGains;
  double? _pendingPreamp;
  bool _isFlushing = false;

  /// Creates an [EqController] initialized from [store].
  EqController({
    required this.engine,
    required this.store,
  })  : _enabled = store.settings.enabled,
        _gains = List.of(store.settings.gains),
        _preampDb = store.settings.preampDb,
        _presetId = store.settings.presetId,
        _lastGoodGains = List.of(store.settings.gains),
        _lastGoodPreamp = store.settings.preampDb,
        _lastGoodPresetId = store.settings.presetId;

  /// Whether the equalizer is currently active.
  bool get enabled => _enabled;

  /// The current 10-band gain values in dB.
  List<double> get gains => List.unmodifiable(_gains);

  /// The current pre-amplification in dB.
  double get preampDb => _preampDb;

  /// Identifier of the active preset ('flat', 'warm', 'custom', or custom preset name).
  String get presetId => _presetId;

  /// List of saved user presets.
  List<CustomPreset> get customPresets => store.settings.customPresets;

  /// Applies saved equalizer configuration to [engine] once after startup initialization.
  Future<void> applyAll() async {
    if (!engine.capabilities.equalizer) return;

    try {
      await engine.setEqGains(_gains);
      await engine.setPreamp(_preampDb);
      await engine.setEqEnabled(_enabled);
      _lastGoodGains = List.of(_gains);
      _lastGoodPreamp = _preampDb;
      _lastGoodPresetId = _presetId;
    } catch (_) {
      // Non-fatal if startup application fails
    }
  }

  /// Enables or disables the equalizer.
  Future<AudioSettingsError?> setEnabled(bool enabled) async {
    if (!engine.capabilities.equalizer) {
      return AudioSettingsError.unsupported;
    }

    try {
      await engine.setEqEnabled(enabled);
      _enabled = enabled;
      store.update((s) => s.copyWith(enabled: enabled));
      notifyListeners();
      return null;
    } catch (_) {
      return AudioSettingsError.failed;
    }
  }

  /// Sets gain for the band at [index] (0..9) clamped to -12.0..12.0 dB.
  ///
  /// Updates local state immediately, marks preset as 'custom', schedules throttled
  /// transmission to the audio engine, and debounces persistence.
  Future<AudioSettingsError?> setBand(int index, double db) async {
    if (!engine.capabilities.equalizer) {
      return AudioSettingsError.unsupported;
    }
    if (index < 0 || index >= 10) return AudioSettingsError.failed;

    final clamped = db.clamp(-12.0, 12.0);
    final newGains = List<double>.of(_gains);
    newGains[index] = clamped;

    _gains = newGains;
    _presetId = 'custom';
    notifyListeners();

    _scheduleEngineSend();
    return null;
  }

  /// Sets the pre-amplification gain in dB clamped to -12.0..12.0 dB.
  Future<AudioSettingsError?> setPreamp(double db) async {
    if (!engine.capabilities.equalizer) {
      return AudioSettingsError.unsupported;
    }

    final clamped = db.clamp(-12.0, 12.0);
    _preampDb = clamped;
    _presetId = 'custom';
    notifyListeners();

    _scheduleEngineSend();
    return null;
  }

  /// Applies preset identified by [id] (built-in or custom).
  Future<AudioSettingsError?> applyPreset(String id) async {
    if (!engine.capabilities.equalizer) {
      return AudioSettingsError.unsupported;
    }

    List<double>? targetGains;
    double? targetPreamp;

    // Check built-in
    final builtIn = kBuiltInEqPresets.where((p) => p.id == id).firstOrNull;
    if (builtIn != null) {
      targetGains = builtIn.gains;
      targetPreamp = builtIn.preampDb;
    } else {
      // Check custom
      final custom = customPresets
          .where((p) => p.name.toLowerCase() == id.toLowerCase())
          .firstOrNull;
      if (custom != null) {
        targetGains = custom.gains;
        targetPreamp = custom.preampDb;
      }
    }

    if (targetGains == null || targetPreamp == null) {
      return AudioSettingsError.failed;
    }

    _throttleTimer?.cancel();
    _pendingGains = null;
    _pendingPreamp = null;

    try {
      await engine.setEqGains(targetGains);
      await engine.setPreamp(targetPreamp);

      _gains = List.of(targetGains);
      _preampDb = targetPreamp;
      _presetId = id;
      _lastGoodGains = List.of(_gains);
      _lastGoodPreamp = _preampDb;
      _lastGoodPresetId = _presetId;

      store.update((s) => s.copyWith(
            presetId: id,
            gains: _gains,
            preampDb: _preampDb,
          ));
      notifyListeners();
      return null;
    } catch (_) {
      // Revert to last good values
      _gains = List.of(_lastGoodGains);
      _preampDb = _lastGoodPreamp;
      _presetId = _lastGoodPresetId;
      notifyListeners();
      return AudioSettingsError.failed;
    }
  }

  /// Resets equalizer to Flat (all 0 dB) and 0 dB preamp, preserving enabled state.
  Future<AudioSettingsError?> reset() async {
    return applyPreset('flat');
  }

  /// Saves current gains and preamp as a custom preset named [name].
  ///
  /// Returns `null` on success, or a validation error key on failure.
  String? saveCustomPreset(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'audioPanels.presetNameEmpty';
    if (trimmed.length > 24) return 'audioPanels.presetNameTooLong';

    // Unique case-insensitive check against built-in preset IDs
    final isBuiltIn = kBuiltInEqPresets.any(
      (p) => p.id.toLowerCase() == trimmed.toLowerCase(),
    );
    if (isBuiltIn || trimmed.toLowerCase() == 'custom') {
      return 'audioPanels.presetNameExists';
    }

    // Unique check against existing custom presets
    final exists = customPresets.any(
      (p) => p.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (exists) return 'audioPanels.presetNameExists';

    if (customPresets.length >= 20) {
      return 'audioPanels.presetLimitReached';
    }

    final newPreset = CustomPreset(
      name: trimmed,
      gains: List.of(_gains),
      preampDb: _preampDb,
    );

    final updated = List<CustomPreset>.from(customPresets)..add(newPreset);
    _presetId = trimmed;
    _lastGoodPresetId = trimmed;

    store.update((s) => s.copyWith(
          presetId: trimmed,
          customPresets: updated,
        ));
    notifyListeners();
    return null;
  }

  /// Deletes custom preset identified by [name].
  void deleteCustomPreset(String name) {
    final updated = customPresets
        .where((p) => p.name.toLowerCase() != name.toLowerCase())
        .toList();

    if (_presetId.toLowerCase() == name.toLowerCase()) {
      _presetId = 'custom';
      _lastGoodPresetId = 'custom';
    }

    store.update((s) => s.copyWith(
          presetId: _presetId,
          customPresets: updated,
        ));
    notifyListeners();
  }

  void _scheduleEngineSend() {
    _pendingGains = List.of(_gains);
    _pendingPreamp = _preampDb;

    if (_throttleTimer == null || !_throttleTimer!.isActive) {
      _throttleTimer = Timer(const Duration(milliseconds: 50), () {
        unawaited(_dispatchToEngine());
      });
    }
  }

  Future<void> _dispatchToEngine() async {
    if (_isFlushing) return;
    _isFlushing = true;

    try {
      while (_pendingGains != null || _pendingPreamp != null) {
        final toSendGains = _pendingGains;
        final toSendPreamp = _pendingPreamp;
        _pendingGains = null;
        _pendingPreamp = null;

        if (toSendGains != null) {
          await engine.setEqGains(toSendGains);
          _lastGoodGains = List.of(toSendGains);
        }
        if (toSendPreamp != null) {
          await engine.setPreamp(toSendPreamp);
          _lastGoodPreamp = toSendPreamp;
        }

        _lastGoodPresetId = _presetId;

        // Persist the latest confirmed values
        store.update((s) => s.copyWith(
              presetId: _presetId,
              gains: _lastGoodGains,
              preampDb: _lastGoodPreamp,
            ));
      }
    } catch (_) {
      // Revert to last successfully applied values
      _gains = List.of(_lastGoodGains);
      _preampDb = _lastGoodPreamp;
      _presetId = _lastGoodPresetId;
      notifyListeners();
    } finally {
      _isFlushing = false;
    }
  }

  /// Flushes any pending throttled values to the engine immediately (for unit tests).
  @visibleForTesting
  Future<void> flushEngine() async {
    _throttleTimer?.cancel();
    await _dispatchToEngine();
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    super.dispose();
  }
}
