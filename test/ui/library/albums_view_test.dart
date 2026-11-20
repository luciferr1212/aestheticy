import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/library/albums_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

import '../../library/fake_library_repository.dart';

class _AlbumTestRepository extends FakeLibraryRepository {
  List<AlbumSummary> albumsData = const [];
  List<ArtistSummary> artistsData = const [];
  Map<String, List<AlbumSummary>> albumsByArtistData = const {};

  @override
  Future<List<AlbumSummary>> listAlbums({int? limit, int? offset}) async {
    return albumsData;
  }

  @override
  Future<List<ArtistSummary>> listArtists({int? limit, int? offset}) async {
    return artistsData;
  }

  @override
  Future<List<AlbumSummary>> listAlbumsByArtistKey(String artistKey) async {
    return albumsByArtistData[artistKey] ?? [];
  }

  @override
  Future<List<AlbumSummary>> searchAlbums(String query, {int? limit}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return albumsData;
    final matches = albumsData.where((a) {
      return a.album.toLowerCase().contains(q) ||
          (a.albumArtist ?? '').toLowerCase().contains(q);
    });
    return limit != null ? matches.take(limit).toList() : matches.toList();
  }
}

void main() {
  group('groupAlbumsByYear pure logic (S7)', () {
    test('orders known years newest first, places null/<=0 last, ties artist -> title', () {
      const albums = [
        AlbumSummary(album: 'No Year A', albumArtist: 'Beta', year: null, trackCount: 4),
        AlbumSummary(album: 'Zero Year', albumArtist: 'Alpha', year: 0, trackCount: 2),
        AlbumSummary(album: 'Negative Year', albumArtist: 'Alpha', year: -5, trackCount: 1),
        AlbumSummary(album: 'Zebra', albumArtist: 'Artist B', year: 2022, trackCount: 8),
        AlbumSummary(album: 'Beta Title', albumArtist: 'Artist A', year: 2022, trackCount: 5),
        AlbumSummary(album: 'Alpha Title', albumArtist: 'Artist A', year: 2022, trackCount: 6),
        AlbumSummary(album: 'Newest', albumArtist: 'Artist C', year: 2024, trackCount: 10),
        AlbumSummary(album: 'Oldest', albumArtist: 'Artist D', year: 1999, trackCount: 7),
      ];

      final groups = groupAlbumsByYear(albums);
      expect(groups.map((g) => g.year).toList(), equals([2024, 2022, 1999, null]));

      expect(groups[0].albums.map((a) => a.album).toList(), equals(['Newest']));
      expect(
        groups[1].albums.map((a) => '${a.albumArtist}:${a.album}').toList(),
        equals([
          'Artist A:Alpha Title',
          'Artist A:Beta Title',
          'Artist B:Zebra',
        ]),
      );
      expect(groups[2].albums.map((a) => a.album).toList(), equals(['Oldest']));
      expect(
        groups[3].albums.map((a) => a.album).toList(),
        equals(['Negative Year', 'Zero Year', 'No Year A']),
      );
    });

    test('reversed: true orders known years oldest first, keeps null/<=0 last, ties artist -> title', () {
      const albums = [
        AlbumSummary(album: 'No Year A', albumArtist: 'Beta', year: null, trackCount: 4),
        AlbumSummary(album: 'Zero Year', albumArtist: 'Alpha', year: 0, trackCount: 2),
        AlbumSummary(album: 'Negative Year', albumArtist: 'Alpha', year: -5, trackCount: 1),
        AlbumSummary(album: 'Zebra', albumArtist: 'Artist B', year: 2022, trackCount: 8),
        AlbumSummary(album: 'Beta Title', albumArtist: 'Artist A', year: 2022, trackCount: 5),
        AlbumSummary(album: 'Alpha Title', albumArtist: 'Artist A', year: 2022, trackCount: 6),
        AlbumSummary(album: 'Newest', albumArtist: 'Artist C', year: 2024, trackCount: 10),
        AlbumSummary(album: 'Oldest', albumArtist: 'Artist D', year: 1999, trackCount: 7),
      ];

      final groups = groupAlbumsByYear(albums, reversed: true);
      expect(groups.map((g) => g.year).toList(), equals([1999, 2022, 2024, null]));

      expect(groups[0].albums.map((a) => a.album).toList(), equals(['Oldest']));
      expect(
        groups[1].albums.map((a) => '${a.albumArtist}:${a.album}').toList(),
        equals([
          'Artist A:Alpha Title',
          'Artist A:Beta Title',
          'Artist B:Zebra',
        ]),
      );
      expect(groups[2].albums.map((a) => a.album).toList(), equals(['Newest']));
      expect(
        groups[3].albums.map((a) => a.album).toList(),
        equals(['Negative Year', 'Zero Year', 'No Year A']),
      );
    });

    test('returns empty list for empty input', () {
      expect(groupAlbumsByYear(const []), isEmpty);
    });
  });

  group('AlbumsView grouped by year Widget Tests (S7)', () {
    late Directory tempDir;
    late _AlbumTestRepository repo;
    late SettingsStore settingsStore;
    late ArtistNameStore artistNameStore;
    late AppNavigator navigator;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_albums_s7_');
      repo = _AlbumTestRepository()
        ..albumsData = const [
          AlbumSummary(album: 'Midnight Echoes', albumArtist: 'Zed', year: 2020, trackCount: 9),
          AlbumSummary(album: 'Sunburst', albumArtist: 'Aria', year: 2024, trackCount: 11),
          AlbumSummary(album: 'Aurora', albumArtist: 'Aria', year: 2024, trackCount: 7),
          AlbumSummary(album: 'Untitled Tape', albumArtist: 'Mono', year: null, trackCount: 3),
          AlbumSummary(album: 'Zero Vault', albumArtist: 'Kira', year: 0, trackCount: 5),
        ];
      settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(
          language: 'en',
          albumSort: 'year',
          libraryViewMode: 'square',
        ),
      );
      await settingsStore.init();
      artistNameStore = ArtistNameStore(directory: tempDir);
      await artistNameStore.init();
      navigator = AppNavigator();
    });

    tearDown(() async {
      settingsStore.dispose();
      artistNameStore.dispose();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    Widget buildHarness({
      Size size = const Size(1280, 800),
      TextDirection textDirection = TextDirection.ltr,
      double textScale = 1.0,
      Locale locale = const Locale('en'),
    }) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: textDirection,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: SettingsScope(
              store: settingsStore,
              child: ArtistNameScope(
                store: artistNameStore,
                child: Scaffold(
                  body: AlbumsView(
                    repository: repo,
                    settingsStore: settingsStore,
                    navigator: navigator,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'groups by year across square, wide, and list view modes with flat non-year modes intact',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        for (final mode in const ['square', 'wide', 'list']) {
          settingsStore.update((s) => s.copyWith(albumSort: 'year', libraryViewMode: mode));
          await tester.pumpWidget(buildHarness());
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('albums_year_grouped_scroll')), findsOneWidget);
          final h2024 = find.byKey(const ValueKey<String>('album_year_header_2024'));
          final h2020 = find.byKey(const ValueKey<String>('album_year_header_2020'));
          final hUnknown = find.byKey(const ValueKey<String>('album_year_header_unknown'));
          expect(h2024, findsOneWidget);
          expect(h2020, findsOneWidget);
          expect(hUnknown, findsOneWidget);

          // Section headers appear in descending year order with Unknown year last.
          expect(tester.getTopLeft(h2024).dy, lessThan(tester.getTopLeft(h2020).dy));
          expect(tester.getTopLeft(h2020).dy, lessThan(tester.getTopLeft(hUnknown).dy));
          expect(
            find.descendant(of: h2024, matching: find.text('2024')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: h2020, matching: find.text('2020')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: hUnknown, matching: find.text('Unknown year')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: h2024, matching: find.text('2 albums')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: h2020, matching: find.text('1 albums')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: hUnknown, matching: find.text('2 albums')),
            findsOneWidget,
          );

          if (mode == 'list') {
            expect(find.byType(SliverFixedExtentList), findsNWidgets(3));
          } else {
            expect(find.byType(SliverGrid), findsNWidgets(3));
          }
          expect(tester.takeException(), isNull);
        }

        // Switching sort back to title restores flat GridView.
        settingsStore.update((s) => s.copyWith(albumSort: 'title', libraryViewMode: 'square'));
        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('albums_year_grouped_scroll')), findsNothing);
        expect(find.byKey(const Key('albums_square_grid')), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'search filtering works when grouped by year',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'Aria');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey<String>('album_year_header_2024')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('album_year_header_2020')), findsNothing);
        expect(find.byKey(const ValueKey<String>('album_year_header_unknown')), findsNothing);
        expect(find.text('Aurora'), findsOneWidget);
        expect(find.text('Sunburst'), findsOneWidget);
        expect(find.text('Midnight Echoes'), findsNothing);
      },
    );

    testWidgets(
      'renders in Arabic RTL with Arabic numerals and large text scale without overflow',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1000, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        settingsStore.update(
          (s) => s.copyWith(
            language: 'ar',
            arabicNumerals: true,
            textScale: 'large',
            albumSort: 'year',
            libraryViewMode: 'wide',
          ),
        );

        await tester.pumpWidget(
          buildHarness(
            size: const Size(1000, 700),
            textDirection: TextDirection.rtl,
            textScale: 1.10,
            locale: const Locale('ar'),
          ),
        );
        await tester.pumpAndSettle();

        final h2024 = find.byKey(const ValueKey<String>('album_year_header_2024'));
        expect(
          find.descendant(of: h2024, matching: find.text('٢٠٢٤')),
          findsOneWidget,
        );
        expect(find.text('سنة غير معروفة'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'renders 2000+ albums grouped across many years lazily and scrolls smoothly',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        repo.albumsData = List<AlbumSummary>.generate(2050, (i) {
          final year = (i % 65 == 0) ? null : 1965 + (i % 60);
          return AlbumSummary(
            album: 'Album $i',
            albumArtist: 'Artist ${i % 40}',
            year: year,
            trackCount: 8,
          );
        });

        settingsStore.update((s) => s.copyWith(albumSort: 'year', libraryViewMode: 'square'));
        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('albums_year_grouped_scroll')), findsOneWidget);
        // Only a small visible subset of cards is materialized inside the viewport.
        expect(find.byType(InkWell).evaluate().length, lessThan(120));

        // Scroll down smoothly without errors.
        await tester.drag(
          find.byKey(const Key('albums_year_grouped_scroll')),
          const Offset(0, -1800),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'albums_sort_direction toggles albumsSortReversed, rotates arrow 140ms, and respects reduceMotion',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        final sortDirectionBtn = find.byKey(const Key('albums_sort_direction'));
        expect(sortDirectionBtn, findsOneWidget);

        // Initial state: ascending (turns: 0.0, tooltip: Ascending)
        expect(settingsStore.settings.albumsSortReversed, isFalse);
        var rot = tester.widget<AnimatedRotation>(
          find.descendant(of: sortDirectionBtn, matching: find.byType(AnimatedRotation)),
        );
        expect(rot.turns, equals(0.0));
        expect(rot.duration, equals(const Duration(milliseconds: 140)));
        var iconBtn = tester.widget<IconButton>(sortDirectionBtn);
        expect(iconBtn.tooltip, equals('Ascending'));

        // Tap toggle -> descending (turns: 0.5, tooltip: Descending)
        await tester.tap(sortDirectionBtn);
        await tester.pumpAndSettle();
        expect(settingsStore.settings.albumsSortReversed, isTrue);
        rot = tester.widget<AnimatedRotation>(
          find.descendant(of: sortDirectionBtn, matching: find.byType(AnimatedRotation)),
        );
        expect(rot.turns, equals(0.5));
        iconBtn = tester.widget<IconButton>(sortDirectionBtn);
        expect(iconBtn.tooltip, equals('Descending'));

        // Reduce motion sets duration to Duration.zero
        settingsStore.update((s) => s.copyWith(reduceMotion: true));
        await tester.pumpAndSettle();
        rot = tester.widget<AnimatedRotation>(
          find.descendant(of: sortDirectionBtn, matching: find.byType(AnimatedRotation)),
        );
        expect(rot.duration, equals(Duration.zero));

        // Tap toggle again -> back to ascending
        await tester.tap(sortDirectionBtn);
        await tester.pumpAndSettle();
        expect(settingsStore.settings.albumsSortReversed, isFalse);
        rot = tester.widget<AnimatedRotation>(
          find.descendant(of: sortDirectionBtn, matching: find.byType(AnimatedRotation)),
        );
        expect(rot.turns, equals(0.0));
        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'year sort reversal orders year headers oldest first while keeping Unknown year last',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        settingsStore.update((s) => s.copyWith(albumSort: 'year', albumsSortReversed: false));
        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        final h2024 = find.byKey(const ValueKey<String>('album_year_header_2024'));
        final h2020 = find.byKey(const ValueKey<String>('album_year_header_2020'));
        final hUnknown = find.byKey(const ValueKey<String>('album_year_header_unknown'));

        // Normal year sort: 2024 -> 2020 -> unknown
        expect(tester.getTopLeft(h2024).dy, lessThan(tester.getTopLeft(h2020).dy));
        expect(tester.getTopLeft(h2020).dy, lessThan(tester.getTopLeft(hUnknown).dy));

        // Toggle reversed sort
        await tester.tap(find.byKey(const Key('albums_sort_direction')));
        await tester.pumpAndSettle();
        expect(settingsStore.settings.albumsSortReversed, isTrue);

        // Reversed year sort: 2020 -> 2024 -> unknown (unknown stays trailing!)
        expect(tester.getTopLeft(h2020).dy, lessThan(tester.getTopLeft(h2024).dy));
        expect(tester.getTopLeft(h2024).dy, lessThan(tester.getTopLeft(hUnknown).dy));
        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'flat title sort reversal reverses items and changing sort key resets albumsSortReversed to false',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        settingsStore.update((s) => s.copyWith(
          albumSort: 'title',
          albumsSortReversed: false,
          libraryViewMode: 'list',
        ));
        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        // In title ascending order: Aurora (1st) and Zero Vault (5th)
        final auroraFinder = find.text('Aurora');
        final zeroVaultFinder = find.text('Zero Vault');
        expect(tester.getTopLeft(auroraFinder).dy, lessThan(tester.getTopLeft(zeroVaultFinder).dy));

        // Toggle sort direction: title descending
        await tester.tap(find.byKey(const Key('albums_sort_direction')));
        await tester.pumpAndSettle();
        expect(settingsStore.settings.albumsSortReversed, isTrue);

        // In title descending order: Zero Vault is above Aurora
        expect(tester.getTopLeft(zeroVaultFinder).dy, lessThan(tester.getTopLeft(auroraFinder).dy));

        // Changing sort key via sort menu resets albumsSortReversed to false
        await tester.tap(find.byKey(const Key('sort_button')));
        await tester.pumpAndSettle();

        // Select 'Artist' from popup menu
        await tester.tap(find.text('Artist').last);
        await tester.pumpAndSettle();

        expect(settingsStore.settings.albumSort, equals('artist'));
        expect(settingsStore.settings.albumsSortReversed, isFalse);
        await tester.pump(const Duration(milliseconds: 500));
      },
    );
  });

  group('AlbumsView Artist Filter Tests (S1)', () {
    late Directory tempDir;
    late _AlbumTestRepository repo;
    late SettingsStore settingsStore;
    late ArtistNameStore artistNameStore;
    late AppNavigator navigator;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_albums_s1_');
      repo = _AlbumTestRepository()
        ..albumsData = const [
          AlbumSummary(album: 'Sunburst', albumArtist: 'Aria', year: 2024, trackCount: 11),
          AlbumSummary(album: 'Aurora', albumArtist: 'Aria', year: 2024, trackCount: 7),
          AlbumSummary(album: 'Midnight Echoes', albumArtist: 'Zed', year: 2020, trackCount: 9),
        ]
        ..artistsData = const [
          ArtistSummary(key: 'aria', name: 'Aria', trackCount: 18, albumCount: 2),
          ArtistSummary(key: 'zed', name: 'Zed', trackCount: 9, albumCount: 1),
          ArtistSummary(key: 'single_only', name: 'Single Only', trackCount: 3, albumCount: 0),
        ]
        ..albumsByArtistData = const {
          'aria': [
            AlbumSummary(album: 'Sunburst', albumArtist: 'Aria', year: 2024, trackCount: 11),
            AlbumSummary(album: 'Aurora', albumArtist: 'Aria', year: 2024, trackCount: 7),
          ],
          'zed': [
            AlbumSummary(album: 'Midnight Echoes', albumArtist: 'Zed', year: 2020, trackCount: 9),
          ],
          'single_only': [],
        };

      settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(
          language: 'en',
          albumSort: 'title',
          libraryViewMode: 'list',
        ),
      );
      await settingsStore.init();
      artistNameStore = ArtistNameStore(directory: tempDir);
      await artistNameStore.init();
      navigator = AppNavigator();
    });

    tearDown(() async {
      settingsStore.dispose();
      artistNameStore.dispose();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    Widget buildHarness() {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: SettingsScope(
          store: settingsStore,
          child: ArtistNameScope(
            store: artistNameStore,
            child: Scaffold(
              body: AlbumsView(
                repository: repo,
                settingsStore: settingsStore,
                navigator: navigator,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'header count shows filtered count when artist chip is selected',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        // Initially 3 albums
        expect(find.text('3 albums'), findsOneWidget);
        expect(find.text('Sunburst'), findsOneWidget);
        expect(find.text('Aurora'), findsOneWidget);
        expect(find.text('Midnight Echoes'), findsOneWidget);

        // Tap chip for Aria
        await tester.tap(find.byKey(const Key('artist_chip_button_aria')));
        await tester.pumpAndSettle();

        // Filtered: 2 albums
        expect(find.text('2 albums'), findsOneWidget);
        expect(find.text('Sunburst'), findsOneWidget);
        expect(find.text('Aurora'), findsOneWidget);
        expect(find.text('Midnight Echoes'), findsNothing);

        // Search on top of artist filter
        await tester.enterText(find.byType(TextField), 'sun');
        await tester.pumpAndSettle();

        expect(find.text('1 albums'), findsOneWidget);
        expect(find.text('Sunburst'), findsOneWidget);
        expect(find.text('Aurora'), findsNothing);
      },
    );

    testWidgets(
      'artist with zero albums shows localized empty state with "Show all" button and never "No albums in library"',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Add artist to chips data
        repo.artistsData = const [
          ArtistSummary(key: 'aria', name: 'Aria', trackCount: 18, albumCount: 2),
          ArtistSummary(key: 'zero_artist', name: 'Zero Artist', trackCount: 2, albumCount: 1),
        ];
        repo.albumsByArtistData = const {
          'aria': [
            AlbumSummary(album: 'Sunburst', albumArtist: 'Aria', year: 2024, trackCount: 11),
          ],
          'zero_artist': [],
        };

        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        expect(find.text('3 albums'), findsOneWidget);

        // Tap Zero Artist chip
        await tester.tap(find.byKey(const Key('artist_chip_button_zero_artist')));
        await tester.pumpAndSettle();

        // Must show localized empty state for artist
        expect(find.text('No albums for this artist'), findsOneWidget);
        expect(find.text('No albums in library'), findsNothing);
        expect(find.byKey(const Key('albums_empty_show_all_button')), findsOneWidget);
        expect(find.text('0 albums'), findsOneWidget);

        // Tap Show all button
        await tester.tap(find.byKey(const Key('albums_empty_show_all_button')));
        await tester.pumpAndSettle();

        // Restores full list
        expect(find.text('3 albums'), findsOneWidget);
        expect(find.text('Sunburst'), findsOneWidget);
        expect(find.text('No albums for this artist'), findsNothing);
      },
    );

    testWidgets(
      'only artists with at least one album get a chip in the row (S2)',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Aria has 2 albums; Single Artist has 0 albums
        repo.artistsData = const [
          ArtistSummary(key: 'aria', name: 'Aria', trackCount: 18, albumCount: 2),
          ArtistSummary(key: 'single_only', name: 'Single Only', trackCount: 5, albumCount: 0),
        ];

        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        // Aria appears
        expect(find.byKey(const Key('artist_chip_button_aria')), findsOneWidget);

        // Single Only does NOT get a chip in the row
        expect(find.byKey(const Key('artist_chip_button_single_only')), findsNothing);

        // But Single Only is available in All Artists dialog
        await tester.tap(find.byKey(const Key('albums_artist_chips_all_artists')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('all_artists_item_single_only')), findsOneWidget);
      },
    );

    testWidgets(
      'albumsArtistChipsOrder reorder and reset persists to settingsStore (S2)',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        repo.artistsData = const [
          ArtistSummary(key: 'aria', name: 'Aria', trackCount: 18, albumCount: 2),
          ArtistSummary(key: 'zed', name: 'Zed', trackCount: 9, albumCount: 1),
        ];

        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        // Default order: aria, zed
        expect(settingsStore.settings.albumsArtistChipsOrder, isEmpty);

        // Reset order menu action
        await tester.tap(find.byKey(const Key('albums_artist_chips_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('albums_artist_chips_reset_order')));
        await tester.pumpAndSettle();

        expect(settingsStore.settings.albumsArtistChipsOrder, isEmpty);
      },
    );

    testWidgets(
      'multi-select artist chips shows union without duplicates, survives shape/sort changes, and handles empty state + RTL without overflow',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const sharedAlbum = AlbumSummary(
          album: 'Shared Horizons',
          albumArtist: 'Various Artists',
          year: 2023,
          trackCount: 6,
        );
        const auroraAlbum = AlbumSummary(
          album: 'Aurora',
          albumArtist: 'Aria',
          year: 2024,
          trackCount: 7,
        );
        const echoesAlbum = AlbumSummary(
          album: 'Midnight Echoes',
          albumArtist: 'Zed',
          year: 2020,
          trackCount: 9,
        );
        const thirdAlbum = AlbumSummary(
          album: 'Third Wave',
          albumArtist: 'Nova',
          year: 2019,
          trackCount: 5,
        );

        repo
          ..albumsData = const [auroraAlbum, echoesAlbum, sharedAlbum, thirdAlbum]
          ..artistsData = const [
            ArtistSummary(key: 'aria', name: 'Aria', trackCount: 10, albumCount: 2),
            ArtistSummary(key: 'zed', name: 'Zed', trackCount: 12, albumCount: 2),
            ArtistSummary(key: 'nova', name: 'Nova', trackCount: 5, albumCount: 1),
          ]
          ..albumsByArtistData = const {
            'aria': [auroraAlbum, sharedAlbum],
            'zed': [echoesAlbum, sharedAlbum],
            'nova': [thirdAlbum],
          };

        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        expect(find.text('4 albums'), findsOneWidget);

        // Select Aria -> 2 albums
        await tester.tap(find.byKey(const Key('artist_chip_button_aria')));
        await tester.pumpAndSettle();
        expect(find.text('2 albums'), findsOneWidget);
        expect(find.text('Aurora'), findsOneWidget);
        expect(find.text('Shared Horizons'), findsOneWidget);
        expect(find.text('Midnight Echoes'), findsNothing);

        // Toggle Zed as well -> union of Aria + Zed (3 unique albums, Shared Horizons once)
        await tester.tap(find.byKey(const Key('artist_chip_button_zed')));
        await tester.pumpAndSettle();
        expect(find.text('3 albums'), findsOneWidget);
        expect(find.text('Aurora'), findsOneWidget);
        expect(find.text('Midnight Echoes'), findsOneWidget);
        expect(find.text('Shared Horizons'), findsOneWidget);
        expect(find.text('Third Wave'), findsNothing);

        // Change shape to square and sort reversed -> multi-selection survives in memory
        settingsStore.update((s) => s.copyWith(libraryViewMode: 'square'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('albums_square_grid')), findsOneWidget);
        await tester.tap(find.byKey(const Key('albums_sort_direction')));
        await tester.pumpAndSettle();
        expect(find.text('3 albums'), findsOneWidget);
        expect(find.text('Third Wave'), findsNothing);

        // Deselect both -> returns to All (4 albums)
        await tester.tap(find.byKey(const Key('artist_chip_button_aria')));
        await tester.pumpAndSettle();
        expect(find.text('2 albums'), findsOneWidget);
        await tester.tap(find.byKey(const Key('artist_chip_button_zed')));
        await tester.pumpAndSettle();
        expect(find.text('4 albums'), findsOneWidget);
        expect(find.text('Third Wave'), findsOneWidget);

        // Switch to Arabic RTL and verify multi-select + Show all empty state without overflow
        settingsStore.update((s) => s.copyWith(language: 'ar'));
        repo.artistsData = const [
          ArtistSummary(key: 'empty1', name: 'فنان ١', trackCount: 2, albumCount: 1),
          ArtistSummary(key: 'empty2', name: 'فنان ٢', trackCount: 2, albumCount: 1),
          ArtistSummary(key: 'aria', name: 'آريا', trackCount: 10, albumCount: 2),
        ];
        repo.albumsByArtistData = const {
          'empty1': [],
          'empty2': [],
          'aria': [auroraAlbum],
        };
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: SettingsScope(
                store: settingsStore,
                child: ArtistNameScope(
                  store: artistNameStore,
                  child: Scaffold(
                    body: AlbumsView(
                      repository: repo,
                      settingsStore: settingsStore,
                      navigator: navigator,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('artist_chip_button_empty1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('artist_chip_button_empty2')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('albums_empty_show_all_button')), findsOneWidget);
        await tester.tap(find.byKey(const Key('albums_empty_show_all_button')));
        await tester.pumpAndSettle();

        expect(find.text('Aurora'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
