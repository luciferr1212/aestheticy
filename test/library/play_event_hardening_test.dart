import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/history/play_recorder.dart';
import 'package:aestheticy/library/history_models.dart';
import 'package:aestheticy/library/migrations.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/userdata_migrator.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/startup_identity_reconciler.dart';

void main() {
  group('Play-Event Log Hardening (S3)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_history_s3_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    AudioSource makeSource(String path, String title, int durationSec) {
      return AudioSource(
        path,
        extras: {
          'title': title,
          'artist': 'Artist $title',
          'album': 'Album $title',
          'albumArtist': 'Artist $title',
          'durationMs': (durationSec * 1000).toString(),
        },
      );
    }

    test(
        'fills track_uid, source, session_id, ended_reason (completed/skipped/stopped/error) via PlayRecorder',
        () async {
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);
      final folder = await repo.addFolder('C:\\Music');

      const path1 = 'C:\\Music\\song1.mp3';
      const path2 = 'C:\\Music\\song2.mp3';
      const path3 = 'C:\\Music\\song3.mp3';
      await repo.upsertTracks([
        Track(
          path: path1,
          folderId: folder.id!,
          title: 'Song 1',
          artist: 'Artist 1',
          album: 'Album 1',
          durationMs: 60000,
          mtimeMs: 1000,
          sizeBytes: 1024,
          addedAt: DateTime.utc(2026, 11, 20),
        ),
        Track(
          path: path2,
          folderId: folder.id!,
          title: 'Song 2',
          artist: 'Artist 2',
          album: 'Album 2',
          durationMs: 60000,
          mtimeMs: 1000,
          sizeBytes: 1024,
          addedAt: DateTime.utc(2026, 11, 20),
        ),
        Track(
          path: path3,
          folderId: folder.id!,
          title: 'Song 3',
          artist: 'Artist 3',
          album: 'Album 3',
          durationMs: 60000,
          mtimeMs: 1000,
          sizeBytes: 1024,
          addedAt: DateTime.utc(2026, 11, 20),
        ),
      ]);
      await repo.reconcileTrackIdentities();

      final engine = FakeAudioEngine();
      final queue = PlaybackQueue();
      final controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
      addTearDown(controller.dispose);
      addTearDown(engine.dispose);

      var now = DateTime.utc(2026, 11, 26, 10, 0, 0);
      final recorder = PlayRecorder(
        controller: controller,
        repository: repo,
        clock: () => now,
        sessionId: 'fixed-session-id-123',
      );
      addTearDown(recorder.dispose);

      // 1. Play from 'album' and complete
      engine.fakeDuration = const Duration(seconds: 60);
      await controller.playQueue(
        [
          makeSource(path1, 'Song 1', 60),
          makeSource(path2, 'Song 2', 60),
          makeSource(path3, 'Song 3', 60),
        ],
        source: 'album',
      );
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 60));
      engine.simulateCompletion();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 2. Skip song 2 after 12s -> endedReason = 'skipped'
      now = now.add(const Duration(seconds: 12));
      await controller.skipNext();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 3. Stop song 3 via clearQueue after 8s -> endedReason = 'stopped'
      now = now.add(const Duration(seconds: 8));
      await controller.clearQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 4. Play from 'favorites' and hit playback error after 6s -> endedReason = 'error'
      await controller.playQueue(
        [makeSource(path1, 'Song 1', 60)],
        source: 'favorites',
      );
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 6));
      engine.simulateError(const AudioError(
        code: AudioErrorCode.engineFailure,
        message: 'Decode failure',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final events = await repo.recentPlayEvents(limit: 10);
      expect(events, hasLength(4));

      // Chronological reverse order (newest first):
      final errEvent = events[0];
      expect(errEvent.endedReason, equals('error'));
      expect(errEvent.source, equals('favorites'));
      expect(errEvent.sessionId, equals('fixed-session-id-123'));
      expect(errEvent.trackUid, equals(await repo.resolveTrackUid(path1)));

      final stopEvent = events[1];
      expect(stopEvent.endedReason, equals('stopped'));
      expect(stopEvent.source, equals('album'));
      expect(stopEvent.trackUid, equals(await repo.resolveTrackUid(path3)));

      final skipEvent = events[2];
      expect(skipEvent.endedReason, equals('skipped'));
      expect(skipEvent.counted, isFalse);
      expect(skipEvent.trackUid, equals(await repo.resolveTrackUid(path2)));

      final completeEvent = events[3];
      expect(completeEvent.endedReason, equals('completed'));
      expect(completeEvent.completed, isTrue);
      expect(completeEvent.counted, isTrue);
      expect(completeEvent.trackUid, equals(await repo.resolveTrackUid(path1)));
    });

    test(
        'heartbeat updates listened_ms while playing and closes unended rows as interrupted on next startup',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final userPath = p.join(tempDir.path, 'userdata.db');
      final backupsDir = Directory(p.join(tempDir.path, 'backups'));

      final repo1 = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
      );
      final folder = await repo1.addFolder('C:\\Music');
      const trackPath = 'C:\\Music\\long_symphony.flac';
      await repo1.upsertTracks([
        Track(
          path: trackPath,
          folderId: folder.id!,
          title: 'Long Symphony',
          artist: 'Orchestra',
          album: 'Live',
          durationMs: 600000, // threshold 240s
          mtimeMs: 1000,
          sizeBytes: 20480,
          addedAt: DateTime.utc(2026, 11, 20),
        ),
      ]);
      await repo1.reconcileTrackIdentities();

      final engine = FakeAudioEngine();
      final controller = PlaybackController(
        engine: engine,
        queue: PlaybackQueue(),
      );
      await controller.init();

      var now = DateTime.utc(2026, 11, 26, 14, 0, 0);
      final recorder = PlayRecorder(
        controller: controller,
        repository: repo1,
        clock: () => now,
        heartbeatInterval: const Duration(seconds: 30),
      );

      await controller.playQueue(
        [makeSource(trackPath, 'Long Symphony', 600)],
        source: 'playlist',
      );
      await Future<void>.delayed(Duration.zero);

      // First heartbeat at 30s (before 240s threshold!) creates open row.
      now = now.add(const Duration(seconds: 30));
      await recorder.sendHeartbeat();

      var events = await repo1.recentPlayEvents();
      expect(events, hasLength(1));
      expect(events.first.listenedMs, equals(30000));
      expect(events.first.counted, isFalse);
      expect(events.first.endedReason, isNull);

      // Second heartbeat at 60s updates listened_ms in-place (no duplicate row).
      now = now.add(const Duration(seconds: 30));
      await recorder.sendHeartbeat();

      events = await repo1.recentPlayEvents();
      expect(events, hasLength(1));
      expect(events.first.listenedMs, equals(60000));
      expect(events.first.endedReason, isNull);

      // Simulate abrupt crash by closing DB without calling recorder.dispose().
      await controller.dispose();
      await engine.dispose();
      await repo1.close();

      // Reopen on next startup and close interrupted events.
      final repo2 = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: backupsDir,
      );
      addTearDown(repo2.close);
      final interruptedCount = await repo2.closeInterruptedPlayEvents();
      expect(interruptedCount, equals(1));

      final recovered = (await repo2.recentPlayEvents()).single;
      expect(recovered.endedReason, equals('interrupted'));
      expect(recovered.listenedMs, equals(60000));
      expect(recovered.source, equals('playlist'));
    });

    test(
        'backfills track_uid for legacy events, indexes started_at_ms & track_uid, and executes all analytics queries cleanly',
        () async {
      final libPath = p.join(tempDir.path, 'analytics_lib.db');
      final userPath = p.join(tempDir.path, 'analytics_user.db');
      final raw = sqlite3.open(libPath);
      raw.execute("ATTACH DATABASE '${userPath.replaceAll("'", "''")}' AS userdata;");
      SchemaMigrator.apply(raw);
      UserDataMigrator.createV1SchemaStatements(raw);
      raw.execute('PRAGMA userdata.user_version = 1;');
      raw.execute(
        'INSERT INTO userdata.play_events (uri, title, artist, album, started_at_ms, listened_ms, counted, completed) '
        "VALUES ('C:\\Music\\track_a.mp3', 'Track A', 'Artist 1', 'Album X', ?, 120000, 1, 1);",
        [DateTime.utc(2026, 11, 1, 10).millisecondsSinceEpoch],
      );
      raw.close();

      final repo = SqliteLibraryRepository.openFile(
        libPath,
        userDataPath: userPath,
        backupsDir: Directory(p.join(tempDir.path, 'backups')),
      );
      addTearDown(repo.close);

      // Verify both indexes exist on userdata.play_events
      final indexes = repo.rawDatabase
          .select(
            "SELECT name FROM userdata.sqlite_master WHERE type = 'index' AND tbl_name = 'play_events';",
          )
          .map((r) => r['name'] as String)
          .toSet();
      expect(indexes, contains('idx_play_events_started_at_ms'));
      expect(indexes, contains('idx_play_events_track_uid'));

      // Run post-startup identity backfill reconcile once tracks/library are ready
      await StartupIdentityReconciler(repository: repo).runOnce();
      final uidA = await repo.resolveTrackUid('C:\\Music\\track_a.mp3');
      expect(uidA, isNotNull);
      final backfilled = (await repo.recentPlayEvents()).single;
      expect(backfilled.trackUid, equals(uidA));
      expect(await repo.backfillPlayEventTrackUids(), equals(0));

      // Seed additional events across multiple days, tracks, artists, and albums
      await repo.insertPlayEvent(PlayEvent(
        uri: 'C:\\Music\\track_a.mp3',
        title: 'Track A',
        artist: 'Artist 1',
        album: 'Album X',
        startedAt: DateTime.utc(2026, 11, 10, 14),
        listenedMs: 180000,
        counted: true,
        completed: true,
      ));
      await repo.insertPlayEvent(PlayEvent(
        uri: 'C:\\Music\\track_b.mp3',
        title: 'Track B',
        artist: 'Artist 1',
        album: 'Album X',
        startedAt: DateTime.utc(2026, 11, 10, 16),
        listenedMs: 240000,
        counted: true,
        completed: true,
      ));
      await repo.insertPlayEvent(PlayEvent(
        uri: 'C:\\Music\\track_c.mp3',
        title: 'Track C',
        artist: 'Artist 2',
        album: 'Album Y',
        startedAt: DateTime.utc(2026, 11, 11, 9),
        listenedMs: 90000,
        counted: true,
        completed: false,
      ));

      final rangeStart = DateTime.utc(2026, 11, 10, 0);
      final rangeEnd = DateTime.utc(2026, 11, 11, 23, 59, 59);

      // 1. Events between dates
      final between = await repo.playEventsBetween(rangeStart, rangeEnd);
      expect(between.map((e) => e.title), equals(['Track A', 'Track B', 'Track C']));

      // 2. Top tracks (Track B has 240s > Track A 180s > Track C 90s in range)
      final topTracks = await repo.topTracksInRange(
        rangeStart,
        rangeEnd,
        metric: HistoryRankingMetric.listenedMs,
      );
      expect(topTracks.map((t) => t.title), equals(['Track B', 'Track A', 'Track C']));
      expect(topTracks.first.totalListenedMs, equals(240000));

      // Full range by playCount puts Track A (2 plays) first
      final topTracksByCount = await repo.topTracksInRange(
        DateTime.utc(2026, 10, 31),
        rangeEnd,
        metric: HistoryRankingMetric.playCount,
      );
      expect(topTracksByCount.first.title, equals('Track A'));
      expect(topTracksByCount.first.playCount, equals(2));

      // 3. Top artists
      final topArtists = await repo.topArtistsInRange(rangeStart, rangeEnd);
      expect(topArtists, hasLength(2));
      expect(topArtists.first.artist, equals('Artist 1'));
      expect(topArtists.first.totalListenedMs, equals(420000));
      expect(topArtists.first.playCount, equals(2));

      // 4. Top albums
      final topAlbums = await repo.topAlbumsInRange(rangeStart, rangeEnd);
      expect(topAlbums, hasLength(2));
      expect(topAlbums.first.album, equals('Album X'));
      expect(topAlbums.first.totalListenedMs, equals(420000));

      // 5. Listening minutes per day
      final daily = await repo.listeningMinutesPerDay(rangeStart, rangeEnd);
      expect(daily, hasLength(2));
      expect(daily[0].dateKey, equals('2026-11-10'));
      expect(daily[0].totalListenedMs, equals(420000));
      expect(daily[0].minutes, closeTo(7.0, 0.001));
      expect(daily[1].dateKey, equals('2026-11-11'));
      expect(daily[1].totalListenedMs, equals(90000));

      // 6. Distinct tracks first played in range (Track A was first played Nov 1, so only B & C count for Nov 10..11)
      final newDiscoveries = await repo.distinctTracksFirstPlayedInRange(
        rangeStart,
        rangeEnd,
      );
      expect(newDiscoveries, equals(2));

      // 7. clearPlayEvents still clears all history cleanly
      await repo.clearPlayEvents();
      expect(await repo.playEventCount(), equals(0));
    });
  });
}
