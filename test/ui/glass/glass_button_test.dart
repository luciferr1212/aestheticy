import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/ui/glass/glass_button.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';

void main() {
  group('GlassIconButton Widget Tests', () {
    testWidgets('renders semantic label, tooltip and states', (tester) async {
      int pressCount = 0;
      final controller = GlassController(quality: GlassQuality.light);

      await tester.pumpWidget(
        MaterialApp(
          home: GlassScope(
            controller: controller,
            child: Scaffold(
              body: Center(
                child: GlassIconButton(
                  icon: Icons.play_arrow,
                  tooltip: 'Play',
                  semanticLabel: 'Play Track',
                  variant: GlassButtonVariant.primary,
                  onPressed: () => pressCount++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Semantics present
      expect(
        find.bySemanticsLabel('Play Track'),
        findsOneWidget,
      );

      // Tooltip present
      expect(find.byTooltip('Play'), findsOneWidget);

      // Verify primary variant fill is translucent (alpha < 255)
      final animatedContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decoration = animatedContainer.decoration! as BoxDecoration;
      expect(decoration.color!.a, lessThan(1.0));

      // Tap triggers callback
      await tester.tap(find.byType(GlassIconButton));
      await tester.pumpAndSettle();
      expect(pressCount, equals(1));
    });

    testWidgets('disabled button does not trigger callback and has 40% opacity', (
      tester,
    ) async {
      final controller = GlassController(quality: GlassQuality.light);

      await tester.pumpWidget(
        MaterialApp(
          home: GlassScope(
            controller: controller,
            child: const Scaffold(
              body: Center(
                child: GlassIconButton(
                  icon: Icons.skip_next,
                  tooltip: 'Next',
                  semanticLabel: 'Next Track',
                  onPressed: null, // Disabled
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final opacityFinder = find.byType(Opacity);
      expect(opacityFinder, findsOneWidget);
      final opacityWidget = tester.widget<Opacity>(opacityFinder);
      expect(opacityWidget.opacity, equals(0.40));

      // Tapping disabled does nothing
      await tester.tap(find.byType(GlassIconButton));
      await tester.pumpAndSettle();
    });

    testWidgets('hover and pressed gesture states work', (tester) async {
      final controller = GlassController(quality: GlassQuality.light);

      await tester.pumpWidget(
        MaterialApp(
          home: GlassScope(
            controller: controller,
            child: Scaffold(
              body: Center(
                child: GlassIconButton(
                  icon: Icons.shuffle,
                  tooltip: 'Shuffle',
                  semanticLabel: 'Shuffle',
                  variant: GlassButtonVariant.selected,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Test hover gesture
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.byType(GlassIconButton)));
      await tester.pump(const Duration(milliseconds: 150));

      // Test press gesture
      final downPointer = await tester.press(find.byType(GlassIconButton));
      await tester.pump(const Duration(milliseconds: 150));
      await downPointer.up();
      await tester.pumpAndSettle();
    });

    testWidgets('GlassQuality.off renders solid fill with alpha 255', (
      tester,
    ) async {
      final controller = GlassController(quality: GlassQuality.off);

      await tester.pumpWidget(
        MaterialApp(
          home: GlassScope(
            controller: controller,
            child: Scaffold(
              body: Center(
                child: GlassIconButton(
                  icon: Icons.pause,
                  tooltip: 'Pause',
                  semanticLabel: 'Pause',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final animatedContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decoration = animatedContainer.decoration! as BoxDecoration;
      expect(decoration.color!.a, equals(1.0));
    });
  });

  group('GlassPillButton Widget Tests', () {
    testWidgets('renders label and leading icon with semantics', (tester) async {
      int pressCount = 0;
      final controller = GlassController(quality: GlassQuality.light);

      await tester.pumpWidget(
        MaterialApp(
          home: GlassScope(
            controller: controller,
            child: Scaffold(
              body: Center(
                child: GlassPillButton(
                  label: 'Add Folder',
                  leadingIcon: Icons.folder,
                  tooltip: 'Add new library folder',
                  onPressed: () => pressCount++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add Folder'), findsOneWidget);
      expect(find.byIcon(Icons.folder), findsOneWidget);
      expect(find.byTooltip('Add new library folder'), findsOneWidget);

      await tester.tap(find.byType(GlassPillButton));
      await tester.pumpAndSettle();
      expect(pressCount, equals(1));
    });
  });
}
