/// Repository coordinating local sidecar, embedded tags, and online LRCLIB lyrics.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../library/artist_splitter.dart';
import '../../library/tag_reader.dart';
import 'lrc_parser.dart';
import 'lyrics_cache.dart';
import 'lyrics_http.dart';
import 'lyrics_models.dart';

/// Classification of network or parsing failure reasons.
enum LyricsErrorReason {
  /// No network connection or socket failure.
  offline,

  /// Request timed out (exceeded deadline).
  timeout,

  /// Upstream server returned 5xx HTTP error.
  serverError,

  /// Upstream server returned 4xx (except 404) or malformed payload.
  badResponse,
}

/// Result returned from resolving a track's lyrics.
sealed class LyricsResult {
  const LyricsResult();
}

/// Successfully resolved a valid lyrics document.
class LyricsResultFound extends LyricsResult {
  /// The resolved lyrics document.
  final LyricsDocument document;

  /// Creates a [LyricsResultFound].
  const LyricsResultFound(this.document);

  @override
  String toString() => 'LyricsResultFound(${document.kind}, source: ${document.source})';
}

/// No lyrics were found across the active sources.
class LyricsResultNotFound extends LyricsResult {
  /// Creates a [LyricsResultNotFound].
  const LyricsResultNotFound();

  @override
  String toString() => 'LyricsResultNotFound()';
}

/// An error occurred during retrieval (e.g. timeout or offline).
class LyricsResultError extends LyricsResult {
  /// Why retrieval failed.
  final LyricsErrorReason reason;

  /// Creates a [LyricsResultError].
  const LyricsResultError(this.reason);

  @override
  String toString() => 'LyricsResultError($reason)';
}

/// Retrieval was skipped because lyrics are turned off.
class LyricsResultOff extends LyricsResult {
  /// Creates a [LyricsResultOff].
  const LyricsResultOff();

  @override
  String toString() => 'LyricsResultOff()';
}

/// Orchestrates local and remote lyrics resolution based on configured modes.
class LyricsRepository {
  final LyricsHttp http;
  final LyricsCache cache;
  final TagReader tagReader;

  /// Creates a [LyricsRepository].
  LyricsRepository({
    LyricsHttp? http,
    LyricsCache? cache,
    TagReader? tagReader,
  })  : http = http ?? const DefaultLyricsHttp(),
        cache = cache ?? LyricsCache(),
        tagReader = tagReader ?? const AudioMetadataTagReader();

  /// Resolves lyrics for a track according to [mode].
  Future<LyricsResult> resolve({
    required String filePath,
    required String title,
    required String artist,
    String? album,
    required int durationMs,
    required String mode,
  }) async {
    if (mode == 'off') {
      return const LyricsResultOff();
    }

    if (mode == 'localOnly') {
      final local = await resolveLocal(filePath);
      return local != null ? LyricsResultFound(local) : const LyricsResultNotFound();
    }

    if (mode == 'onlineOnly') {
      return resolveOnline(
        filePath: filePath,
        title: title,
        artist: artist,
        album: album,
        durationMs: durationMs,
      );
    }

    if (mode == 'onlineThenLocal') {
      final onlineRes = await resolveOnline(
        filePath: filePath,
        title: title,
        artist: artist,
        album: album,
        durationMs: durationMs,
      );

      if (onlineRes is LyricsResultFound) {
        if (onlineRes.document.kind == LyricsKind.synced ||
            onlineRes.document.kind == LyricsKind.instrumental) {
          return onlineRes;
        }
        // Online gave plain; check if local has synced
        final local = await resolveLocal(filePath);
        if (local != null && local.kind == LyricsKind.synced) {
          return LyricsResultFound(local);
        }
        return onlineRes;
      }

      // Online was not found or had an error: try local
      final local = await resolveLocal(filePath);
      if (local != null) {
        return LyricsResultFound(local);
      }
      return onlineRes;
    }

    // Default: 'localThenOnline'
    final local = await resolveLocal(filePath);
    if (local != null) {
      if (local.kind == LyricsKind.synced ||
          local.kind == LyricsKind.instrumental) {
        return LyricsResultFound(local);
      }

      // Local is plain: try online to see if synced exists
      final onlineRes = await resolveOnline(
        filePath: filePath,
        title: title,
        artist: artist,
        album: album,
        durationMs: durationMs,
      );
      if (onlineRes is LyricsResultFound &&
          onlineRes.document.kind == LyricsKind.synced) {
        return onlineRes;
      }
      return LyricsResultFound(local);
    }

    // Local had nothing: try online
    return resolveOnline(
      filePath: filePath,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
    );
  }

