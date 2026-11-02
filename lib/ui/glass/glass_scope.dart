import 'package:flutter/widgets.dart';

import 'glass_quality.dart';

/// Controller coordinating active glass rendering tier and motion reduction.
class GlassController extends ChangeNotifier {
  GlassQuality _quality = GlassQuality.full;
  bool _reduceMotion = false;

  /// Creates a [GlassController] with default [GlassQuality.full].
  GlassController({
    GlassQuality? quality,
    bool? reduceMotion,
  }) {
    if (quality != null) {
      _quality = quality;
    }
    if (reduceMotion != null) {
      _reduceMotion = reduceMotion;
    }
  }

  /// The active glass quality tier.
  GlassQuality get quality => _quality;
  set quality(GlassQuality value) {
    if (_quality != value) {
      _quality = value;
      notifyListeners();
    }
  }

  /// Whether animations and motion should be reduced or disabled.
  bool get reduceMotion => _reduceMotion;
  set reduceMotion(bool value) {
    if (_reduceMotion != value) {
      _reduceMotion = value;
      notifyListeners();
    }
  }
}

/// Inherited widget exposing [GlassController] to descendant widgets.
class GlassScope extends InheritedNotifier<GlassController> {
  /// Creates a [GlassScope].
  const GlassScope({
    super.key,
    required GlassController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Retrieves the [GlassController] from [context] and registers a dependency.
  static GlassController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GlassScope>();
    assert(scope != null, 'No GlassScope found in context');
    return scope!.notifier!;
  }

  /// Retrieves the [GlassController] from [context] without registering a dependency.
  static GlassController controllerOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<GlassScope>();
    assert(scope != null, 'No GlassScope found in context');
    return scope!.notifier!;
  }

  /// Convenience accessor returning the current [GlassQuality], listening for updates.
  static GlassQuality qualityOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GlassScope>();
    return scope?.notifier?.quality ?? GlassQuality.full;
  }
}
