import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/theme/dither_noise.dart';

void main() {
  group('DitherNoise & DitherOverlay (S4)', () {
    test('Noise tile is generated once deterministically with 128x128 dimensions', () async {
      final image1 = await DitherNoise.image;
      final image2 = await DitherNoise.image;

      expect(image1.width, equals(128));
      expect(image1.height, equals(128));
      // Reused instance
      expect(identical(image1, image2), isTrue);
    });

    testWidgets(
      'DitherOverlay is IgnorePointer, RepaintBoundary and renders repeated tile',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final store = SettingsStore(
          initialSettings: const AppSettings(glassQuality: GlassQuality.full),
        );
        await DitherNoise.image;

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScope(
              store: store,
              child: const Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 300,
                  child: DitherOverlay(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(DitherOverlay), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DitherOverlay),
            matching: find.byType(IgnorePointer),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(DitherOverlay),
            matching: find.byType(RepaintBoundary),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'DitherOverlay skips painting when GlassQuality is off',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final store = SettingsStore(
          initialSettings: const AppSettings(glassQuality: GlassQuality.off),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScope(
              store: store,
              child: const Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 300,
                  child: DitherOverlay(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // When quality is off, DitherOverlay returns SizedBox.shrink()
        final sizedBoxFinder = find.descendant(
          of: find.byType(DitherOverlay),
          matching: find.byType(SizedBox),
        );
        expect(sizedBoxFinder, findsOneWidget);
        final sizedBox = tester.widget<SizedBox>(sizedBoxFinder);
        expect(sizedBox.width, equals(0.0));
        expect(sizedBox.height, equals(0.0));
      },
    );
  });
}
