import 'package:flutter/widgets.dart';

import '../l10n/app_strings.dart';
import '../settings/settings_scope.dart';
import 'artist_name_store.dart';

/// An inherited notifier exposing [ArtistNameStore] to the widget tree.
class ArtistNameScope extends InheritedNotifier<ArtistNameStore> {
  /// Creates an [ArtistNameScope].
  const ArtistNameScope({
    super.key,
    required ArtistNameStore store,
    required super.child,
  }) : super(notifier: store);

  /// Obtains the ambient [ArtistNameStore] if present.
  static ArtistNameStore? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ArtistNameScope>()
        ?.notifier;
  }
}

/// Convenience extension on [BuildContext] to resolve artist display names.
extension ArtistDisplayContext on BuildContext {
  /// Resolves [original] artist name using active UI language and user settings.
  /// If [original] is null or empty, returns localized Unknown Artist.
  /// If [original] is 'various', returns localized Various Artists.
  String displayArtist(String? original) {
    if (original == null || original.isEmpty) {
      return t('library.unknownArtist');
    }
    if (original == 'various') {
      return t('library.variousArtists');
    }
    final settings = SettingsScope.maybeOf(this)?.settings;
    final nameStore = ArtistNameScope.maybeOf(this);
    if (settings == null || nameStore == null) {
      return original;
    }
    return nameStore.displayArtist(original, settings: settings);
  }
}
