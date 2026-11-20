import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/cover_cache.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/glass/glass_blur_budget.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/library/artist_detail_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/theme/app_colors.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

const List<int> _kValid1x1Png = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00,
  0x1F, 0x15, 0xC4, 0x89,
  0x00, 0x00, 0x00, 0x0A,
  0x49, 0x44, 0x41, 0x54,
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
  0x0D, 0x0A, 0x2D, 0xB4,
  0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
];

class _PreloadSpyFakeEngine extends FakeAudioEngine {
  int preloadCallCount = 0;
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
    preloadCallCount++;
    preloadedUris.add(next?.uri);
    await super.preloadNext(next);
  }
}

void main() {
  group('ArtistDetailView Apple Music Layout (S2)', () {
    late Directory tempDir;
    late _PreloadSpyFakeEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late SqliteLibraryRepository repository;
    late SettingsStore settingsStore;
    late AppNavigator navigator;

    setUp(() async {
      GlassBlurBudget.instance.resetForTesting();
      tempDir = await Directory.systemTemp.createTemp('aestheticy_artist_s2_');
      engine = _PreloadSpyFakeEngine();
      await engine.init();
      queue = PlaybackQueue(random: math.Random(42));
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
      repository = SqliteLibraryRepository.inMemory();
      settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(
          language: 'en',
          glassQuality: GlassQuality.off,
          reduceMotion: true,
        ),
      );
      await settingsStore.init();
      navigator = AppNavigator();
    });

    tearDown(() async {
      CoverCache.resetForTesting();
      await repository.close();
      await controller.dispose();
      await engine.dispose();
      settingsStore.dispose();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    void setViewport(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    Widget buildView({
      required ArtistSummary artist,
      TextDirection textDirection = TextDirection.ltr,
      Locale locale = const Locale('en'),
      String? artistImagePath,
      math.Random? random,
    }) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: textDirection,
          child: GlassScope(
            controller: GlassController(quality: GlassQuality.off),
            child: SettingsScope(
              store: settingsStore,
              child: Scaffold(
                body: ArtistDetailView(
                  artist: artist,
                  repository: repository,
                  controller: controller,
                  settingsStore: settingsStore,
                  navigator: navigator,
                  artistImagePath: artistImagePath,
                  random: random ?? math.Random(7),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'renders header and sections in exact Apple Music order with counts and no category chips',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 900));
        final folder = await repository.addFolder('/music');
        final now = DateTime(2026, 1, 1);
        const target = 'Layla';

        final tracks = <Track>[
          // 7 tracks -> Albums
          ...List.generate(
            7,
            (i) => Track(
              path: '/music/alb_$i.mp3',
              folderId: folder.id!,
              title: 'Album Song $i',
              artist: target,
              albumArtist: target,
              album: 'Midnight LP',
              year: 2023,
              durationMs: 180000,
              mtimeMs: 1000,
              sizeBytes: 1024,
              addedAt: now,
            ),
          ),
          // 1 track -> Singles & EPs
          Track(
            path: '/music/single.mp3',
            folderId: folder.id!,
            title: 'Aurora Track',
            artist: target,
            albumArtist: target,
            album: 'Aurora - Single',
            year: 2025,
            durationMs: 190000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
          // Compilation
          Track(
            path: '/music/comp.mp3',
            folderId: folder.id!,
            title: 'Festival Tune',
            artist: target,
            albumArtist: 'Various Artists',
            album: 'Summer Anthology',
            year: 2022,
            durationMs: 200000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
          // Appears on
          Track(
            path: '/music/feat.mp3',
            folderId: folder.id!,
            title: 'Duet Verse',
            artist: 'Headliner feat. $target',
            albumArtist: 'Headliner',
            album: 'Headliner Record',
            year: 2024,
            durationMs: 210000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
        ];

        await repository.upsertTracks(tracks);
        await repository.rebuildArtistLinks();

        final artists = await repository.listArtists();
        final artist = artists.firstWhere((a) => a.name == target);

        await tester.pumpWidget(buildView(artist: artist));
        await tester.pumpAndSettle();

        // Header monogram, artist name, stats, Play & Shuffle
        expect(find.byKey(const Key('artist_header_avatar')), findsOneWidget);
        expect(find.text('L'), findsOneWidget);
        expect(find.text(target), findsOneWidget);
        expect(find.text('4 albums · 10 tracks'), findsOneWidget);
        expect(find.byKey(const Key('artist_play_button')), findsOneWidget);
        expect(find.byKey(const Key('artist_shuffle_button')), findsOneWidget);

        // No old release-category chips
        expect(find.byKey(const Key('artist_category_chips_scroll')), findsNothing);
        expect(find.byKey(const Key('artist_category_chip_all')), findsNothing);

        // All 5 sections exist in strict top-to-bottom order
        final albumsFinder = find.byKey(const Key('artist_section_albums'));
        final singlesFinder =
            find.byKey(const Key('artist_section_singlesAndEps'));
        final compFinder =
            find.byKey(const Key('artist_section_compilations'));
        final appearsFinder =
            find.byKey(const Key('artist_section_appearsOn'));
        final tracksFinder = find.byKey(const Key('artist_section_tracks'));

        double docY(Finder finder) {
          final scrollable = Scrollable.of(tester.element(finder));
          return scrollable.position.pixels + tester.getTopLeft(finder).dy;
        }

        Future<double> scrollAndMeasureDocY(Finder finder) async {
          await tester.scrollUntilVisible(
            finder,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(finder, findsOneWidget);
          return docY(finder);
        }

        final albumsY = await scrollAndMeasureDocY(albumsFinder);
        final singlesY = await scrollAndMeasureDocY(singlesFinder);
        final compY = await scrollAndMeasureDocY(compFinder);
        final appearsY = await scrollAndMeasureDocY(appearsFinder);
        final tracksY = await scrollAndMeasureDocY(tracksFinder);

        expect(albumsY, lessThan(singlesY));
        expect(singlesY, lessThan(compY));
        expect(compY, lessThan(appearsY));
        expect(appearsY, lessThan(tracksY));
      },
    );

    testWidgets(
      'hides empty album sections when artist only has singles and tracks',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 800));
        final folder = await repository.addFolder('/music');
        final now = DateTime(2026, 1, 1);

        await repository.upsertTracks([
          Track(
            path: '/music/s1.mp3',
            folderId: folder.id!,
            title: 'Only Single Song',
            artist: 'Minimal Artist',
            albumArtist: 'Minimal Artist',
            album: 'Minimal Single',
            year: 2025,
            durationMs: 180000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
        ]);
        await repository.rebuildArtistLinks();

        const artist = ArtistSummary(
          name: 'Minimal Artist',
          albumCount: 1,
          trackCount: 1,
        );

        await tester.pumpWidget(buildView(artist: artist));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('artist_section_albums')), findsNothing);
        expect(
          find.byKey(const Key('artist_section_singlesAndEps')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('artist_section_compilations')), findsNothing);
        expect(find.byKey(const Key('artist_section_appearsOn')), findsNothing);
        expect(find.byKey(const Key('artist_section_tracks')), findsOneWidget);
      },
    );

    testWidgets(
      'Show all toggle expands and collapses multi-row card section in place without navigation',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 900));
        final folder = await repository.addFolder('/music');
        final now = DateTime(2026, 1, 1);
        const artistName = 'Prolific Artist';

        // 8 distinct albums (each 7 tracks -> Albums section).
        // At 1280px width (availableWidth 1232, card 172 + gap 16 = 188 -> 6 cards per row).
        final tracks = <Track>[];
        for (var a = 0; a < 8; a++) {
          for (var t = 0; t < 7; t++) {
            tracks.add(
              Track(
                path: '/music/a${a}_t$t.mp3',
                folderId: folder.id!,
                title: 'Album $a Track $t',
                artist: artistName,
                albumArtist: artistName,
                album: 'Release $a',
                year: 2025 - a,
                durationMs: 180000,
                mtimeMs: 1000,
                sizeBytes: 1024,
                addedAt: now,
              ),
            );
          }
        }
        // Plus 1 single (only 1 item -> should NOT have Show all toggle)
        tracks.add(
          Track(
            path: '/music/one_single.mp3',
            folderId: folder.id!,
            title: 'Solo Single',
            artist: artistName,
            albumArtist: artistName,
            album: 'Solo Single',
            year: 2026,
            durationMs: 180000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
        );

        await repository.upsertTracks(tracks);
        await repository.rebuildArtistLinks();

        const artist = ArtistSummary(
          name: artistName,
          albumCount: 9,
          trackCount: 57,
        );

        await tester.pumpWidget(buildView(artist: artist));
        await tester.pumpAndSettle();

        final initialNavEntry = navigator.currentEntry;

        // Singles & EPs has 1 item -> no Show all toggle
        expect(
          find.byKey(const Key('artist_section_toggle_singlesAndEps')),
          findsNothing,
        );

        // Albums has 8 items (> 6 per row) -> collapsed to 6 cards initially
        final toggleFinder =
            find.byKey(const Key('artist_section_toggle_albums'));
        expect(toggleFinder, findsOneWidget);
        expect(find.text('Show all'), findsOneWidget);

        Finder albumCardsInAlbumsSection() => find.descendant(
              of: find.byKey(const Key('artist_section_albums')),
              matching: find.byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>)
                        .value
                        .startsWith('artist_album_card_albums_'),
              ),
            );

        expect(albumCardsInAlbumsSection(), findsNWidgets(6));

        // Expand
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();

        expect(albumCardsInAlbumsSection(), findsNWidgets(8));
        expect(find.text('Show less'), findsOneWidget);
        expect(navigator.currentEntry, equals(initialNavEntry));

        // Collapse
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();

        expect(albumCardsInAlbumsSection(), findsNWidgets(6));
        expect(find.text('Show all'), findsOneWidget);
        expect(navigator.currentEntry, equals(initialNavEntry));
      },
    );

    testWidgets(
      'album card displays cover with cacheWidth, title, year, track count, and opens album detail on tap',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 800));
        CoverCache.setCustomDirectory(tempDir.path);
        const artistName = 'Cover Artist';
        const albumTitle = 'Glass Horizons';
        final coverKey = CoverCache.saveCoverSync(
          albumArtist: artistName,
          album: albumTitle,
          bytes: Uint8List.fromList(_kValid1x1Png),
        );

        final folder = await repository.addFolder('/music');
        final now = DateTime(2026, 1, 1);

        await repository.upsertTracks(
          List.generate(
            7,
            (i) => Track(
              path: '/music/cov_$i.mp3',
              folderId: folder.id!,
              title: 'Horizon $i',
              artist: artistName,
              albumArtist: artistName,
              album: albumTitle,
              year: 2024,
              coverKey: coverKey,
              durationMs: 180000,
              mtimeMs: 1000,
              sizeBytes: 1024,
              addedAt: now,
            ),
          ),
        );
        await repository.rebuildArtistLinks();

        const artist = ArtistSummary(
          name: artistName,
          albumCount: 1,
          trackCount: 7,
        );

        await tester.pumpWidget(buildView(artist: artist));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        const cardKey = ValueKey<String>(
          'artist_album_card_albums_Glass Horizons|Cover Artist',
        );
        final cardFinder = find.byKey(cardKey);
        expect(cardFinder, findsOneWidget);

        // Card metadata
        expect(
          find.descendant(of: cardFinder, matching: find.text(albumTitle)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: cardFinder, matching: find.text('2024 · 7 tracks')),
          findsOneWidget,
        );

        // Cover Image uses cacheWidth
        final imageFinder = find.descendant(
          of: cardFinder,
          matching: find.byType(Image),
        );
        expect(imageFinder, findsOneWidget);
        final imageWidget = tester.widget<Image>(imageFinder);
        // Image.file wraps FileImage in ResizeImage when cacheWidth is supplied.
        expect(imageWidget.image, isA<ResizeImage>());
        final resizeProvider = imageWidget.image as ResizeImage;
        expect(resizeProvider.imageProvider, isA<FileImage>());
        expect(resizeProvider.width, equals(320));

        // Tap opens album page
        await tester.tap(cardFinder);
        await tester.pump();

        expect(navigator.current, equals(AppDestination.albumDetail));
        expect(navigator.selectedAlbumId, equals(albumTitle));
        expect(navigator.selectedAlbum?.album, equals(albumTitle));
        expect(navigator.selectedAlbum?.albumArtist, equals(artistName));

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'album card shows click cursor on hover and keyboard focus ring on focus',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 800));
        final folder = await repository.addFolder('/music');
        final now = DateTime(2026, 1, 1);

        await repository.upsertTracks(
          List.generate(
            7,
            (i) => Track(
              path: '/music/kf_$i.mp3',
              folderId: folder.id!,
              title: 'Focus Track $i',
              artist: 'Focus Artist',
              albumArtist: 'Focus Artist',
              album: 'Focus Album',
              year: 2024,
              durationMs: 180000,
              mtimeMs: 1000,
              sizeBytes: 1024,
              addedAt: now,
            ),
          ),
        );
        await repository.rebuildArtistLinks();

        const artist = ArtistSummary(
          name: 'Focus Artist',
          albumCount: 1,
          trackCount: 7,
        );

        await tester.pumpWidget(buildView(artist: artist));
        await tester.pumpAndSettle();

        final cardFinder = find.byKey(
          const ValueKey<String>(
            'artist_album_card_albums_Focus Album|Focus Artist',
          ),
        );
        expect(cardFinder, findsOneWidget);

        // 1. Hover cursor check
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        await tester.pump();
        await gesture.moveTo(tester.getCenter(cardFinder));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          equals(SystemMouseCursors.click),
        );
        await gesture.removePointer();
        await tester.pump();

        // 2. Tab to the card to switch FocusManager to keyboard highlight mode & focus it
        for (var i = 0; i < 12; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final primaryFocus = FocusManager.instance.primaryFocus;
          if (primaryFocus?.context != null) {
            final cardEl = tester.element(cardFinder);
            var isInsideCard = false;
            primaryFocus!.context!.visitAncestorElements((ancestor) {
              if (ancestor == cardEl) {
                isInsideCard = true;
                return false;
              }
              return true;
            });
            if (isInsideCard) break;
          }
        }
        await tester.pumpAndSettle();

        final animatedContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: cardFinder,
            matching: find.byType(AnimatedContainer),
          ),
        );
        final decoration = animatedContainer.decoration! as BoxDecoration;
        expect(
          (decoration.border! as Border).top.color,
          equals(AppColors.accent),
        );

        // 3. Pressing Enter activates the card and navigates to album detail
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(navigator.current, equals(AppDestination.albumDetail));
        expect(navigator.selectedAlbumId, equals('Focus Album'));
      },
    );

    testWidgets(
      'Tracks section double-click plays, search filters tracks only, and shuffle refreshes preload via PlaybackController',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 900));
        final folder = await repository.addFolder('/music');
        final now = DateTime(2026, 1, 1);
        const artistName = 'Track Control Artist';

        await repository.upsertTracks([
          Track(
            path: '/music/t1.mp3',
            folderId: folder.id!,
            title: 'Alpha Dawn',
            artist: artistName,
            albumArtist: artistName,
            album: 'First Single - Single',
            year: 2024,
            durationMs: 180000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
          Track(
            path: '/music/t2.mp3',
            folderId: folder.id!,
            title: 'Beta Night',
            artist: artistName,
            albumArtist: artistName,
            album: 'Second Single - Single',
            year: 2025,
            durationMs: 210000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
          Track(
            path: '/music/t3.mp3',
            folderId: folder.id!,
            title: 'Gamma Echo',
            artist: artistName,
            albumArtist: artistName,
            album: 'Third Single - Single',
            year: 2026,
            durationMs: 240000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
        ]);
        await repository.rebuildArtistLinks();

        const artist = ArtistSummary(
          name: artistName,
          albumCount: 3,
          trackCount: 3,
        );

        await tester.pumpWidget(buildView(artist: artist));
        await tester.pumpAndSettle();

        // 1. Double-click track "Beta Night" -> plays queue at Beta Night
        final betaFinder = find.text('Beta Night');
        await tester.ensureVisible(betaFinder);
        await tester.pump();
        await tester.tap(betaFinder);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(betaFinder);
        await tester.pump(const Duration(milliseconds: 100));

        expect(engine.openedSource?.uri, equals('/music/t2.mp3'));
        expect(controller.queue.current?.uri, equals('/music/t2.mp3'));
        expect(controller.queue.length, equals(3));

        // 2. Search in Tracks section filters tracks ONLY (album cards remain intact)
        await tester.enterText(
          find.byKey(const Key('artist_tracks_search_field')),
          'Gamma',
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Gamma Echo'), findsOneWidget);
        expect(find.text('Alpha Dawn'), findsNothing);
        // Album card for First Single is still rendered above
        expect(
          find.byKey(
            const ValueKey<String>(
              'artist_album_card_singlesAndEps_First Single - Single|Track Control Artist',
            ),
          ),
          findsOneWidget,
        );

        // Clear search so all 3 tracks are present for shuffle check
        await tester.tap(find.byKey(const Key('artist_tracks_search_clear')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Alpha Dawn'), findsOneWidget);

        // 3. Tracks section Shuffle button uses PlaybackController.setShuffle + refreshes preload
        engine.preloadCallCount = 0;
        engine.preloadedUris.clear();

        final sectionShuffleBtn =
            find.byKey(const Key('artist_tracks_shuffle_button'));
        await tester.ensureVisible(sectionShuffleBtn);
        await tester.pump();
        await tester.tap(sectionShuffleBtn);
        await tester.pump(const Duration(milliseconds: 100));

        expect(controller.queue.isShuffled, isTrue);
        expect(controller.queue.length, equals(3));
        expect(engine.preloadCallCount, greaterThanOrEqualTo(1));
        expect(
          engine.preloadedUris.last,
          equals(controller.queue.peekNext()?.uri),
        );

        // 4. Header Shuffle button also uses PlaybackController.setShuffle + refreshes preload
        await controller.setShuffle(false);
        engine.preloadCallCount = 0;
        engine.preloadedUris.clear();

        final headerShuffleBtn = find.byKey(const Key('artist_shuffle_button'));
        await tester.ensureVisible(headerShuffleBtn);
        await tester.pump();
        await tester.tap(headerShuffleBtn);
        await tester.pump(const Duration(milliseconds: 100));

        expect(controller.queue.isShuffled, isTrue);
        expect(controller.queue.length, equals(3));
        expect(engine.preloadCallCount, greaterThanOrEqualTo(1));
        expect(
          engine.preloadedUris.last,
          equals(controller.queue.peekNext()?.uri),
        );
      },
    );

    testWidgets(
      'renders cleanly in RTL and LTR across narrow, normal, and wide viewports without overflow',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final folder = await repository.addFolder('/music');
        final now = DateTime(2026, 1, 1);
        const arArtist = 'فيروز';

        await repository.upsertTracks([
          ...List.generate(
            7,
            (i) => Track(
              path: '/music/ar_alb_$i.mp3',
              folderId: folder.id!,
              title: 'أغنية ألبوم رقم $i',
              artist: arArtist,
              albumArtist: arArtist,
              album: 'ألبوم الصباح الطويل',
              year: 1990,
              durationMs: 200000,
              mtimeMs: 1000,
              sizeBytes: 1024,
              addedAt: now,
            ),
          ),
          Track(
            path: '/music/ar_s1.mp3',
            folderId: folder.id!,
            title: 'منفردة جميلة',
            artist: arArtist,
            albumArtist: arArtist,
            album: 'سهرة حب - Single',
            year: 2020,
            durationMs: 180000,
            mtimeMs: 1000,
            sizeBytes: 1024,
            addedAt: now,
          ),
        ]);
        await repository.rebuildArtistLinks();

        const artist = ArtistSummary(
          name: arArtist,
          albumCount: 2,
          trackCount: 8,
        );

        const widths = [520.0, 960.0, 1440.0];

        for (final dir in [TextDirection.rtl, TextDirection.ltr]) {
          final isRtl = dir == TextDirection.rtl;
          settingsStore.update(
            (s) => s.copyWith(language: isRtl ? 'ar' : 'en'),
          );

          for (final width in widths) {
            setViewport(tester, Size(width, 800));
            await tester.pumpWidget(
              buildView(
                artist: artist,
                textDirection: dir,
                locale: Locale(isRtl ? 'ar' : 'en'),
              ),
            );
            await tester.pumpAndSettle();

            expect(
              tester.takeException(),
              isNull,
              reason: 'No overflow/exception expected at width=$width dir=$dir',
            );
            if (isRtl) {
              expect(find.text('الألبومات'), findsOneWidget);
              expect(find.text('الأغاني المنفردة والأسطوانات المطولة'), findsOneWidget);
            } else {
              expect(find.text('Albums'), findsOneWidget);
              expect(find.text('Singles & EPs'), findsOneWidget);
            }
          }
        }
      },
    );
  });
}
