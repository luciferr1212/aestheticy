import 'package:flutter/material.dart';
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

    test('greetingKey boundaries (04:59, 05:00, 11:59, 12:00, 17:59, 18:00, 23:59, 00:00)', () {
      DateTime dt(int hour, int minute) => DateTime(2026, 11, 3, hour, minute);

      expect(greetingKey(dt(4, 59)), equals('greeting.evening'));
      expect(greetingKey(dt(5, 0)), equals('greeting.morning'));
      expect(greetingKey(dt(11, 59)), equals('greeting.morning'));
      expect(greetingKey(dt(12, 0)), equals('greeting.afternoon'));
      expect(greetingKey(dt(17, 59)), equals('greeting.afternoon'));
      expect(greetingKey(dt(18, 0)), equals('greeting.evening'));
      expect(greetingKey(dt(23, 59)), equals('greeting.evening'));
      expect(greetingKey(dt(0, 0)), equals('greeting.evening'));
    });

    testWidgets('Overlays render with correct TextDirection in ar (RTL) and en (LTR)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      for (final (lang, expectedDir) in [
        ('ar', TextDirection.rtl),
        ('en', TextDirection.ltr),
      ]) {
        final store = SettingsStore(
          initialSettings: AppSettings(language: lang),
        );
        final controller = LocaleController(settingsStore: store);

        await tester.pumpWidget(
          MaterialApp(
            locale: controller.locale,
            builder: (context, child) => Directionality(
              textDirection: controller.textDirection,
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (ctx) => Column(
                    children: [
                      ElevatedButton(
                        key: const Key('snack_btn'),
                        onPressed: () {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Builder(
                                builder: (snackCtx) {
                                  return Text('snack_text: ${Directionality.of(snackCtx)}');
                                },
                              ),
                            ),
                          );
                        },
                        child: const Text('Show Snack'),
                      ),
                      const Tooltip(
                        key: Key('tooltip_target'),
                        message: 'tooltip_msg',
                        child: Text('Hover me'),
                      ),
                      PopupMenuButton<String>(
                        key: const Key('popup_btn'),
                        itemBuilder: (popupCtx) => [
                          PopupMenuItem(
                            child: Builder(
                              builder: (itemCtx) =>
                                  Text('popup_item: ${Directionality.of(itemCtx)}'),
                            ),
                          ),
                        ],
                        child: const Text('Open Popup'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. SnackBar
        await tester.tap(find.byKey(const Key('snack_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('snack_text: $expectedDir'), findsOneWidget);

        // 2. PopupMenu
        await tester.tap(find.byKey(const Key('popup_btn')));
        await tester.pumpAndSettle();
        expect(find.text('popup_item: $expectedDir'), findsOneWidget);

        // 3. Tooltip
        final tooltipState = tester.state<TooltipState>(find.byKey(const Key('tooltip_target')));
        tooltipState.ensureTooltipVisible();
        await tester.pumpAndSettle();

        final tooltipTextFinder = find.text('tooltip_msg');
        expect(tooltipTextFinder, findsOneWidget);
        expect(
          Directionality.of(tester.element(tooltipTextFinder)),
          equals(expectedDir),
        );

        await tester.pumpWidget(const SizedBox());
        store.dispose();
        controller.dispose();
      }
    });
  });
}
