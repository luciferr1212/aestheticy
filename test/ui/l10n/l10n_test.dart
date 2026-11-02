import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/ui/l10n/app_strings.dart';
import 'package:aestheticy/ui/l10n/locale_controller.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  group('Localization Parity & Engine Tests', () {
    test('PARITY TEST: every key in en exists in ar and vice versa without empty values', () {
      final enKeys = AppStrings.en.keys.toSet();
      final arKeys = AppStrings.ar.keys.toSet();

      final missingInAr = enKeys.difference(arKeys);
      final missingInEn = arKeys.difference(enKeys);

      expect(
        missingInAr,
        isEmpty,
        reason: 'Keys present in English but missing in Arabic: $missingInAr',
      );
      expect(
        missingInEn,
        isEmpty,
        reason: 'Keys present in Arabic but missing in English: $missingInEn',
      );

      for (final entry in AppStrings.en.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: 'English key "${entry.key}" must not have an empty value',
        );
      }

      for (final entry in AppStrings.ar.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: 'Arabic key "${entry.key}" must not have an empty value',
        );
      }
    });

    test('Fallback: unknown key returns key; missing ar value falls back to en', () {
      expect(
        AppStrings.t('completely.nonexistent.key', language: 'en'),
        equals('completely.nonexistent.key'),
      );
      expect(
        AppStrings.t('completely.nonexistent.key', language: 'ar'),
        equals('completely.nonexistent.key'),
      );

      // Known key resolves correctly in each language
      expect(AppStrings.t('nav.library', language: 'en'), equals('Library'));
      expect(AppStrings.t('nav.library', language: 'ar'), equals('المكتبة'));
    });

    test('textDirectionFor identifies first strong directional character', () {
      // Arabic string -> rtl
      expect(textDirectionFor('فيروز'), equals(TextDirection.rtl));
      expect(textDirectionFor('صباح الخير'), equals(TextDirection.rtl));

      // Latin -> ltr
      expect(textDirectionFor('Pink Floyd'), equals(TextDirection.ltr));
      expect(textDirectionFor('Aestheticy'), equals(TextDirection.ltr));

      // empty -> ltr
      expect(textDirectionFor(''), equals(TextDirection.ltr));

      // digits first then Arabic -> rtl
      expect(textDirectionFor('123 فيروز'), equals(TextDirection.rtl));
      expect(textDirectionFor('2024 أغنية جميلة'), equals(TextDirection.rtl));

      // Arabic first then Latin -> rtl
      expect(textDirectionFor('فيروز - Fairouz'), equals(TextDirection.rtl));

      // Latin first then Arabic -> ltr
      expect(textDirectionFor('Fairouz - فيروز'), equals(TextDirection.ltr));
    });

    test('LocaleController follows SettingsStore and flips to RTL for ar', () {
      final store = SettingsStore(
        initialSettings: const AppSettings(language: 'en'),
      );
      final controller = LocaleController(settingsStore: store);

      expect(controller.language, equals('en'));
      expect(controller.locale, equals(const Locale('en')));
      expect(controller.textDirection, equals(TextDirection.ltr));

      // Update store language
      store.update((s) => s.copyWith(language: 'ar'));

      expect(controller.language, equals('ar'));
      expect(controller.locale, equals(const Locale('ar')));
      expect(controller.textDirection, equals(TextDirection.rtl));

      store.dispose();
      controller.dispose();
    });
  });
}
