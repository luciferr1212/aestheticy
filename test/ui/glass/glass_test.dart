import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/ui/glass/glass_blur_budget.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/glass/glass_surface.dart';

void main() {
  group('GlassBlurBudget Tests', () {
    setUp(() {
      GlassBlurBudget.instance.resetForTesting();
    });

    test('default quality is full on controller', () {
      final controller = GlassController();
      expect(controller.quality, equals(GlassQuality.full));
    });

    test('budget allows at most 6 concurrent acquires and the 7th fails', () {
      final owners = List.generate(7, (_) => Object());

      for (int i = 0; i < 6; i++) {
        expect(GlassBlurBudget.instance.tryAcquire(owners[i]), isTrue);
      }
      expect(GlassBlurBudget.instance.activeCount, equals(6));

      // 7th acquire must fail
      expect(GlassBlurBudget.instance.tryAcquire(owners[6]), isFalse);
      expect(GlassBlurBudget.instance.activeCount, equals(6));

      // Idempotent re-acquire for existing owner succeeds
      expect(GlassBlurBudget.instance.tryAcquire(owners[0]), isTrue);

      // Releasing an owner frees up a slot
      GlassBlurBudget.instance.release(owners[0]);
      expect(GlassBlurBudget.instance.activeCount, equals(5));

      // Now 7th owner can acquire
      expect(GlassBlurBudget.instance.tryAcquire(owners[6]), isTrue);
      expect(GlassBlurBudget.instance.activeCount, equals(6));
    });
  });

  group('GlassSurface Widget Tests', () {
    setUp(() {
      GlassBlurBudget.instance.resetForTesting();
    });

    testWidgets(
      'in full mode with 7 surfaces, exactly 6 have BackdropFilter and 7th is light',
      (tester) async {
        final controller = GlassController(quality: GlassQuality.full);

        await tester.pumpWidget(
          GlassScope(
            controller: controller,
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    GlassSurface(child: Text('Surface 1')),
                    GlassSurface(child: Text('Surface 2')),
                    GlassSurface(child: Text('Surface 3')),
                    GlassSurface(child: Text('Surface 4')),
                    GlassSurface(child: Text('Surface 5')),
                    GlassSurface(child: Text('Surface 6')),
                    GlassSurface(child: Text('Surface 7')),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Exactly 6 BackdropFilter widgets app-wide
        expect(find.byType(BackdropFilter), findsNWidgets(6));
      },
    );

    testWidgets('in light and off modes, zero BackdropFilter widgets exist', (
      tester,
    ) async {
      final controller = GlassController(quality: GlassQuality.light);

      await tester.pumpWidget(
        GlassScope(
          controller: controller,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                GlassSurface(child: Text('Surface A')),
                GlassSurface(child: Text('Surface B')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);

      controller.quality = GlassQuality.off;
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('changing quality via GlassController rebuilds surfaces', (
      tester,
    ) async {
      final controller = GlassController(quality: GlassQuality.light);

      await tester.pumpWidget(
        GlassScope(
          controller: controller,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: GlassSurface(child: Text('Dynamic Surface')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);

      // Switch to full quality
      controller.quality = GlassQuality.full;
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);

      // Switch to off quality
      controller.quality = GlassQuality.off;
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('full mode applies composed blur sigma 30 and saturation filter', (
      tester,
    ) async {
      final controller = GlassController(quality: GlassQuality.full);

      await tester.pumpWidget(
        GlassScope(
          controller: controller,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: GlassSurface(child: Text('Filtered Surface')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      final expectedFilter = ImageFilter.compose(
        outer: const ColorFilter.matrix(<double>[
          1.3935, -0.3575, -0.0360, 0.0, 0.0,
          -0.1065, 1.1425, -0.0360, 0.0, 0.0,
          -0.1065, -0.3575, 1.4640, 0.0, 0.0,
          0.0, 0.0, 0.0, 1.0, 0.0,
        ]),
        inner: ImageFilter.blur(sigmaX: 30.0, sigmaY: 30.0),
      );

      expect(backdrop.filter, equals(expectedFilter));
    });

    testWidgets('GlassDensity.clear in full mode applies blur sigma 22', (
      tester,
    ) async {
      final controller = GlassController(quality: GlassQuality.full);

      await tester.pumpWidget(
        GlassScope(
          controller: controller,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: GlassSurface(
              density: GlassDensity.clear,
              child: Text('Clear Surface'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final backdrop =
          tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      final expectedFilter = ImageFilter.compose(
        outer: const ColorFilter.matrix(<double>[
          1.3935, -0.3575, -0.0360, 0.0, 0.0,
          -0.1065, 1.1425, -0.0360, 0.0, 0.0,
          -0.1065, -0.3575, 1.4640, 0.0, 0.0,
          0.0, 0.0, 0.0, 1.0, 0.0,
        ]),
        inner: ImageFilter.blur(sigmaX: 22.0, sigmaY: 22.0),
      );

      expect(backdrop.filter, equals(expectedFilter));
    });

    testWidgets('GlassDensity.clear in light mode builds Container with 0.45 alpha gradient', (
      tester,
    ) async {
      final controller = GlassController(quality: GlassQuality.light);

      await tester.pumpWidget(
        GlassScope(
          controller: controller,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: GlassSurface(
              density: GlassDensity.clear,
              child: Text('Light Clear Surface'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final surfaceContainer = containers.firstWhere(
        (c) => c.decoration is BoxDecoration && (c.decoration as BoxDecoration).gradient != null,
      );
      final gradient = (surfaceContainer.decoration as BoxDecoration).gradient as LinearGradient;
      expect(gradient.colors[0], equals(const Color.fromRGBO(52, 50, 62, 0.45)));
      expect(gradient.colors[1], equals(const Color.fromRGBO(32, 31, 40, 0.45)));
    });
  });
}
