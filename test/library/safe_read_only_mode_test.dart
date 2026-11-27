import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/diagnostics/diagnostic_report.dart';
import 'package:aestheticy/features/collections/m3u.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/features/history/play_recorder.dart';
import 'package:aestheticy/features/integration/app_shutdown.dart';
import 'package:aestheticy/features/library/artist_rules_sheet.dart';
import 'package:aestheticy/library/cover_cache.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite/legacy_userdata_migrator.dart';
import 'package:aestheticy/library/sqlite/userdata_backup_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/track_audio_source_mapper.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';
import 'package:aestheticy/platform/fake_platform_services.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/l10n/app_strings.dart';
import 'package:aestheticy/ui/library/track_actions_menu.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/settings/widgets/settings_system_sections.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';

void _seedLegacyDbForReadOnly(String libPath) {
  final db = sqlite3.open(libPath);
  db.execute('PRAGMA foreign_keys = ON;');
  db.execute('''
    CREATE TABLE folders (id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE, last_scan_at INTEGER);
    CREATE TABLE tracks (
      id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE,
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      title TEXT, artist TEXT, album_artist TEXT, album TEXT,
      track_no INTEGER, disc_no INTEGER, year INTEGER,
      duration_ms INTEGER NOT NULL, mtime_ms INTEGER NOT NULL, size_bytes INTEGER NOT NULL,
      cover_key TEXT, added_at INTEGER NOT NULL, search_text TEXT NOT NULL
    );
    CREATE TABLE track_artists (
      track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
      artist_key TEXT NOT NULL, artist_name TEXT NOT NULL, PRIMARY KEY(track_id, artist_key)
    );
    CREATE TABLE artist_aliases (alias_key TEXT PRIMARY KEY, canonical_key TEXT NOT NULL, canonical_name TEXT NOT NULL);
    CREATE TABLE artist_no_split (artist_key TEXT PRIMARY KEY, artist_name TEXT NOT NULL);
    CREATE TABLE play_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT, uri TEXT NOT NULL, title TEXT, artist TEXT,
      album TEXT, album_artist TEXT, duration_ms INTEGER, started_at_ms INTEGER NOT NULL,
      listened_ms INTEGER NOT NULL, counted INTEGER NOT NULL, completed INTEGER NOT NULL
    );
    CREATE TABLE favorites (path TEXT PRIMARY KEY, added_at_ms INTEGER NOT NULL);
    CREATE TABLE ratings (path TEXT PRIMARY KEY, stars INTEGER NOT NULL CHECK(stars BETWEEN 1 AND 5), rated_at_ms INTEGER NOT NULL);
    CREATE TABLE playlists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL);
    CREATE TABLE playlist_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT, playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
      position INTEGER NOT NULL, path TEXT NOT NULL, added_at_ms INTEGER NOT NULL
    );
    PRAGMA user_version = 4;
  ''');
  db.execute("INSERT INTO folders (id, path) VALUES (1, 'C:\\Music');");
  db.execute(
    'INSERT INTO tracks (id, path, folder_id, title, artist, album, duration_ms, mtime_ms, size_bytes, added_at, search_text) '
    "VALUES (1, 'C:\\Music\\song.mp3', 1, 'Morning Song', 'Fairouz', 'Morning', 200000, 10, 10, 1000, 'morning song fairouz');",
  );
  db.execute("INSERT INTO track_artists VALUES (1, 'fairouz', 'Fairouz');");
  db.execute("INSERT INTO artist_aliases VALUES ('fayrouz', 'fairouz', 'Fairouz');");
  db.execute("INSERT INTO artist_no_split VALUES ('simon & garfunkel', 'Simon & Garfunkel');");
  db.execute("INSERT INTO favorites VALUES ('C:\\Music\\song.mp3', 1000);");
  db.execute("INSERT INTO ratings VALUES ('C:\\Music\\song.mp3', 5, 1000);");
  db.execute("INSERT INTO playlists VALUES (1, 'Calm', 1000, 1000);");
  db.execute("INSERT INTO playlist_items VALUES (1, 1, 0, 'C:\\Music\\song.mp3', 1000);");
  db.execute(
    'INSERT INTO play_events (id, uri, title, artist, album, duration_ms, started_at_ms, listened_ms, counted, completed) '
    "VALUES (1, 'C:\\Music\\song.mp3', 'Morning Song', 'Fairouz', 'Morning', 200000, 5000, 180000, 1, 1);",
  );
  db.close();
}

