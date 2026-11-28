import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite/legacy_userdata_migrator.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/l10n/app_strings.dart';
import 'package:aestheticy/ui/library/library_data_cache.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import 'package:aestheticy/ui/wrapped/wrapped_view.dart';

void main() {
  group('WrappedView & Recap Flow Tests', () {
    late FakeAudioEngine engine;
    late PlaybackController controller;
    late SqliteLibraryRepository repo;
    late ScanService scanService;
    late LibraryDataCache dataCache;
    late SettingsStore settingsStore;
    late GlassController glassController;
    late ArtistNameStore artistNameStore;
    late AppNavigator navigator;
    final fakeNow = DateTime(2026, 11, 28, 15, 0);

    setUp(() async {
      engine = FakeAudioEngine();
      await engine.init();
      controller = PlaybackController(engine: engine, queue: PlaybackQueue());
      await controller.init();
      repo = SqliteLibraryRepository.inMemory();
      scanService = ScanService(repository: repo);
      dataCache = LibraryDataCache(repository: repo, scanService: scanService);
      settingsStore = SettingsStore(
        initialSettings: const AppSettings(
          language: 'en',
          arabicNumerals: false,
          glassQuality: GlassQuality.light,
          reduceMotion: true,
        ),
      );
      glassController = GlassController();
      settingsStore.bindGlassController(glassController);
      artistNameStore = ArtistNameStore();
      navigator = AppNavigator(initialDestination: AppDestination.home);
    });

    tearDown(() async {
      dataCache.dispose();
      scanService.dispose();
      settingsStore.dispose();
      artistNameStore.dispose();
      glassController.dispose();
      await repo.close();
      await controller.dispose();
      await engine.dispose();
    });

    Future<void> seedMonth(
      SqliteLibraryRepository target, {
      required int count,
      int year = 2026,
      int month = 11,
      int hour = 14,
    }) async {
      final existingFolders = await target.listFolders();
      final folder = existingFolders.isNotEmpty
          ? existingFolders.first
          : await target.addFolder('C:\\Music');
      final tracks = <Track>[
        for (var i = 0; i < 6; i++)
          Track(
            path: 'C:\\Music\\track_$i.mp3',
            folderId: folder.id!,
            title: 'Track Title $i',
            artist: i.isEven ? 'Fairouz' : 'Omar Khairat',
            albumArtist: i.isEven ? 'Fairouz' : 'Omar Khairat',
            album: i < 3 ? 'Winter Suites' : 'Desert Wind',
            durationMs: 240000,
            mtimeMs: 1000,
            sizeBytes: 2048,
            addedAt: DateTime(year, month, 1),
          ),
      ];
      await target.upsertTracks(tracks);

      for (var i = 0; i < count; i++) {
        final t = tracks[i % tracks.length];
        await target.insertPlayEvent(
          PlayEvent(
            uri: t.path,
            title: t.title,
            artist: t.artist,
            album: t.album,
            albumArtist: t.albumArtist,
            durationMs: t.durationMs,
            startedAt: DateTime(year, month, 1 + (i % 25), hour, i % 50),
            listenedMs: 180000, // 3m each
            counted: true,
            completed: true,
          ),
        );
      }
    }

    Widget wrapShell({LibraryRepository? customRepo}) {
      final useRepo = customRepo ?? repo;
      final useCache = customRepo != null
          ? LibraryDataCache(repository: useRepo)
          : dataCache;
      if (customRepo != null) {
        addTearDown(useCache.dispose);
      }
      return SettingsScope(
        store: settingsStore,
        child: GlassScope(
          controller: glassController,
          child: ArtistNameScope(
            store: artistNameStore,
            child: ListenableBuilder(
              listenable: settingsStore,
              builder: (context, _) {
                final lang = settingsStore.settings.language;
                return MaterialApp(
                  theme: buildAppTheme(),
                  locale: Locale(lang),
                  builder: (context, child) => Directionality(
                    textDirection: lang == 'ar'
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: child ?? const SizedBox.shrink(),
                  ),
                  home: AppShell(
                    engine: engine,
                    controller: controller,
                    repository: useRepo,
                    scanService: scanService,
                    settingsStore: settingsStore,
                    navigator: navigator,
                    dataCache: useCache,
                    homeClock: () => fakeNow,
                    statsClock: () => fakeNow,
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    Widget wrapStandaloneWrapped({
      LibraryRepository? customRepo,
      double mediaTextScale = 1.0,
    }) {
      final useRepo = customRepo ?? repo;
      final useCache = customRepo != null
          ? LibraryDataCache(repository: useRepo)
          : dataCache;
      if (customRepo != null) {
        addTearDown(useCache.dispose);
      }
      return SettingsScope(
        store: settingsStore,
        child: GlassScope(
          controller: glassController,
          child: ArtistNameScope(
            store: artistNameStore,
            child: ListenableBuilder(
              listenable: settingsStore,
              builder: (context, _) {
                final lang = settingsStore.settings.language;
                return MaterialApp(
                  theme: buildAppTheme(),
                  locale: Locale(lang),
                  builder: (context, child) {
                    final mq = MediaQuery.of(context);
                    return MediaQuery(
                      data: mq.copyWith(
                        textScaler: TextScaler.linear(mediaTextScale),
                      ),
                      child: Directionality(
                        textDirection: lang == 'ar'
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: child ?? const SizedBox.shrink(),
                      ),
                    );
                  },
                  home: Scaffold(
                    body: WrappedView(
                      repository: useRepo,
                      settingsStore: settingsStore,
                      navigator: navigator,
                      dataCache: useCache,
                      clock: () => fakeNow,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    testWidgets(
      'navigates from Home and Stats weekly section, pages all 8 cards via buttons & keyboard in EN',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await seedMonth(repo, count: 22, month: 11);
        await seedMonth(repo, count: 20, month: 10);
        await dataCache.refresh();

        await tester.pumpWidget(wrapShell());
        await tester.pumpAndSettle();

        // Open Wrapped directly from Home
        await tester.tap(find.byKey(const Key('home_wrapped_button')));
        await tester.pumpAndSettle();
        expect(navigator.current, AppDestination.wrapped);
        expect(find.byKey(const Key('wrapped_card_0')), findsOneWidget);
        expect(find.byKey(const Key('wrapped_month_selector')), findsOneWidget);
        expect(find.text('1 / 8'), findsOneWidget);

        // Next card via arrow button
        await tester.tap(find.byKey(const Key('wrapped_next_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('wrapped_card_1')), findsOneWidget);
        expect(find.text('2 / 8'), findsOneWidget);

        // Right/Left keyboard navigation across remaining cards to summary (card 7)
        for (var i = 0; i < 6; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
        }
        expect(find.byKey(const Key('wrapped_card_7')), findsOneWidget);
        expect(find.text('8 / 8'), findsOneWidget);
        expect(
          find.byKey(const Key('wrapped_summary_share_button')),
          findsOneWidget,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('wrapped_card_6')), findsOneWidget);

        // Navigate to Stats and open Weekly recap from Weekly listening activity
        navigator.openStats();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('stats_weekly_recap_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('wrapped_header_title')), findsOneWidget);
        expect(find.text('Weekly recap'), findsOneWidget);
      },
    );

    testWidgets(
      'supports Arabic RTL keyboard/button flow and arabicNumerals without overflow',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await seedMonth(repo, count: 24, month: 11);
        await dataCache.refresh();
        settingsStore.update(
          (s) => s.copyWith(language: 'ar', arabicNumerals: true),
        );

        await tester.pumpWidget(wrapStandaloneWrapped());
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 450));

        expect(
          find.text(AppStrings.t('wrapped.title', language: 'ar')),
          findsOneWidget,
        );
        expect(find.text('١ / ٨'), findsOneWidget);

        // In RTL, ArrowLeft advances to page 1
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('wrapped_card_1')), findsOneWidget);
        expect(find.text('٢ / ٨'), findsOneWidget);

        // ArrowRight returns to page 0 in RTL
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('wrapped_card_0')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'shows calm not-enough-listening state below 20 plays in EN and AR',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await seedMonth(repo, count: 6, month: 11);
        await dataCache.refresh();

        await tester.pumpWidget(wrapStandaloneWrapped());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('wrapped_not_enough_state')), findsOneWidget);
        expect(find.text('Not enough listening yet'), findsOneWidget);

        settingsStore.update((s) => s.copyWith(language: 'ar'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 450));
        expect(
          find.text(AppStrings.t('wrapped.notEnough.title', language: 'ar')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'works in safe read-only mode and across narrow/wide/large text scale with zero overflow',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('aestheticy_wrapped_ro_');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final libPath = p.join(tempDir.path, 'library.db');
        final backupsDir = Directory(p.join(tempDir.path, 'backups'));

        final db = sqlite3.open(libPath);
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
        for (var i = 0; i < 20; i++) {
          final ts = DateTime(2026, 11, 1 + (i % 20), 22, i).millisecondsSinceEpoch;
          db.execute(
            'INSERT INTO play_events (id, uri, title, artist, album, duration_ms, started_at_ms, listened_ms, counted, completed) '
            "VALUES (${i + 1}, 'C:\\Music\\legacy_$i.mp3', 'Legacy $i', 'Legacy Artist', 'Legacy LP', 200000, $ts, 180000, 1, 1);",
          );
        }
        db.close();

        final roRepo = SqliteLibraryRepository.openFile(
          libPath,
          backupsDir: backupsDir,
          migrationHooks: LegacyMigrationTestHooks(failBackup: () => true),
        );
        addTearDown(roRepo.close);
        expect(roRepo.userDataAccessMode, UserDataAccessMode.safeReadOnly);

        tester.view.physicalSize = const Size(640, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          wrapStandaloneWrapped(customRepo: roRepo, mediaTextScale: 1.4),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('wrapped_card_0')), findsOneWidget);
        expect(tester.takeException(), isNull);

        tester.view.physicalSize = const Size(1600, 960);
        await tester.pumpWidget(
          wrapStandaloneWrapped(customRepo: roRepo, mediaTextScale: 1.4),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
