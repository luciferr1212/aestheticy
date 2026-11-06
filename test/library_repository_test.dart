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

    test('migration from empty DB sets user_version to current version and creates schema',
        () {
      final rawDb = sqlite3.openInMemory();
      SchemaMigrator.apply(rawDb);

      final versionResult = rawDb.select('PRAGMA user_version;');
      expect(versionResult.first.values.first, 4);

      // Verify tables exist
      final tables = rawDb
          .select("SELECT name FROM sqlite_master WHERE type = 'table';")
          .map((r) => r['name'] as String)
          .toSet();
      expect(tables.contains('folders'), isTrue);
      expect(tables.contains('tracks'), isTrue);
      expect(tables.contains('track_artists'), isTrue);
      expect(tables.contains('play_events'), isTrue);
      expect(tables.contains('artist_aliases'), isTrue);
      expect(tables.contains('artist_no_split'), isTrue);

      // Verify indexes exist
      final indexes = rawDb
          .select("SELECT name FROM sqlite_master WHERE type = 'index';")
          .map((r) => r['name'] as String)
          .toSet();
      expect(indexes.contains('idx_tracks_folder_id'), isTrue);
      expect(indexes.contains('idx_tracks_album'), isTrue);
      expect(indexes.contains('idx_tracks_artist'), isTrue);
      expect(indexes.contains('idx_tracks_search_text'), isTrue);
      expect(indexes.contains('idx_track_artists_artist_key'), isTrue);

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

    test('markFolderScanned updates last_scan_at', () async {
      final folder = await repo.addFolder('C:\\Music\\ScanTest');
      expect(folder.lastScanAt, isNull);

      final scanTime = DateTime.utc(2026, 10, 31, 12, 0, 0);
      await repo.markFolderScanned(folder.id!, scanTime);

      final folders = await repo.listFolders();
      final updated = folders.firstWhere((f) => f.id == folder.id);
      expect(updated.lastScanAt, scanTime);
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
      await repo.rebuildArtistLinks();

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
      await repo.rebuildArtistLinks();

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
      await repo.rebuildArtistLinks();

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
      expect(await repo.searchAlbums(''), isEmpty);
      expect(await repo.searchArtists(''), isEmpty);

      // 6. searchAlbums and searchArtists with Arabic query with diacritics
      final albumResults = await repo.searchAlbums('أَغَانِي');
      expect(albumResults.length, 1);
      expect(albumResults.first.album, 'أغَانِي الصَّبَاح');

      final artistResults = await repo.searchArtists('فَيْرُوزْ');
      expect(artistResults.length, 1);
      expect(artistResults.first.name, 'فَيْرُوز');

      // 7. Search tracks, albums, and artists with literal '%' query
      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\percent1.mp3',
          folderId: folder.id!,
          title: '100% Hits',
          artist: 'Percent Band 100%',
          album: 'Discount 50% Off',
          durationMs: 120000,
          mtimeMs: 20,
          sizeBytes: 20,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\percent2.mp3',
          folderId: folder.id!,
          title: '1000 Hits',
          artist: 'Percent Band 1000',
          album: 'Discount 500 Off',
          durationMs: 120000,
          mtimeMs: 20,
          sizeBytes: 20,
          addedAt: now,
        ),
      ]);
      await repo.rebuildArtistLinks();

      final trackPercentResults = await repo.search('100%');
      expect(trackPercentResults.length, 1);
      expect(trackPercentResults.first.path, 'C:\\Music\\percent1.mp3');

      final albumPercentResults = await repo.searchAlbums('50%');
      expect(albumPercentResults.length, 1);
      expect(albumPercentResults.first.album, 'Discount 50% Off');

      final artistPercentResults = await repo.searchArtists('100%');
      expect(artistPercentResults.length, 1);
      expect(artistPercentResults.first.name, 'Percent Band 100%');
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

    test('migrating a v1 database that already has tracks populates track_artists', () {
      final rawDb = sqlite3.openInMemory();
      rawDb.execute('PRAGMA foreign_keys = ON;');

      // 1. Manually create v1 schema
      rawDb.execute('''
        CREATE TABLE folders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          path TEXT NOT NULL UNIQUE,
          last_scan_at INTEGER
        );
        CREATE TABLE tracks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          path TEXT NOT NULL UNIQUE,
          folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
          title TEXT,
          artist TEXT,
          album_artist TEXT,
          album TEXT,
          track_no INTEGER,
          disc_no INTEGER,
          year INTEGER,
          duration_ms INTEGER NOT NULL,
          mtime_ms INTEGER NOT NULL,
          size_bytes INTEGER NOT NULL,
          cover_key TEXT,
          added_at INTEGER NOT NULL,
          search_text TEXT NOT NULL
        );
        PRAGMA user_version = 1;
      ''');

      // 2. Insert v1 tracks
      rawDb.execute("INSERT INTO folders (path) VALUES ('C:\\\\Music');");
      rawDb.execute('''
        INSERT INTO tracks (path, folder_id, title, artist, album, duration_ms, mtime_ms, size_bytes, added_at, search_text)
        VALUES ('C:\\\\Music\\\\1.mp3', 1, 'Song 1', 'Fairouz', 'Album 1', 100, 10, 10, 1000, 'song 1 fairouz');
      ''');
      rawDb.execute('''
        INSERT INTO tracks (path, folder_id, title, artist, album, duration_ms, mtime_ms, size_bytes, added_at, search_text)
        VALUES ('C:\\\\Music\\\\2.mp3', 1, 'Duet', 'Fairouz; Ziad Rahbani', 'Album 2', 100, 10, 10, 1000, 'duet fairouz ziad');
      ''');

      // 3. Apply migration (migrates to current schema version 4)
      SchemaMigrator.apply(rawDb);

      expect(rawDb.select('PRAGMA user_version;').first.values.first, 4);

      // 4. Verify track_artists populated
      final rows = rawDb.select('SELECT track_id, artist_key, artist_name FROM track_artists ORDER BY track_id, artist_name;');
      expect(rows.length, 3);
      expect(rows[0]['track_id'], 1);
      expect(rows[0]['artist_name'], 'Fairouz');
      expect(rows[1]['track_id'], 2);
      expect(rows[1]['artist_name'], 'Fairouz');
      expect(rows[2]['track_id'], 2);
      expect(rows[2]['artist_name'], 'Ziad Rahbani');

      rawDb.close();
    });

    test('duet: Amr Diab, Mohamed Mounir, Amr Diab and Mohamed Mounir appears under both, no combined entry', () async {
      final folder = await repo.addFolder('C:\\Music\\Arabic');
      final now = DateTime.now();

      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\amr.mp3',
          folderId: folder.id!,
          title: 'Tamally Maak',
          artist: 'عمرو دياب',
          album: 'Tamally Maak',
          durationMs: 200000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\mounir.mp3',
          folderId: folder.id!,
          title: 'El Leila Ya Samra',
          artist: 'محمد منير',
          album: 'El Leila',
          durationMs: 200000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\duet.mp3',
          folderId: folder.id!,
          title: 'Al Qahira',
          artist: 'عمرو دياب اند مُحَمَّدْ مُنير',
          album: 'Singles',
          durationMs: 220000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
      ]);
      await repo.rebuildArtistLinks();

      expect(await repo.artistCount(), 2);
      final artists = await repo.listArtists();
      expect(artists.length, 2);
      expect(artists.map((a) => a.name).toSet(), {'عمرو دياب', 'محمد منير'});

      // Duet appears under Amr Diab
      final amrTracks = await repo.tracksOfArtist('عمرو دياب');
      expect(amrTracks.length, 2);
      expect(amrTracks.map((t) => t.title).toSet(), {'Tamally Maak', 'Al Qahira'});

      // Duet appears under Mohamed Mounir
      final mounirTracks = await repo.tracksOfArtist('محمد منير');
      expect(mounirTracks.length, 2);
      expect(mounirTracks.map((t) => t.title).toSet(), {'El Leila Ya Samra', 'Al Qahira'});

      // Track retains its original artist tag for display
      final duetTrack = amrTracks.firstWhere((t) => t.title == 'Al Qahira');
      expect(duetTrack.artist, 'عمرو دياب اند مُحَمَّدْ مُنير');
    });

    test('fairouz, fairouz and kaza kaza (kaza kaza never alone) => two artists, duet under both', () async {
      final folder = await repo.addFolder('C:\\Music\\Fairouz');
      final now = DateTime.now();

      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\f1.mp3',
          folderId: folder.id!,
          title: 'Kifak Inta',
          artist: 'fairouz',
          album: 'Album 1',
          durationMs: 180000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\f2.mp3',
          folderId: folder.id!,
          title: 'Duet Song',
          artist: 'fairouz and kaza kaza',
          album: 'Album 2',
          durationMs: 200000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
      ]);
      await repo.rebuildArtistLinks();

      expect(await repo.artistCount(), 2);
      final artists = await repo.listArtists();
      expect(artists.map((a) => a.name).toSet(), {'fairouz', 'kaza kaza'});

      final fairouzTracks = await repo.tracksOfArtist('fairouz');
      expect(fairouzTracks.length, 2);

      final kazaTracks = await repo.tracksOfArtist('kaza kaza');
      expect(kazaTracks.length, 1);
      expect(kazaTracks.first.title, 'Duet Song');
    });

    test('Simon & Garfunkel alone stays one', () async {
      final folder = await repo.addFolder('C:\\Music\\Folk');
      final now = DateTime.now();

      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\sg.mp3',
          folderId: folder.id!,
          title: 'The Sound of Silence',
          artist: 'Simon & Garfunkel',
          album: 'Wednesday Morning, 3 A.M.',
          durationMs: 185000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
      ]);
      await repo.rebuildArtistLinks();

      expect(await repo.artistCount(), 1);
      final artists = await repo.listArtists();
      expect(artists.first.name, 'Simon & Garfunkel');
    });

    test('A feat. B always splits', () async {
      final folder = await repo.addFolder('C:\\Music\\Collab');
      final now = DateTime.now();

      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\collab.mp3',
          folderId: folder.id!,
          title: 'Collab Song',
          artist: 'Artist Alpha feat. Artist Beta',
          album: 'Collab Album',
          durationMs: 210000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
      ]);
      await repo.rebuildArtistLinks();

      expect(await repo.artistCount(), 2);
      final artists = await repo.listArtists();
      expect(artists.map((a) => a.name).toSet(), {'Artist Alpha', 'Artist Beta'});
    });

    test('Merge فيروز into fairouz => one entry, tracks from both, survives rescan, unmerge restores', () async {
      final folder = await repo.addFolder('C:\\Music\\FMerge');
      final now = DateTime.now();

      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\ar.mp3',
          folderId: folder.id!,
          title: 'Habaytak',
          artist: 'فيروز',
          album: 'Album A',
          durationMs: 180000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\en.mp3',
          folderId: folder.id!,
          title: 'Li Beirut',
          artist: 'fairouz',
          album: 'Album B',
          durationMs: 190000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
      ]);
      await repo.rebuildArtistLinks();

      expect(await repo.artistCount(), 2);

      // Merge Arabic spelling into English spelling
      final artistsBefore = await repo.listArtists();
      final arArtist = artistsBefore.firstWhere((a) => a.name == 'فيروز');
      final enArtist = artistsBefore.firstWhere((a) => a.name == 'fairouz');

      await repo.mergeArtists(arArtist.key, enArtist.key);

      expect(await repo.artistCount(), 1);
      final artistsAfterMerge = await repo.listArtists();
      expect(artistsAfterMerge.length, 1);
      expect(artistsAfterMerge.first.trackCount, 2);

      final combinedTracks = await repo.tracksOfArtist('fairouz');
      expect(combinedTracks.length, 2);

      // Survives a rebuild / rescan
      await repo.rebuildArtistLinks();
      expect(await repo.artistCount(), 1);

      // Unmerge restores
      await repo.unmergeArtist(arArtist.key);
      expect(await repo.artistCount(), 2);
      final restored = await repo.listArtists();
      expect(restored.length, 2);
    });

    test('No-split keeps X and Y whole', () async {
      final folder = await repo.addFolder('C:\\Music\\NoSplit');
      final now = DateTime.now();

      // First add standalone X so normally "X and Y" would split
      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\x.mp3',
          folderId: folder.id!,
          title: 'Solo X',
          artist: 'Artist X',
          album: 'Album X',
          durationMs: 120000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
        Track(
          path: 'C:\\Music\\xy.mp3',
          folderId: folder.id!,
          title: 'Band XY',
          artist: 'Artist X and Artist Y',
          album: 'Album XY',
          durationMs: 150000,
          mtimeMs: 10,
          sizeBytes: 10,
          addedAt: now,
        ),
      ]);
      await repo.rebuildArtistLinks();

      // Before no-split: splits into Artist X and Artist Y
      expect(await repo.artistCount(), 2);

      // Add no-split rule for 'Artist X and Artist Y'
      await repo.addNoSplit('Artist X and Artist Y');

      // Now "Artist X and Artist Y" stays whole as its own artist
      expect(await repo.artistCount(), 2);
      final artists = await repo.listArtists();
      expect(artists.map((a) => a.name).toSet(), {'Artist X', 'Artist X and Artist Y'});

      // Remove no-split
      final noSplits = await repo.listNoSplit();
      expect(noSplits.length, 1);
      await repo.removeNoSplit(noSplits.first.artistKey);

      // After removal, splits again into Artist X and Artist Y
      final artistsRestored = await repo.listArtists();
      expect(artistsRestored.map((a) => a.name).toSet(), {'Artist X', 'Artist Y'});
    });

    test('Chain merging resolves to root canonical and cycles are rejected', () async {
      final folder = await repo.addFolder('C:\\Music\\Chains');
      final now = DateTime.now();

      await repo.upsertTracks([
        Track(path: 'C:\\Music\\a.mp3', folderId: folder.id!, title: 'A', artist: 'Artist AAA', album: 'Alb', durationMs: 100, mtimeMs: 1, sizeBytes: 1, addedAt: now),
        Track(path: 'C:\\Music\\b.mp3', folderId: folder.id!, title: 'B', artist: 'Artist BBB', album: 'Alb', durationMs: 100, mtimeMs: 1, sizeBytes: 1, addedAt: now),
        Track(path: 'C:\\Music\\c.mp3', folderId: folder.id!, title: 'C', artist: 'Artist CCC', album: 'Alb', durationMs: 100, mtimeMs: 1, sizeBytes: 1, addedAt: now),
      ]);
      await repo.rebuildArtistLinks();

      final artists = await repo.listArtists();
      final aKey = artists.firstWhere((x) => x.name == 'Artist AAA').key;
      final bKey = artists.firstWhere((x) => x.name == 'Artist BBB').key;
      final cKey = artists.firstWhere((x) => x.name == 'Artist CCC').key;

      // Merge A -> B
      await repo.mergeArtists(aKey, bKey);
      expect(await repo.artistCount(), 2);

      // Merge B -> C (A should also resolve to C)
      await repo.mergeArtists(bKey, cKey);
      expect(await repo.artistCount(), 1);

      final aliases = await repo.listAliases();
      expect(aliases.length, 2);
      for (final alias in aliases) {
        expect(alias.canonicalKey, cKey);
      }

      // Reject self merge
      expect(() => repo.mergeArtists(cKey, cKey), throwsArgumentError);

      // Reject cycle: merging C -> A
      expect(() => repo.mergeArtists(cKey, aKey), throwsArgumentError);
    });

    test('Deleting a track or folder leaves no orphan rows in track_artists', () async {
      final folder = await repo.addFolder('C:\\Music\\Orphans');
      final now = DateTime.now();

      await repo.upsertTracks([
        Track(path: 'C:\\Music\\o1.mp3', folderId: folder.id!, title: 'O1', artist: 'Orphan Artist 1', album: 'Alb', durationMs: 100, mtimeMs: 1, sizeBytes: 1, addedAt: now),
        Track(path: 'C:\\Music\\o2.mp3', folderId: folder.id!, title: 'O2', artist: 'Orphan Artist 2', album: 'Alb', durationMs: 100, mtimeMs: 1, sizeBytes: 1, addedAt: now),
      ]);
      await repo.rebuildArtistLinks();

      expect(await repo.artistCount(), 2);

      // Delete one track
      await repo.removeTracksByPath(['C:\\Music\\o1.mp3']);
      expect(await repo.artistCount(), 1);

      // Delete folder
      await repo.removeFolder(folder.id!);
      expect(await repo.artistCount(), 0);
    });

    test('merge Fairouz (more tracks) into فيروز => list shows فيروز; after unmerge it goes back', () async {
      final folder = await repo.addFolder('C:\\Music\\DisplayNameTest');
      final now = DateTime.now();

      // 5 tracks with 'Fairouz'
      final fairouzTracks = List.generate(5, (i) => Track(
        path: 'C:\\Music\\en_$i.mp3',
        folderId: folder.id!,
        title: 'Song $i',
        artist: 'Fairouz',
        durationMs: 100,
        mtimeMs: 1,
        sizeBytes: 1,
        addedAt: now,
      ));

      // 1 track with 'فيروز'
      final arTrack = Track(
        path: 'C:\\Music\\ar_1.mp3',
        folderId: folder.id!,
        title: 'Arabic Song',
        artist: 'فيروز',
        durationMs: 100,
        mtimeMs: 1,
        sizeBytes: 1,
        addedAt: now,
      );

      await repo.upsertTracks([...fairouzTracks, arTrack]);
      await repo.rebuildArtistLinks();

      final before = await repo.listArtists();
      expect(before.length, 2);

      final fairouzKey = before.firstWhere((a) => a.name == 'Fairouz').key;
      final arKey = before.firstWhere((a) => a.name == 'فيروز').key;

      // Merge Fairouz (5 tracks) into فيروز (1 track)
      await repo.mergeArtists(fairouzKey, arKey, targetName: 'فيروز');

      final afterMerge = await repo.listArtists();
      expect(afterMerge.length, 1);
      // Must show 'فيروز' (canonical_name from artist_aliases), NOT 'Fairouz' (most frequent)
      expect(afterMerge.first.name, 'فيروز');
      expect(afterMerge.first.trackCount, 6);

      // Search also shows 'فيروز'
      final searchResults = await repo.searchArtists('fairouz');
      expect(searchResults.length, 1);
      expect(searchResults.first.name, 'فيروز');

      // Unmerge restores
      await repo.unmergeArtist(fairouzKey);
      final afterUnmerge = await repo.listArtists();
      expect(afterUnmerge.length, 2);
      expect(afterUnmerge.map((a) => a.name).toSet(), {'Fairouz', 'فيروز'});
    });

    test('Performance benchmark: 20,000 tracks with ~3,000 distinct artist strings', () async {
      final folder = await repo.addFolder('C:\\Music\\Bench');
      final now = DateTime.now();

      final batch = List.generate(20000, (i) {
        return Track(
          path: 'C:\\Music\\bench_$i.mp3',
          folderId: folder.id!,
          title: 'Track $i',
          artist: 'Artist ${i % 3000}; Featured ${i % 100}',
          album: 'Album ${i % 500}',
          durationMs: 180000,
          mtimeMs: 1000,
          sizeBytes: 2048,
          addedAt: now,
        );
      });

      await repo.upsertTracks(batch);

      final stopwatch = Stopwatch()..start();
      await repo.rebuildArtistLinks();
      stopwatch.stop();

      // ignore: avoid_print
      print('Real rebuild time for 20,000 tracks (~3,000 distinct artists): ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
    });
  });
}
