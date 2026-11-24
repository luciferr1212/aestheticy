import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/features/library_view/release_kind.dart';
import 'package:aestheticy/library/album_identity.dart';
import 'package:aestheticy/library/cover_cache.dart';
import 'package:aestheticy/library/library_scanner.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/tag_reader.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/library/albums_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

class _MapTagReader implements TagReader {
  final Map<String, RawTags> tagsByPath;
  _MapTagReader(Map<String, RawTags> tags)
      : tagsByPath = tags.map((k, v) => MapEntry(p.normalize(k), v));

  @override
  RawTags readTags(String filePath, {bool readCover = true}) {
    return tagsByPath[p.normalize(filePath)] ?? const RawTags();
  }
}

void main() {
  group('AlbumIdentity (S1)', () {
    test('uses album + normalized albumArtist, falling back to artist, and trackPath when album is empty', () {
      final k1 = AlbumIdentity.key(
        album: 'Greatest Hits',
        albumArtist: 'Artist One',
        artist: 'Ignored',
        trackPath: 'C:\\a.mp3',
      );
      final k2 = AlbumIdentity.key(
        album: 'greatest  hits',
        albumArtist: 'artist one',
        artist: 'Someone Else',
        trackPath: 'C:\\b.mp3',
      );
      expect(k1, equals(k2));

      // Null/empty albumArtist falls back to track artist
      final kFallbackA = AlbumIdentity.key(
        album: 'Greatest Hits',
        albumArtist: null,
        artist: 'Artist Alpha',
        trackPath: 'C:\\1.mp3',
      );
      final kFallbackB = AlbumIdentity.key(
        album: 'Greatest Hits',
        albumArtist: '   ',
        artist: 'Artist Beta',
        trackPath: 'C:\\2.mp3',
      );
      expect(kFallbackA, isNot(equals(kFallbackB)));

      // Matching explicit albumArtist and null albumArtist + same artist produce same identity
      final kExplicitAlpha = AlbumIdentity.key(
        album: 'Greatest Hits',
        albumArtist: 'Artist Alpha',
        artist: 'Artist Alpha',
      );
      expect(kFallbackA, equals(kExplicitAlpha));

      // Arabic diacritics normalize identically
      final kAr1 = AlbumIdentity.key(
        album: 'أغَانِي',
        albumArtist: 'فَيْرُوز',
      );
      final kAr2 = AlbumIdentity.key(
        album: 'اغاني',
        albumArtist: 'فيروز',
      );
      expect(kAr1, equals(kAr2));

      // Singles without an album tag key uniquely by track path
      final s1 = AlbumIdentity.key(
        album: null,
        albumArtist: null,
        artist: 'Same Artist',
        trackPath: 'C:\\Music\\single_one.mp3',
      );
      final s2 = AlbumIdentity.key(
        album: '   ',
        albumArtist: null,
        artist: 'Same Artist',
        trackPath: 'C:\\Music\\single_two.mp3',
      );
      expect(s1, isNot(equals(s2)));
      expect(s1, startsWith('track::'));
      expect(s2, startsWith('track::'));
    });

    test('CoverCache.computeCoverKey generates unique keys per album identity and per untagged single path', () {
      final sameTitleDiffArtist1 = CoverCache.computeCoverKey(
        album: 'Unplugged',
        albumArtist: null,
        artist: 'Artist One',
      );
      final sameTitleDiffArtist2 = CoverCache.computeCoverKey(
        album: 'Unplugged',
        albumArtist: null,
        artist: 'Artist Two',
      );
      expect(sameTitleDiffArtist1, isNot(equals(sameTitleDiffArtist2)));

      final untagged1 = CoverCache.computeCoverKey(
        album: null,
        artist: 'Solo Artist',
        trackPath: 'C:\\Singles\\track1.mp3',
      );
      final untagged2 = CoverCache.computeCoverKey(
        album: '',
        artist: 'Solo Artist',
        trackPath: 'C:\\Singles\\track2.mp3',
      );
      expect(untagged1, isNot(equals(untagged2)));

      // Explicit albumArtist and null albumArtist fallback for same artist match
      final fromAA = CoverCache.computeCoverKey(
        album: 'Debut',
        albumArtist: 'Nadia',
      );
      final fromArtist = CoverCache.computeCoverKey(
        album: 'Debut',
        artist: 'Nadia',
      );
      expect(fromAA, equals(fromArtist));
    });
  });

  group('SqliteLibraryRepository with unified AlbumIdentity (S1)', () {
    late SqliteLibraryRepository repo;
    late LibraryFolder folder;
    final now = DateTime.utc(2026, 2, 1);

    setUp(() async {
      repo = SqliteLibraryRepository.inMemory();
      folder = await repo.addFolder('C:\\Music');
    });

    tearDown(() async {
      await repo.close();
    });

    test('keeps same-titled albums separate when albumArtist is null or differs', () async {
      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\alpha_1.mp3',
          folderId: folder.id!,
          title: 'Alpha 1',
          artist: 'Artist Alpha',
          albumArtist: null,
          album: 'Greatest Hits',
          trackNo: 1,
          durationMs: 180000,
          mtimeMs: 10,
          sizeBytes: 100,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\alpha_2.mp3',
          folderId: folder.id!,
          title: 'Alpha 2',
          artist: 'Artist Alpha',
          albumArtist: null,
          album: 'Greatest Hits',
          trackNo: 2,
          durationMs: 190000,
          mtimeMs: 10,
          sizeBytes: 100,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\beta_1.mp3',
          folderId: folder.id!,
          title: 'Beta 1',
          artist: 'Artist Beta',
          albumArtist: null,
          album: 'Greatest Hits',
          trackNo: 1,
          durationMs: 200000,
          mtimeMs: 10,
          sizeBytes: 100,
          addedAt: now,
        ),
      ]);
      await repo.rebuildArtistLinks();

      expect(await repo.albumCount(), equals(2));

      final albums = await repo.listAlbums();
      expect(albums.length, equals(2));
      expect(
        albums.map((a) => '${a.album}:${a.displayArtist}:${a.trackCount}').toSet(),
        equals({
          'Greatest Hits:Artist Alpha:2',
          'Greatest Hits:Artist Beta:1',
        }),
      );

      // tracksOfAlbum with albumArtist matches each artist cleanly
      final alphaTracks = await repo.tracksOfAlbum(
        'Greatest Hits',
        albumArtist: 'Artist Alpha',
      );
      expect(alphaTracks.map((t) => t.title), equals(['Alpha 1', 'Alpha 2']));

      final betaTracks = await repo.tracksOfAlbum(
        'Greatest Hits',
        albumArtist: 'Artist Beta',
      );
      expect(betaTracks.map((t) => t.title), equals(['Beta 1']));

      // tracksOfAlbum with null albumArtist NEVER merges Artist Alpha and Artist Beta
      final nullTracks = await repo.tracksOfAlbum('Greatest Hits');
      expect(nullTracks, isEmpty);

      // albumKey lookup matches exact album
      final alphaSummary =
          albums.firstWhere((a) => a.displayArtist == 'Artist Alpha');
      final byKey = await repo.tracksOfAlbum(
        alphaSummary.album,
        albumKey: alphaSummary.identityKey,
      );
      expect(byKey.length, equals(2));

      // listAlbumsByArtistKey returns only the matching artist's album
      final artistAlphaAlbums = await repo.listAlbumsByArtistKey('artist alpha');
      expect(artistAlphaAlbums.length, equals(1));
      expect(artistAlphaAlbums.first.trackCount, equals(2));
      expect(artistAlphaAlbums.first.displayArtist, equals('Artist Alpha'));

      // searchAlbums preserves the two separate albums
      final searched = await repo.searchAlbums('Greatest Hits');
      expect(searched.length, equals(2));
    });

    test('keeps singles without an album tag separate and retrieves individual tracks by albumKey', () async {
      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\Singles\\loose_1.mp3',
          folderId: folder.id!,
          title: 'Loose 1',
          artist: 'Solo Artist',
          album: null,
          durationMs: 150000,
          mtimeMs: 10,
          sizeBytes: 100,
          coverKey: 'cov_1',
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\Singles\\loose_2.mp3',
          folderId: folder.id!,
          title: 'Loose 2',
          artist: 'Solo Artist',
          album: '',
          durationMs: 160000,
          mtimeMs: 10,
          sizeBytes: 100,
          coverKey: 'cov_2',
          addedAt: now,
        ),
      ]);

      expect(await repo.albumCount(), equals(2));
      final albums = await repo.listAlbums();
      expect(albums.length, equals(2));
      expect(albums.every((a) => a.trackCount == 1), isTrue);
      expect(
        albums.map((a) => a.identityKey).toSet().length,
        equals(2),
      );

      final single1Summary = albums.firstWhere((a) => a.coverKey == 'cov_1');
      final single1Tracks = await repo.tracksOfAlbum(
        single1Summary.album,
        albumKey: single1Summary.identityKey,
      );
      expect(single1Tracks.length, equals(1));
      expect(single1Tracks.first.title, equals('Loose 1'));
    });

    test('explicit Various Artists groups multi-artist compilation together', () async {
      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\va1.mp3',
          folderId: folder.id!,
          title: 'Track 1',
          artist: 'Singer A',
          albumArtist: 'Various Artists',
          album: 'Summer Mix',
          durationMs: 180000,
          mtimeMs: 10,
          sizeBytes: 100,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\va2.mp3',
          folderId: folder.id!,
          title: 'Track 2',
          artist: 'Singer B',
          albumArtist: 'Various Artists',
          album: 'Summer Mix',
          durationMs: 180000,
          mtimeMs: 10,
          sizeBytes: 100,
          addedAt: now,
        ),
      ]);

      expect(await repo.albumCount(), equals(1));
      final tracks = await repo.tracksOfAlbum(
        'Summer Mix',
        albumArtist: 'Various Artists',
      );
      expect(tracks.length, equals(2));
    });
  });

  group('LibraryScanner untagged singles & unique cover keys (S1)', () {
    late Directory tempDir;
    late Directory coversDir;
    late SqliteLibraryRepository repo;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('aestheticy_s1_scan_');
      coversDir = Directory(p.join(tempDir.path, 'covers'))..createSync();
      CoverCache.setCustomDirectory(coversDir.path);
      repo = SqliteLibraryRepository.inMemory();
    });

    tearDown(() async {
      await repo.close();
      CoverCache.resetForTesting();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('untagged singles in same folder are NOT grouped under parent folder and keep unique cover keys', () async {
      final parent = Directory(p.join(tempDir.path, 'Mixes'))..createSync();
      final f1 = File(p.join(parent.path, 'SingleOne.mp3'))..writeAsBytesSync([1, 2]);
      final f2 = File(p.join(parent.path, 'SingleTwo.mp3'))..writeAsBytesSync([3, 4]);

      final cover1 = Uint8List.fromList([1, 1, 1, 1]);
      final cover2 = Uint8List.fromList([2, 2, 2, 2]);

      final reader = _MapTagReader({
        f1.path: RawTags(
          title: 'Single One',
          artist: 'Same Artist',
          album: null,
          embeddedCover: cover1,
        ),
        f2.path: RawTags(
          title: 'Single Two',
          artist: 'Same Artist',
          album: '   ',
          embeddedCover: cover2,
        ),
      });

      final scanner = LibraryScanner(
        repository: repo,
        tagReader: reader,
        coversDirectory: coversDir.path,
      );

      final folder = await repo.addFolder(tempDir.path);
      await scanner.scan(folder).last;

      final tracks = await repo.listTracks();
      expect(tracks.length, equals(2));
      expect(tracks.every((t) => t.album == null), isTrue);

      final t1 = tracks.firstWhere((t) => t.path == p.normalize(f1.path));
      final t2 = tracks.firstWhere((t) => t.path == p.normalize(f2.path));
      expect(t1.coverKey, isNotNull);
      expect(t2.coverKey, isNotNull);
      expect(t1.coverKey, isNot(equals(t2.coverKey)));

      expect(
        File(CoverCache.pathFor(t1.coverKey!, coversDirectory: coversDir.path))
            .readAsBytesSync(),
        equals(cover1),
      );
      expect(
        File(CoverCache.pathFor(t2.coverKey!, coversDirectory: coversDir.path))
            .readAsBytesSync(),
        equals(cover2),
      );

      expect(await repo.albumCount(), equals(2));
    });
  });

  group('ReleaseKindClassifier with unified AlbumIdentity (S1)', () {
    test('separates null-albumArtist same-named albums across tracks and summaries', () {
      const targetArtist = 'Nadia';
      final now = DateTime.utc(2026, 1, 1);

      final tOwn = List.generate(
        8,
        (i) => Track(
          path: '/nadia_$i.mp3',
          folderId: 1,
          title: 'Own $i',
          artist: targetArtist,
          albumArtist: null,
          album: 'Self Titled',
          durationMs: 180000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: now,
        ),
      );
      final tOther = Track(
        path: '/other.mp3',
        folderId: 1,
        title: 'Other Track',
        artist: 'Other Artist feat. $targetArtist',
        albumArtist: null,
        album: 'Self Titled',
        durationMs: 180000,
        mtimeMs: 1,
        sizeBytes: 100,
        addedAt: now,
      );

      final classification = ReleaseKindClassifier.classify(
        artistName: targetArtist,
        tracks: [...tOwn, tOther],
      );
      expect(classification.releaseCounts[ReleaseCategory.albums], equals(1));
      expect(classification.releaseCounts[ReleaseCategory.appearsOn], equals(1));

      final classifiedAlbums = ReleaseKindClassifier.classifyAlbums(
        artistName: targetArtist,
        albums: [
          AlbumSummary(
            album: 'Self Titled',
            albumArtist: null,
            displayArtist: targetArtist,
            trackCount: 8,
            identityKey: AlbumIdentity.key(
              album: 'Self Titled',
              artist: targetArtist,
            ),
          ),
          AlbumSummary(
            album: 'Self Titled',
            albumArtist: null,
            displayArtist: 'Other Artist feat. $targetArtist',
            trackCount: 1,
            identityKey: AlbumIdentity.key(
              album: 'Self Titled',
              artist: 'Other Artist feat. $targetArtist',
            ),
          ),
        ],
        tracks: [...tOwn, tOther],
      );
      expect(classifiedAlbums[ReleaseCategory.albums]!.length, equals(1));
      expect(classifiedAlbums[ReleaseCategory.appearsOn]!.length, equals(1));
    });
  });

  group('AlbumsView sort by displayed artist (S1)', () {
    late Directory tempDir;
    late SqliteLibraryRepository repo;
    late SettingsStore settingsStore;
    late ArtistNameStore artistNameStore;
    late AppNavigator navigator;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_s1_ui_');
      repo = SqliteLibraryRepository.inMemory();
      settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(
          language: 'en',
          albumSort: 'artist',
          albumsSortReversed: false,
          libraryViewMode: 'list',
          artistNameMode: 'followLanguage',
        ),
      );
      await settingsStore.init();
      artistNameStore = ArtistNameStore(directory: tempDir);
      await artistNameStore.init();
      navigator = AppNavigator();
    });

    tearDown(() async {
      await repo.close();
      settingsStore.dispose();
      artistNameStore.dispose();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    testWidgets(
      'sorts by displayed artist including null-albumArtist displayArtist fallback and artist translations',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final folder = await repo.addFolder('C:\\Music');
        final now = DateTime.utc(2026, 1, 1);
        await repo.upsertTracks([
          Track(
            path: 'C:\\Music\\1.mp3',
            folderId: folder.id!,
            title: 'Song Z',
            artist: 'Zeta Singer',
            albumArtist: null,
            album: 'Album First Alphabetically',
            durationMs: 180000,
            mtimeMs: 1,
            sizeBytes: 100,
            addedAt: now,
          ),
          Track(
            path: 'C:\\Music\\2.mp3',
            folderId: folder.id!,
            title: 'Song A',
            artist: 'Aaron Singer',
            albumArtist: null,
            album: 'Album Last Alphabetically',
            durationMs: 180000,
            mtimeMs: 1,
            sizeBytes: 100,
            addedAt: now,
          ),
        ]);

        // Also map 'Zeta Singer' -> 'AAA Translated' via alwaysArabic so displayed artist changes order
        settingsStore.update((s) => s.copyWith(artistNameMode: 'alwaysArabic'));
        artistNameStore.setEntry('Zeta Singer', ar: 'AAA Translated');

        await tester.pumpWidget(
          MaterialApp(
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
          ),
        );
        await tester.pumpAndSettle();

        final zetaDisplayed = find.text('Album First Alphabetically');
        final aaronDisplayed = find.text('Album Last Alphabetically');
        expect(zetaDisplayed, findsOneWidget);
        expect(aaronDisplayed, findsOneWidget);

        // AAA Translated comes BEFORE Aaron Singer
        expect(
          tester.getTopLeft(zetaDisplayed).dy,
          lessThan(tester.getTopLeft(aaronDisplayed).dy),
        );

        // Removing translation restores Aaron Singer before Zeta Singer
        artistNameStore.removeEntry('Zeta Singer');
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(aaronDisplayed).dy,
          lessThan(tester.getTopLeft(zetaDisplayed).dy),
        );
        await tester.pump(const Duration(milliseconds: 500));
      },
    );
  });
}
