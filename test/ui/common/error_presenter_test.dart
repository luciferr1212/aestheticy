import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/core/result.dart';
import 'package:aestheticy/ui/common/error_presenter.dart';
import 'package:aestheticy/ui/l10n/app_strings.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  group('ErrorPresenter Widget Tests (S2)', () {
    testWidgets(
      'maps AppError to localized EN/AR message and triggers optional retry or open-log actions',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final store = SettingsStore(
          initialSettings: const AppSettings(language: 'en'),
        );
        addTearDown(store.dispose);

        var retried = false;
        var openedLog = false;

        await tester.pumpWidget(
          SettingsScope(
            store: store,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      ElevatedButton(
                        key: const Key('btn_retry'),
                        onPressed: () {
                          ErrorPresenter.show(
                            context,
                            const IoFailure(),
                            onRetry: () => retried = true,
                          );
                        },
                        child: const Text('Trigger IO'),
                      ),
                      ElevatedButton(
                        key: const Key('btn_open_log'),
                        onPressed: () {
                          ErrorPresenter.show(
                            context,
                            const DatabaseFailure(),
                            onOpenLog: () => openedLog = true,
                          );
                        },
                        child: const Text('Trigger DB'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Retry action in EN
        await tester.tap(find.byKey(const Key('btn_retry')));
        await tester.pumpAndSettle();
        expect(find.text(AppStrings.t('error.ioFailure')), findsOneWidget);
        expect(find.text(AppStrings.t('error.actionRetry')), findsOneWidget);

        await tester.tap(find.text(AppStrings.t('error.actionRetry')));
        await tester.pumpAndSettle();
        expect(retried, isTrue);

        // Wait out previous SnackBar and switch to Arabic RTL
        await tester.pump(const Duration(seconds: 5));
        store.update((s) => s.copyWith(language: 'ar'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_open_log')));
        await tester.pumpAndSettle();
        expect(
          find.text(AppStrings.t('error.databaseFailure', language: 'ar')),
          findsOneWidget,
        );
        expect(
          find.text(AppStrings.t('error.actionOpenLog', language: 'ar')),
          findsOneWidget,
        );

        await tester.tap(
          find.text(AppStrings.t('error.actionOpenLog', language: 'ar')),
        );
        await tester.pumpAndSettle();
        expect(openedLog, isTrue);
      },
    );
  });
}
