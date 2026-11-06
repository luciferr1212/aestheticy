import 'dart:io';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/ui/library/playlists_view.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../library/fake_library_repository.dart';

void main() {
  late Directory tempDir;
  late FakeLibraryRepository repo;
  late UserCollections collections;
  late FakeAudioEngine engine;
  late PlaybackQueue queue;
  late PlaybackController controller;
  late SettingsStore settingsStore;
  late AppNavigator navigator;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('playlists_view_test_');
    repo = FakeLibraryRepository();
    collections = UserCollections(repository: repo);
    await collections.init();

    engine = FakeAudioEngine();
    queue = PlaybackQueue();
    controller = PlaybackController(engine: engine, queue: queue);
    settingsStore = SettingsStore(directory: tempDir);
    await settingsStore.init();
    navigator = AppNavigator();
  });

  tearDown(() {
    controller.dispose();
    collections.dispose();
    settingsStore.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget buildTestWidget({
    TextDirection textDirection = TextDirection.ltr,
    double textScaleFactor = 1.0,
  }) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: Directionality(
        textDirection: textDirection,
        child: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScaleFactor),
          ),
          child: Scaffold(
            body: PlaylistsView(
              collections: collections,
              repository: repo,
              controller: controller,
              settingsStore: settingsStore,
              navigator: navigator,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'PlaylistsView shows empty state and creates new playlist',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('empty_new_playlist_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('empty_new_playlist_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('create_playlist_text_field')), 'Summer Hits');
      await tester.tap(find.byKey(const Key('create_playlist_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Summer Hits'), findsOneWidget);
    },
  );

  testWidgets(
    'PlaylistsView renders in LTR and RTL without overflow at 1000x700 and 1280x800',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      await collections.createPlaylist('Classics');
      await collections.createPlaylist('Lo-Fi Study');

      for (final size in [const Size(1280, 800), const Size(1000, 700)]) {
        for (final dir in [TextDirection.ltr, TextDirection.rtl]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(buildTestWidget(
            textDirection: dir,
            textScaleFactor: 1.3,
          ));
          await tester.pumpAndSettle();

          expect(find.text('Classics'), findsOneWidget);
          expect(find.text('Lo-Fi Study'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
