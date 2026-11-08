/// Persistent atomic disk cache for lyrics lookup results.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'lyrics_models.dart';

/// Cache entry wrapping a resolved document or a recorded negative result.
class LyricsCacheEntry {
  /// Whether valid lyrics were found for this track.
  final bool found;

  /// The cached lyrics document, if found.
  final LyricsDocument? document;

  /// Timestamp when this cache entry was written.
  final DateTime cachedAt;

  /// Creates a [LyricsCacheEntry].
  const LyricsCacheEntry({
    required this.found,
    this.document,
    required this.cachedAt,
  });

  /// Checks if this cache entry is still valid according to the manual clock.
  bool isValid(DateTime now) {
    final age = now.difference(cachedAt);
    if (age.isNegative) return false;
    if (found) {
      return age.inDays < 30;
    } else {
      return age.inDays < 3;
    }
  }
}

/// Disk cache storing track lyrics under the application support directory.
class LyricsCache {
  final Directory? _injectedDirectory;
  final DateTime Function() clock;
  String? _resolvedDirPath;

  /// Creates a [LyricsCache].
  LyricsCache({
    Directory? directory,
    DateTime Function()? clock,
  })  : _injectedDirectory = directory,
        clock = clock ?? DateTime.now;

  /// Resolves the storage directory on disk, ensuring it exists.
  Future<String> resolveDirectory() async {
    final injected = _injectedDirectory;
    if (injected != null) {
      if (!injected.existsSync()) {
        injected.createSync(recursive: true);
      }
      return injected.path;
    }

    if (_resolvedDirPath != null) return _resolvedDirPath!;
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'Aestheticy', 'lyrics'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _resolvedDirPath = dir.path;
    return dir.path;
  }

  /// Computes a stable hexadecimal cache key from the track's filesystem path.
  static String computeKey(String trackFilePath) {
    return md5.convert(utf8.encode(trackFilePath)).toString();
  }

  File _fileForKey(String dirPath, String key) {
    return File(p.join(dirPath, '$key.json'));
  }

  /// Reads a cached entry for [trackFilePath], returning null if missing or expired.
  Future<LyricsCacheEntry?> read(String trackFilePath) async {
    try {
      final dir = await resolveDirectory();
      final key = computeKey(trackFilePath);
      final file = _fileForKey(dir, key);

      if (!file.existsSync()) return null;

      final content = await file.readAsString();
      final json = jsonDecode(content);
      if (json is! Map<String, Object?>) {
        _deleteQuietly(file);
        return null;
      }

      final cachedAtMs = json['cachedAt'];
      if (cachedAtMs is! int) {
        _deleteQuietly(file);
        return null;
      }
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);

      final found = json['found'] == true;
      final entry = LyricsCacheEntry(
        found: found,
        cachedAt: cachedAt,
        document: found ? _documentFromJson(json) : null,
      );

      if (!entry.isValid(clock())) {
        return null;
      }

      if (found && entry.document == null) {
        _deleteQuietly(file);
        return null;
      }

      return entry;
    } catch (_) {
      return null;
    }
  }

  /// Writes a found or not-found entry atomically to disk.
  Future<void> write(String trackFilePath, LyricsDocument? document) async {
    try {
      final dir = await resolveDirectory();
      final key = computeKey(trackFilePath);
      final file = _fileForKey(dir, key);
      final tmpFile = File('${file.path}.tmp');

      final data = <String, Object?>{
        'cachedAt': clock().millisecondsSinceEpoch,
        'found': document != null,
      };

      if (document != null) {
        data['kind'] = document.kind.name;
        data['source'] = document.source.name;
        data['hasWordTiming'] = document.hasWordTiming;
        data['lines'] = document.lines
            .map((l) => {
                  'startMs': l.startMs,
                  'text': l.text,
                  if (l.words != null)
                    'words': l.words!
                        .map((w) => {
                              'startMs': w.startMs,
                              'endMs': w.endMs,
                              'text': w.text,
                            })
                        .toList(),
                })
            .toList();
      }

      final encoded = jsonEncode(data);
      await tmpFile.writeAsString(encoded, flush: true);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
      await tmpFile.rename(file.path);
    } catch (_) {
      // Disk failures never throw into audio playback
    }
  }

  LyricsDocument? _documentFromJson(Map<String, Object?> json) {
    try {
      final rawKind = json['kind'];
      final kind = switch (rawKind) {
        'synced' => LyricsKind.synced,
        'plain' => LyricsKind.plain,
        'instrumental' => LyricsKind.instrumental,
        _ => LyricsKind.plain,
      };

      final rawSource = json['source'];
      final source = switch (rawSource) {
        'local' => LyricsSourceOrigin.local,
        'embedded' => LyricsSourceOrigin.embedded,
        'lrclib' => LyricsSourceOrigin.lrclib,
        _ => LyricsSourceOrigin.local,
      };

      final hasWordTiming = json['hasWordTiming'] == true;

      final rawLines = json['lines'];
      final lines = <LyricsLine>[];
      if (rawLines is List) {
        for (final item in rawLines) {
          if (item is Map) {
            final startMs = item['startMs'] is int ? item['startMs'] as int : 0;
            final text = item['text'] is String ? item['text'] as String : '';

            List<LyricsWord>? words;
            final rawWords = item['words'];
            if (rawWords is List) {
              words = [];
              for (final w in rawWords) {
                if (w is Map) {
                  words.add(LyricsWord(
                    startMs: w['startMs'] is int ? w['startMs'] as int : 0,
                    endMs: w['endMs'] is int ? w['endMs'] as int : null,
                    text: w['text'] is String ? w['text'] as String : '',
                  ));
                }
              }
            }

            lines.add(LyricsLine(
              startMs: startMs,
              text: text,
              words: words,
            ));
          }
        }
      }

      return LyricsDocument(
        kind: kind,
        lines: lines,
        source: source,
        hasWordTiming: hasWordTiming,
      );
    } catch (_) {
      return null;
    }
  }

  void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
