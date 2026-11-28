import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/session/saved_session.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/ui/home/home_controller.dart';
import 'package:aestheticy/ui/home/home_models.dart';
import 'package:aestheticy/ui/library/library_data_cache.dart';

import '../../library/fake_library_repository.dart';

class _ThrowingHomeRepo extends FakeLibraryRepository {
  bool throwOnRecentAlbums = false;
  bool throwOnForgotten = false;

  @override
  Future<List<AlbumSummary>> recentAlbumsPlayed({int limit = 8}) async {
    if (throwOnRecentAlbums) throw StateError('db error');
    return super.recentAlbumsPlayed(limit: limit);
  }

  @override
  Future<List<Track>> forgottenFavorites({
    required Duration olderThan,
    int limit = 8,
    DateTime? now,
  }) async {
    if (throwOnForgotten) throw StateError('forgotten error');
    return super.forgottenFavorites(
      olderThan: olderThan,
      limit: limit,
      now: now,
    );
  }
}

Track _track(String path, String title, String album, DateTime addedAt) {
  return Track(
    path: path,
    folderId: 1,
    title: title,
    artist: 'Artist',
    albumArtist: 'Artist',
    album: album,
    durationMs: 180000,
    mtimeMs: 1000,
    sizeBytes: 1024,
    addedAt: addedAt,
  );
}

