import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/features/collections/user_collections.dart';
import '../../library/fake_library_repository.dart';

class FailingTestRepository extends FakeLibraryRepository {
  bool shouldFailFavorites = false;
  bool shouldFailRatings = false;
  bool shouldFailPlaylists = false;

  @override
  Future<void> setFavorite(String path, bool value) async {
    if (shouldFailFavorites) throw Exception('Simulated DB error');
    return super.setFavorite(path, value);
  }

  @override
  Future<void> setRating(String path, int stars) async {
    if (shouldFailRatings) throw Exception('Simulated DB error');
    return super.setRating(path, stars);
  }

  @override
  Future<void> renamePlaylist(int id, String name) async {
    if (shouldFailPlaylists) throw Exception('Simulated DB error');
    return super.renamePlaylist(id, name);
  }

  @override
  Future<void> deletePlaylist(int id) async {
    if (shouldFailPlaylists) throw Exception('Simulated DB error');
    return super.deletePlaylist(id);
  }
}

void main() {
  group('UserCollections Controller Tests', () {
    late FailingTestRepository repo;
    late UserCollections collections;

    setUp(() async {
      repo = FailingTestRepository();
      collections = UserCollections(repository: repo);
    });

    test('Initial load populates favorites, ratings, and playlists', () async {
      await repo.setFavorite('C:/track1.mp3', true);
      await repo.setRating('C:/track1.mp3', 4);
      await repo.createPlaylist('Chill');

      expect(collections.isLoaded, isFalse);
      expect(collections.isFavorite('C:/track1.mp3'), isFalse);
      expect(collections.ratingOf('C:/track1.mp3'), equals(0));
      expect(collections.playlists, isEmpty);

      var notifyCount = 0;
      collections.addListener(() => notifyCount++);

      await collections.init();

      expect(collections.isLoaded, isTrue);
      expect(notifyCount, equals(1));
      expect(collections.isFavorite('C:/track1.mp3'), isTrue);
      expect(collections.ratingOf('C:/track1.mp3'), equals(4));
      expect(collections.playlists.length, equals(1));
      expect(collections.playlists.first.name, equals('Chill'));
    });

    test('Optimistic toggleFavorite succeeds and notifies', () async {
      await collections.init();
      var notified = false;
      collections.addListener(() => notified = true);

      await collections.toggleFavorite('C:/fav.mp3');

      expect(collections.isFavorite('C:/fav.mp3'), isTrue);
      expect(notified, isTrue);
      expect((await repo.favoritePaths()), contains('C:/fav.mp3'));

      // Untoggle
      await collections.toggleFavorite('C:/fav.mp3');
      expect(collections.isFavorite('C:/fav.mp3'), isFalse);
      expect((await repo.favoritePaths()), isEmpty);
    });

    test('Optimistic toggleFavorite reverts on failure and rethrows', () async {
      await collections.init();
      repo.shouldFailFavorites = true;

      var notifyCount = 0;
      collections.addListener(() => notifyCount++);

      await expectLater(
        collections.toggleFavorite('C:/fail.mp3'),
        throwsException,
      );

      // Reverted to false
      expect(collections.isFavorite('C:/fail.mp3'), isFalse);
      // Notified twice: once for optimistic update, once for rollback
      expect(notifyCount, equals(2));
      expect(await repo.favoritePaths(), isEmpty);
    });

    test('Optimistic setRating succeeds and reverts on failure', () async {
      await collections.init();
      await collections.setRating('C:/rated.mp3', 5);
      expect(collections.ratingOf('C:/rated.mp3'), equals(5));

      repo.shouldFailRatings = true;
      await expectLater(
        collections.setRating('C:/rated.mp3', 2),
        throwsException,
      );

      // Reverted to 5
      expect(collections.ratingOf('C:/rated.mp3'), equals(5));
    });

    test('Playlist operations: create, rename, delete, add, remove, move', () async {
      await collections.init();

      final pl = await collections.createPlaylist('Work');
      expect(collections.playlists.any((p) => p.name == 'Work'), isTrue);

      await collections.renamePlaylist(pl.id, 'Deep Work');
      expect(collections.playlists.any((p) => p.name == 'Deep Work'), isTrue);

      // Add to playlist
      final count = await collections.addToPlaylist(pl.id, ['C:/1.mp3', 'C:/2.mp3']);
      expect(count, equals(2));
      expect(collections.playlists.firstWhere((p) => p.id == pl.id).trackCount, equals(2));

      // Move entry
      final entries = await repo.playlistEntries(pl.id);
      await collections.moveEntry(pl.id, entries[0].entryId, 1);
      final reordered = await repo.playlistEntries(pl.id);
      expect(reordered[0].entryId, equals(entries[1].entryId));

      // Remove entry
      await collections.removeFromPlaylist(pl.id, [entries[0].entryId]);
      expect(collections.playlists.firstWhere((p) => p.id == pl.id).trackCount, equals(1));

      // Delete playlist
      await collections.deletePlaylist(pl.id);
      expect(collections.playlists, isEmpty);
    });

    test('Rename and delete rollback on failure', () async {
      await collections.init();
      final pl = await collections.createPlaylist('Study');

      repo.shouldFailPlaylists = true;

      // Rename rollback
      await expectLater(
        collections.renamePlaylist(pl.id, 'Study Hard'),
        throwsException,
      );
      expect(collections.playlists.firstWhere((p) => p.id == pl.id).name, equals('Study'));

      // Delete rollback
      await expectLater(
        collections.deletePlaylist(pl.id),
        throwsException,
      );
      expect(collections.playlists.any((p) => p.id == pl.id), isTrue);
    });

    test('Large set performance: 50,000 favorites read synchronously in microseconds', () async {
      final bigRepo = FakeLibraryRepository();
      for (var i = 0; i < 50000; i++) {
        await bigRepo.setFavorite('C:/music/track_$i.mp3', true);
      }

      final bigCollections = UserCollections(repository: bigRepo);
      await bigCollections.init();

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        expect(bigCollections.isFavorite('C:/music/track_12345.mp3'), isTrue);
        expect(bigCollections.isFavorite('C:/music/track_nonexistent.mp3'), isFalse);
      }
      stopwatch.stop();

      // 2000 lookups should finish in under 20ms
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });
}
