/// Glass rendering quality tier.
enum GlassQuality {
  /// Real BackdropFilter blur composed with 1.5x saturation boost and translucent fill.
  ///
  /// Flagship default mode, budgeted to at most 6 concurrent surfaces app-wide.
  full,

  /// Opaque simulated glass gradient with soft drop shadow.
  ///
  /// High-performance fallback mode, zero BackdropFilter cost on weaker hardware.
  light,

  /// Flat solid surface with no blur, no gradient, and no shadow.
  ///
  /// Maximum compatibility fallback.
  off,
}
