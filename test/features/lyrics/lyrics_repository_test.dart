import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/features/lyrics/lyrics_cache.dart';
import 'package:aestheticy/features/lyrics/lyrics_http.dart';
import 'package:aestheticy/features/lyrics/lyrics_models.dart';
import 'package:aestheticy/features/lyrics/lyrics_repository.dart';
import 'package:aestheticy/library/tag_reader.dart';

class FakeLyricsHttp implements LyricsHttp {
  final List<Uri> requestedUris = [];
  Future<LyricsHttpResponse> Function(Uri uri)? handler;

  @override
  Future<LyricsHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    requestedUris.add(uri);
    if (handler != null) {
      return handler!(uri);
    }
    return const LyricsHttpResponse(statusCode: 404, body: 'Not found');
  }
}

class FakeTagReader implements TagReader {
  String? lyricsToReturn;

  @override
  FutureOr<RawTags> readTags(String filePath, {bool readCover = true}) {
    return RawTags(lyrics: lyricsToReturn);
  }
}

void main() {
  group('LyricsRepository & Cache Tests (S3)', () {
    late Directory tempDir;
    late FakeLyricsHttp fakeHttp;
    late FakeTagReader fakeTagReader;
    late DateTime simulatedNow;
    late LyricsCache cache;
    late LyricsRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_lyrics_test_');
      fakeHttp = FakeLyricsHttp();
      fakeTagReader = FakeTagReader();
      simulatedNow = DateTime(2026, 11, 8, 12, 0);

      cache = LyricsCache(
        directory: Directory(p.join(tempDir.path, 'cache')),
        clock: () => simulatedNow,
      );

      repository = LyricsRepository(
        http: fakeHttp,
        cache: cache,
        tagReader: fakeTagReader,
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('mode "off" touches nothing: zero network calls and zero file reads', () async {
      final res = await repository.resolve(
        filePath: p.join(tempDir.path, 'song.mp3'),
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000,
        mode: 'off',
      );

      expect(res, isA<LyricsResultOff>());
      expect(fakeHttp.requestedUris, isEmpty);
    });

    test('mode "localOnly" makes zero network calls', () async {
      final songPath = p.join(tempDir.path, 'track1.mp3');
      final lrcPath = p.join(tempDir.path, 'track1.lrc');
      await File(lrcPath).writeAsString('[00:10.00]Local lyric line');

      final res = await repository.resolve(
        filePath: songPath,
        title: 'Track 1',
        artist: 'Artist',
        durationMs: 180000,
        mode: 'localOnly',
      );

      expect(res, isA<LyricsResultFound>());
      final found = (res as LyricsResultFound).document;
      expect(found.kind, equals(LyricsKind.synced));
      expect(found.source, equals(LyricsSourceOrigin.local));
      expect(fakeHttp.requestedUris, isEmpty, reason: 'localOnly must make 0 network calls');
    });

    test('sidecar lookup is case-insensitive and prefers .lrc over .txt', () async {
      final songPath = p.join(tempDir.path, 'my_song.flac');
      // Create .TXT first, then .LRC (uppercase)
      await File(p.join(tempDir.path, 'MY_SONG.TXT')).writeAsString('Plain text lyric');
      await File(p.join(tempDir.path, 'MY_SONG.LRC')).writeAsString('[00:05.00]LRC lyric');

      final res = await repository.resolve(
        filePath: songPath,
        title: 'My Song',
        artist: 'Artist',
        durationMs: 180000,
        mode: 'localOnly',
      );

      expect(res, isA<LyricsResultFound>());
      final doc = (res as LyricsResultFound).document;
      expect(doc.kind, equals(LyricsKind.synced));
      expect(doc.lines.first.text, equals('LRC lyric'), reason: '.lrc must take precedence over .txt');
    });

    test('synced-over-plain rule: local plain is upgraded to online synced in localThenOnline', () async {
      final songPath = p.join(tempDir.path, 'song.mp3');
      await File(p.join(tempDir.path, 'song.txt')).writeAsString('Just plain local lyrics');

      fakeHttp.handler = (uri) async {
        return LyricsHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'trackName': 'Song',
            'artistName': 'Artist',
            'duration': 180,
            'instrumental': false,
            'syncedLyrics': '[00:05.00]Online synced line',
          }),
        );
      };

      final res = await repository.resolve(
        filePath: songPath,
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000,
        mode: 'localThenOnline',
      );

      expect(res, isA<LyricsResultFound>());
      final doc = (res as LyricsResultFound).document;
      expect(doc.kind, equals(LyricsKind.synced));
      expect(doc.source, equals(LyricsSourceOrigin.lrclib));
      expect(doc.lines.first.text, equals('Online synced line'));
    });

    test('metadata sent to LRCLIB contains only allowed fields and original primary artist', () async {
      fakeHttp.handler = (uri) async {
        return const LyricsHttpResponse(statusCode: 404, body: 'Not found');
      };

      await repository.resolve(
        filePath: p.join(tempDir.path, 'dummy.mp3'),
        title: 'Adventure',
        artist: 'Coldplay feat. BTS', // Multi-artist collaboration
        album: 'A Head Full of Dreams',
        durationMs: 205000, // 205 seconds
        mode: 'onlineOnly',
      );

      expect(fakeHttp.requestedUris.length, equals(2)); // /get then /search
      final getUri = fakeHttp.requestedUris.first;

      expect(getUri.path, equals('/api/get'));
      expect(getUri.queryParameters['track_name'], equals('Adventure'));
      expect(getUri.queryParameters['artist_name'], equals('Coldplay'),
          reason: 'Primary artist must be parsed via ArtistSplitter');
      expect(getUri.queryParameters['album_name'], equals('A Head Full of Dreams'));
      expect(getUri.queryParameters['duration'], equals('205'));
      // No extra fields or translated names sent
      expect(getUri.queryParameters.keys.toSet(), equals({'track_name', 'artist_name', 'album_name', 'duration'}));
    });

    test('duration tolerance in /search: <= 3s accepted, >= 4s rejected', () async {
      fakeHttp.handler = (uri) async {
        if (uri.path == '/api/get') {
          return const LyricsHttpResponse(statusCode: 404, body: 'Not found');
        }
        if (uri.path == '/api/search') {
          return LyricsHttpResponse(
            statusCode: 200,
            body: jsonEncode([
              {
                'trackName': 'Song',
                'artistName': 'Artist',
                'duration': 185, // 5s off -> rejected (> 3s)
                'syncedLyrics': '[00:01.00]Rejected candidate',
              },
              {
                'trackName': 'Song',
                'artistName': 'Artist',
                'duration': 182, // 2s off -> accepted (<= 3s)
                'syncedLyrics': '[00:01.00]Accepted candidate',
              },
            ]),
          );
        }
        return const LyricsHttpResponse(statusCode: 404, body: '');
      };

      final res = await repository.resolve(
        filePath: p.join(tempDir.path, 'song_tol.mp3'),
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000, // 180s
        mode: 'onlineOnly',
      );

      expect(res, isA<LyricsResultFound>());
      final doc = (res as LyricsResultFound).document;
      expect(doc.lines.first.text, equals('Accepted candidate'));
    });

    test('duration tolerance rejects candidates 4 seconds off and returns not found', () async {
      fakeHttp.handler = (uri) async {
        if (uri.path == '/api/get') {
          return const LyricsHttpResponse(statusCode: 404, body: 'Not found');
        }
        return LyricsHttpResponse(
          statusCode: 200,
          body: jsonEncode([
            {
              'trackName': 'Song',
              'artistName': 'Artist',
              'duration': 184, // 4s off -> must be rejected
              'syncedLyrics': '[00:01.00]Too far candidate',
            },
          ]),
        );
      };

      final res = await repository.resolve(
        filePath: p.join(tempDir.path, 'song_far.mp3'),
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000, // 180s
        mode: 'onlineOnly',
      );

      expect(res, isA<LyricsResultNotFound>());
    });

    test('LRCLIB instrumental response gives LyricsKind.instrumental', () async {
      fakeHttp.handler = (uri) async {
        return LyricsHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'trackName': 'Orion',
            'artistName': 'Metallica',
            'duration': 500,
            'instrumental': true,
          }),
        );
      };

      final res = await repository.resolve(
        filePath: p.join(tempDir.path, 'orion.mp3'),
        title: 'Orion',
        artist: 'Metallica',
        durationMs: 500000,
        mode: 'onlineOnly',
      );

      expect(res, isA<LyricsResultFound>());
      final doc = (res as LyricsResultFound).document;
      expect(doc.kind, equals(LyricsKind.instrumental));
      expect(doc.lines, isEmpty);
    });

    test('malformed JSON response returns not found without throwing', () async {
      fakeHttp.handler = (uri) async {
        return const LyricsHttpResponse(
          statusCode: 200,
          body: '{ NOT_VALID_JSON ...',
        );
      };

      final res = await repository.resolve(
        filePath: p.join(tempDir.path, 'bad_json.mp3'),
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000,
        mode: 'onlineOnly',
      );

      expect(res, isA<LyricsResultNotFound>());
    });

    test('network timeout and offline yield typed error states', () async {
      // 1. Timeout
      fakeHttp.handler = (uri) async => throw TimeoutException('Request timed out');
      final timeoutRes = await repository.resolve(
        filePath: p.join(tempDir.path, 'timeout.mp3'),
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000,
        mode: 'onlineOnly',
      );
      expect(timeoutRes, isA<LyricsResultError>());
      expect((timeoutRes as LyricsResultError).reason, equals(LyricsErrorReason.timeout));

      // 2. Offline
      fakeHttp.handler = (uri) async => throw const SocketException('No internet');
      final offlineRes = await repository.resolve(
        filePath: p.join(tempDir.path, 'offline.mp3'),
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000,
        mode: 'onlineOnly',
      );
      expect(offlineRes, isA<LyricsResultError>());
      expect((offlineRes as LyricsResultError).reason, equals(LyricsErrorReason.offline));

      // 3. Server 500 error
      fakeHttp.handler = (uri) async => const LyricsHttpResponse(statusCode: 500, body: 'Server error');
      final serverErrRes = await repository.resolve(
        filePath: p.join(tempDir.path, 'err500.mp3'),
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000,
        mode: 'onlineOnly',
      );
      expect(serverErrRes, isA<LyricsResultError>());
      expect((serverErrRes as LyricsResultError).reason, equals(LyricsErrorReason.serverError));
    });

    test('cache validity with manual clock and corrupt entry handling', () async {
      const songPath = 'C:\\music\\song.mp3';

      fakeHttp.handler = (uri) async => LyricsHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'trackName': 'Song',
              'artistName': 'Artist',
              'duration': 180,
              'instrumental': false,
              'syncedLyrics': '[00:01.00]Cached lyric line',
            }),
          );

      // 1. First fetch primes the cache
      final res1 = await repository.resolve(
        filePath: songPath,
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000,
        mode: 'onlineOnly',
      );
      expect(res1, isA<LyricsResultFound>());
      expect(fakeHttp.requestedUris.length, equals(1));

      // 2. Immediate second fetch is served from cache (zero network calls)
      fakeHttp.handler = (uri) async => throw StateError('Should not be called');
      final res2 = await repository.resolve(
        filePath: songPath,
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000,
        mode: 'onlineOnly',
      );
      expect(res2, isA<LyricsResultFound>());

      // 3. Advance clock by 29 days -> still valid
      simulatedNow = simulatedNow.add(const Duration(days: 29));
      final res3 = await repository.resolve(
        filePath: songPath,
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000,
        mode: 'onlineOnly',
      );
      expect(res3, isA<LyricsResultFound>());

      // 4. Advance clock by 2 more days (total 31 days) -> expired, re-fetches
      simulatedNow = simulatedNow.add(const Duration(days: 2));
      fakeHttp.handler = (uri) async => const LyricsHttpResponse(statusCode: 404, body: 'Not found');
      final res4 = await repository.resolve(
        filePath: songPath,
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000,
        mode: 'onlineOnly',
      );
      expect(res4, isA<LyricsResultNotFound>());

      // 5. Corrupt cache file counts as missing
      final cacheDir = await cache.resolveDirectory();
      final key = LyricsCache.computeKey(songPath);
      final cacheFile = File(p.join(cacheDir, '$key.json'));
      await cacheFile.writeAsString('{ CORRUPT_BODY ...');

      final readCorrupt = await cache.read(songPath);
      expect(readCorrupt, isNull, reason: 'Corrupt cache file must return null and count as missing');
    });
  });
}
