import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'fake_library_repository.dart';

void main() {
  group('S2 Repository API Tests', () {
    for (final repoType in ['SqliteLibraryRepository', 'FakeLibraryRepository']) {
      group(repoType, () {
        late LibraryRepository repo;

        setUp(() async {
          if (repoType == 'SqliteLibraryRepository') {
            repo = SqliteLibraryRepository.inMemory();
          } else {
            repo = FakeLibraryRepository();
          }
          await repo.addFolder('C:/Music');
        });

        tearDown(() async {
          await repo.close();
        });

        Track makeTrack(String path, {String? title, String? coverKey, int durationMs = 120000}) {
          return Track(
            path: path,
            folderId: 1,
            title: title ?? path,
            durationMs: durationMs,
            mtimeMs: 1000,
            sizeBytes: 5000,
            coverKey: coverKey,
            addedAt: DateTime.now().toUtc(),
          );
        }

        test('Favorites CRUD and ordering (newest first)', () async {
          await repo.upsertTracks([
            makeTrack('C:/track1.mp3', title: 'Track 1'),
            makeTrack('C:/track2.mp3', title: 'Track 2'),
            makeTrack('C:/track3.mp3', title: 'Track 3'),
          ]);

          expect(await repo.favoritePaths(), isEmpty);
          expect(await repo.favoriteTracks(), isEmpty);

          await repo.setFavorite('C:/track1.mp3', true);
          await Future<void>.delayed(const Duration(milliseconds: 2));
          await repo.setFavorite('C:/track2.mp3', true);

          final paths = await repo.favoritePaths();
          expect(paths, containsAll(['C:/track1.mp3', 'C:/track2.mp3']));
          expect(paths.length, equals(2));

          final tracks = await repo.favoriteTracks();
          expect(tracks.length, equals(2));
          expect(tracks[0].path, equals('C:/track2.mp3'));
          expect(tracks[1].path, equals('C:/track1.mp3'));

          await repo.setFavorite('C:/track2.mp3', false);
          final updatedTracks = await repo.favoriteTracks();
          expect(updatedTracks.length, equals(1));
          expect(updatedTracks.first.path, equals('C:/track1.mp3'));
        });

        test('Favorites survive removeTracksByPath and reappear after re-upsert', () async {
          await repo.upsertTracks([makeTrack('C:/survivor.mp3', title: 'Survivor')]);
          await repo.setFavorite('C:/survivor.mp3', true);

          expect((await repo.favoriteTracks()).length, equals(1));

          // Remove track from library
          await repo.removeTracksByPath(['C:/survivor.mp3']);

          // Favorite path is still kept
          expect(await repo.favoritePaths(), contains('C:/survivor.mp3'));
          // But favoriteTracks skips it because it is not in library
          expect(await repo.favoriteTracks(), isEmpty);

          // Re-upsert track
          await repo.upsertTracks([makeTrack('C:/survivor.mp3', title: 'Survivor Returns')]);

          // Reappears in favoriteTracks
          final favs = await repo.favoriteTracks();
          expect(favs.length, equals(1));
          expect(favs.first.title, equals('Survivor Returns'));
        });

        test('Ratings bounds: 1..5 valid, 0 clears, outside throws ArgumentError', () async {
          expect(await repo.allRatings(), isEmpty);

          await repo.setRating('C:/song.mp3', 4);
          expect((await repo.allRatings())['C:/song.mp3'], equals(4));

          await repo.setRating('C:/song.mp3', 5);
          expect((await repo.allRatings())['C:/song.mp3'], equals(5));

          await repo.setRating('C:/song.mp3', 0);
          expect((await repo.allRatings())['C:/song.mp3'], isNull);

          expect(() => repo.setRating('C:/song.mp3', -1), throwsArgumentError);
          expect(() => repo.setRating('C:/song.mp3', 6), throwsArgumentError);
        });

        test('Playlists creation and name validation rules', () async {
          // Empty or whitespace throws empty
          expect(
            () => repo.createPlaylist('   '),
            throwsA(isA<PlaylistNameException>().having((e) => e.error, 'error', PlaylistNameError.empty)),
          );

          // Too long (>60)
          final longName = 'A' * 61;
          expect(
            () => repo.createPlaylist(longName),
            throwsA(isA<PlaylistNameException>().having((e) => e.error, 'error', PlaylistNameError.tooLong)),
          );

          // Valid create
          final p1 = await repo.createPlaylist('Chill Vibes');
          expect(p1.name, equals('Chill Vibes'));
          expect(p1.trackCount, equals(0));

          // Duplicate case-insensitive
          expect(
            () => repo.createPlaylist('chill vibes'),
            throwsA(isA<PlaylistNameException>().having((e) => e.error, 'error', PlaylistNameError.duplicate)),
          );

          // Rename duplicate
          final p2 = await repo.createPlaylist('Workout');
          expect(
            () => repo.renamePlaylist(p2.id, 'CHILL VIBES'),
            throwsA(isA<PlaylistNameException>().having((e) => e.error, 'error', PlaylistNameError.duplicate)),
          );

          // Valid rename
          await repo.renamePlaylist(p2.id, 'Morning Cardio');
          final list = await repo.listPlaylists();
          expect(list.any((p) => p.name == 'Morning Cardio'), isTrue);
        });

        test('Playlist items: duplicates allowed, renumbering on delete, move up/down/ends', () async {
          await repo.upsertTracks([
            makeTrack('C:/1.mp3', title: 'Track 1', coverKey: 'cov1', durationMs: 60000),
            makeTrack('C:/2.mp3', title: 'Track 2', coverKey: 'cov2', durationMs: 40000),
          ]);

          final pl = await repo.createPlaylist('Mixed');

          // Append with duplicates
          final added = await repo.addToPlaylist(pl.id, [
            'C:/1.mp3',
            'C:/2.mp3',
            'C:/1.mp3', // duplicate
            'C:/missing.mp3', // not in library
          ]);
          expect(added, equals(4));

          var entries = await repo.playlistEntries(pl.id);
          expect(entries.length, equals(4));
          expect(entries[0].position, equals(0));
          expect(entries[0].track?.title, equals('Track 1'));
          expect(entries[1].position, equals(1));
          expect(entries[1].track?.title, equals('Track 2'));
          expect(entries[2].position, equals(2));
          expect(entries[2].track?.title, equals('Track 1'));
          expect(entries[3].position, equals(3));
          expect(entries[3].track, isNull); // missing track kept

          // Playlist summary aggregate
          final summaries = await repo.listPlaylists();
          final summary = summaries.firstWhere((s) => s.id == pl.id);
          expect(summary.trackCount, equals(4));
          expect(summary.totalDurationMs, equals(160000)); // 60k + 40k + 60k
          expect(summary.coverKey, equals('cov1'));

          // Move item: move index 0 to index 2
          final entry0Id = entries[0].entryId;
          await repo.movePlaylistEntry(pl.id, entry0Id, 2);

          entries = await repo.playlistEntries(pl.id);
          expect(entries.map((e) => e.path).toList(), equals([
            'C:/2.mp3',
            'C:/1.mp3', // old index 2
            'C:/1.mp3', // moved item now at index 2
            'C:/missing.mp3',
          ]));
          expect(entries.map((e) => e.position).toList(), equals([0, 1, 2, 3]));

          // Move to beginning
          final lastId = entries.last.entryId;
          await repo.movePlaylistEntry(pl.id, lastId, 0);
          entries = await repo.playlistEntries(pl.id);
          expect(entries.first.path, equals('C:/missing.mp3'));
          expect(entries.first.position, equals(0));

          // Remove entry and verify renumbering without gaps
          final removeId = entries[1].entryId; // 'C:/2.mp3'
          await repo.removePlaylistEntries(pl.id, [removeId]);

          entries = await repo.playlistEntries(pl.id);
          expect(entries.length, equals(3));
          expect(entries.map((e) => e.position).toList(), equals([0, 1, 2]));

          // Delete playlist explicitly cleans up items
          await repo.deletePlaylist(pl.id);
          expect(await repo.listPlaylists(), isEmpty);
          expect(await repo.playlistEntries(pl.id), isEmpty);
        });

        test('Recently played: distinct by path, newest first, skip missing', () async {
          await repo.upsertTracks([
            makeTrack('C:/songA.mp3', title: 'Song A'),
            makeTrack('C:/songB.mp3', title: 'Song B'),
          ]);

          final now = DateTime.now().toUtc();
          // Insert play events:
          // Song A at now - 10s (counted = 1)
          await repo.insertPlayEvent(PlayEvent(
            uri: 'C:/songA.mp3',
            startedAt: now.subtract(const Duration(seconds: 10)),
            listenedMs: 60000,
            counted: true,
            completed: true,
          ));

          // Song B at now - 5s (counted = 1)
          await repo.insertPlayEvent(PlayEvent(
            uri: 'C:/songB.mp3',
            startedAt: now.subtract(const Duration(seconds: 5)),
            listenedMs: 60000,
            counted: true,
            completed: true,
          ));

          // Uncounted event for Song C (should be ignored)
          await repo.insertPlayEvent(PlayEvent(
            uri: 'C:/songC.mp3',
            startedAt: now.subtract(const Duration(seconds: 2)),
            listenedMs: 5000,
            counted: false,
            completed: false,
          ));

          // Another counted event for Song A at now (should update Song A to newest)
          await repo.insertPlayEvent(PlayEvent(
            uri: 'file://C:/songA.mp3',
            startedAt: now,
            listenedMs: 60000,
            counted: true,
            completed: true,
          ));

          // Missing file counted event
          await repo.insertPlayEvent(PlayEvent(
            uri: 'C:/ghost.mp3',
            startedAt: now.add(const Duration(seconds: 1)),
            listenedMs: 60000,
            counted: true,
            completed: true,
          ));

          final recent = await repo.recentlyPlayedTracks();
          expect(recent.length, equals(2)); // Song A, Song B (ghost is missing, uncounted ignored)
          expect(recent[0].path, equals('C:/songA.mp3')); // newest
          expect(recent[1].path, equals('C:/songB.mp3'));
        });
      });
    }
  });
}
