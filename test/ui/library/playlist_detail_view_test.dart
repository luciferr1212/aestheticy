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
      expect(controller.queue.isShuffled, isFalse);

      // Shuffle playlist sets shuffle state on controller/queue
      await tester.tap(find.byKey(const Key('playlist_shuffle_button')));
      await tester.pumpAndSettle();

      expect(controller.queue.items.length, 2);
      expect(controller.queue.isShuffled, isTrue);
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

  testWidgets(
    'S3: playing a track in a playlist with missing files at start, middle, and end starts the exact clicked track',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final track3 = Track(
        id: 3,
        folderId: 1,
        path: 'C:/Music/song3.mp3',
        durationMs: 170000,
        title: 'Song Three',
        artist: 'Artist C',
        album: 'Album C',
        mtimeMs: 0,
        sizeBytes: 1000,
        addedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      await repo.upsertTracks([track3]);

      const missingStart = 'C:/Music/missing_start.mp3';
      const missingMid = 'C:/Music/missing_mid.mp3';
      const missingEnd = 'C:/Music/missing_end.mp3';

      final mixedPlaylist = await collections.createPlaylist('Mixed Missing');
      await collections.addToPlaylist(mixedPlaylist.id, [
        missingStart, // row 0 (missing at start)
        track1.path, // row 1 -> playable index 0
        missingMid, // row 2 (missing in middle)
        track2.path, // row 3 -> playable index 1
        track3.path, // row 4 -> playable index 2
        missingEnd, // row 5 (missing at end)
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: UserCollectionsScope(
              collections: collections,
              child: PlaylistDetailView(
                playlistId: mixedPlaylist.id,
                initialPlaylist: mixedPlaylist,
                repository: repo,
                collections: collections,
                controller: controller,
                settingsStore: settingsStore,
                navigator: navigator,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> tapRowText(String label) async {
        final finder = find.text(label);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
      }

      // Clicking playable row after missing start plays Song One
      await tapRowText('Song One');
      expect(controller.queue.current?.uri, track1.path);
      expect(
        controller.queue.items.map((s) => s.uri).toList(),
        [track1.path, track2.path, track3.path],
      );

      // Clicking playable row after missing middle plays Song Two (previously played Song Three!)
      await tapRowText('Song Two');
      expect(controller.queue.current?.uri, track2.path);

      // Clicking last playable row before missing end plays Song Three
      await tapRowText('Song Three');
      expect(controller.queue.current?.uri, track3.path);

      // Tapping a missing row at start, middle, or end does nothing
      await tapRowText('missing_start.mp3');
      expect(controller.queue.current?.uri, track3.path);

      await tapRowText('missing_mid.mp3');
      expect(controller.queue.current?.uri, track3.path);

      await tapRowText('missing_end.mp3');
      expect(controller.queue.current?.uri, track3.path);
      expect(tester.takeException(), isNull);
    },
  );
}