  /// Searches for local sidecar files (.lrc, then .txt) and embedded metadata tags.
  Future<LyricsDocument?> resolveLocal(String filePath) async {
    try {
      final file = File(filePath);
      final dir = file.parent;
      if (dir.existsSync()) {
        final targetBase = p.basenameWithoutExtension(filePath).toLowerCase();

        String? lrcPath;
        String? txtPath;

        final entities = dir.listSync();
        for (final entity in entities) {
          if (entity is! File) continue;
          final base = p.basenameWithoutExtension(entity.path).toLowerCase();
          if (base == targetBase) {
            final ext = p.extension(entity.path).toLowerCase();
            if (ext == '.lrc' && lrcPath == null) {
              lrcPath = entity.path;
            } else if (ext == '.txt' && txtPath == null) {
              txtPath = entity.path;
            }
          }
        }

        final selectedSidecar = lrcPath ?? txtPath;
        if (selectedSidecar != null) {
          final sidecarFile = File(selectedSidecar);
          final fileLength = await sidecarFile.length();
          final readCap = fileLength > 1024 * 1024 ? 1024 * 1024 : fileLength;

          final bytes = <int>[];
          await for (final chunk in sidecarFile.openRead(0, readCap)) {
            bytes.addAll(chunk);
            if (bytes.length >= 1024 * 1024) break;
          }

          final text = decodeLyricsBytes(bytes);
          return parseLrc(text, source: LyricsSourceOrigin.local);
        }
      }

      // If no sidecar file was found, inspect embedded tags
      final rawTags = await tagReader.readTags(filePath, readCover: false);
      if (rawTags.lyrics != null && rawTags.lyrics!.trim().isNotEmpty) {
        return parseLrc(
          rawTags.lyrics!.trim(),
          source: LyricsSourceOrigin.embedded,
        );
      }
    } catch (_) {
      // Local file access failures return null safely
    }

    return null;
  }

  /// Performs online lookup via LRCLIB with disk cache integration.
  Future<LyricsResult> resolveOnline({
    required String filePath,
    required String title,
    required String artist,
    String? album,
    required int durationMs,
  }) async {
    // 1. Check local cache
    final cached = await cache.read(filePath);
    if (cached != null) {
      if (cached.found && cached.document != null) {
        return LyricsResultFound(cached.document!);
      }
      return const LyricsResultNotFound();
    }

    final primaryArtist = ArtistSplitter.split(artist).first.name;
    final durationSeconds = (durationMs / 1000).round();

    final queryParams = <String, String>{
      'track_name': title,
      'artist_name': primaryArtist,
      if (album != null && album.isNotEmpty) 'album_name': album,
      'duration': durationSeconds.toString(),
    };

    final getUri = Uri.https('lrclib.net', '/api/get', queryParams);

    try {
      final getResp = await http.get(getUri);

      if (getResp.statusCode == 200) {
        final doc = _parseLrclibResponse(getResp.body);
        if (doc != null) {
          await cache.write(filePath, doc);
          return LyricsResultFound(doc);
        }
        await cache.write(filePath, null);
        return const LyricsResultNotFound();
      }

      if (getResp.statusCode == 404) {
        // Fallback to /api/search
        final searchUri = Uri.https('lrclib.net', '/api/search', {
          'track_name': title,
          'artist_name': primaryArtist,
        });

        final searchResp = await http.get(searchUri);
        if (searchResp.statusCode == 200) {
          final doc = _selectBestSearchCandidate(
            searchResp.body,
            targetDurationSec: durationSeconds,
          );
          if (doc != null) {
            await cache.write(filePath, doc);
            return LyricsResultFound(doc);
          }
          await cache.write(filePath, null);
          return const LyricsResultNotFound();
        }

        if (searchResp.statusCode >= 500) {
          return const LyricsResultError(LyricsErrorReason.serverError);
        }
        if (searchResp.statusCode != 404) {
          return const LyricsResultError(LyricsErrorReason.badResponse);
        }
        await cache.write(filePath, null);
        return const LyricsResultNotFound();
      }

      if (getResp.statusCode >= 500) {
        return const LyricsResultError(LyricsErrorReason.serverError);
      }

      return const LyricsResultError(LyricsErrorReason.badResponse);
    } on TimeoutException {
      return const LyricsResultError(LyricsErrorReason.timeout);
    } on SocketException {
      return const LyricsResultError(LyricsErrorReason.offline);
    } catch (_) {
      return const LyricsResultError(LyricsErrorReason.offline);
    }
  }

  LyricsDocument? _parseLrclibResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) return null;

      final isInstrumental = decoded['instrumental'] == true;
      if (isInstrumental) {
        return LyricsDocument.instrumental(source: LyricsSourceOrigin.lrclib);
      }

      final syncedLyrics = decoded['syncedLyrics'];
      if (syncedLyrics is String && syncedLyrics.trim().isNotEmpty) {
        return parseLrc(syncedLyrics, source: LyricsSourceOrigin.lrclib);
      }

      final plainLyrics = decoded['plainLyrics'];
      if (plainLyrics is String && plainLyrics.trim().isNotEmpty) {
        return parseLrc(plainLyrics, source: LyricsSourceOrigin.lrclib);
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  LyricsDocument? _selectBestSearchCandidate(
    String body, {
    required int targetDurationSec,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List) return null;

      Map<String, Object?>? bestCandidate;
      var bestDiff = 999999;
      var bestHasSynced = false;

      for (final item in decoded) {
        if (item is! Map<String, Object?>) continue;

        final rawDuration = item['duration'];
        if (rawDuration is! num) continue;
        final candidateDur = rawDuration.round();
        final diff = (candidateDur - targetDurationSec).abs();

        // Reject candidates more than 3 seconds off
        if (diff > 3) continue;

        final hasSynced = (item['syncedLyrics'] is String &&
                (item['syncedLyrics'] as String).trim().isNotEmpty) ||
            item['instrumental'] == true;

        var isBetter = false;
        if (bestCandidate == null) {
          isBetter = true;
        } else if (hasSynced && !bestHasSynced) {
          isBetter = true;
        } else if (hasSynced == bestHasSynced && diff < bestDiff) {
          isBetter = true;
        }

        if (isBetter) {
          bestCandidate = item;
          bestDiff = diff;
          bestHasSynced = hasSynced;
        }
      }

      if (bestCandidate != null) {
        return _parseLrclibResponse(jsonEncode(bestCandidate));
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}
