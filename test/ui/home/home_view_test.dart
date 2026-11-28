import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/session/saved_session.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite/legacy_userdata_migrator.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/home/home_view.dart';
import 'package:aestheticy/ui/l10n/app_strings.dart';
import 'package:aestheticy/ui/library/library_data_cache.dart';
import 'package:aestheticy/ui/library/welcome_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

void main() {
  group('HomeView & Shell Integration', () {
    late FakeAudioEngine engine;
    late PlaybackController controller;
    late SqliteLibraryRepository repo;
    late ScanService scanService;
    late LibraryDataCache dataCache;
    late SettingsStore settingsStore;
    late GlassController glassController;
    late ArtistNameStore artistNameStore;
    late AppNavigator navigator;

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
          userName: 'Mido',
          glassQuality: GlassQuality.full,
          reduceMotion: true,
        ),
      );
      glassController = GlassController();
      settingsStore.bindGlassController(glassController);
      artistNameStore = ArtistNameStore();
      navigator = AppNavigator();
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

    Future<void> seedHistory() async {
      final folder = await repo.addFolder('C:\\Music');
      final t1 = Track(
        path: 'C:\\Music\\a1.mp3',
        folderId: folder.id!,
        title: 'Dawn Song',
        artist: 'Fairouz',
        albumArtist: 'Fairouz',
        album: 'Morning Album',
        durationMs: 200000,
        mtimeMs: 1000,
        sizeBytes: 1024,
        addedAt: DateTime.utc(2026, 11, 20),
      );
      final t2 = Track(
        path: 'C:\\Music\\b1.mp3',
        folderId: folder.id!,
        title: 'Dusk Song',
        artist: 'Solaris',
        albumArtist: 'Solaris',
        album: 'Evening Album',
        durationMs: 210000,
        mtimeMs: 1000,
        sizeBytes: 1024,
        addedAt: DateTime.utc(2026, 11, 21),
      );
      await repo.upsertTracks([t1, t2]);
      await repo.insertPlayEvent(
        PlayEvent(
          uri: t1.path,
          startedAt: DateTime.utc(2026, 11, 27, 10),
          listenedMs: 180000,
          counted: true,
          completed: true,
        ),
      );
      await repo.insertPlayEvent(
        PlayEvent(
          uri: t2.path,
          startedAt: DateTime.utc(2026, 11, 28, 10),
          listenedMs: 180000,
          counted: true,
          completed: true,
        ),
      );
    }

    Widget wrapHome({
      required String language,
      DateTime Function()? clock,
      SessionStore? sessionStore,
      double systemTextScale = 1.0,
    }) {
      return GlassScope(
        controller: glassController,
        child: MaterialApp(
          locale: Locale(language),
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(systemTextScale),
            ),
            child: Directionality(
              textDirection:
                  language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
              child: SettingsScope(
                store: settingsStore,
                child: ArtistNameScope(
                  store: artistNameStore,
                  child: Scaffold(body: child),
                ),
              ),
            ),
          ),
          home: HomeView(
            repository: repo,
            controller: controller,
            settingsStore: settingsStore,
            navigator: navigator,
            dataCache: dataCache,
            sessionStore: sessionStore,
            clock: clock,
          ),
        ),
      );
    }

    Widget wrapShell({
      Key? key,
      required String language,
      DateTime Function()? clock,
      SessionStore? sessionStore,
      SqliteLibraryRepository? customRepo,
    }) {
      final effectiveRepo = customRepo ?? repo;
      final effectiveScan = customRepo != null
          ? ScanService(repository: customRepo)
          : scanService;
      if (customRepo != null) {
        addTearDown(effectiveScan.dispose);
      }
      return GlassScope(
        controller: glassController,
        child: MaterialApp(
          locale: Locale(language),
          theme: buildAppTheme(),
          builder: (context, child) => Directionality(
            textDirection:
                language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            child: SettingsScope(
              store: settingsStore,
              child: ArtistNameScope(
                store: artistNameStore,
                child: child!,
              ),
            ),
          ),
          home: AppShell(
            key: key,
            engine: engine,
            controller: controller,
            repository: effectiveRepo,
            scanService: effectiveScan,
            settingsStore: settingsStore,
            navigator: navigator,
            sessionStore: sessionStore,
            homeClock: clock,
          ),
        ),
      );
    }

    testWidgets(
      'renders greeting with name, Now Playing hero, Continue listening, and ONE rotating row in en and ar',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await seedHistory();
        await controller.playQueue([
          const AudioSource(
            'C:\\Music\\a1.mp3',
            extras: {'title': 'Dawn Song', 'artist': 'Fairouz'},
          ),
        ]);

        var now = DateTime(2026, 11, 28, 9, 30);

        // English morning
        await tester.pumpWidget(
          wrapHome(
            language: 'en',
            clock: () => now,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Good morning, Mido'), findsOneWidget);
        expect(find.byKey(const Key('home_hero_now_playing')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('home_hero_now_playing')),
            matching: find.text('Dawn Song'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('home_continue_listening_row')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('home_rotating_row')), findsOneWidget);
        expect(find.text('Continue listening'), findsOneWidget);
        expect(find.text('Evening Album'), findsWidgets);
        // Only 1 BackdropFilter in HomeView itself (the Hero card GlassSurface)
        expect(find.byType(BackdropFilter), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Toggle play/pause via Hero button
        await tester.tap(find.byKey(const Key('home_hero_play_pause')));
        await tester.pumpAndSettle();
        expect(controller.currentState, PlaybackState.paused);

        // Arabic RTL night
        now = DateTime(2026, 11, 28, 22, 0);
        settingsStore.update((s) => s.copyWith(language: 'ar'));
        await settingsStore.flush();
        await tester.pumpWidget(
          wrapHome(
            language: 'ar',
            clock: () => now,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('ليلة هادئة، Mido'), findsOneWidget);
        expect(find.text('متابعة الاستماع'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'without history shows friendly empty state instead of empty rows in en and ar',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await repo.addFolder('C:\\Music');
        var now = DateTime(2026, 11, 28, 14, 0);

        await tester.pumpWidget(
          wrapHome(
            language: 'en',
            clock: () => now,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Good afternoon, Mido'), findsOneWidget);
        expect(find.byKey(const Key('home_hero_idle')), findsOneWidget);
        expect(find.byKey(const Key('home_empty_history')), findsOneWidget);
        expect(
          find.byKey(const Key('home_continue_listening_row')),
          findsNothing,
        );
        expect(find.byKey(const Key('home_rotating_row')), findsNothing);

        now = DateTime(2026, 11, 28, 18, 0);
        settingsStore.update((s) => s.copyWith(language: 'ar'));
        await settingsStore.flush();
        await tester.pumpWidget(
          wrapHome(
            language: 'ar',
            clock: () => now,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('مساء الخير، Mido'), findsOneWidget);
        expect(find.byKey(const Key('home_empty_history')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'no saved name renders neutral greeting in en and ar, and updates live when userName changes',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        var now = DateTime(2026, 11, 28, 13, 0);
        settingsStore.update((s) => s.copyWith(userName: '   '));
        await settingsStore.flush();
        await tester.pumpWidget(
          wrapHome(
            language: 'en',
            clock: () => now,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Good afternoon'), findsOneWidget);

        // Changing userName in SettingsStore updates Home greeting live
        settingsStore.update((s) => s.copyWith(userName: 'Salma'));
        await settingsStore.flush();
        await tester.pumpAndSettle();
        expect(find.text('Good afternoon, Salma'), findsOneWidget);

        // Arabic without name
        now = DateTime(2026, 11, 28, 8, 0);
        settingsStore.update((s) => s.copyWith(language: 'ar', userName: ''));
        await settingsStore.flush();
        await tester.pumpWidget(
          wrapHome(
            language: 'ar',
            clock: () => now,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('صباح الخير'), findsOneWidget);
      },
    );

    testWidgets(
      'nothing playing shows Resume last session card and tapping Resume restores queue and plays',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final sessionStore = SessionStore(
          initialSession: const SavedSession(
            queue: [
              SavedSessionItem(
                entryId: 10,
                uri: 'asset_song1',
                extras: {'title': 'Last Track', 'artist': 'Fairouz'},
              ),
              SavedSessionItem(
                entryId: 11,
                uri: 'asset_song2',
                extras: {'title': 'Next Track', 'artist': 'Fairouz'},
              ),
            ],
            currentIndex: 0,
            currentEntryId: 10,
            currentUri: 'asset_song1',
          ),
        );
        addTearDown(sessionStore.dispose);

        await tester.pumpWidget(
          wrapHome(
            language: 'en',
            sessionStore: sessionStore,
            clock: () => DateTime(2026, 11, 28, 19, 0),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('home_hero_resume')), findsOneWidget);
        expect(find.text('Last Track'), findsOneWidget);

        await tester.tap(find.byKey(const Key('home_hero_resume_button')));
        await tester.pumpAndSettle();

        expect(controller.queue.length, 2);
        expect(controller.queue.current?.uri, 'asset_song1');
        expect(controller.currentState, PlaybackState.playing);
      },
    );

    testWidgets(
      'narrow (640x700) and wide (1440x900) windows with largest text scale render with zero overflow',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await seedHistory();
        settingsStore.update((s) => s.copyWith(textScale: 'large'));
        await settingsStore.flush();
        await controller.playQueue([
          const AudioSource(
            'C:\\Music\\a1.mp3',
            extras: {
              'title': 'A Very Long Track Title That Must Ellipsize Cleanly',
              'artist': 'A Very Long Artist Name',
            },
          ),
        ]);

        // Narrow window + large text scale
        tester.view.physicalSize = const Size(640, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          wrapHome(
            language: 'en',
            systemTextScale: 1.35,
            clock: () => DateTime(2026, 11, 28, 10, 0),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Wide window + Arabic RTL + large text scale
        tester.view.physicalSize = const Size(1440, 900);
        settingsStore.update((s) => s.copyWith(language: 'ar'));
        await settingsStore.flush();
        await tester.pumpWidget(
          wrapHome(
            language: 'ar',
            systemTextScale: 1.35,
            clock: () => DateTime(2026, 11, 28, 10, 0),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AppShell starts on Home when folders exist, WelcomeView without folders, sidebar_home is first, and keyboard activation works',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. No folders -> WelcomeView
        await tester.pumpWidget(
          wrapShell(
            language: 'en',
            clock: () => DateTime(2026, 11, 28, 10, 0),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byType(WelcomeView), findsOneWidget);
        expect(find.byType(HomeView), findsNothing);

        // Verify Home is above Albums in sidebar
        final homeY = tester.getTopLeft(find.byKey(const Key('sidebar_home'))).dy;
        final albumsY =
            tester.getTopLeft(find.byKey(const Key('sidebar_albums'))).dy;
        expect(homeY, lessThan(albumsY));

        // 2. Add folder + history -> HomeView is default destination
        await seedHistory();
        await dataCache.refresh();
        await tester.pumpWidget(
          wrapShell(
            key: const ValueKey('shell_with_folders'),
            language: 'en',
            clock: () => DateTime(2026, 11, 28, 10, 0),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byType(HomeView), findsOneWidget);
        expect(navigator.current, AppDestination.home);

        // Navigate to Albums and goBack -> returns to Home
        await tester.tap(find.byKey(const Key('sidebar_albums')));
        await tester.pumpAndSettle();
        expect(navigator.current, AppDestination.albums);
        expect(navigator.goBack(), isTrue);
        await tester.pumpAndSettle();
        expect(navigator.current, AppDestination.home);
        expect(find.byType(HomeView), findsOneWidget);

        // Keyboard focus + Enter activation on a media card
        final firstCard = find.descendant(
          of: find.byKey(const Key('home_continue_listening_row')),
          matching: find.byType(InkWell),
        );
        final innerGesture = find.descendant(
          of: firstCard.first,
          matching: find.byType(GestureDetector),
        );
        Focus.of(tester.element(innerGesture.first)).requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(navigator.current, AppDestination.albumDetail);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'AppShell in safeReadOnly mode renders Home and SafeReadOnlyBanner without overflow',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final tempDir =
            Directory.systemTemp.createTempSync('aestheticy_home_shell_ro_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final libPath = p.join(tempDir.path, 'library.db');
        final backupsDir = Directory(p.join(tempDir.path, 'backups'));
        final db = sqlite3.open(libPath);
        db.execute('''
          CREATE TABLE folders (id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE, last_scan_at INTEGER);
          CREATE TABLE tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE,
            folder_id INTEGER NOT NULL,
            title TEXT, artist TEXT, album_artist TEXT, album TEXT,
            track_no INTEGER, disc_no INTEGER, year INTEGER,
            duration_ms INTEGER NOT NULL, mtime_ms INTEGER NOT NULL, size_bytes INTEGER NOT NULL,
            cover_key TEXT, added_at INTEGER NOT NULL, search_text TEXT NOT NULL
          );
          CREATE TABLE track_artists (track_id INTEGER NOT NULL, artist_key TEXT NOT NULL, artist_name TEXT NOT NULL, PRIMARY KEY(track_id, artist_key));
          CREATE TABLE artist_aliases (alias_key TEXT PRIMARY KEY, canonical_key TEXT NOT NULL, canonical_name TEXT NOT NULL);
          CREATE TABLE artist_no_split (artist_key TEXT PRIMARY KEY, artist_name TEXT NOT NULL);
          CREATE TABLE play_events (id INTEGER PRIMARY KEY AUTOINCREMENT, uri TEXT NOT NULL, title TEXT, artist TEXT, album TEXT, album_artist TEXT, duration_ms INTEGER, started_at_ms INTEGER NOT NULL, listened_ms INTEGER NOT NULL, counted INTEGER NOT NULL, completed INTEGER NOT NULL);
          CREATE TABLE favorites (path TEXT PRIMARY KEY, added_at_ms INTEGER NOT NULL);
          CREATE TABLE ratings (path TEXT PRIMARY KEY, stars INTEGER NOT NULL, rated_at_ms INTEGER NOT NULL);
          CREATE TABLE playlists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL);
          CREATE TABLE playlist_items (id INTEGER PRIMARY KEY AUTOINCREMENT, playlist_id INTEGER NOT NULL, position INTEGER NOT NULL, path TEXT NOT NULL, added_at_ms INTEGER NOT NULL);
          PRAGMA user_version = 4;
        ''');
        db.execute("INSERT INTO folders (id, path) VALUES (1, 'C:\\Music');");
        db.close();

        final ro = SqliteLibraryRepository.openFile(
          libPath,
          backupsDir: backupsDir,
          migrationHooks: LegacyMigrationTestHooks(failBackup: () => true),
        );
        final roScan = ScanService(repository: ro);
        final roNav = AppNavigator();

        await tester.pumpWidget(
          GlassScope(
            controller: glassController,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: AppShell(
                key: const ValueKey('shell_ro'),
                engine: engine,
                controller: controller,
                repository: ro,
                scanService: roScan,
                settingsStore: settingsStore,
                navigator: roNav,
                homeClock: () => DateTime(2026, 11, 28, 10, 0),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('safe_read_only_banner')), findsOneWidget);
        expect(find.byType(HomeView), findsOneWidget);
        expect(
          find.text(AppStrings.t('home.emptyHistoryTitle', language: 'en')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        roScan.dispose();
        await ro.close();
      },
    );
  });
}
