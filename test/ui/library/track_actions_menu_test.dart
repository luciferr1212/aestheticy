import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/library/track_actions_menu.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../library/fake_library_repository.dart';

void main() {
  late FakeLibraryRepository repo;
  late UserCollections collections;
  late FakeAudioEngine engine;
  late PlaybackQueue queue;
  late PlaybackController controller;

  final testTrack = Track(
    id: 1,
    folderId: 1,
    path: 'C:/Music/test.mp3',
    durationMs: 180000,
    title: 'Test Song',
    artist: 'Test Artist',
    album: 'Test Album',
    mtimeMs: 0,
    sizeBytes: 1000,
    addedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  setUp(() async {
    repo = FakeLibraryRepository();
    await repo.addFolder('C:/Music');
    await repo.upsertTracks([testTrack]);
    collections = UserCollections(repository: repo);
    await collections.init();

    engine = FakeAudioEngine();
    queue = PlaybackQueue();
    controller = PlaybackController(engine: engine, queue: queue);
  });

  tearDown(() {
    controller.dispose();
    collections.dispose();
  });

  Widget buildTestApp({
    Track? track,
    bool isMissing = false,
    int? playlistId,
    int? playlistEntryId,
    int? position,
    int? totalCount,
    VoidCallback? onPlay,
    VoidCallback? onRemoveFromPlaylist,
    VoidCallback? onMoveUp,
    VoidCallback? onMoveDown,
  }) {
    final effectiveTrack = track ?? testTrack;
    return MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: UserCollectionsScope(
          collections: collections,
          child: Center(
            child: TrackActionsMenuAnchor(
              track: effectiveTrack,
              isMissing: isMissing,
              controller: controller,
              userCollections: collections,
              playlistId: playlistId,
              playlistEntryId: playlistEntryId,
              position: position,
              totalCount: totalCount,
              onPlay: onPlay,
              onRemoveFromPlaylist: onRemoveFromPlaylist,
              onMoveUp: onMoveUp,
              onMoveDown: onMoveDown,
              builder: (context, menuController) {
                return GestureDetector(
                  key: const Key('row_gesture_detector'),
                  onSecondaryTapUp: (details) {
                    menuController.open(position: details.localPosition);
                  },
                  child: Container(
                    key: const Key('test_track_row'),
                    width: 400,
                    height: 50,
                    color: Colors.grey.shade900,
                    child: Row(
                      children: [
                        const Expanded(child: Text('Test Row')),
                        IconButton(
                          key: const Key('test_more_button'),
                          icon: const Icon(Icons.more_horiz),
                          onPressed: () {
                            if (menuController.isOpen) {
                              menuController.close();
                            } else {
                              menuController.open();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Menu opens on more-button click and right-click',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Open via more button
      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('track_action_play')), findsOneWidget);
      expect(find.byKey(const Key('track_action_favorite')), findsOneWidget);

      // Close menu by tapping outside
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('track_action_play')), findsNothing);

      // Open via right-click (secondary tap)
      final rowLocation = tester.getCenter(find.byKey(const Key('row_gesture_detector')));
      final testPointer = TestPointer(1, PointerDeviceKind.mouse, 0, kSecondaryMouseButton);
      await tester.sendEventToBinding(testPointer.down(rowLocation));
      await tester.sendEventToBinding(testPointer.up());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('track_action_play')), findsOneWidget);
    },
  );

  testWidgets(
    'Play, Play next, and Add to queue trigger expected controller methods',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Tap more-button -> Play
      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('track_action_play')));
      await tester.pumpAndSettle();

      expect(controller.queue.current?.uri, testTrack.path);

      // Tap more-button -> Play next
      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('track_action_play_next')));
      await tester.pumpAndSettle();

      expect(controller.queue.items.length, 2);

      // Tap more-button -> Add to queue
      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('track_action_add_to_queue')));
      await tester.pumpAndSettle();

      expect(controller.queue.items.length, 3);
    },
  );

  testWidgets(
    'Favorite toggles favorite in UserCollections',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(collections.isFavorite(testTrack.path), isFalse);

      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('track_action_favorite')));
      await tester.pumpAndSettle();

      expect(collections.isFavorite(testTrack.path), isTrue);

      // Toggle off
      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('track_action_favorite')));
      await tester.pumpAndSettle();

      expect(collections.isFavorite(testTrack.path), isFalse);
    },
  );

  testWidgets(
    'Rate submenu sets and clears ratings',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(collections.ratingOf(testTrack.path), 0);

      // Open menu -> Rate submenu -> 4 stars
      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('track_action_rate')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('track_rate_4')));
      await tester.pumpAndSettle();

      expect(collections.ratingOf(testTrack.path), 4);

      // Open menu -> Rate submenu -> Clear rating
      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('track_action_rate')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('track_rate_clear')));
      await tester.pumpAndSettle();

      expect(collections.ratingOf(testTrack.path), 0);
    },
  );

  testWidgets(
    'Playlist submenu lists playlists, dispatches addToPlaylist, and handles new playlist dialog',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      final pl1 = await collections.createPlaylist('Chill Vibes');

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Open menu -> Add to playlist -> pl1
      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('track_action_add_to_playlist')));
      await tester.pumpAndSettle();

      expect(find.byKey(Key('track_add_to_playlist_${pl1.id}')), findsOneWidget);
      await tester.tap(find.byKey(Key('track_add_to_playlist_${pl1.id}')));
      await tester.pumpAndSettle();

      final entries = await repo.playlistEntries(pl1.id);
      expect(entries.length, 1);
      expect(entries.first.path, testTrack.path);

      // Open menu -> Add to playlist -> New playlist dialog
      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('track_action_add_to_playlist')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('track_action_new_playlist')));
      await tester.pumpAndSettle();

      // Dialog opens: test duplicate validation
      await tester.enterText(find.byKey(const Key('create_playlist_text_field')), 'chill vibes');
      await tester.tap(find.byKey(const Key('create_playlist_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('A playlist with this name already exists'), findsOneWidget);

      // Enter valid name
      await tester.enterText(find.byKey(const Key('create_playlist_text_field')), 'Workout Energy');
      await tester.tap(find.byKey(const Key('create_playlist_submit_button')));
      await tester.pumpAndSettle();

      final pl2 = collections.playlists.firstWhere((p) => p.name == 'Workout Energy');
      final entries2 = await repo.playlistEntries(pl2.id);
      expect(entries2.length, 1);
      expect(entries2.first.path, testTrack.path);
    },
  );

  testWidgets(
    'Playlist-specific items dispatch callbacks',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      var removed = false;
      var movedUp = false;
      var movedDown = false;

      await tester.pumpWidget(buildTestApp(
        playlistId: 42,
        playlistEntryId: 10,
        position: 1,
        totalCount: 3,
        onRemoveFromPlaylist: () => removed = true,
        onMoveUp: () => movedUp = true,
        onMoveDown: () => movedDown = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('track_action_remove_from_playlist')), findsOneWidget);
      expect(find.byKey(const Key('track_action_move_up')), findsOneWidget);
      expect(find.byKey(const Key('track_action_move_down')), findsOneWidget);

      await tester.tap(find.byKey(const Key('track_action_remove_from_playlist')));
      await tester.pumpAndSettle();
      expect(removed, isTrue);

      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('track_action_move_up')));
      await tester.pumpAndSettle();
      expect(movedUp, isTrue);

      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('track_action_move_down')));
      await tester.pumpAndSettle();
      expect(movedDown, isTrue);
    },
  );

  testWidgets(
    'Missing file disables play actions and hides rate / add to playlist',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      await tester.pumpWidget(buildTestApp(isMissing: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('test_more_button')));
      await tester.pumpAndSettle();

      // Play button should be disabled
      final playBtn = tester.widget<MenuItemButton>(find.byKey(const Key('track_action_play')));
      expect(playBtn.onPressed, isNull);

      // Rate and Add to playlist should be hidden
      expect(find.byKey(const Key('track_action_rate')), findsNothing);
      expect(find.byKey(const Key('track_action_add_to_playlist')), findsNothing);
    },
  );
}
