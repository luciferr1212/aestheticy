import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/library/albums_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/settings/settings_view.dart';
import 'package:aestheticy/ui/shell/ambient_background.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import 'package:aestheticy/ui/theme/dither_noise.dart';

void main() {
  group('DitherNoise & DitherOverlay (HOTFIX 5H)', () {
    test('(a) every tile pixel has r, g, b <= a and a <= 12, and the average alpha is under 6 of 255', () {
      final bytes = generateDitherNoiseBytes(width: 128, height: 128, seed: 42);
      expect(bytes.length, equals(128 * 128 * 4));

      var totalAlpha = 0;
      var hasWhite = false;
      var hasBlack = false;

      for (var i = 0; i < bytes.length; i += 4) {
        final r = bytes[i];
        final g = bytes[i + 1];
        final b = bytes[i + 2];
        final a = bytes[i + 3];

        expect(r, lessThanOrEqualTo(a), reason: 'Premultiplied Red exceeds Alpha at index $i');
        expect(g, lessThanOrEqualTo(a), reason: 'Premultiplied Green exceeds Alpha at index $i');
        expect(b, lessThanOrEqualTo(a), reason: 'Premultiplied Blue exceeds Alpha at index $i');
        expect(a, lessThanOrEqualTo(12), reason: 'Alpha exceeds 12 at index $i');
        expect(a, lessThanOrEqualTo(10), reason: 'Alpha exceeds maximum 10 at index $i');

        totalAlpha += a;
        if (a > 0 && r == a && g == a && b == a) {
          hasWhite = true;
        }
        if (a > 0 && r == 0 && g == 0 && b == 0) {
          hasBlack = true;
        }
      }

      final avgAlpha = totalAlpha / (128 * 128);
      expect(avgAlpha, lessThan(6.0), reason: 'Average alpha must be under 6 of 255');
      expect(hasWhite, isTrue, reason: 'Tile must contain white dither specks (r = g = b = a)');
      expect(hasBlack, isTrue, reason: 'Tile must contain black-ish dither specks (r = g = b = 0)');
    });

    test('(b) the tile is deterministic', () async {
      final bytes1 = generateDitherNoiseBytes(width: 128, height: 128, seed: 42);
      final bytes2 = generateDitherNoiseBytes(width: 128, height: 128, seed: 42);
      expect(bytes1, equals(bytes2));

      DitherNoise.resetForTest();
      final image1 = await DitherNoise.image;
      final image2 = await DitherNoise.image;

      expect(image1.width, equals(128));
      expect(image1.height, equals(128));
      expect(identical(image1, image2), isTrue);
    });

    testWidgets('(e) glass quality Off paints no overlay', (tester) async {
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

      final sizedBoxFinder = find.descendant(
        of: find.byType(DitherOverlay),
        matching: find.byType(SizedBox),
      );
      expect(sizedBoxFinder, findsOneWidget);
      final sizedBox = tester.widget<SizedBox>(sizedBoxFinder);
      expect(sizedBox.width, equals(0.0));
      expect(sizedBox.height, equals(0.0));

      // No CustomPaint/DitherPainter is painted when quality is off
      expect(
        find.descendant(
          of: find.byType(DitherOverlay),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    for (final quality in [GlassQuality.full, GlassQuality.light]) {
      group('Glass quality ${quality.name}', () {
        late FakeAudioEngine engine;
        late PlaybackQueue queue;
        late PlaybackController controller;
        late SqliteLibraryRepository repository;
        late ScanService scanService;
        late SettingsStore settingsStore;
        late GlassController glassController;
        late AppNavigator navigator;

        setUp(() async {
          engine = FakeAudioEngine();
          await engine.init();
          queue = PlaybackQueue();
          controller = PlaybackController(engine: engine, queue: queue);
          await controller.init();
          repository = SqliteLibraryRepository.inMemory();
          await repository.addFolder('C:\\Music');
          scanService = ScanService(repository: repository);
          settingsStore = SettingsStore(
            initialSettings: AppSettings(
              language: 'en',
              glassQuality: quality,
            ),
          );
          glassController = GlassController(quality: quality);
          settingsStore.bindGlassController(glassController);
          navigator = AppNavigator();
        });

        tearDown(() async {
          settingsStore.dispose();
          scanService.dispose();
          await repository.close();
          await controller.dispose();
          await engine.dispose();
        });

        Widget buildApp() {
          return GlassScope(
            controller: glassController,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: AppShell(
                engine: engine,
                controller: controller,
                repository: repository,
                scanService: scanService,
                settingsStore: settingsStore,
                navigator: navigator,
              ),
            ),
          );
        }

        testWidgets(
          '(c) Settings, Albums, and Home have no DitherOverlay above content and content comes after it in z-order',
          (tester) async {
            tester.view.physicalSize = const Size(1280, 800);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(() {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
            });

            for (final destination in [
              AppDestination.settings,
              AppDestination.albums,
              AppDestination.tracks, // Home / default
            ]) {
              navigator.navigateTo(destination);
              await tester.pumpWidget(buildApp());
              await tester.pumpAndSettle();

              // 1. DitherOverlay exists exactly once, inside AmbientBackground
              expect(
                find.descendant(
                  of: find.byType(AmbientBackground),
                  matching: find.byType(DitherOverlay),
                ),
                findsOneWidget,
                reason: 'DitherOverlay must be a descendant of AmbientBackground for ${destination.name}',
              );

              // 2. No DitherOverlay inside page content (SettingsView, AlbumsView, etc.)
              if (destination == AppDestination.settings) {
                expect(
                  find.descendant(
                    of: find.byType(SettingsView),
                    matching: find.byType(DitherOverlay),
                  ),
                  findsNothing,
                  reason: 'SettingsView must not contain DitherOverlay',
                );
              } else if (destination == AppDestination.albums) {
                expect(
                  find.descendant(
                    of: find.byType(AlbumsView),
                    matching: find.byType(DitherOverlay),
                  ),
                  findsNothing,
                  reason: 'AlbumsView must not contain DitherOverlay',
                );
              }

              // 3. AmbientBackground is at index 0 of the Scaffold Stack, and content comes after it in z-order
              final stackFinder = find.ancestor(
                of: find.byType(AmbientBackground),
                matching: find.byType(Stack),
              ).first;
              final stack = tester.widget<Stack>(stackFinder);
              final bgIndex = stack.children.indexWhere(
                (c) => c is Positioned && c.child is AmbientBackground,
              );
              expect(bgIndex, equals(0), reason: 'AmbientBackground must be at base index 0');
              expect(stack.children.length, greaterThan(1), reason: 'Content widgets must come after background layer in z-order');
            }
          },
        );

        testWidgets(
          '(d) Settings page shows its sections and has no widget with a bright opaque fill covering them',
          (tester) async {
            tester.view.physicalSize = const Size(1280, 800);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(() {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
            });

            navigator.navigateTo(AppDestination.settings);
            await tester.pumpWidget(buildApp());
            await tester.pumpAndSettle();

            // Find section titles
            expect(find.text('Language and profile'), findsOneWidget);
            expect(find.text('Appearance'), findsOneWidget);

            // Assert that no widget in SettingsView has a bright opaque fill (which caused gray block)
            final settingsViewFinder = find.byType(SettingsView);
            expect(settingsViewFinder, findsOneWidget);

            final containers = tester.widgetList<Container>(
              find.descendant(of: settingsViewFinder, matching: find.byType(Container)),
            );
            for (final container in containers) {
              final decoration = container.decoration;
              if (decoration is BoxDecoration && decoration.color != null) {
                final color = decoration.color!;
                final isBrightOpaque = color.a > 0.95 &&
                    (color.r > 0.7 && color.g > 0.7 && color.b > 0.7);
                expect(
                  isBrightOpaque,
                  isFalse,
                  reason: 'Found unexpected bright opaque fill $color inside SettingsView',
                );
              }
            }

            // Verify section title is hit-testable and visible
            expect(find.text('Language and profile').hitTestable(), findsOneWidget);
          },
        );
      });
    }
  });
}
