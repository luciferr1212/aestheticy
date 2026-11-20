import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/features/library_view/artist_page_model.dart';
import 'package:aestheticy/features/library_view/release_kind.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';

Track _makeTrack({
  required String path,
  required String artist,
  String? albumArtist,
  String? album,
  int? year,
  int durationMs = 180000,
  String? title,
}) {
  return Track(
    path: path,
    folderId: 1,
    title: title ?? 'Track $path',
    artist: artist,
    albumArtist: albumArtist,
    album: album,
    year: year,
    durationMs: durationMs,
    mtimeMs: 1000,
    sizeBytes: 1024,
    addedAt: DateTime.fromMillisecondsSinceEpoch(1000000),
  );
}

void main() {
  group('ReleaseKindClassifier album-level helpers & ArtistPageModel (S1)', () {
    const artist = 'Fairuz';

    test('classifies each category into albums, singlesAndEps, compilations, appearsOn, and tracks in order', () {
      final albumTracks = List.generate(
        8,
        (i) => _makeTrack(
          path: '/album_$i.mp3',
          artist: artist,
          albumArtist: artist,
          album: 'Studio Album',
          year: 2000,
        ),
      );
      final epTracks = List.generate(
        5,
        (i) => _makeTrack(
          path: '/ep_$i.mp3',
          artist: artist,
          albumArtist: artist,
          album: 'Autumn Sessions',
          year: 2010,
        ),
      );
      final singleTrack = _makeTrack(
        path: '/single.mp3',
        artist: artist,
        albumArtist: artist,
        album: 'Morning Song - Single',
        year: 2022,
      );
      final compTrack = _makeTrack(
        path: '/comp.mp3',
        artist: artist,
        albumArtist: 'Various Artists',
        album: 'Classic Hits',
        year: 2018,
      );
      final appearsTrack = _makeTrack(
        path: '/feat.mp3',
        artist: 'Lead Artist feat. $artist',
        albumArtist: 'Lead Artist',
        album: 'Collaboration LP',
        year: 2019,
      );

      const albums = [
        AlbumSummary(album: 'Studio Album', albumArtist: artist, year: 2000, trackCount: 8),
        AlbumSummary(album: 'Autumn Sessions', albumArtist: artist, year: 2010, trackCount: 5),
        AlbumSummary(album: 'Morning Song - Single', albumArtist: artist, year: 2022, trackCount: 1),
        AlbumSummary(album: 'Classic Hits', albumArtist: 'Various Artists', year: 2018, trackCount: 12),
        AlbumSummary(album: 'Collaboration LP', albumArtist: 'Lead Artist', year: 2019, trackCount: 10),
      ];

      final directClassified = ReleaseKindClassifier.classifyAlbums(
        albums: albums,
        artistName: artist,
        artistKey: 'fairuz',
        tracks: [...albumTracks, ...epTracks, singleTrack, compTrack, appearsTrack],
      );
      expect(directClassified[ReleaseCategory.albums]?.length, equals(1));
      expect(directClassified[ReleaseCategory.singles]?.length, equals(1));
      expect(directClassified[ReleaseCategory.eps]?.length, equals(1));
      expect(directClassified[ReleaseCategory.compilations]?.length, equals(1));
      expect(directClassified[ReleaseCategory.appearsOn]?.length, equals(1));

      final tracks = [
        ...albumTracks,
        ...epTracks,
        singleTrack,
        compTrack,
        appearsTrack,
      ];

      final model = ArtistPageModel.fromData(
        artistName: artist,
        artistKey: 'fairuz',
        albums: albums,
        tracks: tracks,
      );

      expect(model.artistName, equals(artist));
      expect(model.artistKey, equals('fairuz'));
      expect(model.albumCount, equals(5));
      expect(model.trackCount, equals(tracks.length));

      expect(model.albums.map((a) => a.album), equals(['Studio Album']));
      expect(
        model.singlesAndEps.map((a) => a.album),
        equals(['Morning Song - Single', 'Autumn Sessions']),
      );
      expect(model.compilations.map((a) => a.album), equals(['Classic Hits']));
      expect(model.appearsOn.map((a) => a.album), equals(['Collaboration LP']));

      expect(
        model.visibleSections,
        equals([
          ArtistPageSectionKind.albums,
          ArtistPageSectionKind.singlesAndEps,
          ArtistPageSectionKind.compilations,
          ArtistPageSectionKind.appearsOn,
          ArtistPageSectionKind.tracks,
        ]),
      );
      expect(
        model.albumSections.map((s) => s.kind),
        equals([
          ArtistPageSectionKind.albums,
          ArtistPageSectionKind.singlesAndEps,
          ArtistPageSectionKind.compilations,
          ArtistPageSectionKind.appearsOn,
        ]),
      );
    });

    test('hides empty sections', () {
      // Only Singles & EPs + Tracks
      final singlesOnlyModel = ArtistPageModel.fromData(
        artistName: artist,
        albums: const [
          AlbumSummary(
            album: 'One Track Single',
            albumArtist: artist,
            year: 2024,
            trackCount: 1,
          ),
        ],
        tracks: [
          _makeTrack(
            path: '/s1.mp3',
            artist: artist,
            albumArtist: artist,
            album: 'One Track Single',
          ),
        ],
      );
      expect(singlesOnlyModel.hasAlbums, isFalse);
      expect(singlesOnlyModel.hasSinglesAndEps, isTrue);
      expect(singlesOnlyModel.hasCompilations, isFalse);
      expect(singlesOnlyModel.hasAppearsOn, isFalse);
      expect(singlesOnlyModel.hasTracks, isTrue);
      expect(
        singlesOnlyModel.visibleSections,
        equals([
          ArtistPageSectionKind.singlesAndEps,
          ArtistPageSectionKind.tracks,
        ]),
      );

      // Loose track only (no albums)
      final looseOnlyModel = ArtistPageModel.fromData(
        artistName: artist,
        albums: const [],
        tracks: [
          _makeTrack(path: '/loose.mp3', artist: artist, album: null),
        ],
      );
      expect(looseOnlyModel.albumCount, equals(0));
      expect(looseOnlyModel.trackCount, equals(1));
      expect(looseOnlyModel.albumSections, isEmpty);
      expect(looseOnlyModel.visibleSections, equals([ArtistPageSectionKind.tracks]));

      // Completely empty artist
      final emptyModel = ArtistPageModel.fromData(
        artistName: artist,
        albums: const [],
        tracks: const [],
      );
      expect(emptyModel.albumCount, equals(0));
      expect(emptyModel.trackCount, equals(0));
      expect(emptyModel.visibleSections, isEmpty);
    });

    test('various-artists compilations classify to compilations across variants and precede appearsOn', () {
      const albums = [
        AlbumSummary(album: 'Comp 1', albumArtist: 'Various Artists', year: 2020, trackCount: 15),
        AlbumSummary(album: 'Comp 2', albumArtist: 'various', year: 2021, trackCount: 10),
        AlbumSummary(album: 'Comp 3', albumArtist: 'VA', year: 2022, trackCount: 8),
      ];
      final tracks = [
        _makeTrack(path: '/c1.mp3', artist: artist, albumArtist: 'Various Artists', album: 'Comp 1'),
        _makeTrack(path: '/c2.mp3', artist: artist, albumArtist: 'various', album: 'Comp 2'),
        _makeTrack(path: '/c3.mp3', artist: artist, albumArtist: 'VA', album: 'Comp 3'),
      ];

      final model = ArtistPageModel.fromData(
        artistName: artist,
        albums: albums,
        tracks: tracks,
      );

      expect(model.compilations.length, equals(3));
      expect(model.appearsOn, isEmpty);
      expect(model.albums, isEmpty);
      expect(model.singlesAndEps, isEmpty);
    });

    test('appears-on detects different albumArtist, featured-only tracks with null albumArtist, and fallback displayArtist', () {
      const albums = [
        AlbumSummary(
          album: 'Explicit Other Album',
          albumArtist: 'Main Star',
          year: 2023,
          trackCount: 10,
        ),
        AlbumSummary(
          album: 'Null AA Featured Only',
          albumArtist: null,
          year: 2021,
          trackCount: 8,
        ),
        AlbumSummary(
          album: 'Fallback Display Only',
          albumArtist: null,
          displayArtist: 'Guest Star',
          year: 2020,
          trackCount: 9,
        ),
      ];
      final tracks = [
        _makeTrack(
          path: '/a1.mp3',
          artist: 'Main Star feat. $artist',
          albumArtist: 'Main Star',
          album: 'Explicit Other Album',
        ),
        _makeTrack(
          path: '/a2.mp3',
          artist: 'Another Lead feat. $artist',
          albumArtist: null,
          album: 'Null AA Featured Only',
        ),
      ];

      final model = ArtistPageModel.fromData(
        artistName: artist,
        albums: albums,
        tracks: tracks,
      );

      expect(
        model.appearsOn.map((a) => a.album),
        equals([
          'Explicit Other Album',
          'Null AA Featured Only',
          'Fallback Display Only',
        ]),
      );
      expect(model.albums, isEmpty);
    });

    test('null album artist owns release when artist is primary on tracks and ignores sqlite displayArtist=various', () {
      final ownFullAlbumTracks = List.generate(
        8,
        (i) => _makeTrack(
          path: '/null_aa_full_$i.mp3',
          artist: i == 0 ? '$artist feat. Guest' : artist,
          albumArtist: null,
          album: 'Own Full Album',
          year: 2024,
        ),
      );
      final ownEpTracks = List.generate(
        5,
        (i) => _makeTrack(
          path: '/null_aa_ep_$i.mp3',
          artist: artist,
          albumArtist: null,
          album: 'Own EP',
          year: 2023,
        ),
      );
      final ownShortTracks = [
        _makeTrack(
          path: '/null_aa_single_1.mp3',
          artist: artist,
          albumArtist: null,
          album: 'Own Short Release',
          year: 2022,
          durationMs: 180000,
        ),
        _makeTrack(
          path: '/null_aa_single_2.mp3',
          artist: artist,
          albumArtist: null,
          album: 'Own Short Release',
          year: 2022,
          durationMs: 180000,
        ),
      ];

      const albums = [
        // SQLite marks displayArtist='various' when album_artist is null & multiple distinct track artists exist.
        AlbumSummary(
          album: 'Own Full Album',
          albumArtist: null,
          displayArtist: 'various',
          year: 2024,
          trackCount: 8,
        ),
        AlbumSummary(
          album: 'Own EP',
          albumArtist: null,
          displayArtist: artist,
          year: 2023,
          trackCount: 5,
        ),
        AlbumSummary(
          album: 'Own Short Release',
          albumArtist: null,
          displayArtist: artist,
          year: 2022,
          trackCount: 2,
        ),
      ];

      final model = ArtistPageModel.fromData(
        artistName: artist,
        albums: albums,
        tracks: [
          ...ownFullAlbumTracks,
          ...ownEpTracks,
          ...ownShortTracks,
        ],
      );

      expect(model.albums.map((a) => a.album), equals(['Own Full Album']));
      expect(
        model.singlesAndEps.map((a) => a.album),
        equals(['Own EP', 'Own Short Release']),
      );
      expect(model.compilations, isEmpty);
      expect(model.appearsOn, isEmpty);
    });

    test('album with 1-3 short tracks becomes a single while 1-3 tracks over 20 minutes becomes an album', () {
      final shortTracks = [
        _makeTrack(
          path: '/short1.mp3',
          artist: artist,
          albumArtist: artist,
          album: 'Short Two Track',
          year: 2021,
          durationMs: 240000,
        ),
        _makeTrack(
          path: '/short2.mp3',
          artist: artist,
          albumArtist: artist,
          album: 'Short Two Track',
          year: 2021,
          durationMs: 240000,
        ),
      ];
      final longTracks = [
        _makeTrack(
          path: '/long1.mp3',
          artist: artist,
          albumArtist: artist,
          album: 'Long Suite',
          year: 2020,
          durationMs: 700000,
        ),
        _makeTrack(
          path: '/long2.mp3',
          artist: artist,
          albumArtist: artist,
          album: 'Long Suite',
          year: 2020,
          durationMs: 700000, // total 1400s = 23.3m > 20m
        ),
      ];

      final model = ArtistPageModel.fromData(
        artistName: artist,
        albums: const [
          AlbumSummary(
            album: 'Short Two Track',
            albumArtist: artist,
            year: 2021,
            trackCount: 2,
          ),
          AlbumSummary(
            album: 'Long Suite',
            albumArtist: artist,
            year: 2020,
            trackCount: 2,
          ),
        ],
        tracks: [...shortTracks, ...longTracks],
      );

      expect(model.singlesAndEps.map((a) => a.album), equals(['Short Two Track']));
      expect(model.albums.map((a) => a.album), equals(['Long Suite']));
    });

    test('separates same-titled albums with distinct albumArtist via album|albumArtist group key', () {
      final ownTracks = List.generate(
        7,
        (i) => _makeTrack(
          path: '/own_gh_$i.mp3',
          artist: artist,
          albumArtist: artist,
          album: 'Greatest Hits',
          year: 2020,
        ),
      );
      final compTrack = _makeTrack(
        path: '/va_gh.mp3',
        artist: artist,
        albumArtist: 'Various Artists',
        album: 'Greatest Hits',
        year: 2023,
      );

      final model = ArtistPageModel.fromData(
        artistName: artist,
        albums: const [
          AlbumSummary(album: 'Greatest Hits', albumArtist: artist, year: 2020, trackCount: 7),
          AlbumSummary(album: 'Greatest Hits', albumArtist: 'Various Artists', year: 2023, trackCount: 20),
        ],
        tracks: [...ownTracks, compTrack],
      );

      expect(model.albums.length, equals(1));
      expect(model.albums.first.albumArtist, equals(artist));
      expect(model.compilations.length, equals(1));
      expect(model.compilations.first.albumArtist, equals('Various Artists'));
    });

    test('supports aliasKeys so merged albumArtist spelling stays in artist own sections', () {
      final tracks = List.generate(
        7,
        (i) => _makeTrack(
          path: '/alias_$i.mp3',
          artist: 'فيروز',
          albumArtist: 'Fairouz',
          album: 'Alias Album',
          year: 1995,
        ),
      );
      final model = ArtistPageModel.fromData(
        artistName: 'فيروز',
        artistKey: 'فيروز',
        aliasKeys: const {'fairouz'},
        albums: const [
          AlbumSummary(album: 'Alias Album', albumArtist: 'Fairouz', year: 1995, trackCount: 7),
        ],
        tracks: tracks,
      );

      expect(model.albums.map((a) => a.album), equals(['Alias Album']));
      expect(model.appearsOn, isEmpty);
    });

    test('sorts each album section by year descending, unknown/non-positive years last, then normalized title ascending', () {
      final tracks = <Track>[];
      const albums = [
        AlbumSummary(album: 'Unknown Null', albumArtist: artist, year: null, trackCount: 8),
        AlbumSummary(album: 'Zero Year', albumArtist: artist, year: 0, trackCount: 8),
        AlbumSummary(album: 'Beta 2022', albumArtist: artist, year: 2022, trackCount: 8),
        AlbumSummary(album: 'Alpha 2022', albumArtist: artist, year: 2022, trackCount: 8),
        AlbumSummary(album: 'Newest 2025', albumArtist: artist, year: 2025, trackCount: 8),
        AlbumSummary(album: 'Oldest 1998', albumArtist: artist, year: 1998, trackCount: 8),
        AlbumSummary(album: 'أحمد', albumArtist: artist, year: 2022, trackCount: 8),
        AlbumSummary(album: 'باسم', albumArtist: artist, year: 2022, trackCount: 8),
      ];

      final model = ArtistPageModel.fromData(
        artistName: artist,
        albums: albums,
        tracks: tracks,
      );

      expect(
        model.albums.map((a) => a.album),
        equals([
          'Newest 2025',
          'Alpha 2022',
          'Beta 2022',
          'أحمد',
          'باسم',
          'Oldest 1998',
          'Unknown Null',
          'Zero Year',
        ]),
      );
    });

    test('filterTracks matches title and album with Arabic/Latin diacritic normalization', () {
      final model = ArtistPageModel.fromData(
        artistName: 'فيروز',
        albums: const [],
        tracks: [
          _makeTrack(
            path: '/1.mp3',
            artist: 'فيروز',
            title: 'سَأَلتُكَ حَبيبي',
            album: 'ألبوم الشتاء',
          ),
          _makeTrack(
            path: '/2.mp3',
            artist: 'فيروز',
            title: 'Morning Echo',
            album: 'Café Sessions',
          ),
        ],
      );

      expect(model.filterTracks('').length, equals(2));
      expect(model.filterTracks('سالتك').single.path, equals('/1.mp3'));
      expect(model.filterTracks('الشتاء').single.path, equals('/1.mp3'));
      expect(model.filterTracks('cafe echo').single.path, equals('/2.mp3'));
      expect(model.filterTracks('nonexistent'), isEmpty);
    });

    test('integrates end-to-end with SqliteLibraryRepository.listAlbumsByArtistKey and tracksOfArtist', () async {
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);

      final folder = await repo.addFolder('C:\\Music');
      const target = 'Nadia';

      final tracks = <Track>[
        ...List.generate(
          7,
          (i) => Track(
            path: 'C:\\Music\\alb_$i.mp3',
            folderId: folder.id!,
            title: 'Album Track $i',
            artist: target,
            albumArtist: target,
            album: 'Blue Horizon',
            year: 2021,
            durationMs: 180000,
            mtimeMs: 1,
            sizeBytes: 100,
            addedAt: DateTime(2025, 1, 1),
          ),
        ),
        Track(
          path: 'C:\\Music\\single.mp3',
          folderId: folder.id!,
          title: 'Spark',
          artist: target,
          albumArtist: target,
          album: 'Spark',
          year: 2024,
          durationMs: 190000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: DateTime(2025, 1, 2),
        ),
        Track(
          path: 'C:\\Music\\comp.mp3',
          folderId: folder.id!,
          title: 'Summer Mix Song',
          artist: target,
          albumArtist: 'Various Artists',
          album: 'Summer Vibes',
          year: 2023,
          durationMs: 200000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: DateTime(2025, 1, 3),
        ),
        Track(
          path: 'C:\\Music\\feat.mp3',
          folderId: folder.id!,
          title: 'Guest Verse',
          artist: 'Other Star feat. $target',
          albumArtist: 'Other Star',
          album: 'Starlight',
          year: 2022,
          durationMs: 210000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: DateTime(2025, 1, 4),
        ),
        Track(
          path: 'C:\\Music\\loose.mp3',
          folderId: folder.id!,
          title: 'Loose Demo',
          artist: target,
          album: null,
          durationMs: 150000,
          mtimeMs: 1,
          sizeBytes: 100,
          addedAt: DateTime(2025, 1, 5),
        ),
      ];

      await repo.upsertTracks(tracks);
      await repo.rebuildArtistLinks();

      final artists = await repo.listArtists();
      final nadia = artists.firstWhere((a) => a.name == target);
      final albums = await repo.listAlbumsByArtistKey(nadia.key);
      final artistTracks = await repo.tracksOfArtist(nadia.name, artistKey: nadia.key);

      final model = ArtistPageModel.fromData(
        artistName: nadia.name,
        artistKey: nadia.key,
        albums: albums,
        tracks: artistTracks,
      );

      expect(model.albumCount, equals(4));
      expect(model.trackCount, equals(11));
      expect(model.albums.map((a) => a.album), equals(['Blue Horizon']));
      expect(model.singlesAndEps.map((a) => a.album), equals(['Spark']));
      expect(model.compilations.map((a) => a.album), equals(['Summer Vibes']));
      expect(model.appearsOn.map((a) => a.album), equals(['Starlight']));
    });
  });
}
