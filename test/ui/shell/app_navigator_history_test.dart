import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/settings/app_shortcuts.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppNavigator History Stack & Semantics', () {
    test('Initial destination is root: cannot go back or forward', () {
      final nav = AppNavigator(initialDestination: AppDestination.albums);
      expect(nav.current, AppDestination.albums);
      expect(nav.canGoBack, isFalse);
      expect(nav.canGoForward, isFalse);
      expect(nav.history.length, 1);
      expect(nav.historyIndex, 0);

      // goBack at root does nothing and returns false
      expect(nav.goBack(), isFalse);
      expect(nav.current, AppDestination.albums);
    });

    test('Forward and back history navigation', () {
      final nav = AppNavigator();
      nav.navigateTo(AppDestination.tracks);
      nav.navigateTo(AppDestination.artists);

      expect(nav.current, AppDestination.artists);
      expect(nav.canGoBack, isTrue);
      expect(nav.canGoForward, isFalse);
      expect(nav.history.length, 3);
      expect(nav.historyIndex, 2);

      // Go back to tracks
      expect(nav.goBack(), isTrue);
      expect(nav.current, AppDestination.tracks);
      expect(nav.canGoBack, isTrue);
      expect(nav.canGoForward, isTrue);

      // Go back to albums (root)
      expect(nav.goBack(), isTrue);
      expect(nav.current, AppDestination.albums);
      expect(nav.canGoBack, isFalse);
      expect(nav.canGoForward, isTrue);

      // Move forward to tracks
      expect(nav.goForward(), isTrue);
      expect(nav.current, AppDestination.tracks);

      // Move forward to artists
      expect(nav.goForward(), isTrue);
      expect(nav.current, AppDestination.artists);
      expect(nav.canGoForward, isFalse);
    });

    test('Pushing destination equal to current does nothing', () {
      final nav = AppNavigator();
      expect(nav.history.length, 1);

      nav.navigateTo(AppDestination.albums);
      expect(nav.history.length, 1);

      nav.openAlbumDetail('Abbey Road');
      expect(nav.history.length, 2);

      nav.openAlbumDetail('Abbey Road');
      expect(nav.history.length, 2);
    });

    test('Toggle back to previous destination suppresses duplicate pushes (treats as goBack)', () {
      final nav = AppNavigator();
      nav.openNowPlaying(); // index 1: nowPlaying
      nav.openLyrics(); // index 2: lyrics
      expect(nav.history.length, 3);
      expect(nav.current, AppDestination.lyrics);

      // User clicks Now Playing while on Lyrics (toggling back to previous)
      nav.openNowPlaying();
      expect(nav.current, AppDestination.nowPlaying);
      // Stack did not grow beyond 3; cursor moved back to 1
      expect(nav.historyIndex, 1);
      expect(nav.canGoForward, isTrue);
    });

    test('New branch drops forward history', () {
      final nav = AppNavigator();
      nav.navigateTo(AppDestination.tracks);
      nav.navigateTo(AppDestination.artists);
      nav.goBack(); // at tracks, artists is forward

      expect(nav.canGoForward, isTrue);

      // Navigating to playlists drops artists
      nav.navigateTo(AppDestination.playlists);
      expect(nav.current, AppDestination.playlists);
      expect(nav.canGoForward, isFalse);
      expect(nav.history.map((e) => e.destination).toList(), [
        AppDestination.albums,
        AppDestination.tracks,
        AppDestination.playlists,
      ]);
    });

    test('50-entry cap drops oldest', () {
      final nav = AppNavigator();
      for (var i = 0; i < 65; i++) {
        nav.openAlbumDetail('Album $i');
      }

      expect(nav.history.length, AppNavigator.kMaxHistory);
      expect(nav.history.length, 50);
      expect(nav.historyIndex, 49);
      expect(nav.selectedAlbumId, 'Album 64');
      // The oldest entries (Album 0 .. Album 14) were dropped
      expect(nav.history.first.albumId, 'Album 15');
    });

    test('Full screen exit returns to whatever screen was open before full screen', () {
      final nav = AppNavigator();
      nav.openArtistDetail('Pink Floyd', artist: const ArtistSummary(name: 'Pink Floyd', albumCount: 5, trackCount: 50));
      expect(nav.current, AppDestination.artistDetail);
      expect(nav.selectedArtistId, 'Pink Floyd');

      // Enter full screen
      nav.openFullScreen();
      expect(nav.current, AppDestination.fullScreen);

      // Exit full screen via toggleFullScreen
      nav.toggleFullScreen();
      expect(nav.current, AppDestination.artistDetail);
      expect(nav.selectedArtistId, 'Pink Floyd');
    });
  });

  group('Mouse & Shortcut Navigation Widgets', () {
    testWidgets(
      'Mouse back and forward buttons navigate history',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final nav = AppNavigator();
        nav.navigateTo(AppDestination.tracks);
        nav.navigateTo(AppDestination.playlists);

        await tester.pumpWidget(
          MaterialApp(
            home: Listener(
              onPointerDown: (event) {
                if ((event.buttons & kBackMouseButton) != 0) {
                  if (nav.canGoBack) nav.goBack();
                } else if ((event.buttons & kForwardMouseButton) != 0) {
                  if (nav.canGoForward) nav.goForward();
                }
              },
              child: const Scaffold(body: Center(child: Text('Content'))),
            ),
          ),
        );

        expect(nav.current, AppDestination.playlists);

        // Click mouse back button (button 4 / kBackMouseButton)
        final center = tester.getCenter(find.text('Content'));
        await tester.sendEventToBinding(
          PointerDownEvent(
            position: center,
            kind: PointerDeviceKind.mouse,
            buttons: kBackMouseButton,
          ),
        );
        await tester.sendEventToBinding(
          PointerUpEvent(
            position: center,
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pumpAndSettle();

        expect(nav.current, AppDestination.tracks);

        // Click mouse forward button (button 5 / kForwardMouseButton)
        await tester.sendEventToBinding(
          PointerDownEvent(
            position: center,
            kind: PointerDeviceKind.mouse,
            buttons: kForwardMouseButton,
          ),
        );
        await tester.sendEventToBinding(
          PointerUpEvent(
            position: center,
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pumpAndSettle();

        expect(nav.current, AppDestination.playlists);
      },
    );

    testWidgets(
      'Alt+Left and Alt+Right navigate back and forward',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final nav = AppNavigator();
        nav.navigateTo(AppDestination.tracks);
        nav.navigateTo(AppDestination.artists);

        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        KeyEventResult handleKey(FocusNode node, KeyEvent event) {
          final isAlt = HardwareKeyboard.instance.isAltPressed ||
              HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altLeft) ||
              HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altRight);
          if (isAlt && (event is KeyDownEvent || event is KeyRepeatEvent)) {
            if (isArrowLeftKey(event)) {
              if (nav.canGoBack) {
                nav.goBack();
                return KeyEventResult.handled;
              }
            } else if (isArrowRightKey(event)) {
              if (nav.canGoForward) {
                nav.goForward();
                return KeyEventResult.handled;
              }
            }
          }
          return KeyEventResult.ignored;
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Focus(
              focusNode: focusNode,
              autofocus: true,
              onKeyEvent: handleKey,
              child: const Scaffold(body: SizedBox.expand()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(nav.current, AppDestination.artists);

        // Press Alt+Left
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();

        expect(nav.current, AppDestination.tracks);

        // Press Alt+Right
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();

        expect(nav.current, AppDestination.artists);
      },
    );

    testWidgets(
      'View state scroll offset is preserved across navigation',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final nav = AppNavigator();

        await tester.pumpWidget(
          MaterialApp(
            home: AnimatedBuilder(
              animation: nav,
              builder: (context, _) {
                if (nav.current == AppDestination.tracks) {
                  return const Scaffold(body: Text('Tracks View'));
                }
                return _TestRestorerView(
                  key: ValueKey('view_${nav.currentEntry.id}'),
                  entry: nav.currentEntry,
                  navigator: nav,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Scroll the list down
        final scrollableFinder = find.byType(Scrollable);
        expect(scrollableFinder, findsOneWidget);
        await tester.drag(scrollableFinder, const Offset(0, -300));
        await tester.pumpAndSettle();

        // Offset should be ~300
        final initialOffset = tester.state<ScrollableState>(scrollableFinder).position.pixels;
        expect(initialOffset, greaterThan(200));

        // Navigate away to tracks
        nav.navigateTo(AppDestination.tracks);
        await tester.pumpAndSettle();
        expect(find.text('Tracks View'), findsOneWidget);

        // Navigate back to albums
        nav.goBack();
        await tester.pumpAndSettle();

        // Verify the offset was restored
        final restoredOffset = tester.state<ScrollableState>(scrollableFinder).position.pixels;
        expect(restoredOffset, equals(initialOffset));
      },
    );
  });
}

class _TestRestorerView extends StatefulWidget {
  final NavEntry entry;
  final AppNavigator navigator;

  const _TestRestorerView({
    super.key,
    required this.entry,
    required this.navigator,
  });

  @override
  State<_TestRestorerView> createState() => _TestRestorerViewState();
}

class _TestRestorerViewState extends State<_TestRestorerView> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    final savedOffset =
        (widget.entry.viewState['scrollOffset'] as num?)?.toDouble() ?? 0.0;
    _scrollController = ScrollController(initialScrollOffset: savedOffset);
    widget.navigator.onCaptureViewState = (state) {
      if (_scrollController.hasClients) {
        state['scrollOffset'] = _scrollController.offset;
      }
    };
  }

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      widget.entry.viewState['scrollOffset'] = _scrollController.offset;
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PrimaryScrollController(
        controller: _scrollController,
        child: ListView.builder(
          itemCount: 100,
          itemExtent: 50,
          itemBuilder: (context, i) => Text('Item $i'),
        ),
      ),
    );
  }
}
