import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/result.dart';
import '../../diagnostics/app_logger.dart';
import '../../features/persistence/atomic_file_writer.dart';
import '../../features/persistence/versioned_json_store.dart';

/// Predefined equalizer preset descriptor.
class EqPreset {
  /// Unique identifier of the preset.
  final String id;

  /// Localization key for the preset name.
  final String nameKey;

  /// Gain values in dB for the 10 frequency bands (-12.0 to +12.0 dB).
  final List<double> gains;

  /// Pre-amplification in dB (-12.0 to +12.0 dB).
  final double preampDb;

  /// Creates an immutable [EqPreset].
  const EqPreset({
    required this.id,
    required this.nameKey,
    required this.gains,
    required this.preampDb,
  });
}

/// The standard 5 built-in equalizer presets.
const List<EqPreset> kBuiltInEqPresets = [
  EqPreset(
    id: 'flat',
    nameKey: 'eq.preset.flat',
    gains: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    preampDb: 0.0,
  ),
  EqPreset(
    id: 'warm',
    nameKey: 'eq.preset.warm',
    gains: [3.0, 3.0, 2.0, 1.0, 0.0, 0.0, -1.0, -1.0, -2.0, -2.0],
    preampDb: -3.0,
  ),
  EqPreset(
    id: 'bassBoost',
    nameKey: 'eq.preset.bassBoost',
    gains: [6.0, 5.0, 4.0, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    preampDb: -6.0,
  ),
  EqPreset(
    id: 'vocal',
    nameKey: 'eq.preset.vocal',
    gains: [-2.0, -2.0, -1.0, 1.0, 3.0, 3.0, 2.0, 1.0, 0.0, -1.0],
    preampDb: -3.0,
  ),
  EqPreset(
    id: 'bright',
    nameKey: 'eq.preset.bright',
    gains: [-1.0, -1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 3.0, 4.0, 4.0],
    preampDb: -4.0,
  ),
];

/// User-created custom equalizer preset.
class CustomPreset {
  /// Name of the preset (1 to 24 characters).
  final String name;

  /// Gains for the 10 bands clamped between -12.0 and +12.0 dB.
  final List<double> gains;

  /// Preamp gain clamped between -12.0 and +12.0 dB.
  final double preampDb;

  /// Creates a [CustomPreset].
  const CustomPreset({
    required this.name,
    required this.gains,
    required this.preampDb,
  });

  /// Serializes preset to JSON.
  Map<String, Object?> toJson() => {
        'name': name,
        'gains': gains,
        'preampDb': preampDb,
      };

  /// Tolerantly deserializes preset from JSON.
  factory CustomPreset.fromJson(Map<String, Object?> json) {
    final rawName = json['name'];
    final name = (rawName is String ? rawName.trim() : 'Custom').substring(
      0,
      rawName is String && rawName.trim().length > 24
          ? 24
          : (rawName is String ? rawName.trim().length : 6),
    );

    final rawGains = json['gains'];
    final List<double> gains = [];
    if (rawGains is List) {
      for (final g in rawGains) {
        if (g is num) {
          gains.add(g.toDouble().clamp(-12.0, 12.0));
        }
      }
    }
    while (gains.length < 10) {
      gains.add(0.0);
    }
    final finalGains = gains.take(10).toList();

    final rawPreamp = json['preampDb'];
    final preamp =
        rawPreamp is num ? rawPreamp.toDouble().clamp(-12.0, 12.0) : 0.0;

    return CustomPreset(
      name: name.isEmpty ? 'Custom' : name,
      gains: finalGains,
      preampDb: preamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomPreset &&
          other.name.toLowerCase() == name.toLowerCase() &&
          listEquals(other.gains, gains) &&
          other.preampDb == preampDb;

  @override
  int get hashCode => Object.hash(
        name.toLowerCase(),
        Object.hashAll(gains),
        preampDb,
      );
}

/// Immutable configuration state for the equalizer.
class EqSettings {
  /// Whether equalizer processing is enabled.
  final bool enabled;

  /// Gains for the 10 frequency bands in dB (-12.0 to +12.0 dB).
  final List<double> gains;

  /// Pre-amplification gain in dB (-12.0 to +12.0 dB).
  final double preampDb;

  /// Identifier of the currently applied preset ('flat', 'custom', or custom preset name).
  final String presetId;

  /// List of saved user presets (maximum 20).
  final List<CustomPreset> customPresets;

  /// Creates an immutable [EqSettings].
  const EqSettings({
    this.enabled = false,
    this.gains = const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    this.preampDb = 0.0,
    this.presetId = 'flat',
    this.customPresets = const [],
  });

  /// Copies settings with optional replacements.
  EqSettings copyWith({
    bool? enabled,
    List<double>? gains,
    double? preampDb,
    String? presetId,
    List<CustomPreset>? customPresets,
  }) {
    return EqSettings(
      enabled: enabled ?? this.enabled,
      gains: gains != null
          ? List.unmodifiable(gains.map((g) => g.clamp(-12.0, 12.0)))
          : this.gains,
      preampDb: preampDb?.clamp(-12.0, 12.0) ?? this.preampDb,
      presetId: presetId ?? this.presetId,
      customPresets: customPresets != null
          ? List.unmodifiable(customPresets.take(20))
          : this.customPresets,
    );
  }

  /// Serializes to a JSON map.
  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'gains': gains,
        'preampDb': preampDb,
        'presetId': presetId,
        'customPresets': customPresets.map((p) => p.toJson()).toList(),
      };

  /// Tolerantly deserializes from JSON map, resetting invalid fields to defaults.
  factory EqSettings.fromJson(Map<String, Object?> json) {
    final enabled = json['enabled'] is bool ? json['enabled'] as bool : false;

    final rawGains = json['gains'];
    final List<double> gains = [];
    if (rawGains is List) {
      for (final g in rawGains) {
        if (g is num) {
          gains.add(g.toDouble().clamp(-12.0, 12.0));
        }
      }
    }
    while (gains.length < 10) {
      gains.add(0.0);
    }
    final finalGains = gains.take(10).toList();

    final rawPreamp = json['preampDb'];
    final preamp =
        rawPreamp is num ? rawPreamp.toDouble().clamp(-12.0, 12.0) : 0.0;

    final rawPresetId = json['presetId'];
    final presetId = rawPresetId is String && rawPresetId.isNotEmpty
        ? rawPresetId
        : 'flat';

    final rawCustom = json['customPresets'];
    final List<CustomPreset> customPresets = [];
    if (rawCustom is List) {
      for (final item in rawCustom) {
        if (item is Map) {
          final p = CustomPreset.fromJson(Map<String, Object?>.from(item));
          final exists = customPresets.any(
            (c) => c.name.toLowerCase() == p.name.toLowerCase(),
          );
          if (!exists && customPresets.length < 20) {
            customPresets.add(p);
          }
        }
      }
    }

    return EqSettings(
      enabled: enabled,
      gains: finalGains,
      preampDb: preamp,
      presetId: presetId,
      customPresets: customPresets,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EqSettings &&
          other.enabled == enabled &&
          listEquals(other.gains, gains) &&
          other.preampDb == preampDb &&
          other.presetId == presetId &&
          listEquals(other.customPresets, customPresets);

  @override
  int get hashCode => Object.hash(
        enabled,
        Object.hashAll(gains),
        preampDb,
        presetId,
        Object.hashAll(customPresets),
      );
}

/// Persistent store managing equalizer settings in `eq_settings.json`.
class EqStore extends ChangeNotifier {
  static const int currentSchemaVersion = 1;
  static const Set<String> _knownKeys = {
    'enabled',
    'gains',
    'preampDb',
    'presetId',
    'customPresets',
  };

  Future<Directory> Function()? _directoryProvider;
  Directory? _directory;
  final void Function(AppError error)? onError;
  EqSettings _settings;
  Timer? _debounceTimer;
  AtomicFileWriter? _writer;
  Map<String, Object?> _unknownFields = const {};
  final VersionedJsonStoreHelper _versionHelper = VersionedJsonStoreHelper(
    storeName: 'EqStore',
    fileName: 'eq_settings.json',
    currentSchemaVersion: currentSchemaVersion,
    knownKeys: _knownKeys,
  );

  /// Creates an [EqStore] with an optional injected directory or directory provider.
  EqStore({
    Future<Directory> Function()? directoryProvider,
    Directory? directory,
    this.onError,
    EqSettings initialSettings = const EqSettings(),
  }) : _settings = initialSettings {
    _directoryProvider = directoryProvider;
    _directory = directory;
    if (directory != null) {
      _writer = AtomicFileWriter(
        File(p.join(directory.path, 'eq_settings.json')),
        onError: onError,
      );
    }
  }

  /// Current immutable equalizer settings.
  EqSettings get settings => _settings;

  AtomicFileWriter? _getWriter() {
    if (_writer != null) return _writer;
    if (_directory != null) {
      return _writer = AtomicFileWriter(
        File(p.join(_directory!.path, 'eq_settings.json')),
        onError: onError,
      );
    }
    return null;
  }

  /// Initializes the store and loads configuration from disk.
  Future<void> init() async {
    try {
      if (_directory == null) {
        final provider = _directoryProvider;
        if (provider != null) {
          _directory = await provider();
        } else {
          final supportDir = await getApplicationSupportDirectory();
          _directory = Directory(p.join(supportDir.path, 'Aestheticy'));
        }
      }
      if (!_directory!.existsSync()) {
        _directory!.createSync(recursive: true);
      }
      _writer ??= AtomicFileWriter(
        File(p.join(_directory!.path, 'eq_settings.json')),
        onError: onError,
      );
      await _loadFromFile();
    } catch (e, st) {
      // Retain in-memory defaults on error
      AppLogger.instance.warn(
        'EqStore',
        'EqStore.init failed, keeping defaults',
        e,
        st,
      );
    }
  }

  /// Updates settings using [updater] and schedules a debounced atomic write.
  void update(EqSettings Function(EqSettings current) updater) {
    _settings = updater(_settings);
    notifyListeners();
    _scheduleWrite();
  }

  Future<void> _loadFromFile() async {
    final dir = _directory;
    if (dir == null) return;
    final loaded = await _versionHelper.load(dir);
    if (loaded.wasQuarantined) {
      _settings = const EqSettings();
      _unknownFields = const {};
      return;
    }
    final data = loaded.data;
    if (data != null) {
      _settings = EqSettings.fromJson(data);
      _unknownFields = loaded.unknownFields;
    }
  }

  void _scheduleWrite() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _writeToDisk();
    });
  }

  Future<void> _writeToDisk() async {
    final writer = _getWriter();
    if (writer == null) return;
    try {
      final payload = _versionHelper.preparePayload(
        _settings.toJson(),
        _unknownFields,
      );
      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
      await writer.write(jsonStr);
      final dir = _directory;
      if (dir != null) {
        _versionHelper.writeRollingBackupSync(dir, jsonStr);
      }
    } catch (e, st) {
      AppLogger.instance.error('EqStore', 'Failed writing eq_settings.json', e, st);
      onError?.call(AppError.fromException(e, st, 'error.settingsSaveFailed'));
    }
  }

  /// Immediately flushes pending writes to disk (used primarily for unit tests).
  @visibleForTesting
  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _writeToDisk();
    await _writer?.flush();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _writer?.dispose();
    super.dispose();
  }
}
