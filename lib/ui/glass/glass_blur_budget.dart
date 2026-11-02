import 'package:flutter/foundation.dart';

/// Maximum allowed concurrent blurred surfaces app-wide.
const int kMaxBlurredSurfaces = 6;

/// Enforces an app-wide budget allowing at most 6 concurrent BackdropFilter surfaces.
class GlassBlurBudget {
  GlassBlurBudget._();

  /// Shared singleton instance.
  static final GlassBlurBudget instance = GlassBlurBudget._();

  /// Maximum allowed concurrent blurred surfaces.
  static const int maxConcurrentBlurs = kMaxBlurredSurfaces;

  final Set<Object> _activeOwners = <Object>{};

  /// Current count of actively held blur allocations.
  int get activeCount => _activeOwners.length;

  /// Attempts to acquire a blur slot for [owner].
  ///
  /// Returns `true` if a slot was already held or successfully acquired.
  /// Returns `false` if the maximum budget of 6 has already been reached.
  bool tryAcquire(Object owner) {
    if (_activeOwners.contains(owner)) {
      return true;
    }
    if (_activeOwners.length < maxConcurrentBlurs) {
      _activeOwners.add(owner);
      return true;
    }
    return false;
  }

  /// Releases a blur slot held by [owner].
  void release(Object owner) {
    _activeOwners.remove(owner);
  }

  /// Resets all active blur allocations (strictly intended for unit tests).
  @visibleForTesting
  void resetForTesting() {
    _activeOwners.clear();
  }
}
