import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/main.dart';
import 'package:aestheticy/ui/gallery/design_gallery_screen.dart';
import 'package:aestheticy/ui/glass/glass_button.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/l10n/locale_controller.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  group('DesignGallery Widget & Shortcut Tests', () {
    testWidgets('Ctrl+Shift+G shortcut opens the DesignGalleryScreen', (
      tester,
    ) async {
      await tester.pumpWidget(const AestheticyApp());
      await tester.pumpAndSettle();

      // Gallery is not initially open
      expect(find.byType(DesignGalleryScreen), findsNothing);

      // Send Ctrl+Shift+G shortcut
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);

      await tester.pumpAndSettle();

      // Gallery is now open
      expect(find.byType(DesignGalleryScreen), findsOneWidget);
      expect(find.textContaining('Design Gallery'), findsOneWidget);

      // Esc closes it
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DesignGalleryScreen), findsNothing);
    });

    testWidgets('quality selector changes GlassScope quality', (tester) async {
      final glassController = GlassController(quality: GlassQuality.light);
      final settingsStore = SettingsStore();
      final localeController = LocaleController(settingsStore: settingsStore);

      await tester.pumpWidget(
        MaterialApp(
          home: GlassScope(
            controller: glassController,
            child: DesignGalleryScreen(
              glassController: glassController,
              localeController: localeController,
              settingsStore: settingsStore,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(glassController.quality, equals(GlassQuality.light));

      // Tap 'OFF' pill
      await tester.tap(find.widgetWithText(GlassPillButton, 'OFF'));
      await tester.pumpAndSettle();
      expect(glassController.quality, equals(GlassQuality.off));

      // Tap 'FULL' pill
      await tester.tap(find.widgetWithText(GlassPillButton, 'FULL'));
      await tester.pumpAndSettle();
      expect(glassController.quality, equals(GlassQuality.full));

      await tester.pump(const Duration(milliseconds: 500));
      settingsStore.dispose();
    });
  });
}
