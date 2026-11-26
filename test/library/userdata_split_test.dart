import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/migrations.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/userdata_migrator.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';

void main() {
  group('S1: Split library.db and userdata.db', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('userdata_split_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('openFile creates separate library.db and userdata.db with isolated schemas',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final repo = SqliteLibraryRepository.openFile(libPath);

      final userDataFile = File(p.join(tempDir.path, 'userdata.db'));
      expect(File(libPath).existsSync(), isTrue);
      expect(userDataFile.existsSync(), isTrue);

      await repo.close();

      final libOnly = sqlite3.open(libPath);
      final libTables = libOnly
          .select("SELECT name FROM sqlite_master WHERE type = 'table';")
          .map((r) => r['name'] as String)
          .toSet();
      expect(libTables, containsAll(['folders', 'tracks', 'track_artists']));
      for (final userTable in kUserDataTables) {
        expect(libTables.contains(userTable), isFalse);
      }
      expect(
        libOnly.select('PRAGMA user_version;').first.values.first,
        equals(kLibrarySchemaVersion),
      );
      libOnly.close();

      final userOnly = sqlite3.open(userDataFile.path);
      final userTables = userOnly
          .select("SELECT name FROM sqlite_master WHERE type = 'table';")
          .map((r) => r['name'] as String)
          .toSet();
      expect(userTables, containsAll(['meta', ...kUserDataTables]));
      expect(userTables.contains('folders'), isFalse);
      expect(userTables.contains('tracks'), isFalse);
      expect(userTables.contains('track_artists'), isFalse);
      expect(
        userOnly.select('PRAGMA user_version;').first.values.first,
        equals(kUserDataSchemaVersion),
      );
      userOnly.close();
    });

    test('all factories (inMemory, openFile, fromDatabase, openDefault) work with split schema',
        () async {
      // 1. inMemory
      final memRepo = SqliteLibraryRepository.inMemory();
      await memRepo.setFavorite('C:\\song.mp3', true);
      expect(await memRepo.favoritePaths(), contains('C:\\song.mp3'));
      await memRepo.close();

      // 2. fromDatabase
      final raw = sqlite3.openInMemory();
      final fromDbRepo = SqliteLibraryRepository.fromDatabase(raw);
      await fromDbRepo.setRating('C:\\song.mp3', 4);
      expect(await fromDbRepo.allRatings(), equals({'C:\\song.mp3': 4}));
      await fromDbRepo.close();

      // 3. openDefault with injected supportDir
      final supportRepo = await SqliteLibraryRepository.openDefault(
        supportDir: tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'Aestheticy', 'library.db')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(tempDir.path, 'Aestheticy', 'userdata.db')).existsSync(),
        isTrue,
      );
      await supportRepo.createPlaylist('Default Mix');
      expect(
        (await supportRepo.listPlaylists()).map((pl) => pl.name),
        contains('Default Mix'),
      );
      await supportRepo.close();
    });

    test('rebuildArtistLinks reads aliases and no-split rules from userdata',
        () async {
      final repo = SqliteLibraryRepository.inMemory();
      final folder = await repo.addFolder('C:\\Music');
      await repo.upsertTracks([
        Track(
          path: 'C:\\Music\\a.mp3',
          folderId: folder.id!,
          title: 'Track A',
          artist: 'Fayrouz',
          durationMs: 120000,
          mtimeMs: 1000,
          sizeBytes: 100,
          addedAt: DateTime.utc(2026, 1, 1),
        ),
        Track(
          path: 'C:\\Music\\b.mp3',
          folderId: folder.id!,
          title: 'Track B',
          artist: 'Simon & Garfunkel',
          durationMs: 120000,
          mtimeMs: 1000,
          sizeBytes: 100,
          addedAt: DateTime.utc(2026, 1, 1),
        ),
        Track(
          path: 'C:\\Music\\c.mp3',
          folderId: folder.id!,
          title: 'Track C',
          artist: 'Simon',
          durationMs: 120000,
          mtimeMs: 1000,
          sizeBytes: 100,
          addedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);

      await repo.mergeArtists('fayrouz', 'fairouz', targetName: 'Fairouz');
      await repo.addNoSplit('Simon & Garfunkel');

      // Explicitly reset and rebuild track_artists from userdata rules.
      repo.rawDatabase.execute('DELETE FROM main.track_artists;');
      await repo.rebuildArtistLinks();

      final artists = await repo.listArtists();
      final names = artists.map((a) => a.name).toSet();
      expect(names, contains('Fairouz'));
      expect(names, contains('Simon & Garfunkel'));
      expect(names, contains('Simon'));
      expect(names, isNot(contains('Garfunkel')));

      await repo.close();
    });

    test('resetting library or removing folder preserves all userdata and rescanning resolves everything again',
        () async {
      final libPath = p.join(tempDir.path, 'library.db');
      final repo = SqliteLibraryRepository.openFile(libPath);

      final folder = await repo.addFolder('C:\\Music');
      final track1 = Track(
        path: 'C:\\Music\\song1.flac',
        folderId: folder.id!,
        title: 'Song One',
        artist: 'Fairouz',
        album: 'Morning',
        durationMs: 180000,
        mtimeMs: 1000,
        sizeBytes: 4096,
        addedAt: DateTime.utc(2026, 1, 1),
      );
      final track2 = Track(
        path: 'C:\\Music\\song2.flac',
        folderId: folder.id!,
        title: 'Song Two',
        artist: 'Simon & Garfunkel',
        album: 'Bridge',
        durationMs: 210000,
        mtimeMs: 1000,
        sizeBytes: 4096,
        addedAt: DateTime.utc(2026, 1, 1),
      );
      await repo.upsertTracks([track1, track2]);
      await repo.rebuildArtistLinks();

      // Seed all kinds of user data.
      await repo.setFavorite(track1.path, true);
      await repo.setRating(track1.path, 5);
      final playlist = await repo.createPlaylist('Favorites Mix');
      await repo.addToPlaylist(playlist.id, [track1.path, track2.path]);
      await repo.insertPlayEvent(
        PlayEvent(
          uri: track1.path,
          title: track1.title,
          artist: track1.artist,
          album: track1.album,
          durationMs: track1.durationMs,
          startedAt: DateTime.utc(2026, 2, 1),
          listenedMs: 120000,
          counted: true,
          completed: true,
        ),
      );
      await repo.mergeArtists('fayrouz', 'fairouz', targetName: 'Fairouz');
      await repo.addNoSplit('Simon & Garfunkel');

      // Remove folder and reset library completely.
      await repo.removeFolder(folder.id!);
      await repo.resetLibrary();

      expect(await repo.trackCount(), equals(0));
      expect(await repo.listFolders(), isEmpty);

      // User data must remain completely intact!
      expect(await repo.favoritePaths(), equals({track1.path}));
      expect(await repo.allRatings(), equals({track1.path: 5}));
      expect((await repo.listPlaylists()).single.trackCount, equals(2));
      expect(await repo.playEventCount(), equals(1));
      expect((await repo.listAliases()).single.aliasKey, equals('fayrouz'));
      expect(
        (await repo.listNoSplit()).single.artistName,
        equals('Simon & Garfunkel'),
      );
      // Resolved track queries skip missing tracks gracefully.
      expect(await repo.favoriteTracks(), isEmpty);
      expect(await repo.recentlyPlayedTracks(), isEmpty);

      // Rescanning re-adds the folder and tracks -> everything resolves again!
      final newFolder = await repo.addFolder('C:\\Music');
      await repo.upsertTracks([
        track1.copyWith(folderId: newFolder.id),
        track2.copyWith(folderId: newFolder.id),
      ]);
      await repo.rebuildArtistLinks();

      final favTracks = await repo.favoriteTracks();
      expect(favTracks, hasLength(1));
      expect(favTracks.single.path, equals(track1.path));

      final recent = await repo.recentlyPlayedTracks();
      expect(recent, hasLength(1));
      expect(recent.single.path, equals(track1.path));

      final entries = await repo.playlistEntries(playlist.id);
      expect(entries, hasLength(2));
      expect(entries[0].track?.path, equals(track1.path));
      expect(entries[1].track?.path, equals(track2.path));

      final artists = await repo.listArtists();
      expect(
        artists.map((a) => a.name),
        containsAll(['Fairouz', 'Simon & Garfunkel']),
      );

      await repo.close();
    });
  });
}
