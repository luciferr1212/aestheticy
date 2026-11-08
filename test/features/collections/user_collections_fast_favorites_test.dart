import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/library/favorites_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

import '../../library/fake_library_repository.dart';

/// Fake repository with controlled latency and failure simulation.
class _DelayedRepository extends FakeLibraryRepository {
  Completer<void>? setFavoriteCompleter;
  bool shouldFail = false;

  @override
  Future<void> setFavorite(String path, bool favorite) async {
    if (setFavoriteCompleter != null) {
      await setFavoriteCompleter!.future;
    }
    if (shouldFail) {
      throw Exception('Database write failed');
    }
    return super.setFavorite(path, favorite);
  }
}

Track createTestTrack({
  required String path,
  String title = 'Title',
  String artist = 'Artist',
  String album = 'Album',
  int durationMs = 180000,
}) {
  return Track(
    folderId: 1,
    path: path,
    title: title,
    artist: artist,
    album: album,
    durationMs: durationMs,
    mtimeMs: 1000,
    sizeBytes: 5000000,
    addedAt: DateTime.now(),
  );
}

void main() {
  group('Instant Favorites Tests (I3)', () {
    late _DelayedRepository repository;
    late UserCollections collections;
    late PlaybackController controller;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late SettingsStore settingsStore;

    final testTrack1 = createTestTrack(
      path: 'C:\\Music\\song1.mp3',
      title: 'Song One',
      artist: 'Artist One',
      album: 'Album One',
      durationMs: 180000,
    );

    final testTrack2 = createTestTrack(
      path: 'C:\\Music\\song2.mp3',
      title: 'Song Two',
      artist: 'Artist Two',
      album: 'Album Two',
      durationMs: 200000,
    );

    setUp(() async {
      repository = _DelayedRepository();
      await repository.addFolder('C:\\Music');
      await repository.upsertTracks([testTrack1, testTrack2]);

      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();

      settingsStore = SettingsStore(
        initialSettings: const AppSettings(
          language: 'en',
          reduceMotion: true,
        ),
      );

      collections = UserCollections(repository: repository);
      await collections.init();
    });

    tearDown(() async {
      settingsStore.dispose();
      collections.dispose();
      await controller.dispose();
      await engine.dispose();
    });

    Widget createFavoritesApp() {
      return MaterialApp(
        locale: const Locale('en'),
        theme: buildAppTheme(),
        home: Scaffold(
          body: FavoritesView(
            repository: repository,
            collections: collections,
            controller: controller,
            settingsStore: settingsStore,
          ),
        ),
      );
    }

    testWidgets('Toggle favorite appears immediately in FavoritesView without awaiting repo',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      await tester.pumpWidget(createFavoritesApp());
      await tester.pump();

      // Initially empty
      expect(find.text('Song One'), findsNothing);

      // Block repository completion
      repository.setFavoriteCompleter = Completer<void>();

      // Call toggleFavorite with track
      final toggleFuture = collections.toggleFavorite(testTrack1.path, track: testTrack1);

      // Single pump without awaiting repository completion
      await tester.pump();

      // Song One MUST immediately appear in FavoritesView
      expect(find.text('Song One'), findsOneWidget,
          reason: 'FavoritesView must build synchronously from in-memory favoriteTracks');
      expect(collections.isFavorite(testTrack1.path), isTrue);

      // Release repository completer
      repository.setFavoriteCompleter!.complete();
      await toggleFuture;
      await tester.pump();

      expect(find.text('Song One'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Removing favorite disappears immediately and failure reverts both',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      // First add favorite
      await collections.toggleFavorite(testTrack1.path, track: testTrack1);

      await tester.pumpWidget(createFavoritesApp());
      await tester.pump();
      expect(find.text('Song One'), findsOneWidget);

      // Block repo & configure failure
      repository.setFavoriteCompleter = Completer<void>();
      repository.shouldFail = true;

      // Toggle off (remove)
      final removeFuture = collections.toggleFavorite(testTrack1.path);

      // Immediate single pump: should disappear immediately
      await tester.pump();
      expect(find.text('Song One'), findsNothing,
          reason: 'Removing favorite must disappear immediately');
      expect(collections.isFavorite(testTrack1.path), isFalse);

      // Complete with failure
      repository.setFavoriteCompleter!.complete();
      try {
        await removeFuture;
      } catch (_) {}
      await tester.pump();

      // Rolled back after failure
      expect(find.text('Song One'), findsOneWidget,
          reason: 'Failure must revert favorite');
      expect(collections.isFavorite(testTrack1.path), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });

    test('Favorites list maintains newest first order', () async {
      await collections.toggleFavorite(testTrack1.path, track: testTrack1);
      await collections.toggleFavorite(testTrack2.path, track: testTrack2);

      // testTrack2 was added last, so it must be first
      expect(collections.favoriteTracks.first.path, equals(testTrack2.path));
      expect(collections.favoriteTracks.last.path, equals(testTrack1.path));
    });

    test('50,000 favorites stay fast (performance benchmark)', () {
      final bigList = List.generate(
        50000,
        (i) => createTestTrack(
          path: 'C:\\Music\\song_$i.mp3',
          title: 'Song $i',
        ),
      );

      final sw = Stopwatch()..start();
      // Emulate initial loading of 50,000 tracks
      collections.initForTesting(bigList);
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(100),
          reason: 'Loading 50,000 favorites into memory must take < 100ms');

      final lookupSw = Stopwatch()..start();
      for (int i = 0; i < 1000; i++) {
        collections.isFavorite('C:\\Music\\song_$i.mp3');
      }
      lookupSw.stop();

      expect(lookupSw.elapsedMilliseconds, lessThan(20),
          reason: '1000 isFavorite lookups in 50k items must take < 20ms');
    });
  });
}
