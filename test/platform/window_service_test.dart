import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/platform/window_service.dart';

void main() {
  group('WindowGeometry Value Class Tests', () {
    test('value class equality and hashCode', () {
      const g1 = WindowGeometry(
        position: Offset(100, 150),
        size: Size(800, 600),
        isMaximized: false,
        isFullScreen: false,
      );
      const g2 = WindowGeometry(
        position: Offset(100, 150),
        size: Size(800, 600),
        isMaximized: false,
        isFullScreen: false,
      );
      const g3 = WindowGeometry(
        position: Offset(200, 150),
        size: Size(800, 600),
        isMaximized: false,
        isFullScreen: false,
      );

      expect(g1, equals(g2));
      expect(g1.hashCode, equals(g2.hashCode));
      expect(g1 == g3, isFalse);
      expect(g1.toString(), contains('pos: Offset(100.0, 150.0)'));
    });

    test('copyWith updates specified fields only', () {
      const g = WindowGeometry(
        position: Offset(10, 20),
        size: Size(500, 400),
        isMaximized: false,
        isFullScreen: false,
      );

      final modified = g.copyWith(
        isMaximized: true,
        position: const Offset(30, 40),
      );

      expect(modified.position, const Offset(30, 40));
      expect(modified.size, const Size(500, 400));
      expect(modified.isMaximized, isTrue);
      expect(modified.isFullScreen, isFalse);
    });
  });

  group('FakeWindowService Call Recording Tests', () {
    test('records all calls in exact sequential order', () async {
      final fake = FakeWindowService(
        initialGeometry: const WindowGeometry(
          position: Offset(50, 50),
          size: Size(1024, 768),
          isMaximized: false,
          isFullScreen: false,
        ),
        displaySizeProvider: () => const Size(2560, 1440),
      );

      final initial = await fake.getGeometry();
      expect(initial.size, const Size(1024, 768));

      await fake.setResizable(false);
      await fake.applyGeometry(const Offset(200, 300), const Size(480, 170));
      await fake.setAlwaysOnTop(true);
      await fake.setFullScreen(true);
      await fake.maximize();
      await fake.unmaximize();
      final display = await fake.getDisplaySize();
      expect(display, const Size(2560, 1440));

      expect(fake.calls, [
        'getGeometry',
        'setResizable(false)',
        'applyGeometry(pos: Offset(200.0, 300.0), size: Size(480.0, 170.0))',
        'setAlwaysOnTop(true)',
        'setFullScreen(true)',
        'maximize',
        'unmaximize',
        'getDisplaySize',
      ]);
    });
  });
}
