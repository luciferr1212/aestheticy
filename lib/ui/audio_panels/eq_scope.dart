import 'package:flutter/widgets.dart';

import 'eq_controller.dart';

/// Scope providing [EqController] to descendants.
class EqScope extends InheritedNotifier<EqController> {
  /// Creates an [EqScope].
  const EqScope({
    super.key,
    required EqController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Retrieves the [EqController] from the closest ancestor [EqScope].
  static EqController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<EqScope>();
    assert(scope != null, 'No EqScope found in context');
    return scope!.notifier!;
  }

  /// Retrieves the [EqController] from the closest ancestor [EqScope], if present.
  static EqController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<EqScope>()?.notifier;
  }
}