void main() {
  group('HomeController', () {
    late FakeAudioEngine engine;
    late PlaybackController playback;
    late _ThrowingHomeRepo repo;
    late ScanService scanService;
    late LibraryDataCache dataCache;

    setUp(() async {
      engine = FakeAudioEngine();
      await engine.init();
      playback = PlaybackController(engine: engine, queue: PlaybackQueue());
      await playback.init();
      repo = _ThrowingHomeRepo();
      await repo.addFolder('C:\\Music');
      scanService = ScanService(repository: repo);
      dataCache = LibraryDataCache(repository: repo, scanService: scanService);
    });

    tearDown(() async {
      dataCache.dispose();
      scanService.dispose();
      await playback.dispose();
      await engine.dispose();
    });

    test(
      'rotates deterministically across consecutive days using local daysSinceEpoch modulo non-empty candidates',
      () async {
        // Seed all 4 rotating candidates
        final t1 = _track(
          'C:\\Music\\1.mp3',
          'Track One',
          'Album One',
          DateTime.utc(2026, 11, 20),
        );
        final t2 = _track(
          'C:\\Music\\2.mp3',
          'Track Two',
          'Album Two',
          DateTime.utc(2026, 11, 21),
        );
        await repo.upsertTracks([t1, t2]);
        await repo.setFavorite(t1.path, true); // forgottenFavorite
        // On this day in 2025 (for 2026-11-28..2026-12-01? let's seed plays on all 4 consecutive days or test pickRotatingRow)
        await repo.insertPlayEvent(
          PlayEvent(
            uri: t2.path,
            startedAt: DateTime(2025, 11, 28, 10),
            listenedMs: 120000,
            counted: true,
            completed: true,
          ),
        );
        await repo.insertPlayEvent(
          PlayEvent(
            uri: t2.path,
            startedAt: DateTime(2026, 11, 15, 10),
            listenedMs: 120000,
            counted: true,
            completed: true,
          ),
        );

        // Verify pickRotatingRow cycles cleanly through all 4 kinds over 4 consecutive days
        final baseDay = DateTime(2026, 11, 28, 9);
        final kinds = <HomeRotatingRowKind>{};
        for (var d = 0; d < 4; d++) {
          final day = baseDay.add(Duration(days: d));
          final row = HomeController.pickRotatingRow(
            localDate: day,
            recentlyAdded: const [AlbumSummary(album: 'A', trackCount: 1)],
            forgottenFavorites: [t1],
            onThisDay: [t2],
            mostPlayedThisMonth: [t2],
          );
          expect(row, isNotNull);
          kinds.add(row!.kind);
          // Deterministic repeat on same day at different hour
          final sameDayNight = DateTime(day.year, day.month, day.day, 23, 30);
          final rowAgain = HomeController.pickRotatingRow(
            localDate: sameDayNight,
            recentlyAdded: const [AlbumSummary(album: 'A', trackCount: 1)],
            forgottenFavorites: [t1],
            onThisDay: [t2],
            mostPlayedThisMonth: [t2],
          );
          expect(rowAgain?.kind, row.kind);
        }
        expect(kinds.length, 4);

        // Skipping empty candidates: with only recentlyAdded + mostPlayedThisMonth non-empty,
        // controller alternates only between those 2 on consecutive days
        var now = DateTime(2026, 11, 28, 10);
        final ctrl = HomeController(
          repository: repo,
          playbackController: playback,
          dataCache: dataCache,
          clock: () => now,
        );
        addTearDown(ctrl.dispose);

        await ctrl.refresh();
        final firstKind = ctrl.rotatingRow?.kind;
        expect(firstKind, isNotNull);

        now = DateTime(2026, 11, 29, 10);
        await ctrl.refresh();
        expect(ctrl.rotatingRow?.kind, isNotNull);
        expect(ctrl.rotatingRow?.kind, isNot(firstKind));
      },
    );

    test(
      'empty candidate rows are skipped and returns null when all 4 are empty',
      () async {
        final none = HomeController.pickRotatingRow(
          localDate: DateTime(2026, 11, 28),
          recentlyAdded: const [],
          forgottenFavorites: const [],
          onThisDay: const [],
          mostPlayedThisMonth: const [],
        );
        expect(none, isNull);

        final t1 = _track(
          'C:\\Music\\only.mp3',
          'Only Track',
          'Only Album',
          DateTime.utc(2026, 11, 1),
        );
        for (var d = 0; d < 5; d++) {
          final picked = HomeController.pickRotatingRow(
            localDate: DateTime(2026, 11, 28 + d),
            recentlyAdded: const [],
            forgottenFavorites: [t1],
            onThisDay: const [],
            mostPlayedThisMonth: const [],
          );
          expect(picked?.kind, HomeRotatingRowKind.forgottenFavorites);
        }
      },
    );

    test(
      'tracks nowPlaying and resumeSession summaries and revalidates stale-while-revalidate via LibraryDataCache',
      () async {
        final t1 = _track(
          'C:\\Music\\song.mp3',
          'Cached Title',
          'Cached Album',
          DateTime.utc(2026, 11, 1),
        ).copyWith(coverKey: 'cov_123');
        await repo.upsertTracks([t1]);

        final sessionStore = SessionStore(
          initialSession: SavedSession(
            queue: [
              SavedSessionItem(
                entryId: 1,
                uri: t1.path,
                extras: const {'title': 'Session Song', 'artist': 'Artist X'},
              ),
            ],
            currentIndex: 0,
            currentEntryId: 1,
          ),
        );
        addTearDown(sessionStore.dispose);

        final ctrl = HomeController(
          repository: repo,
          playbackController: playback,
          dataCache: dataCache,
          sessionStore: sessionStore,
          clock: () => DateTime(2026, 11, 28, 14),
        );
        addTearDown(ctrl.dispose);

        expect(ctrl.nowPlaying.hasTrack, isFalse);
        expect(ctrl.resumeSession?.title, 'Session Song');
        expect(ctrl.resumeSession?.trackCount, 1);

        // Start playback -> nowPlaying updates
        await playback.playQueue([
          AudioSource(
            t1.path,
            extras: const {'title': 'Playing Now', 'artist': 'Artist Y'},
          ),
        ]);
        await Future<void>.delayed(Duration.zero);
        expect(ctrl.nowPlaying.hasTrack, isTrue);
        expect(ctrl.nowPlaying.title, 'Playing Now');
        expect(ctrl.nowPlaying.isPlaying, isTrue);

        await playback.pause();
        await Future<void>.delayed(Duration.zero);
        expect(ctrl.nowPlaying.isPlaying, isFalse);

        // Stale-while-revalidate via dataCache
        await ctrl.refresh();
        expect(ctrl.rotatingRow?.kind, HomeRotatingRowKind.recentlyAdded);
        expect(ctrl.rotatingRow?.albums.first.album, 'Cached Album');

        // Seed cache update -> controller refreshes in background without clearing old data first
        dataCache.seed(tracks: [t1]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(ctrl.hasLoaded, isTrue);
        expect(ctrl.rotatingRow?.albums.first.album, 'Cached Album');
      },
    );

    test(
      'query error is logged and hides only the failing row without throwing',
      () async {
        final t1 = _track(
          'C:\\Music\\ok.mp3',
          'Ok Song',
          'Ok Album',
          DateTime.utc(2026, 11, 20),
        );
        await repo.upsertTracks([t1]);
        repo.throwOnRecentAlbums = true;

        final ctrl = HomeController(
          repository: repo,
          playbackController: playback,
          dataCache: dataCache,
          clock: () => DateTime(2026, 11, 28, 9),
        );
        addTearDown(ctrl.dispose);

        await ctrl.refresh();
        expect(ctrl.hasLoaded, isTrue);
        expect(ctrl.continueListening, isEmpty);
        expect(ctrl.rotatingRow, isNotNull);
        expect(ctrl.rotatingRow!.kind, HomeRotatingRowKind.recentlyAdded);
      },
    );
  });
}
