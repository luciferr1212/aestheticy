import 'dart:io';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/library/favorites_view.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
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

  final track1 = Track(
    id: 1,
    folderId: 1,
    path: 'C:/Music/fav1.mp3',
    durationMs: 210000,
    title: 'Favorite Song 1',
    artist: 'Fav Artist',
    album: 'Fav Album',
    mtimeMs: 0,
    sizeBytes: 1000,
    addedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('favorites_view_test_');
    repo = FakeLibraryRepository();
    await repo.addFolder('C:/Music');
    await repo.upsertTracks([track1]);

    collections = UserCollections(repository: repo);
    await collections.init();
    await collections.toggleFavorite(track1.path);

    engine = FakeAudioEngine();
    queue = PlaybackQueue();
    controller = PlaybackController(engine: engine, queue: queue);
    settingsStore = SettingsStore(directory: tempDir);
    await settingsStore.init();
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
              child: FavoritesView(
                repository: repo,
                collections: collections,
                controller: controller,
                settingsStore: settingsStore,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'FavoritesView displays favorites, plays, and removes track live when unfavorited',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Favorite Song 1'), findsOneWidget);

      // Play favorites
      await tester.tap(find.byKey(const Key('favorites_play_button')));
      await tester.pumpAndSettle();

      expect(controller.queue.current?.uri, track1.path);

      // Unfavorite live
      await collections.toggleFavorite(track1.path);
      await tester.pumpAndSettle();

      expect(find.text('Favorite Song 1'), findsNothing);
      expect(find.text('No favorite tracks yet'), findsOneWidget);
    },
  );

  testWidgets(
    'FavoritesView renders in LTR and RTL without overflow at 1000x700 and 1280x800',
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

          expect(find.text('Favorite Song 1'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
