import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/features/library_view/release_kind.dart';
import 'package:aestheticy/library/models.dart';

Track makeTrack({
  required String path,
  required String artist,
  String? albumArtist,
  String? album,
  int durationMs = 180000,
}) {
  return Track(
    path: path,
    folderId: 1,
    title: 'Test Track',
    artist: artist,
    albumArtist: albumArtist,
    album: album,
    durationMs: durationMs,
    mtimeMs: 1000,
    sizeBytes: 1024,
    addedAt: DateTime.fromMillisecondsSinceEpoch(1000000),
  );
}

void main() {
  group('ReleaseKindClassifier Rules & Order (S3)', () {
    const mainArtist = 'Artist Name';

    test('Rule 1: Various Artists or compilation maps to Compilations', () {
      final t1 = makeTrack(
        path: '/t1.mp3',
        artist: mainArtist,
        albumArtist: 'Various Artists',
        album: 'Hits 2026',
      );
      final t2 = makeTrack(
        path: '/t2.mp3',
        artist: mainArtist,
        albumArtist: 'VA',
        album: 'Summer Hits',
      );
      final t3 = makeTrack(
        path: '/t3.mp3',
        artist: mainArtist,
        albumArtist: 'Various',
        album: 'Top 40',
      );

      final map = ReleaseKindClassifier.classifyTracks(
        artistName: mainArtist,
        tracks: [t1, t2, t3],
      );

      expect(map[ReleaseCategory.compilations]?.length, equals(3));
    });

    test('Rule 2: Artist not being album artist maps to Appears On', () {
      final t1 = makeTrack(
        path: '/t1.mp3',
        artist: mainArtist,
        albumArtist: 'Other Lead Artist',
        album: 'Other Album',
      );

      final map = ReleaseKindClassifier.classifyTracks(
        artistName: mainArtist,
        tracks: [t1],
      );

      expect(map[ReleaseCategory.appearsOn]?.length, equals(1));
      expect(map[ReleaseCategory.albums]?.isEmpty, isTrue);
    });

    test('Rule 1 takes precedence over Rule 2 (Various Artists -> Compilations, not Appears On)', () {
      final t1 = makeTrack(
        path: '/t1.mp3',
        artist: mainArtist,
        albumArtist: 'Various Artists',
        album: 'Mix',
      );

      final map = ReleaseKindClassifier.classifyTracks(
        artistName: mainArtist,
        tracks: [t1],
      );

      expect(map[ReleaseCategory.compilations]?.length, equals(1));
      expect(map[ReleaseCategory.appearsOn]?.isEmpty, isTrue);
    });

    test('Rule 3: Title hints for Singles and EPs (English, case-insensitive)', () {
      final single1 = makeTrack(
        path: '/s1.mp3',
        artist: mainArtist,
        albumArtist: mainArtist,
        album: 'Song Title - Single',
      );
      final single2 = makeTrack(
        path: '/s2.mp3',
        artist: mainArtist,
        albumArtist: mainArtist,
        album: 'Another (Single)',
      );
      final ep1 = makeTrack(
        path: '/ep1.mp3',
        artist: mainArtist,
        albumArtist: mainArtist,
        album: 'Debut - EP',
      );
      final ep2 = makeTrack(
        path: '/ep2.mp3',
        artist: mainArtist,
        albumArtist: mainArtist,
        album: 'Project (EP)',
      );
      final ep3 = makeTrack(
        path: '/ep3.mp3',
        artist: mainArtist,
        albumArtist: mainArtist,
        album: 'Soundtrack EP',
      );

      final map = ReleaseKindClassifier.classifyTracks(
        artistName: mainArtist,
        tracks: [single1, single2, ep1, ep2, ep3],
      );

      expect(map[ReleaseCategory.singles]?.length, equals(2));
      expect(map[ReleaseCategory.eps]?.length, equals(3));
    });

    test('Rule 4: Owned track count & duration heuristic', () {
      // 1 to 3 tracks and under 20 mins -> Singles
      final shortAlbumTracks = [
        makeTrack(
          path: '/t1.mp3',
          artist: mainArtist,
          album: 'Short Release',
          durationMs: 300000,
        ),
        makeTrack(
          path: '/t2.mp3',
          artist: mainArtist,
          album: 'Short Release',
          durationMs: 300000,
        ),
      ];

      // 1 to 3 tracks over 20 mins -> Albums
      final longSymphonyTracks = [
        makeTrack(
          path: '/s1.mp3',
          artist: mainArtist,
          album: 'Symphony No 1',
          durationMs: 1300000, // ~21.6 mins
        ),
      ];

      // 4 to 6 tracks -> EPs
      final epTracks = List.generate(
        5,
        (i) => makeTrack(
          path: '/ep$i.mp3',
          artist: mainArtist,
          album: 'Mini Release',
          durationMs: 180000,
        ),
      );

      // 7 or more tracks -> Albums
      final fullAlbumTracks = List.generate(
        8,
        (i) => makeTrack(
          path: '/alb$i.mp3',
          artist: mainArtist,
          album: 'Full Studio Album',
          durationMs: 180000,
        ),
      );

      final allTracks = [
        ...shortAlbumTracks,
        ...longSymphonyTracks,
        ...epTracks,
        ...fullAlbumTracks,
      ];

      final map = ReleaseKindClassifier.classifyTracks(
        artistName: mainArtist,
        tracks: allTracks,
      );

      expect(map[ReleaseCategory.singles]?.length, equals(2));
      expect(map[ReleaseCategory.eps]?.length, equals(5));
      expect(map[ReleaseCategory.albums]?.length, equals(9)); // 1 symphony + 8 full album
    });

    test('Rule 5: Tracks without an album count as Singles', () {
      final t1 = makeTrack(
        path: '/loose1.mp3',
        artist: mainArtist,
        album: null,
      );
      final t2 = makeTrack(
        path: '/loose2.mp3',
        artist: mainArtist,
        album: '   ',
      );

      final map = ReleaseKindClassifier.classifyTracks(
        artistName: mainArtist,
        tracks: [t1, t2],
      );

      expect(map[ReleaseCategory.singles]?.length, equals(2));
    });

    test('Ordering precedence: Rule 3 (title hint) precedes Rule 4 (count)', () {
      // 10 tracks but titled "Something - EP" -> EPs, not Albums
      final ep10Tracks = List.generate(
        10,
        (i) => makeTrack(
          path: '/track$i.mp3',
          artist: mainArtist,
          album: 'Huge Session - EP',
          durationMs: 180000,
        ),
      );

      final map = ReleaseKindClassifier.classifyTracks(
        artistName: mainArtist,
        tracks: ep10Tracks,
      );

      expect(map[ReleaseCategory.eps]?.length, equals(10));
      expect(map[ReleaseCategory.albums]?.isEmpty, isTrue);
    });
  });
}
