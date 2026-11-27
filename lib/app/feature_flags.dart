import '../ui/settings/app_settings.dart';

/// Typed feature flags with compile-time `false` defaults, overridable from a
/// hidden `featureFlags` map in `ui_settings.json` (no UI exposed).
class FeatureFlags {
  final bool canvas;
  final bool jam;
  final bool tagEditor;
  final bool scrobbling;
  final bool videoConcerts;

  /// Creates a [FeatureFlags] instance with all flags defaulting to `false`.
  const FeatureFlags({
    this.canvas = false,
    this.jam = false,
    this.tagEditor = false,
    this.scrobbling = false,
    this.videoConcerts = false,
  });

  /// Default production flags (all disabled).
  static const FeatureFlags defaults = FeatureFlags();

  /// Builds [FeatureFlags] from an arbitrary JSON/settings map, falling back
  /// to `false` for missing or non-boolean entries.
  factory FeatureFlags.fromMap(Map<String, Object?>? map) {
    if (map == null || map.isEmpty) return defaults;
    bool flag(String key) {
      final raw = map[key];
      return raw is bool ? raw : false;
    }

    return FeatureFlags(
      canvas: flag('canvas'),
      jam: flag('jam'),
      tagEditor: flag('tagEditor'),
      scrobbling: flag('scrobbling'),
      videoConcerts: flag('videoConcerts'),
    );
  }

  /// Resolves [FeatureFlags] from [AppSettings.featureFlags].
  factory FeatureFlags.fromSettings(AppSettings settings) =>
      FeatureFlags.fromMap(settings.featureFlags);

  /// Serializes all flags to a JSON-compatible map.
  Map<String, bool> toMap() => {
        'canvas': canvas,
        'jam': jam,
        'tagEditor': tagEditor,
        'scrobbling': scrobbling,
        'videoConcerts': videoConcerts,
      };

  /// Returns a copy with specified overrides.
  FeatureFlags copyWith({
    bool? canvas,
    bool? jam,
    bool? tagEditor,
    bool? scrobbling,
    bool? videoConcerts,
  }) {
    return FeatureFlags(
      canvas: canvas ?? this.canvas,
      jam: jam ?? this.jam,
      tagEditor: tagEditor ?? this.tagEditor,
      scrobbling: scrobbling ?? this.scrobbling,
      videoConcerts: videoConcerts ?? this.videoConcerts,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureFlags &&
          other.canvas == canvas &&
          other.jam == jam &&
          other.tagEditor == tagEditor &&
          other.scrobbling == scrobbling &&
          other.videoConcerts == videoConcerts;

  @override
  int get hashCode =>
      Object.hash(canvas, jam, tagEditor, scrobbling, videoConcerts);
}
