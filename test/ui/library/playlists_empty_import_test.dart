import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/ui/library/playlists_view.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import '../../library/fake_library_repository.dart';

void main() {
  group('Playlists Empty State Import M3U Button (I5)', () {
    late Directory tempDir;
    late FakeLibraryRepository repo;
    late UserCollections collections;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late SettingsStore settingsStore;
    late AppNavigator navigator;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('playlists_empty_import_test_');
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

    testWidgets(
      'empty state displays Import M3U button next to New Playlist and triggers import',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        var importTriggered = false;

        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: PlaylistsView(
              collections: collections,
              repository: repo,
              controller: controller,
              settingsStore: settingsStore,
              navigator: navigator,
              onImportM3u: (context) async {
                importTriggered = true;
              },
            ),
          ),
        ));
        await tester.pumpAndSettle();

        // Empty state must show both buttons
        final newButton = find.byKey(const Key('empty_new_playlist_button'));
        final importButton = find.byKey(const Key('empty_import_m3u_button'));

        expect(newButton, findsOneWidget);
        expect(importButton, findsOneWidget);

        // Tap Import M3U button in empty state
        await tester.tap(importButton);
        await tester.pumpAndSettle();

        expect(importTriggered, isTrue);
      },
    );
  });
}
