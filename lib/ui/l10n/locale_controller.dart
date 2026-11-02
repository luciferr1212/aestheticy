import 'package:flutter/widgets.dart';

import '../settings/settings_store.dart';

/// Controller coordinating the ambient application [Locale] and [TextDirection].
class LocaleController extends ChangeNotifier {
  String _language;

  /// Creates a [LocaleController] with optional [initialLanguage] and [SettingsStore] binding.
  LocaleController({
    String initialLanguage = 'en',
    SettingsStore? settingsStore,
  }) : _language = initialLanguage {
    if (settingsStore != null) {
      bindSettingsStore(settingsStore);
    }
  }

  /// Active language code ('en' or 'ar').
  String get language => _language;

  /// Active Flutter [Locale].
  Locale get locale => Locale(_language);

  /// Natural text direction associated with the active language.
  TextDirection get textDirection =>
      _language == 'ar' ? TextDirection.rtl : TextDirection.ltr;

  /// Updates active language and notifies listeners.
  void setLanguage(String lang) {
    if (lang != _language && (lang == 'en' || lang == 'ar')) {
      _language = lang;
      notifyListeners();
    }
  }

  /// Binds this controller to [store], mirroring language changes automatically.
  void bindSettingsStore(SettingsStore store) {
    _language = store.settings.language;
    store.addListener(() {
      final storeLang = store.settings.language;
      if (storeLang != _language) {
        _language = storeLang;
        notifyListeners();
      }
    });
  }
}
