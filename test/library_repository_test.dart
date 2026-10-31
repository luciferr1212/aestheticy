import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/migrations.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/library/track_audio_source_mapper.dart';

void main() {
  group('SqliteLibraryRepository', () {
    late SqliteLibraryRepository repo;

    setUp(() {
      repo = SqliteLibraryRepository.inMemory();
    });

    tearDown(() async {
      await repo.close();
    });

    test('migration from empty DB sets user_version to 1 and creates schema',
        () {
      final rawDb = sqlite3.openInMemory();
      SchemaMigrator.apply(rawDb);

      final versionResult = rawDb.select('PRAGMA user_version;');
      expect(versionResult.first.values.first, 1);

      // Verify tables exist
      final tables = rawDb
          .select("SELECT name FROM sqlite_master WHERE type = 'table';")
          .map((r) => r['name'] as String)
          .toSet();
      expect(tables.contains('folders'), isTrue);
      expect(tables.contains('tracks'), isTrue);

      // Verify indexes exist
      final indexes = rawDb
          .select("SELECT name FROM sqlite_master WHERE type = 'index';")
          .map((r) => r['name'] as String)
          .toSet();
      expect(indexes.contains('idx_tracks_folder_id'), isTrue);
      expect(indexes.contains('idx_tracks_album'), isTrue);
      expect(indexes.contains('idx_tracks_artist'), isTrue);
      expect(indexes.contains('idx_tracks_search_text'), isTrue);

      rawDb.close();
    });

    test('addFolder and listFolders manage folders correctly', () async {
      final f1 = await repo.addFolder('C:\\Music\\Rock');
      expect(f1.id, isNotNull);
      expect(f1.path, 'C:\\Music\\Rock');

      // Adding the same folder returns existing folder without duplicating
      final f1Dup = await repo.addFolder('C:\\Music\\Rock');
      expect(f1Dup.id, f1.id);

      await repo.addFolder('C:\\Music\\Jazz');
      final list = await repo.listFolders();
      expect(list.length, 2);
      expect(list.map((f) => f.path).toList(), [
        'C:\\Music\\Jazz',
        'C:\\Music\\Rock',
      ]);
    });

    test('folder removal cascades to delete all its tracks', () async {
      final folder = await repo.addFolder('C:\\Music\\Deletable');
      final now = DateTime.now();

      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\Deletable\\song1.mp3',
          folderId: folder.id!,
          title: 'Song 1',
          durationMs: 120000,
          mtimeMs: 1000,
          sizeBytes: 2048,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\Deletable\\song2.mp3',
          folderId: folder.id!,
          title: 'Song 2',
          durationMs: 180000,
          mtimeMs: 1000,
          sizeBytes: 4096,
          addedAt: now,
        ),
      ]);

      expect(await repo.trackCount(), 2);

      await repo.removeFolder(folder.id!);

      expect(await repo.listFolders(), isEmpty);
      expect(await repo.trackCount(), 0);
    });

    test('upsertTracks insert + update in one transaction with unique path',
        () async {
      final folder = await repo.addFolder('C:\\Music');
      final initialAddedAt = DateTime.utc(2026, 1, 1, 12, 0, 0);

      final track1 = Track(
        path: 'C:\\Music\\track1.flac',
        folderId: folder.id!,
        title: 'Original Title',
        artist: 'Original Artist',
        album: 'Original Album',
        durationMs: 200000,
        mtimeMs: 1000,
        sizeBytes: 5000000,
        addedAt: initialAddedAt,
      );

      // 1. Initial insert
      await repo.upsertTracks([track1]);
      expect(await repo.trackCount(), 1);

      var tracks = await repo.listTracks();
      expect(tracks.first.title, 'Original Title');
      expect(tracks.first.addedAt, initialAddedAt);

      // 2. Update with modified tags and later addedAt
      final updatedTrack = track1.copyWith(
        title: 'Updated Title',
        artist: 'New Artist',
        durationMs: 205000,
        mtimeMs: 2000,
        addedAt: DateTime.utc(2026, 5, 1, 15, 30, 0),
      );

      await repo.upsertTracks([updatedTrack]);

      // Count is still 1 due to unique path conflict resolution
      expect(await repo.trackCount(), 1);

      tracks = await repo.listTracks();
      final saved = tracks.first;
      expect(saved.title, 'Updated Title');
      expect(saved.artist, 'New Artist');
      expect(saved.durationMs, 205000);
      expect(saved.mtimeMs, 2000);
      // Verify original addedAt is preserved across updates
      expect(saved.addedAt, initialAddedAt);
    });

    test('existingFiles returns map of mtimeMs and sizeBytes', () async {
      final folder = await repo.addFolder('C:\\Music');
      final now = DateTime.now();

      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\a.mp3',
          folderId: folder.id!,
          durationMs: 100,
          mtimeMs: 123456,
          sizeBytes: 7890,
          addedAt: now,
        ),
      ]);

      final files = await repo.existingFiles(folder.id!);
      expect(files.containsKey('C:\\Music\\a.mp3'), isTrue);
      expect(files['C:\\Music\\a.mp3']?.mtimeMs, 123456);
      expect(files['C:\\Music\\a.mp3']?.sizeBytes, 7890);
    });

    test('removeTracksByPath removes matching records', () async {
      final folder = await repo.addFolder('C:\\Music');
      final now = DateTime.now();

      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\keep.mp3',
          folderId: folder.id!,
          title: 'Keep',
          durationMs: 100,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\drop.mp3',
          folderId: folder.id!,
          title: 'Drop',
          durationMs: 100,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
      ]);

      expect(await repo.trackCount(), 2);

      await repo.removeTracksByPath(['C:\\Music\\drop.mp3']);

      expect(await repo.trackCount(), 1);
      final remaining = await repo.listTracks();
      expect(remaining.first.path, 'C:\\Music\\keep.mp3');
    });

    test('derived albums and artists grouping', () async {
      final folder = await repo.addFolder('C:\\Music');
      final now = DateTime.now();

      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\1.mp3',
          folderId: folder.id!,
          title: 'Intro',
          artist: 'Radiohead',
          albumArtist: 'Radiohead',
          album: 'Kid A',
          trackNo: 1,
          discNo: 1,
          year: 2000,
          durationMs: 180000,
          mtimeMs: 10,
          sizeBytes: 10,
          coverKey: 'art-kid-a',
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\2.mp3',
          folderId: folder.id!,
          title: 'Idioteque',
          artist: 'Radiohead',
          albumArtist: 'Radiohead',
          album: 'Kid A',
          trackNo: 8,
          discNo: 1,
          year: 2000,
          durationMs: 300000,
          mtimeMs: 10,
          sizeBytes: 10,
          coverKey: 'art-kid-a',
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\3.mp3',
          folderId: folder.id!,
          title: '15 Step',
          artist: 'Radiohead',
          albumArtist: 'Radiohead',
          album: 'In Rainbows',
          trackNo: 1,
          discNo: 1,
          year: 2007,
          durationMs: 240000,
          mtimeMs: 10,
          sizeBytes: 10,
          coverKey: 'art-in-rainbows',
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\4.mp3',
          folderId: folder.id!,
          title: 'Starman',
          artist: 'David Bowie',
          albumArtist: 'David Bowie',
          album: 'Ziggy Stardust',
          trackNo: 4,
          discNo: 1,
          year: 1972,
          durationMs: 250000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
      ]);

      // Albums query
      expect(await repo.albumCount(), 3);
      final albums = await repo.listAlbums();
      expect(albums.length, 3);
      final kidA = albums.firstWhere((a) => a.album == 'Kid A');
      expect(kidA.trackCount, 2);
      expect(kidA.albumArtist, 'Radiohead');
      expect(kidA.year, 2000);
      expect(kidA.coverKey, 'art-kid-a');

      // Artists query
      expect(await repo.artistCount(), 2);
      final artists = await repo.listArtists();
      expect(artists.length, 2);
      final radiohead = artists.firstWhere((a) => a.name == 'Radiohead');
      expect(radiohead.albumCount, 2);
      expect(radiohead.trackCount, 3);

      final bowie = artists.firstWhere((a) => a.name == 'David Bowie');
      expect(bowie.albumCount, 1);
      expect(bowie.trackCount, 1);

      // tracksOfAlbum order check
      final kidATracks = await repo.tracksOfAlbum('Kid A');
      expect(kidATracks.map((t) => t.trackNo).toList(), [1, 8]);

      // tracksOfArtist check
      final bowieTracks = await repo.tracksOfArtist('David Bowie');
      expect(bowieTracks.length, 1);
      expect(bowieTracks.first.title, 'Starman');
    });

    test('search handles Arabic diacritics, letter variants, and accents',
        () async {
      final folder = await repo.addFolder('C:\\Music');
      final now = DateTime.now();

      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\amr.mp3',
          folderId: folder.id!,
          title: 'أغْنِيَةٌ حُبّْ',
          artist: 'عَمْرُو دِيَاب',
          album: 'مَكَانَك',
          durationMs: 210000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\fairuz.mp3',
          folderId: folder.id!,
          title: 'نَسَمْ عَلَيْنَا الْهَوَى',
          artist: 'فَيْرُوز',
          album: 'أغَانِي الصَّبَاح',
          durationMs: 250000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\cafe.mp3',
          folderId: folder.id!,
          title: 'Café Del Mar (Chilled Chillout Mix)',
          artist: 'José Padilla',
          album: 'Ibiza Clásicos',
          durationMs: 360000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
      ]);

      // 1. Search Arabic without Tashkeel
      var results = await repo.search('اغنية حب');
      expect(results.length, 1);
      expect(results.first.path, 'C:\\Music\\amr.mp3');

      // 2. Search Arabic with alternate Alef / Taa Marbuta
      results = await repo.search('مكانك');
      expect(results.length, 1);
      expect(results.first.artist, 'عَمْرُو دِيَاب');

      results = await repo.search('فيروز');
      expect(results.length, 1);
      expect(results.first.title, 'نَسَمْ عَلَيْنَا الْهَوَى');

      // 3. Search Latin with accents stripped
      results = await repo.search('cafe del mar');
      expect(results.length, 1);
      expect(results.first.path, 'C:\\Music\\cafe.mp3');

      // 4. Search Latin artist with accent stripped
      results = await repo.search('Jose Padilla');
      expect(results.length, 1);
      expect(results.first.path, 'C:\\Music\\cafe.mp3');

      // 5. Empty query returns empty list
      expect(await repo.search(''), isEmpty);
      expect(await repo.search('   '), isEmpty);
    });

    test('pagination and sorting work as expected', () async {
      final folder = await repo.addFolder('C:\\Music');

      final tracks = List.generate(10, (i) {
        final char = String.fromCharCode(65 + i); // A, B, C...
        return Track(
          path: 'C:\\Music\\$char.mp3',
          folderId: folder.id!,
          title: 'Track $char',
          durationMs: 100000 + i * 1000,
          mtimeMs: 1000 + i,
          sizeBytes: 1000 + i,
          addedAt: DateTime.utc(2026, 1, 1 + i),
        );
      });

      await repo.upsertTracks(tracks);
      expect(await repo.trackCount(), 10);

      // Page 1 (limit 3, offset 0)
      final p1 = await repo.listTracks(
        sort: TrackSort.titleAsc,
        limit: 3,
        offset: 0,
      );
      expect(p1.map((t) => t.title).toList(), [
        'Track A',
        'Track B',
        'Track C',
      ]);

      // Page 2 (limit 3, offset 3)
      final p2 = await repo.listTracks(
        sort: TrackSort.titleAsc,
        limit: 3,
        offset: 3,
      );
      expect(p2.map((t) => t.title).toList(), [
        'Track D',
        'Track E',
        'Track F',
      ]);

      // Sort title descending
      final desc = await repo.listTracks(
        sort: TrackSort.titleDesc,
        limit: 2,
      );
      expect(desc.map((t) => t.title).toList(), ['Track J', 'Track I']);

      // Sort addedAt descending
      final newest = await repo.listTracks(
        sort: TrackSort.addedAtDesc,
        limit: 2,
      );
      expect(newest.map((t) => t.title).toList(), ['Track J', 'Track I']);
    });

    test('TrackAudioSourceMapper maps Track to AudioSource', () {
      final track = Track(
        path: 'C:\\Music\\song.flac',
        folderId: 1,
        title: 'Song Title',
        artist: 'Artist Name',
        albumArtist: 'Band Name',
        album: 'Album Name',
        trackNo: 3,
        discNo: 1,
        year: 2024,
        durationMs: 240000,
        mtimeMs: 5000,
        sizeBytes: 1234567,
        coverKey: 'cover-123',
        addedAt: DateTime.utc(2026, 1, 1),
      );

      final source = track.toAudioSource();
      expect(source.uri, 'C:\\Music\\song.flac');
      expect(source.extras?['title'], 'Song Title');
      expect(source.extras?['artist'], 'Artist Name');
      expect(source.extras?['album'], 'Album Name');
      expect(source.extras?['albumArtist'], 'Band Name');
      expect(source.extras?['trackNo'], '3');
      expect(source.extras?['discNo'], '1');
      expect(source.extras?['year'], '2024');
      expect(source.extras?['coverKey'], 'cover-123');
      expect(source.extras?['durationMs'], '240000');
    });
  });
}
