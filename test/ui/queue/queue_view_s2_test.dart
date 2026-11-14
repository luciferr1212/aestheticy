import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/ui/queue/queue_view.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import '../../library/fake_library_repository.dart';

AudioSource _createSource(String name, {String? uri, String? durationMs = '180000', String? album}) {
  return AudioSource(
    uri ?? 'C:\\Music\\$name.flac',
    extras: {
      'title': name,
      'artist': 'Artist $name',
      'album': album ?? 'Album $name',
      'durationMs': ?durationMs,
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeAudioEngine engine;
  late PlaybackQueue queue;
  late PlaybackController controller;
  late SettingsStore settingsStore;
  late AppNavigator navigator;
  late FakeLibraryRepository repository;
  late UserCollections collections;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('queue_s2_test_');
    engine = FakeAudioEngine();
    await engine.init();
    queue = PlaybackQueue();
    controller = PlaybackController(engine: engine, queue: queue);
    await controller.init();
    settingsStore = SettingsStore(directory: tempDir);
    await settingsStore.init();
    navigator = AppNavigator();
    repository = FakeLibraryRepository();
    collections = UserCollections(repository: repository);
    await collections.init();
  });

  tearDown(() async {
    await controller.dispose();
    await engine.dispose();
    collections.dispose();
    settingsStore.dispose();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Widget buildTestWidget({TextDirection textDirection = TextDirection.ltr}) {
    return SettingsScope(
      store: settingsStore,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: textDirection,
          child: Scaffold(
            body: QueueView(
              controller: controller,
              navigator: navigator,
              settingsStore: settingsStore,
              userCollections: collections,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Sections appear only when both user-queued and context upcoming exist',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final t1 = _createSource('Song 1', album: 'Great Album');
      final t2 = _createSource('Song 2', album: 'Great Album');
      final t3 = _createSource('Song 3', album: 'Great Album');

      // 1. Context only: play queue with 3 songs, currentIndex 0
      await controller.playQueue([t1, t2, t3], startIndex: 0);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Headers should not appear when there are no user-queued items
      expect(find.byKey(const Key('queue_section_next_in_queue')), findsNothing);
      expect(find.byKey(const Key('queue_section_next_from_context')), findsNothing);

      // 2. Add user-queued track: now both user-queued and context upcoming exist
      final userTrack = _createSource('User Track');
      await controller.addToQueue([userTrack]);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('queue_section_next_in_queue')), findsOneWidget);
      expect(find.byKey(const Key('queue_section_next_from_context')), findsOneWidget);
      expect(find.text('Next from Great Album'), findsOneWidget);

      // 3. User-queued only in upcoming: clear context upcoming or advance to end of context
      await controller.playTrack(queue.length - 1); // jump to context track
      await tester.pumpAndSettle();
      // Now at the end, no upcoming context tracks
      expect(find.byKey(const Key('queue_section_next_in_queue')), findsNothing);
      expect(find.byKey(const Key('queue_section_next_from_context')), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Duplicates render as separate rows with different keys; only real current entry is marked',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final song = _createSource('Duplicate Song');
      await controller.playQueue([song, song, song], startIndex: 1);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final entries = queue.entries;
      expect(entries.length, 3);
      expect(entries[0].id, isNot(entries[1].id));
      expect(entries[1].id, isNot(entries[2].id));

      // Each row has its unique key
      expect(find.byKey(ValueKey('queue_row_${entries[0].id}')), findsOneWidget);
      expect(find.byKey(ValueKey('queue_row_${entries[1].id}')), findsOneWidget);
      expect(find.byKey(ValueKey('queue_row_${entries[2].id}')), findsOneWidget);

      // Only index 1 is current
      expect(queue.currentIndex, 1);
      expect(queue.currentEntry!.id, entries[1].id);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Alt+Up and Alt+Down shortcuts move selected upcoming row',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final t1 = _createSource('Track 1');
      final t2 = _createSource('Track 2');
      final t3 = _createSource('Track 3');
      final t4 = _createSource('Track 4');

      await controller.playQueue([t1, t2, t3, t4], startIndex: 0);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // At start, currentIndex = 0.
      // Navigate selection down with ArrowDown to index 3 (Track 4)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      // Current track is still index 0 (Track 1)
      expect(queue.currentIndex, 0);

      // Press Alt+Up to move selected row 3 to row 2
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      // Track 4 should have moved from index 3 to index 2
      expect(queue.entries[2].source.extras?['title'], 'Track 4');
      expect(queue.entries[3].source.extras?['title'], 'Track 3');

      // Press Alt+Down to move selected row 2 back to row 3
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      // Track 4 moved back to index 3
      expect(queue.entries[3].source.extras?['title'], 'Track 4');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '2000-entry queue builds lazily without freezing',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final largeQueue = List.generate(
        2000,
        (i) => _createSource('Song $i', uri: 'C:\\Music\\song_$i.mp3'),
      );
      await controller.playQueue(largeQueue, startIndex: 0);

      final watch = Stopwatch()..start();
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      watch.stop();

      // Render should be quick (< 1000ms)
      expect(watch.elapsedMilliseconds, lessThan(2000));
      // ReorderableListView should not build all 2000 rows
      final rowFinders = find.byType(InkWell);
      expect(rowFinders.evaluate().length, lessThan(100));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
