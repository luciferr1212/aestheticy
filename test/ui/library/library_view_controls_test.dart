import 'dart:io';

import 'package:aestheticy/ui/glass/glass_surface.dart';
import 'package:aestheticy/ui/library/library_view_controls.dart';
import 'package:aestheticy/ui/library/sort_direction_button.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LibraryViewControls & Settings Migration (S7)', () {
    late Directory tempDir;
    late SettingsStore settingsStore;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('library_view_controls_test_');
      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();
    });

    tearDown(() {
      settingsStore.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('AppSettings migration: libraryViewMode migrates to albums view mode and preserves old files', () {
      final oldJson = {
        'libraryViewMode': 'wide',
      };
      final settings = AppSettings.fromJson(oldJson);
      expect(settings.libraryViewMode, equals('wide'));
      expect(settings.artistsViewMode, equals('circle'));
      expect(settings.playlistsViewMode, equals('square'));
    });

    Widget buildHarness({
      required List<String> allowedShapes,
      String? currentShape,
      ValueChanged<String>? onShapeChanged,
      required List<String> sortOptions,
      required String currentSort,
      required ValueChanged<String> onSortChanged,
      required SortDirection sortDirection,
      required ValueChanged<SortDirection> onSortDirectionChanged,
      bool reduceMotion = false,
      TextDirection textDirection = TextDirection.ltr,
    }) {
      return MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: textDirection,
          child: Scaffold(
            body: Center(
              child: LibraryViewControls(
                allowedShapes: allowedShapes,
                currentShape: currentShape,
                onShapeChanged: onShapeChanged,
                sortOptions: sortOptions,
                currentSort: currentSort,
                onSortChanged: onSortChanged,
                sortDirection: sortDirection,
                onSortDirectionChanged: onSortDirectionChanged,
                reduceMotion: reduceMotion,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'renders only allowed shapes for Albums: square, wide, list',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        String shape = 'square';
        await tester.pumpWidget(
          buildHarness(
            allowedShapes: const ['square', 'wide', 'list'],
            currentShape: shape,
            onShapeChanged: (s) => shape = s,
            sortOptions: const ['title', 'artist', 'year'],
            currentSort: 'title',
            onSortChanged: (_) {},
            sortDirection: SortDirection.ascending,
            onSortDirectionChanged: (_) {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('view_mode_square')), findsOneWidget);
        expect(find.byKey(const Key('view_mode_wide')), findsOneWidget);
        expect(find.byKey(const Key('view_mode_list')), findsOneWidget);
        expect(find.byKey(const Key('view_mode_circle')), findsNothing);

        // Tap wide
        await tester.tap(find.byKey(const Key('view_mode_wide')));
        expect(shape, equals('wide'));
      },
    );

    testWidgets(
      'renders only allowed shapes for Artists: circle, square, list',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          buildHarness(
            allowedShapes: const ['circle', 'square', 'list'],
            currentShape: 'circle',
            onShapeChanged: (_) {},
            sortOptions: const ['name', 'mostSongs', 'mostAlbums'],
            currentSort: 'name',
            onSortChanged: (_) {},
            sortDirection: SortDirection.ascending,
            onSortDirectionChanged: (_) {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('view_mode_circle')), findsOneWidget);
        expect(find.byKey(const Key('view_mode_square')), findsOneWidget);
        expect(find.byKey(const Key('view_mode_list')), findsOneWidget);
        expect(find.byKey(const Key('view_mode_wide')), findsNothing);
      },
    );

    testWidgets(
      'renders no shape switcher when allowedShapes is empty (Tracks/Favorites/Recent)',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          buildHarness(
            allowedShapes: const [],
            sortOptions: const ['title', 'artist', 'duration'],
            currentSort: 'title',
            onSortChanged: (_) {},
            sortDirection: SortDirection.ascending,
            onSortDirectionChanged: (_) {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('view_mode_square')), findsNothing);
        expect(find.byKey(const Key('view_mode_circle')), findsNothing);
        expect(find.byKey(const Key('sort_button')), findsOneWidget);
        expect(find.byKey(const Key('sort_direction_button')), findsOneWidget);
      },
    );

    testWidgets(
      'sliding selection indicator respects reduceMotion duration',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          buildHarness(
            allowedShapes: const ['square', 'wide', 'list'],
            currentShape: 'square',
            sortOptions: const ['title'],
            currentSort: 'title',
            onSortChanged: (_) {},
            sortDirection: SortDirection.ascending,
            onSortDirectionChanged: (_) {},
            reduceMotion: true,
          ),
        );
        await tester.pumpAndSettle();

        final animatedPos = tester.widget<AnimatedPositionedDirectional>(
          find.byType(AnimatedPositionedDirectional),
        );
        expect(animatedPos.duration, equals(Duration.zero));
      },
    );

    testWidgets(
      'renders in RTL without layout overflows',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1000, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildHarness(
            allowedShapes: const ['circle', 'square', 'list'],
            currentShape: 'circle',
            sortOptions: const ['name', 'mostSongs', 'mostAlbums', 'recentlyAdded'],
            currentSort: 'name',
            onSortChanged: (_) {},
            sortDirection: SortDirection.ascending,
            onSortDirectionChanged: (_) {},
            textDirection: TextDirection.rtl,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(GlassSurface), findsOneWidget);
      },
    );
  });
}
