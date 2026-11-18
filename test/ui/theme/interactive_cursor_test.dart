import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/glass/glass_button.dart';
import 'package:aestheticy/ui/library/track_table.dart';
import 'package:aestheticy/ui/now_playing/metadata_link.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/sidebar.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import 'package:aestheticy/ui/theme/interactive_cursor.dart';

void main() {
  group('Interactive Controls Mouse Cursors (S2)', () {
    Future<MouseCursor?> hoverAndGetCursor(
      WidgetTester tester,
      Finder finder,
    ) async {
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(finder));
      await tester.pump();
      final cursor =
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
      await gesture.removePointer();
      await tester.pump();
      return cursor;
    }

    testWidgets(
      'GlassIconButton shows click cursor when enabled and basic cursor when disabled',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Column(
                children: [
                  GlassIconButton(
                    key: const Key('btn_enabled'),
                    icon: Icons.play_arrow,
                    tooltip: 'Play',
                    semanticLabel: 'Play',
                    onPressed: () {},
                  ),
                  const GlassIconButton(
                    key: Key('btn_disabled'),
                    icon: Icons.pause,
                    tooltip: 'Pause',
                    semanticLabel: 'Pause',
                    onPressed: null,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final enabledCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('btn_enabled')),
        );
        expect(enabledCursor, equals(SystemMouseCursors.click));

        final disabledCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('btn_disabled')),
        );
        expect(disabledCursor, equals(SystemMouseCursors.basic));
      },
    );

    testWidgets(
      'GlassPillButton shows click cursor when enabled and basic cursor when disabled',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Column(
                children: [
                  GlassPillButton(
                    key: const Key('pill_enabled'),
                    label: 'Rock',
                    onPressed: () {},
                  ),
                  const GlassPillButton(
                    key: Key('pill_disabled'),
                    label: 'Pop',
                    onPressed: null,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final enabledCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('pill_enabled')),
        );
        expect(enabledCursor, equals(SystemMouseCursors.click));

        final disabledCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('pill_disabled')),
        );
        expect(disabledCursor, equals(SystemMouseCursors.basic));
      },
    );

    testWidgets(
      'Sidebar tiles show click cursor when enabled and basic cursor when disabled (isSoon)',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final navigator = AppNavigator();
        final settingsStore = SettingsStore(
          initialSettings: const AppSettings(sidebarCompact: false),
        );
        addTearDown(settingsStore.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: SizedBox(
                width: 208,
                child: Sidebar(
                  navigator: navigator,
                  settingsStore: settingsStore,
                  onOpenFolders: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final albumsTileCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('sidebar_albums')),
        );
        expect(albumsTileCursor, equals(SystemMouseCursors.click));

        await tester.ensureVisible(find.byKey(const Key('sidebar_last_fm')));
        await tester.pumpAndSettle();
        final soonTileCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('sidebar_last_fm')),
        );
        expect(soonTileCursor, equals(SystemMouseCursors.basic));
      },
    );

    testWidgets(
      'TrackTable row shows click cursor when interactive and basic cursor when non-interactive',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final now = DateTime.now();
        final track = Track(
          id: 1,
          folderId: 1,
          path: 'C:\\Music\\song.mp3',
          title: 'Aestheticy Song',
          artist: 'Artist',
          album: 'Album',
          durationMs: 180000,
          mtimeMs: 0,
          sizeBytes: 1024,
          addedAt: now,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    key: const Key('table_enabled'),
                    height: 100,
                    child: TrackTable(
                      rows: [TrackTableRow(track: track)],
                      onPlay: (_, _) {},
                    ),
                  ),
                  SizedBox(
                    key: const Key('table_disabled'),
                    height: 100,
                    child: TrackTable(
                      rows: [TrackTableRow(track: track)],
                      onPlay: null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rowEnabledFinder = find.descendant(
          of: find.byKey(const Key('table_enabled')),
          matching: find.byType(InkWell),
        );
        final enabledCursor = await hoverAndGetCursor(tester, rowEnabledFinder.first);
        expect(enabledCursor, equals(SystemMouseCursors.click));

        final rowDisabledFinder = find.descendant(
          of: find.byKey(const Key('table_disabled')),
          matching: find.byType(InkWell),
        );
        final disabledCursor = await hoverAndGetCursor(tester, rowDisabledFinder.first);
        expect(disabledCursor, equals(SystemMouseCursors.basic));
      },
    );

    testWidgets(
      'DragHandleCursor shows grab cursor on hover, grabbing when pressed, and basic when disabled',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(
              body: Column(
                children: [
                  DragHandleCursor(
                    key: Key('drag_enabled'),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.drag_indicator),
                    ),
                  ),
                  DragHandleCursor(
                    key: Key('drag_disabled'),
                    enabled: false,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.drag_indicator),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Hover on enabled drag handle -> grab cursor
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        await tester.pump();
        await gesture.moveTo(tester.getCenter(find.byKey(const Key('drag_enabled'))));
        await tester.pump();

        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          equals(SystemMouseCursors.grab),
        );

        // 2. Press down (dragging) -> grabbing cursor
        await gesture.down(tester.getCenter(find.byKey(const Key('drag_enabled'))));
        await tester.pump();

        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          equals(SystemMouseCursors.grabbing),
        );

        await gesture.up();
        await gesture.removePointer();
        await tester.pump();

        // 3. Hover on disabled drag handle -> basic cursor
        final disabledCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('drag_disabled')),
        );
        expect(disabledCursor, equals(SystemMouseCursors.basic));
      },
    );

    testWidgets(
      'MetadataLink shows click cursor when enabled and basic cursor when disabled (onTap null)',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Column(
                children: [
                  MetadataLink(
                    key: const Key('link_enabled'),
                    text: 'Daft Punk',
                    style: const TextStyle(),
                    onTap: () {},
                  ),
                  const MetadataLink(
                    key: Key('link_disabled'),
                    text: 'Unknown Artist',
                    style: TextStyle(),
                    onTap: null,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final enabledCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('link_enabled')),
        );
        expect(enabledCursor, equals(SystemMouseCursors.click));

        final disabledCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('link_disabled')),
        );
        expect(disabledCursor, equals(SystemMouseCursors.basic));
      },
    );

    testWidgets(
      'Switch shows click cursor when enabled and basic cursor when disabled',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Column(
                children: [
                  Switch(
                    key: const Key('switch_enabled'),
                    value: true,
                    onChanged: (_) {},
                  ),
                  const Switch(
                    key: Key('switch_disabled'),
                    value: false,
                    onChanged: null,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final enabledCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('switch_enabled')),
        );
        expect(enabledCursor, equals(SystemMouseCursors.click));

        final disabledCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('switch_disabled')),
        );
        expect(disabledCursor, equals(SystemMouseCursors.basic));
      },
    );

    testWidgets(
      'Slider shows click cursor when enabled and basic cursor when disabled',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Column(
                children: [
                  Slider(
                    key: const Key('slider_enabled'),
                    value: 0.5,
                    onChanged: (_) {},
                  ),
                  const Slider(
                    key: Key('slider_disabled'),
                    value: 0.0,
                    onChanged: null,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final enabledCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('slider_enabled')),
        );
        expect(enabledCursor, equals(SystemMouseCursors.click));

        final disabledCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('slider_disabled')),
        );
        expect(disabledCursor, equals(SystemMouseCursors.basic));
      },
    );

    testWidgets(
      'MenuItemButton shows click cursor when enabled and basic cursor when disabled',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: MenuBar(
                children: [
                  MenuItemButton(
                    key: const Key('menu_enabled'),
                    onPressed: () {},
                    child: const Text('Add to Queue'),
                  ),
                  const MenuItemButton(
                    key: Key('menu_disabled'),
                    onPressed: null,
                    child: Text('Disabled Action'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final enabledCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('menu_enabled')),
        );
        expect(enabledCursor, equals(SystemMouseCursors.click));

        final disabledCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('menu_disabled')),
        );
        expect(disabledCursor, equals(SystemMouseCursors.basic));
      },
    );

    testWidgets(
      'TextField shows text cursor on mouse hover',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(20),
                child: TextField(
                  key: Key('text_input'),
                  decoration: InputDecoration(hintText: 'Search...'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final textCursor = await hoverAndGetCursor(
          tester,
          find.byKey(const Key('text_input')),
        );
        expect(textCursor, equals(SystemMouseCursors.text));
      },
    );

    testWidgets(
      'Interactive cards and tiles show click cursor on hover',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Column(
                children: [
                  InkWell(
                    key: const Key('album_card_tile'),
                    mouseCursor: SystemMouseCursors.click,
                    hoverColor: const Color(0x14FFFFFF),
                    onTap: () {},
                    child: const SizedBox(width: 100, height: 100, child: Text('Album')),
                  ),
                  InkWell(
                    key: const Key('artist_card_tile'),
                    mouseCursor: SystemMouseCursors.click,
                    hoverColor: const Color(0x14FFFFFF),
                    onTap: () {},
                    child: const SizedBox(width: 100, height: 100, child: Text('Artist')),
                  ),
                  InkWell(
                    key: const Key('playlist_card_tile'),
                    mouseCursor: SystemMouseCursors.click,
                    hoverColor: const Color(0x14FFFFFF),
                    onTap: () {},
                    child: const SizedBox(width: 100, height: 100, child: Text('Playlist')),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          await hoverAndGetCursor(tester, find.byKey(const Key('album_card_tile'))),
          equals(SystemMouseCursors.click),
        );
        expect(
          await hoverAndGetCursor(tester, find.byKey(const Key('artist_card_tile'))),
          equals(SystemMouseCursors.click),
        );
        expect(
          await hoverAndGetCursor(tester, find.byKey(const Key('playlist_card_tile'))),
          equals(SystemMouseCursors.click),
        );
      },
    );
  });
}
