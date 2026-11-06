/// Cover artwork disk cache and deterministic key generation.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages caching of album artwork images on the local filesystem.
abstract final class CoverCache {
  static String? _customDirectory;
  static String? _cachedDefaultDirectory;

  /// Sets an override directory path (primarily for unit tests).
  static void setCustomDirectory(String? path) {
    _customDirectory = path;
  }

  /// Clears cached directories to simulate a cold start in tests.
  @visibleForTesting
  static void resetForTesting() {
    _customDirectory = null;
    _cachedDefaultDirectory = null;
  }

  /// Ensures the covers directory is resolved at startup.
  ///
  /// Can optionally accept [directory] or [directoryProvider] to override resolution in tests.
  static Future<String> ensureInitialized({
    String? directory,
    Future<Directory> Function()? directoryProvider,
  }) async {
    if (directory != null) {
      _cachedDefaultDirectory = directory;
      return directory;
    }
    if (_cachedDefaultDirectory != null) return _cachedDefaultDirectory!;
    if (directoryProvider != null) {
      final dir = await directoryProvider();
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _cachedDefaultDirectory = dir.path;
      return dir.path;
    }
    return resolveDefaultDirectory();
  }

  /// Resolves the default application support covers directory.
  static Future<String> resolveDefaultDirectory() async {
    if (_cachedDefaultDirectory != null) return _cachedDefaultDirectory!;
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'Aestheticy', 'covers'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _cachedDefaultDirectory = dir.path;
    return dir.path;
  }

  /// Computes a stable, deterministic hexadecimal hash for an album.
  ///
  /// Combines [albumArtist] (if present) and [album] to produce a collision-resistant
  /// unique key used for file naming.
  static String computeCoverKey({String? albumArtist, required String album}) {
    final normalizedArtist = (albumArtist ?? '').trim().toLowerCase();
    final normalizedAlbum = album.trim().toLowerCase();
    final payload = '$normalizedArtist::$normalizedAlbum';
    return md5.convert(utf8.encode(payload)).toString();
  }

  /// Returns the absolute filesystem path for a given [coverKey].
  ///
  /// If [coversDirectory] is provided, uses it as the root; otherwise falls back
  /// to the configured custom directory or default covers directory.
  static String pathFor(String coverKey, {String? coversDirectory}) {
    final root = coversDirectory ?? _customDirectory ?? _cachedDefaultDirectory;
    if (root == null) {
      throw StateError(
        'CoverCache has not been initialized. Call CoverCache.ensureInitialized() '
        'at startup or CoverCache.setCustomDirectory() in tests before resolving cover paths.',
      );
    }
    return p.join(root, '$coverKey.jpg');
  }

  /// Checks whether a valid cover file exists on disk for [coverKey].
  ///
  /// Zero-length files are treated as missing.
  static bool hasCover(String coverKey, {String? coversDirectory}) {
    final filePath = pathFor(coverKey, coversDirectory: coversDirectory);
    final file = File(filePath);
    try {
      return file.existsSync() && file.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  /// Saves album cover [bytes] synchronously if not already cached.
  ///
  /// Writes to a temporary file in the same directory first, then atomically
  /// renames to avoid leaving corrupt or zero-length files. Zero-length files
  /// are treated as missing and overwritten. Returns the computed [coverKey].
  static String saveCoverSync({
    String? albumArtist,
    required String album,
    required Uint8List bytes,
    String? coversDirectory,
  }) {
    final key = computeCoverKey(albumArtist: albumArtist, album: album);
    final filePath = pathFor(key, coversDirectory: coversDirectory);
    final file = File(filePath);

    bool existsAndValid = false;
    try {
      existsAndValid = file.existsSync() && file.lengthSync() > 0;
    } catch (_) {
      existsAndValid = false;
    }

    if (!existsAndValid) {
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final tempFile = File(
        p.join(file.parent.path, '$key.${DateTime.now().microsecondsSinceEpoch}.tmp'),
      );
      tempFile.writeAsBytesSync(bytes, flush: true);
      try {
        tempFile.renameSync(filePath);
      } catch (_) {
        if (file.existsSync()) {
          try {
            file.deleteSync();
          } catch (_) {}
        }
        tempFile.renameSync(filePath);
      }
    }

    return key;
  }

  /// Saves album cover [bytes] asynchronously if not already cached.
  ///
  /// Writes to a temporary file in the same directory first, then atomically
  /// renames to avoid leaving corrupt or zero-length files. Zero-length files
  /// are treated as missing and overwritten. Returns the computed [coverKey].
  static Future<String> saveCover({
    String? albumArtist,
    required String album,
    required Uint8List bytes,
    String? coversDirectory,
  }) async {
    final key = computeCoverKey(albumArtist: albumArtist, album: album);
    final filePath = pathFor(key, coversDirectory: coversDirectory);
    final file = File(filePath);

    bool existsAndValid = false;
    try {
      existsAndValid = file.existsSync() && (await file.length()) > 0;
    } catch (_) {
      existsAndValid = false;
    }

    if (!existsAndValid) {
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final tempFile = File(
        p.join(file.parent.path, '$key.${DateTime.now().microsecondsSinceEpoch}.tmp'),
      );
      await tempFile.writeAsBytes(bytes, flush: true);
      try {
        await tempFile.rename(filePath);
      } catch (_) {
        if (file.existsSync()) {
          try {
            await file.delete();
          } catch (_) {}
        }
        await tempFile.rename(filePath);
      }
    }

    return key;
  }
}
