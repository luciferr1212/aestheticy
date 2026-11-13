import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/ui/now_playing/metadata_link.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';

void main() {
  group('MetadataLink & MetadataNavHelper (S5)', () {
    testWidgets(
      'Non-interactive MetadataLink renders plain text without mouse cursor or underline',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MetadataLink(
                text: 'Unknown Artist',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                onTap: null,
              ),
            ),
          ),
        );

        expect(find.text('Unknown Artist'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MetadataLink),
            matching: find.byType(Focus),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(MetadataLink),
            matching: find.byType(MouseRegion),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Interactive MetadataLink has click cursor, hover underline, and keyboard trigger',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        var tapped = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MetadataLink(
                text: 'Daft Punk',
                style: const TextStyle(fontSize: 14, color: Colors.white),
                onTap: () => tapped++,
              ),
            ),
          ),
        );

        expect(find.text('Daft Punk'), findsOneWidget);
        final focusFinder = find.descendant(
          of: find.byType(MetadataLink),
          matching: find.byType(Focus),
        );
        expect(focusFinder, findsOneWidget);

        final mouseRegionFinder = find.descendant(
          of: find.byType(MetadataLink),
          matching: find.byType(MouseRegion),
        );
        expect(mouseRegionFinder, findsOneWidget);
        final mouseRegion = tester.widget<MouseRegion>(mouseRegionFinder);
        expect(mouseRegion.cursor, equals(SystemMouseCursors.click));

        // Hover test
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: tester.getCenter(find.text('Daft Punk')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        final textStyleWidget = tester.widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byType(MetadataLink),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        );
        expect(textStyleWidget.style.decoration, equals(TextDecoration.underline));

        // Tap test
        await tester.tap(find.text('Daft Punk'));
        await tester.pump();
        expect(tapped, equals(1));

        // Keyboard trigger: focus the MetadataLink and press Enter
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(tapped, equals(2));

        // Keyboard trigger: Space
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(tapped, equals(3));
      },
    );

    testWidgets(
      'MetadataNavHelper.openAlbum navigates directly or exits full screen first',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final navigator = AppNavigator(initialDestination: AppDestination.nowPlaying);

        // Empty album does not navigate
        MetadataNavHelper.openAlbum(navigator: navigator, albumTitle: '   ');
        expect(navigator.current, equals(AppDestination.nowPlaying));

        // Normal album navigates to album detail
        MetadataNavHelper.openAlbum(
          navigator: navigator,
          albumTitle: 'Discovery',
        );
        expect(navigator.current, equals(AppDestination.albumDetail));
        expect(navigator.selectedAlbumId, equals('Discovery'));

        // leaveFullScreenFirst calls goBack first
        navigator.openFullScreen();
        expect(navigator.current, equals(AppDestination.fullScreen));

        MetadataNavHelper.openAlbum(
          navigator: navigator,
          albumTitle: 'Random Access Memories',
          leaveFullScreenFirst: true,
        );
        expect(navigator.current, equals(AppDestination.albumDetail));
        expect(navigator.selectedAlbumId, equals('Random Access Memories'));
      },
    );

    testWidgets(
      'MetadataNavHelper.openArtist navigates single artist directly',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final navigator = AppNavigator();

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    MetadataNavHelper.openArtist(
                      context: context,
                      navigator: navigator,
                      rawArtist: 'Daft Punk',
                    );
                  },
                  child: const Text('Open Artist'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Open Artist'));
        await tester.pump();

        expect(navigator.current, equals(AppDestination.artistDetail));
        expect(navigator.selectedArtist?.name, equals('Daft Punk'));
      },
    );

    testWidgets(
      'MetadataNavHelper.openArtist displays disambiguation menu for multiple artists',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final navigator = AppNavigator();

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    MetadataNavHelper.openArtist(
                      context: context,
                      navigator: navigator,
                      rawArtist: 'Daft Punk feat. Pharrell Williams',
                    );
                  },
                  child: const Text('Open Collab'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Open Collab'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        // Popup menu should be displayed showing both artists
        expect(find.text('Daft Punk'), findsOneWidget);
        expect(find.text('Pharrell Williams'), findsOneWidget);

        // Tap Pharrell Williams in the menu
        await tester.tap(find.text('Pharrell Williams'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(navigator.current, equals(AppDestination.artistDetail));
        expect(navigator.selectedArtist?.name, equals('Pharrell Williams'));
      },
    );
  });
}
