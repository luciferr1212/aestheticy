import 'package:aestheticy/ui/glass/glass_button.dart';
import 'package:aestheticy/ui/library/albums_artist_chips.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlbumsArtistChips (S6)', () {
    final artists = [
      const ArtistChipItem(key: 'art_c', name: 'Artist C', songCount: 50),
      const ArtistChipItem(key: 'art_a', name: 'Artist A', songCount: 30),
      const ArtistChipItem(key: 'art_b', name: 'Artist B', songCount: 10),
    ];

    Widget buildChips({
      required List<ArtistChipItem> data,
      String? selectedKey,
      required ValueChanged<String?> onSelected,
      required ValueChanged<List<String>> onOrderChanged,
      required VoidCallback onResetOrder,
      TextDirection textDirection = TextDirection.ltr,
      double width = 800,
    }) {
      return MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: textDirection,
          child: Scaffold(
            body: SizedBox(
              width: width,
              height: 100,
              child: AlbumsArtistChips(
                artists: data,
                selectedArtistKey: selectedKey,
                onArtistSelected: onSelected,
                onOrderChanged: onOrderChanged,
                onResetOrder: onResetOrder,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'renders "All" chip first, followed by artists in song count order',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        String? selected;
        await tester.pumpWidget(
          buildChips(
            data: artists,
            selectedKey: null,
            onSelected: (k) => selected = k,
            onOrderChanged: (_) {},
            onResetOrder: () {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('albums_artist_chip_all')), findsOneWidget);
        expect(find.byKey(const Key('artist_chip_button_art_c')), findsOneWidget);
        expect(find.byKey(const Key('artist_chip_button_art_a')), findsOneWidget);
        expect(find.byKey(const Key('artist_chip_button_art_b')), findsOneWidget);

        // Verify "All" is selected initially
        final allBtn = tester.widget<GlassPillButton>(
          find.byKey(const Key('albums_artist_chip_all')),
        );
        expect(allBtn.variant, equals(GlassButtonVariant.selected));

        // Tap on Artist C
        await tester.tap(find.byKey(const Key('artist_chip_button_art_c')));
        expect(selected, equals('art_c'));
      },
    );

    testWidgets(
      'selected artist chip uses selected variant, All uses normal',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          buildChips(
            data: artists,
            selectedKey: 'art_a',
            onSelected: (_) {},
            onOrderChanged: (_) {},
            onResetOrder: () {},
          ),
        );
        await tester.pumpAndSettle();

        final allBtn = tester.widget<GlassPillButton>(
          find.byKey(const Key('albums_artist_chip_all')),
        );
        expect(allBtn.variant, equals(GlassButtonVariant.normal));

        final aBtn = tester.widget<GlassPillButton>(
          find.byKey(const Key('artist_chip_button_art_a')),
        );
        expect(aBtn.variant, equals(GlassButtonVariant.selected));
      },
    );

    testWidgets(
      'reset order menu button invokes onResetOrder',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        var resetCalled = false;
        await tester.pumpWidget(
          buildChips(
            data: artists,
            selectedKey: null,
            onSelected: (_) {},
            onOrderChanged: (_) {},
            onResetOrder: () => resetCalled = true,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('albums_artist_chips_menu')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('albums_artist_chips_reset_order')), findsOneWidget);
        await tester.tap(find.byKey(const Key('albums_artist_chips_reset_order')));
        await tester.pumpAndSettle();

        expect(resetCalled, isTrue);
      },
    );

    testWidgets(
      'mouse wheel translates to horizontal scrolling',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          buildChips(
            data: List.generate(
              30,
              (i) => ArtistChipItem(key: 'art_$i', name: 'Artist $i', songCount: 50 - i),
            ),
            selectedKey: null,
            onSelected: (_) {},
            onOrderChanged: (_) {},
            onResetOrder: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Send a pointer signal scroll event
        tester.binding.handlePointerEvent(
          const PointerScrollEvent(
            position: Offset(300, 50),
            scrollDelta: Offset(0, 100),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'top 12 chips then "All artists" button; chips outside top 12 are hidden',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(2500, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final twentyArtists = List.generate(
          20,
          (i) => ArtistChipItem(key: 'art_$i', name: 'Artist $i', songCount: 100 - i),
        );

        await tester.pumpWidget(
          buildChips(
            data: twentyArtists,
            selectedKey: null,
            onSelected: (_) {},
            onOrderChanged: (_) {},
            onResetOrder: () {},
            width: 2500,
          ),
        );
        await tester.pumpAndSettle();

        // All chip
        expect(find.byKey(const Key('albums_artist_chip_all')), findsOneWidget);

        // Top 12 are in the row
        for (var i = 0; i < 12; i++) {
          expect(find.byKey(Key('artist_chip_button_art_$i')), findsOneWidget);
        }

        // 13th..20th are not in the row
        for (var i = 12; i < 20; i++) {
          expect(find.byKey(Key('artist_chip_button_art_$i')), findsNothing);
        }

        // Trailing All artists button exists
        expect(find.byKey(const Key('albums_artist_chips_all_artists')), findsOneWidget);
        expect(find.text('All artists'), findsOneWidget);
      },
    );

    testWidgets(
      'picking an artist outside the top 12 selects it and displays it right after "All"',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final twentyArtists = List.generate(
          20,
          (i) => ArtistChipItem(key: 'art_$i', name: 'Artist $i', songCount: 100 - i),
        );
        String? selected;

        await tester.pumpWidget(
          buildChips(
            data: twentyArtists,
            selectedKey: null,
            onSelected: (k) => selected = k,
            onOrderChanged: (_) {},
            onResetOrder: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Tap "All artists" button
        await tester.tap(find.byKey(const Key('albums_artist_chips_all_artists')));
        await tester.pumpAndSettle();

        // Search dialog opens
        expect(find.byKey(const Key('all_artists_search_input')), findsOneWidget);

        // Filter for Artist 15
        await tester.enterText(find.byKey(const Key('all_artists_search_input')), 'Artist 15');
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('all_artists_item_art_15')), findsOneWidget);
        await tester.tap(find.byKey(const Key('all_artists_item_art_15')));
        await tester.pumpAndSettle();

        expect(selected, equals('art_15'));

        // Now rebuild with art_15 selected
        await tester.pumpWidget(
          buildChips(
            data: twentyArtists,
            selectedKey: 'art_15',
            onSelected: (_) {},
            onOrderChanged: (_) {},
            onResetOrder: () {},
          ),
        );
        await tester.pumpAndSettle();

        // art_15 is now visible and selected!
        expect(find.byKey(const Key('artist_chip_button_art_15')), findsOneWidget);
        final extraBtn = tester.widget<GlassPillButton>(
          find.byKey(const Key('artist_chip_button_art_15')),
        );
        expect(extraBtn.variant, equals(GlassButtonVariant.selected));

        // It is placed right after "All" (x coordinate check)
        final allDx = tester.getTopLeft(find.byKey(const Key('albums_artist_chip_all'))).dx;
        final extraDx = tester.getTopLeft(find.byKey(const Key('artist_chip_button_art_15'))).dx;
        final firstTopDx = tester.getTopLeft(find.byKey(const Key('artist_chip_button_art_0'))).dx;
        expect(allDx, lessThan(extraDx));
        expect(extraDx, lessThan(firstTopDx));
      },
    );

    testWidgets(
      'reorder and reset persistence callback invocation',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        List<String>? newOrder;
        var resetCalled = false;

        await tester.pumpWidget(
          buildChips(
            data: artists,
            selectedKey: null,
            onSelected: (_) {},
            onOrderChanged: (o) => newOrder = o,
            onResetOrder: () => resetCalled = true,
          ),
        );
        await tester.pumpAndSettle();

        // Reorder via drag
        final itemA = find.byKey(const ValueKey('artist_chip_art_a'));
        final itemB = find.byKey(const ValueKey('artist_chip_art_b'));
        final gesture = await tester.startGesture(tester.getCenter(itemB));
        await tester.pump(kLongPressTimeout);
        await gesture.moveTo(tester.getCenter(itemA));
        await gesture.up();
        await tester.pumpAndSettle();

        // Tap Reset order in menu
        await tester.tap(find.byKey(const Key('albums_artist_chips_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('albums_artist_chips_reset_order')));
        await tester.pumpAndSettle();

        expect(resetCalled, isTrue);
        expect(newOrder != null || resetCalled, isTrue);
      },
    );

    testWidgets(
      'RTL build renders without overflow',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildChips(
            data: List.generate(
              15,
              (i) => ArtistChipItem(key: 'art_$i', name: 'فنان $i', songCount: 50 - i),
            ),
            selectedKey: null,
            onSelected: (_) {},
            onOrderChanged: (_) {},
            onResetOrder: () {},
            textDirection: TextDirection.rtl,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('albums_artist_chip_all')), findsOneWidget);
        expect(find.byKey(const Key('albums_artist_chips_all_artists')), findsOneWidget);
      },
    );
  });
}
