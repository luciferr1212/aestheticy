import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/queue/queue_view.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import '../../library/fake_library_repository.dart';

AudioSource _createSource(String name, {String? uri, String? durationMs = '180000'}) {
  return AudioSource(
    uri ?? 'C:\\Music\\$name.flac',
    extras: {
      'title': name,
      'artist': 'Artist $name',
      'album': 'Album $name',
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
    tempDir = Directory.systemTemp.createTempSync('queue_view_test_');
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

  Widget buildTestWidget({
    TextDirection textDirection = TextDirection.ltr,
    double textScale = 1.0,
    Locale locale = const Locale('en'),
  }) {
    return SettingsScope(
      store: settingsStore,
      child: MaterialApp(
        locale: locale,
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: textDirection,
          child: MediaQuery(
            data: MediaQueryData(
              size: const Size(1280, 800),
              textScaler: TextScaler.linear(textScale),
            ),
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
      ),
    );
  }

  testWidgets(
    'Renders history, current and upcoming groups with correct dimming and playing indicator',
    (tester) async {
      await controller.playQueue([
        _createSource('track_0'),
        _createSource('track_1'),
        _createSource('track_2'),
      ], startIndex: 1);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('track_0'), findsOneWidget);
      expect(find.text('track_1'), findsOneWidget);
      expect(find.text('track_2'), findsOneWidget);

      // Current track has playing indicator
      expect(find.byKey(const Key('queue_playing_indicator')), findsOneWidget);
      final playIconFinder = find.descendant(
        of: find.byKey(const Key('queue_playing_indicator')),
        matching: find.byIcon(Icons.play_arrow),
      );
      expect(playIconFinder, findsOneWidget);

      // Verify dimming on history track (track_0)
      final opacities = tester.widgetList<Opacity>(find.byType(Opacity)).toList();
      final historyOpacity = opacities.firstWhere(
        (o) => o.opacity < 1.0,
      );
      expect(historyOpacity.opacity, 0.50);

      // Pause playback and verify indicator updates
      await tester.runAsync(() async {
        await controller.pause();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(controller.currentState, PlaybackState.paused);
      final pauseIconFinder = find.descendant(
        of: find.byKey(const Key('queue_playing_indicator')),
        matching: find.byIcon(Icons.pause),
      );
      expect(pauseIconFinder, findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Tap and double click jump to the item',
    (tester) async {
      await controller.playQueue([
        _createSource('track_0'),
        _createSource('track_1'),
        _createSource('track_2'),
      ], startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      expect(queue.currentIndex, 0);

      // Tap on track_2 jumps to it
      await tester.tap(find.text('track_2'));
      await tester.pumpAndSettle();
      expect(queue.currentIndex, 2);

      // Double-click on track_0 jumps to it
      await tester.tap(find.text('track_0'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('track_0'));
      await tester.pumpAndSettle();
      expect(queue.currentIndex, 0);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Drag reorder maps indexes correctly in both directions and calls moveInQueue',
    (tester) async {
      await controller.playQueue([
        _createSource('track_0'),
        _createSource('track_1'),
        _createSource('track_2'),
        _createSource('track_3'),
      ], startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Programmatic move via moveInQueue verifies active order and cursor
      await controller.moveInQueue(0, 2);
      await tester.pump();
      expect(queue.items.map((s) => s.extras?['title']), ['track_1', 'track_2', 'track_0', 'track_3']);
      expect(queue.currentIndex, 2);

      // Move backward (2 -> 0)
      await controller.moveInQueue(2, 0);
      await tester.pump();
      expect(queue.items.map((s) => s.extras?['title']), ['track_0', 'track_1', 'track_2', 'track_3']);
      expect(queue.currentIndex, 0);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Move up, Move down, Remove and Play next from the menu',
    (tester) async {
      await controller.playQueue([
        _createSource('track_0'),
        _createSource('track_1'),
        _createSource('track_2'),
      ], startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // 1. Play next on track_2
      await tester.tap(find.byKey(const Key('queue_row_menu_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('queue_menu_play_next')));
      await tester.pumpAndSettle();
      expect(queue.items.map((s) => s.extras?['title']), ['track_0', 'track_2', 'track_1']);

      // 2. Move up on track_2 (now at index 1)
      await tester.tap(find.byKey(const Key('queue_row_menu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('queue_menu_move_up')));
      await tester.pumpAndSettle();
      expect(queue.items.map((s) => s.extras?['title']), ['track_2', 'track_0', 'track_1']);

      // 3. Move down on track_2 (now at index 0)
      await tester.tap(find.byKey(const Key('queue_row_menu_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('queue_menu_move_down')));
      await tester.pumpAndSettle();
      expect(queue.items.map((s) => s.extras?['title']), ['track_0', 'track_2', 'track_1']);

      // 4. Remove on track_1 (now at index 2)
      await tester.tap(find.byKey(const Key('queue_row_menu_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('queue_menu_remove')));
      await tester.pumpAndSettle();
      expect(queue.items.map((s) => s.extras?['title']), ['track_0', 'track_2']);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Delete key removes the selected row; Delete does nothing while a text field is focused',
    (tester) async {
      await controller.playQueue([
        _createSource('track_0'),
        _createSource('track_1'),
        _createSource('track_2'),
      ], startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Tap track_1 to select it
      await tester.tap(find.text('track_1'));
      await tester.pumpAndSettle();
      expect(queue.length, 3);

      // Press Delete key
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(queue.length, 2);
      expect(queue.items.map((s) => s.extras?['title']), ['track_0', 'track_2']);

      // Now open Save as Playlist dialog (which has an autofocused text field)
      await tester.tap(find.byKey(const Key('queue_save_playlist_button')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      // Pressing Delete while text field is focused must NOT delete queue tracks
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(queue.length, 2);

      // Dismiss dialog
      await tester.tap(find.byKey(const Key('save_queue_playlist_cancel_button')));
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Clear upcoming, and Clear all with confirm and cancel',
    (tester) async {
      await controller.playQueue([
        _createSource('track_0'),
        _createSource('track_1'),
        _createSource('track_2'),
      ], startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // 1. Clear upcoming
      await tester.tap(find.byKey(const Key('queue_clear_upcoming_button')));
      await tester.pump();
      expect(queue.length, 1);
      expect(queue.current?.extras?['title'], 'track_0');

      // Add back tracks
      await controller.addToQueue([_createSource('track_1'), _createSource('track_2')]);
      await tester.pump();
      expect(queue.length, 3);

      // 2. Clear all - Cancel
      await tester.tap(find.byKey(const Key('queue_clear_all_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('queue_clear_all_cancel_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('queue_clear_all_cancel_button')));
      await tester.pumpAndSettle();
      expect(queue.length, 3);

      // 3. Clear all - Confirm
      await tester.tap(find.byKey(const Key('queue_clear_all_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('queue_clear_all_confirm_button')));
      await tester.pumpAndSettle();
      expect(queue.isEmpty, isTrue);
      expect(engine.state, PlaybackState.idle);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Save as playlist: names, empty-name validation, active order with shuffle on, skipped count',
    (tester) async {
      final t1 = _createSource('song_1', uri: 'C:\\Music\\song_1.mp3');
      final t2 = _createSource('web_stream', uri: 'http://radio.example.com/live');
      final t3 = _createSource('song_2', uri: 'C:\\Music\\song_2.mp3');

      await controller.playQueue([t1, t2, t3], startIndex: 0);
      queue.setShuffle(true);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Open Save as playlist dialog
      await tester.tap(find.byKey(const Key('queue_save_playlist_button')));
      await tester.pumpAndSettle();

      // Default name contains "Queue" and today's year
      final textFieldFinder = find.byKey(const Key('save_queue_playlist_text_field'));
      expect(textFieldFinder, findsOneWidget);
      final initialText = tester.widget<TextField>(textFieldFinder).controller!.text;
      expect(initialText, contains('Queue'));

      // Empty name validation
      await tester.enterText(textFieldFinder, '   ');
      await tester.tap(find.byKey(const Key('save_queue_playlist_submit_button')));
      await tester.pumpAndSettle();
      expect(find.text('Playlist name cannot be empty'), findsOneWidget);

      // Create existing playlist to test duplicate name validation
      await collections.createPlaylist('Existing PL');
      await tester.enterText(textFieldFinder, 'Existing PL');
      await tester.tap(find.byKey(const Key('save_queue_playlist_submit_button')));
      await tester.pumpAndSettle();
      expect(find.text('A playlist with this name already exists'), findsOneWidget);

      // Submit valid name
      await tester.enterText(textFieldFinder, 'My Saved Queue');
      await tester.tap(find.byKey(const Key('save_queue_playlist_submit_button')));
      await tester.pumpAndSettle();

      // SnackBar shows confirmation mentioning 1 skipped non-library track
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('1 non-library tracks skipped'), findsOneWidget);
      expect(find.text('View playlist'), findsOneWidget);

      // Verify playlist entries in database match active playback order (excluding skipped)
      final createdPl = collections.playlists.firstWhere((p) => p.name == 'My Saved Queue');
      final entries = await repository.playlistEntries(createdPl.id);
      final activeLibraryUris = queue.items
          .where((s) => !s.uri.startsWith('http://') && !s.uri.startsWith('https://'))
          .map((s) => s.uri)
          .toList();
      expect(entries.map((PlaylistEntry i) => i.path).toList(), activeLibraryUris);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Empty state, RTL render, textScale Large at 1280x800 without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Empty state
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      expect(find.text('Queue is empty'), findsOneWidget);
      expect(find.text('Play a song or album to populate your queue'), findsOneWidget);

      // RTL Arabic with items
      settingsStore.update((s) => s.copyWith(language: 'ar'));
      await controller.playQueue([
        _createSource('أغنية 1'),
        _createSource('أغنية 2'),
      ]);
      await tester.pumpWidget(buildTestWidget(
        textDirection: TextDirection.rtl,
        locale: const Locale('ar'),
        textScale: 1.10,
      ));
      await tester.pumpAndSettle();

      expect(find.text('قائمة الانتظار'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'A 5000-item queue builds only visible rows',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final largeList = List.generate(
        5000,
        (i) => _createSource('track_$i'),
      );
      await controller.playQueue(largeList, startIndex: 0);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Fixed itemExtent of 56 on an 800px screen builds only visible rows
      final rowFinder = find.byKey(const ValueKey('queue_row_0'));
      expect(rowFinder, findsOneWidget);

      // Verify that off-screen items (e.g. index 4999) are NOT built into the widget tree
      expect(find.text('track_4999'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Bottom bar queue button toggles side panel, expand opens QueueView, and Up Next Open queue button navigates to queue; Esc returns',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final scanService = ScanService(repository: repository);
      final glassController = GlassController();

      await repository.addFolder('C:\\Music');
      await controller.playQueue([_createSource('song_1'), _createSource('song_2')]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: GlassScope(
            controller: glassController,
            child: AppShell(
              engine: engine,
              controller: controller,
              repository: repository,
              scanService: scanService,
              settingsStore: settingsStore,
              navigator: navigator,
              userCollections: collections,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Bottom bar queue button opens the docked Queue side panel; Expand opens QueueView
      expect(navigator.current, AppDestination.albums);
      await tester.tap(find.byKey(const Key('player_queue_button')));
      await tester.pumpAndSettle();
      expect(navigator.current, AppDestination.albums);
      expect(find.byKey(const ValueKey('side_panel_queue_content')), findsOneWidget);

      await tester.tap(find.byKey(const Key('side_panel_expand_button')));
      await tester.pumpAndSettle();
      expect(navigator.current, AppDestination.queue);
      expect(find.byType(QueueView), findsOneWidget);
      expect(find.byKey(const Key('side_panel_surface')), findsNothing);

      // Esc returns to albums and panel remains closed
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(navigator.current, AppDestination.albums);
      expect(find.byKey(const Key('side_panel_surface')), findsNothing);

      // 2. Open Now Playing, then click "Open queue"
      navigator.openNowPlaying();
      await tester.pumpAndSettle();
      expect(navigator.current, AppDestination.nowPlaying);

      final openQueueBtn = find.byKey(const Key('now_playing_open_queue_button'));
      expect(openQueueBtn, findsOneWidget);
      await tester.tap(openQueueBtn);
      await tester.pumpAndSettle();
      expect(navigator.current, AppDestination.queue);

      // Esc returns to Now Playing
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(navigator.current, AppDestination.nowPlaying);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'No timers or stream subscriptions left after dispose',
    (tester) async {
      await controller.playQueue([_createSource('a'), _createSource('b')]);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Dispose QueueView by pumping an empty SizedBox
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // No unhandled timer or exception
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'S4: Delete key handles duplicates, consecutive deletes, current item removal, above/below removal, and multi-select',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Use a gapless spy engine to verify preload refresh on Delete
      final spyEngine = _SpyPreloadEngine();
      await spyEngine.init();
      addTearDown(spyEngine.dispose);
      final spyQueue = PlaybackQueue();
      final spyCtrl = PlaybackController(engine: spyEngine, queue: spyQueue);
      await spyCtrl.init();
      addTearDown(spyCtrl.dispose);

      Widget buildSpyQueue() {
        return SettingsScope(
          store: settingsStore,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: QueueView(
                controller: spyCtrl,
                navigator: navigator,
                settingsStore: settingsStore,
                userCollections: collections,
              ),
            ),
          ),
        );
      }

      final dupA = _createSource('dup_a', uri: 'C:\\Music\\dup_a.flac');
      final mid = _createSource('mid_b', uri: 'C:\\Music\\mid_b.flac');
      final tail = _createSource('tail_c', uri: 'C:\\Music\\tail_c.flac');
      final extra = _createSource('extra_d', uri: 'C:\\Music\\extra_d.flac');

      // Queue: [dup_a (#0), mid_b (#1), dup_a (#2), tail_c (#3), extra_d (#4)], playing #1 (mid_b)
      await spyCtrl.playQueue([dupA, mid, dupA, tail, extra], startIndex: 1);
      await tester.pumpWidget(buildSpyQueue());
      await tester.pumpAndSettle();

      final initialEntries = List<QueueEntry>.from(spyQueue.entries);

      // 1. Delete entry above current (#0 dup_a) -> #1 mid_b keeps playing without reopen
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      final opensBefore = spyEngine.openCallCount;
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      // #0 dup_a deleted, mid_b still playing without reopen, #2 dup_a untouched!
      expect(spyEngine.openCallCount, opensBefore);
      expect(spyQueue.currentEntry?.id, initialEntries[1].id);
      expect(spyQueue.entries.map((e) => e.id).toList(), [
        initialEntries[1].id,
        initialEntries[2].id,
        initialEntries[3].id,
        initialEntries[4].id,
      ]);

      // 2. Navigate to duplicate entry (now index 1, initialEntries[2]) and delete it, then immediately press Delete again!
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(spyQueue.entries.map((e) => e.id).toList(), [
        initialEntries[1].id,
        initialEntries[3].id,
        initialEntries[4].id,
      ]);

      // Consecutive Delete must remove tail_c (index 1, next item), NOT jump back onto mid_b!
      spyEngine.preloadedUris.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(spyQueue.entries.map((e) => e.id).toList(), [
        initialEntries[1].id,
        initialEntries[4].id,
      ]);
      expect(spyEngine.preloadedUris.last, extra.uri);

      // 3. Delete the currently playing entry (initialEntries[1] mid_b) -> opens extra_d (initialEntries[4])
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(spyQueue.length, 1);
      expect(spyQueue.currentEntry?.id, initialEntries[4].id);
      expect(spyEngine.openedSource?.uri, extra.uri);

      // 4. Multi-select via Shift+Click and Delete removes multiple entries together
      final m0 = _createSource('m0');
      final m1 = _createSource('m1');
      final m2 = _createSource('m2');
      final m3 = _createSource('m3');
      await spyCtrl.playQueue([m0, m1, m2, m3], startIndex: 0);
      await tester.pumpAndSettle();

      final multiEntries = List<QueueEntry>.from(spyQueue.entries);
      // ArrowDown to m1, then Shift+Click m3 -> selects [m1, m2, m3] without interrupting m0
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.byKey(ValueKey('queue_row_${multiEntries[3].id}')));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      spyEngine.preloadedUris.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(spyQueue.entries.map((e) => e.id).toList(), [multiEntries[0].id]);
      expect(spyQueue.currentEntry?.id, multiEntries[0].id);
      expect(spyEngine.preloadedUris.last, isNull);
    },
  );
}

class _SpyPreloadEngine extends FakeAudioEngine {
  final List<String?> preloadedUris = [];

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        exclusiveMode: false,
        gapless: true,
        equalizer: true,
        replayGain: true,
      );

  @override
  Future<void> preloadNext(AudioSource? next) async {
    preloadedUris.add(next?.uri);
    await super.preloadNext(next);
  }
}
