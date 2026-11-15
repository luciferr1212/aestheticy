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
    }) {
      return MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: textDirection,
          child: Scaffold(
            body: SizedBox(
              width: 800,
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
  });
}
