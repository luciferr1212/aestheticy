import 'dart:io';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/library/playlist_detail_view.dart';
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
  late PlaylistSummary playlist;

  final track1 = Track(
    id: 1,
    folderId: 1,
    path: 'C:/Music/song1.mp3',
    durationMs: 200000,
    title: 'Song One',
    artist: 'Artist A',
    album: 'Album A',
    mtimeMs: 0,
    sizeBytes: 1000,
    addedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  final track2 = Track(
    id: 2,
    folderId: 1,
    path: 'C:/Music/song2.mp3',
    durationMs: 150000,
    title: 'Song Two',
    artist: 'Artist B',
    album: 'Album B',
    mtimeMs: 0,
    sizeBytes: 1000,
    addedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('playlist_detail_view_test_');
    repo = FakeLibraryRepository();
    await repo.addFolder('C:/Music');
    await repo.upsertTracks([track1, track2]);

    collections = UserCollections(repository: repo);
    await collections.init();
    playlist = await collections.createPlaylist('Rock Classics');
    await collections.addToPlaylist(playlist.id, [track1.path, track2.path]);

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
            body: UserCollectionsScope(
              collections: collections,
              child: PlaylistDetailView(
                playlistId: playlist.id,
                initialPlaylist: playlist,
                repository: repo,
                collections: collections,
                controller: controller,
                settingsStore: settingsStore,
                navigator: navigator,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'PlaylistDetailView displays header, tracks, and plays tracks',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Rock Classics'), findsOneWidget);
      expect(find.text('Song One'), findsOneWidget);
      expect(find.text('Song Two'), findsOneWidget);

      // Play whole playlist
      await tester.tap(find.byKey(const Key('playlist_play_button')));
      await tester.pumpAndSettle();

      expect(controller.queue.current?.uri, track1.path);

      // Shuffle playlist
      await tester.tap(find.byKey(const Key('playlist_shuffle_button')));
      await tester.pumpAndSettle();

      expect(controller.queue.items.length, 2);
    },
  );

  testWidgets(
    'PlaylistDetailView renders in LTR and RTL without overflow at 1000x700 and 1280x800',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      for (final size in [const Size(1280, 800), const Size(1000, 700)]) {
        for (final dir in [TextDirection.ltr, TextDirection.rtl]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(buildTestWidget(
            textDirection: dir,
            textScaleFactor: 1.3,
          ));
          await tester.pumpAndSettle();

          expect(find.text('Rock Classics'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
