import 'package:flutter/widgets.dart';

import 'app_settings.dart';
import 'settings_store.dart';

/// An inherited notifier exposing [SettingsStore] and [AppSettings] to the widget tree.
class SettingsScope extends InheritedNotifier<SettingsStore> {
  /// Creates a [SettingsScope].
  const SettingsScope({
    super.key,
    required SettingsStore store,
    required super.child,
  }) : super(notifier: store);

  /// Obtains the ambient [SettingsStore] if available.
  static SettingsStore? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.notifier;
  }

  /// Obtains the current [AppSettings] from the nearest [SettingsScope],
  /// or falls back to default [AppSettings] if none exists.
  static AppSettings of(BuildContext context) {
    return maybeOf(context)?.settings ?? const AppSettings();
  }
}