SqliteLibraryRepository _openSafeReadOnlyRepo(Directory dir) {
  final libPath = p.join(dir.path, 'library.db');
  final backupsDir = Directory(p.join(dir.path, 'backups'));
  _seedLegacyDbForReadOnly(libPath);
  return SqliteLibraryRepository.openFile(
    libPath,
    backupsDir: backupsDir,
    migrationHooks: LegacyMigrationTestHooks(failBackup: () => true),
  );
}

void main() {
  group('S3 Safe Read-Only Mode contract', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('safe_read_only_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('ALLOWED: playback, library browsing, search, scanning, reading legacy user data, settings JSON, diagnostics, and normal quit',
        () async {
      final repo = _openSafeReadOnlyRepo(tempDir);
      addTearDown(repo.close);
      expect(repo.userDataAccessMode, equals(UserDataAccessMode.safeReadOnly));

      // 1. Library browsing
      final tracks = await repo.listTracks();
      expect(tracks, hasLength(1));
      expect(await repo.listAlbums(), hasLength(1));
      expect(await repo.listArtists(), hasLength(1));

      // 2. Search
      expect(await repo.search('Morning'), hasLength(1));
      expect(await repo.searchAlbums('Morning'), hasLength(1));
      expect(await repo.searchArtists('Fairouz'), hasLength(1));

      // 3. Playback of any track
      final engine = FakeAudioEngine();
      await engine.init();
      final controller = PlaybackController(engine: engine, queue: PlaybackQueue());
      await controller.init();
      await controller.playQueue([tracks.single.toAudioSource()]);
      expect(controller.currentState, equals(PlaybackState.playing));

      // 4. Folder scan and rescan (library.db is rebuildable)
      await CoverCache.ensureInitialized(
        directory: p.join(tempDir.path, 'covers'),
      );
      addTearDown(CoverCache.resetForTesting);
      final musicDir = Directory(p.join(tempDir.path, 'music'))..createSync();
      final scanService = ScanService(repository: repo);
      await scanService.addFolder(musicDir.path);
      await scanService.rescanAll();
      expect((await repo.listFolders()).length, equals(2));

      // 5. Reading user data from legacy tables
      expect(await repo.favoritePaths(), equals({'C:\\Music\\song.mp3'}));
      expect(await repo.favoriteTracks(), hasLength(1));
      expect(await repo.allRatings(), equals({'C:\\Music\\song.mp3': 5}));
      expect((await repo.listPlaylists()).single.name, equals('Calm'));
      expect((await repo.playlistEntries(1)).single.path, equals('C:\\Music\\song.mp3'));
      expect(await repo.playEventCount(), equals(1));
      expect((await repo.recentlyPlayedTracks()).single.title, equals('Morning Song'));
      expect((await repo.listAliases()).single.aliasKey, equals('fayrouz'));
      expect((await repo.listNoSplit()).single.artistName, equals('Simon & Garfunkel'));

      // 6. Settings (separate JSON file in temp dir)
      final settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();
      settingsStore.update((s) => s.copyWith(language: 'ar'));
      await settingsStore.flush();
      expect(
        File(p.join(tempDir.path, 'ui_settings.json')).existsSync(),
        isTrue,
      );

      // 7. Exporting diagnostics
      final report = buildDiagnosticReport(
        appName: 'Aestheticy',
        osVersion: 'Windows',
        dartVersion: '3.x',
        engineName: 'FakeAudioEngine',
        capabilities: engine.capabilities,
        outputDeviceName: 'Auto',
        exclusiveMode: false,
        eqEnabled: false,
        replayGainMode: ReplayGainMode.off,
        glassQuality: GlassQuality.full,
        language: 'en',
        textScale: 'normal',
        trackCount: await repo.trackCount(),
        albumCount: await repo.albumCount(),
        artistCount: await repo.artistCount(),
        folderCount: (await repo.listFolders()).length,
        schemaVersion: 4,
        resumeSession: true,
        playEventsCount: await repo.playEventCount(),
        mediaSessionStatus: 'disabled',
        trayEnabled: false,
        sleepPreventionEnabled: false,
        closeBehavior: 'exit',
        lyricsSource: 'local',
        miniPlayerShape: 'wide',
        miniPlayerPosition: 'bottomRight',
        logLines: const [],
      );
      expect(report, contains('Aestheticy'));

      // 8. Quitting normally
      final shutdown = AppShutdownCoordinator(
        settingsStore: settingsStore,
        mediaSessionService: FakeMediaSessionService(),
        sleepInhibitor: FakeSleepInhibitor(),
        trayService: FakeTrayService(),
        windowService: FakeWindowService(),
      );
      await shutdown.shutdown();
      scanService.dispose();
      await controller.dispose();
      await engine.dispose();
      settingsStore.dispose();
    });

    test('BLOCKED repository mutations throw UserDataReadOnlyException, skip play events with single warn log, block backup & migration retry, and leave legacy tables untouched',
        () async {
      final repo = _openSafeReadOnlyRepo(tempDir);
      addTearDown(repo.close);

      final logBuffer = StringBuffer();
      final testLogger = AppLogger(customSink: logBuffer);

      // Favorites
      await expectLater(
        repo.setFavorite('C:\\Music\\other.mp3', true),
        throwsA(isA<UserDataReadOnlyException>()),
      );
      await expectLater(
        repo.setFavorite('C:\\Music\\song.mp3', false),
        throwsA(isA<UserDataReadOnlyException>()),
      );

      // Ratings
      await expectLater(
        repo.setRating('C:\\Music\\song.mp3', 3),
        throwsA(isA<UserDataReadOnlyException>()),
      );

      // Playlists CRUD
      await expectLater(
        repo.createPlaylist('Blocked'),
        throwsA(isA<UserDataReadOnlyException>()),
      );
      await expectLater(
        repo.renamePlaylist(1, 'Renamed'),
        throwsA(isA<UserDataReadOnlyException>()),
      );
      await expectLater(
        repo.deletePlaylist(1),
        throwsA(isA<UserDataReadOnlyException>()),
      );
      await expectLater(
        repo.addToPlaylist(1, ['C:\\Music\\other.mp3']),
        throwsA(isA<UserDataReadOnlyException>()),
      );
      await expectLater(
        repo.removePlaylistEntries(1, [1]),
        throwsA(isA<UserDataReadOnlyException>()),
      );
      await expectLater(
        repo.movePlaylistEntry(1, 1, 0),
        throwsA(isA<UserDataReadOnlyException>()),
      );

      // Clear history
      await expectLater(
        repo.clearPlayEvents(),
        throwsA(isA<UserDataReadOnlyException>()),
      );

      // Artist aliases & no-split rules
      await expectLater(
        repo.mergeArtists('a', 'b'),
        throwsA(isA<UserDataReadOnlyException>()),
      );
      await expectLater(
        repo.unmergeArtist('fayrouz'),
        throwsA(isA<UserDataReadOnlyException>()),
      );
      await expectLater(
        repo.addNoSplit('A & B'),
        throwsA(isA<UserDataReadOnlyException>()),
      );
      await expectLater(
        repo.removeNoSplit('simon & garfunkel'),
        throwsA(isA<UserDataReadOnlyException>()),
      );

      // PlayRecorder skips silently with a single warning log per run
      var clockNow = DateTime.utc(2026, 11, 26, 10, 0, 0);
      final engine = FakeAudioEngine();
      await engine.init();
      final controller = PlaybackController(engine: engine, queue: PlaybackQueue());
      await controller.init();
      final recorder = PlayRecorder(
        controller: controller,
        repository: repo,
        clock: () => clockNow,
        logger: testLogger,
      );
      await controller.playQueue([
        const AudioSource(
          'C:\\Music\\song.mp3',
          extras: {'durationMs': '60000'},
        ),
        const AudioSource(
          'C:\\Music\\song2.mp3',
          extras: {'durationMs': '60000'},
        ),
      ]);
      clockNow = clockNow.add(const Duration(seconds: 35));
      recorder.checkThreshold();
      await controller.skipNext();
      clockNow = clockNow.add(const Duration(seconds: 35));
      recorder.checkThreshold();
      await recorder.dispose();
      await controller.dispose();
      await engine.dispose();

      final warnLines = logBuffer
          .toString()
          .split('\n')
          .where((l) => l.contains('[WARN]') && l.contains('[PlayRecorder]'))
          .toList();
      expect(warnLines, hasLength(1));
      expect(await repo.playEventCount(), equals(1)); // untouched

      // Daily backup service skipped
      final backupSvc = SqliteUserDataBackupService(
        backupsUserDataDir: Directory(p.join(tempDir.path, 'backups', 'userdata')),
        userDataDbPath: p.join(tempDir.path, 'userdata.db'),
        databaseProvider: () => repo.rawDatabase,
      );
      expect(
        await backupSvc.runDailyBackup(accessMode: repo.userDataAccessMode),
        isNull,
      );

      // No second migration attempt in the same run
      expect(await repo.retryLegacyMigrationOnce(), isFalse);

      // Legacy tables remain completely untouched
      expect(await repo.favoritePaths(), equals({'C:\\Music\\song.mp3'}));
      expect((await repo.listPlaylists()).single.name, equals('Calm'));
    });

    testWidgets(
      'AppShell displays persistent localized SafeReadOnlyBanner (en + ar RTL) with Open Logs and Open Backups actions',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final repo = _openSafeReadOnlyRepo(tempDir);
        addTearDown(repo.close);

        for (final lang in ['en', 'ar']) {
          final settingsStore = SettingsStore(
            initialSettings: AppSettings(language: lang),
          );
          final engine = FakeAudioEngine();
          final controller =
              PlaybackController(engine: engine, queue: PlaybackQueue());
          final scanService = ScanService(repository: repo);
          var logsOpened = false;
          var backupsOpened = false;

          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(lang),
              builder: (context, child) => Directionality(
                textDirection:
                    lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                child: SettingsScope(store: settingsStore, child: child!),
              ),
              home: AppShell(
                engine: engine,
                controller: controller,
                repository: repo,
                scanService: scanService,
                settingsStore: settingsStore,
                navigator: AppNavigator(),
                onOpenLogsFolder: () => logsOpened = true,
                onOpenBackupsFolder: () => backupsOpened = true,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('safe_read_only_banner')), findsOneWidget);
          expect(
            find.text(AppStrings.t('userdata.safeReadOnlyBannerTitle', language: lang)),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('safe_read_only_open_logs')));
          await tester.tap(find.byKey(const Key('safe_read_only_open_backups')));
          await tester.pump();
          expect(logsOpened, isTrue);
          expect(backupsOpened, isTrue);

          await tester.pumpWidget(const SizedBox());
          scanService.dispose();
          await controller.dispose();
          await engine.dispose();
          settingsStore.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'UI blocked actions (UserCollections, M3U import, playlist dialog, clear history, artist rules) show localized messages and never crash',
      (tester) async {
        final repo = _openSafeReadOnlyRepo(tempDir);
        addTearDown(repo.close);

        final blockedMessages = <String>[];
        final collections = UserCollections(
          repository: repo,
          onReadOnlyBlocked: blockedMessages.add,
        );
        await collections.init();

        // UserCollections optimistic toggle reverts + notifies
        await collections.toggleFavorite('C:\\Music\\other.mp3');
        expect(collections.isFavorite('C:\\Music\\other.mp3'), isFalse);
        await collections.setRating('C:\\Music\\song.mp3', 2);
        expect(collections.ratingOf('C:\\Music\\song.mp3'), equals(5));
        expect(blockedMessages, hasLength(2));

        final settingsStore = SettingsStore(
          initialSettings: const AppSettings(language: 'en'),
        );
        var confirmingClear = true;

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScope(
              store: settingsStore,
              child: Scaffold(
                body: Builder(
                  builder: (ctx) => Column(
                    children: [
                      ElevatedButton(
                        key: const Key('test_import_m3u'),
                        onPressed: () {
                          M3u.importPlaylistWithSummary(
                            ctx,
                            repository: repo,
                            collections: collections,
                          );
                        },
                        child: const Text('Import'),
                      ),
                      ElevatedButton(
                        key: const Key('test_create_pl'),
                        onPressed: () {
                          showCreatePlaylistDialog(
                            ctx,
                            collections: collections,
                          );
                        },
                        child: const Text('Create'),
                      ),
                      Expanded(
                        child: ArtistRulesSheet(repository: repo),
                      ),
                      SettingsHistorySection(
                        repository: repo,
                        isLoadingStats: false,
                        playEventCount: 1,
                        isConfirmingClear: confirmingClear,
                        onConfirmingClearChanged: (bool v) =>
                            confirmingClear = v,
                        onHistoryCleared: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // M3U import blocked with localized SnackBar
        await tester.tap(find.byKey(const Key('test_import_m3u')));
        await tester.pump();
        expect(
          find.text(AppStrings.t('userdata.safeReadOnlyBlocked')),
          findsOneWidget,
        );

        // Clear history blocked with localized SnackBar
        await tester.tap(find.byKey(const Key('settings_clear_history_confirm_button')));
        await tester.pump();
        expect(
          find.text(AppStrings.t('userdata.safeReadOnlyBlocked')),
          findsOneWidget,
        );

        // Create playlist dialog shows localized error message
        await tester.tap(find.byKey(const Key('test_create_pl')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('create_playlist_text_field')),
          'New Mix',
        );
        await tester.tap(find.byKey(const Key('create_playlist_submit_button')));
        await tester.pumpAndSettle();
        expect(
          find.text(AppStrings.t('userdata.safeReadOnlyBlocked')),
          findsWidgets,
        );

        settingsStore.dispose();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'AppShell shows localized one-time startup SnackBars for library corrupt recreate and userdata restore',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await CoverCache.ensureInitialized(
          directory: p.join(tempDir.path, 'covers'),
        );
        addTearDown(CoverCache.resetForTesting);
        final repo = SqliteLibraryRepository.inMemory();
        addTearDown(repo.close);
        final settingsStore = SettingsStore(
          initialSettings: const AppSettings(language: 'en'),
        );
        final engine = FakeAudioEngine();
        final controller =
            PlaybackController(engine: engine, queue: PlaybackQueue());
        final scanService = ScanService(repository: repo);

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScope(
              store: settingsStore,
              child: AppShell(
                engine: engine,
                controller: controller,
                repository: repo,
                scanService: scanService,
                settingsStore: settingsStore,
                navigator: AppNavigator(),
                startupReport: const DatabaseStartupReport.normal(
                  libraryRecreatedAfterCorruption: true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.text(AppStrings.t('userdata.libraryCorruptNotice')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox());
        scanService.dispose();
        await controller.dispose();
        await engine.dispose();
        settingsStore.dispose();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
