/// Background filesystem crawler and metadata extractor for music folders.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'package:aestheticy/library/cover_cache.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/tag_reader.dart';

/// Progress information emitted during directory scanning.
class ScanProgress {
  /// Total audio files discovered on disk so far.
  final int found;

  /// Total files evaluated (unchanged, added, updated, or skipped).
  final int processed;

  /// New tracks inserted into the library database.
  final int added;

  /// Existing tracks updated due to file modification.
  final int updated;

  /// Tracks removed because their source files were deleted.
  final int removed;

  /// Number of corrupt or unreadable files encountered.
  final int errors;

  /// Number of directories that could not be read due to permission or I/O errors.
  final int unreadableDirs;

  /// Whether the scan operation has completed.
  final bool done;

  /// Paths of any corrupt files encountered during the scan.
  final List<String> corruptPaths;

  /// Creates a [ScanProgress] state snapshot.
  const ScanProgress({
    this.found = 0,
    this.processed = 0,
    this.added = 0,
    this.updated = 0,
    this.removed = 0,
    this.errors = 0,
    this.unreadableDirs = 0,
    this.done = false,
    this.corruptPaths = const [],
  });

  /// Creates a copy of this progress with modified values.
  ScanProgress copyWith({
    int? found,
    int? processed,
    int? added,
    int? updated,
    int? removed,
    int? errors,
    int? unreadableDirs,
    bool? done,
    List<String>? corruptPaths,
  }) {
    return ScanProgress(
      found: found ?? this.found,
      processed: processed ?? this.processed,
      added: added ?? this.added,
      updated: updated ?? this.updated,
      removed: removed ?? this.removed,
      errors: errors ?? this.errors,
      unreadableDirs: unreadableDirs ?? this.unreadableDirs,
      done: done ?? this.done,
      corruptPaths: corruptPaths ?? this.corruptPaths,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScanProgress &&
          runtimeType == other.runtimeType &&
          found == other.found &&
          processed == other.processed &&
          added == other.added &&
          updated == other.updated &&
          removed == other.removed &&
          errors == other.errors &&
          unreadableDirs == other.unreadableDirs &&
          done == other.done;

  @override
  int get hashCode =>
      found.hashCode ^
      processed.hashCode ^
      added.hashCode ^
      updated.hashCode ^
      removed.hashCode ^
      errors.hashCode ^
      unreadableDirs.hashCode ^
      done.hashCode;

  @override
  String toString() =>
      'ScanProgress(found: $found, processed: $processed, added: $added, updated: $updated, removed: $removed, errors: $errors, unreadableDirs: $unreadableDirs, done: $done)';
}

/// Discovers audio files, extracts tags in a background isolate, and synchronizes
/// the library database in transactional batches.
class LibraryScanner {
  /// Supported audio file extensions (lowercase with leading dot).
  static const Set<String> supportedExtensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
    '.wav',
    '.wma',
    '.aiff',
    '.aif',
    '.ape',
    '.wv',
  };

  /// The target storage repository.
  final LibraryRepository repository;

  /// Tag reader used for audio metadata extraction.
  final TagReader tagReader;

  /// Directory path where album cover art is cached.
  final String? coversDirectory;

  /// Batch size for isolate-to-database transactions.
  final int batchSize;

  Isolate? _activeIsolate;
  ReceivePort? _activeReceivePort;
  SendPort? _workerControlPort;
  bool _isCancelled = false;

  /// Directory paths that simulate permission/IO errors during testing.
  final List<String> unreadablePaths;

  /// Creates a [LibraryScanner].
  LibraryScanner({
    required this.repository,
    this.tagReader = const AudioMetadataTagReader(),
    this.coversDirectory,
    this.batchSize = 200,
    this.unreadablePaths = const [],
  });

  /// Cancels any currently executing scan.
  void cancel() {
    _isCancelled = true;
    _workerControlPort?.send(const _CancelSignal());
    _activeIsolate?.kill(priority: Isolate.immediate);
    _cleanupIsolate();
  }

  /// Scans a library folder, yielding [ScanProgress] updates.
  ///
  /// [folder] may be a [LibraryFolder] instance or a [String] filesystem path.
  Stream<ScanProgress> scan(dynamic folder) async* {
    _isCancelled = false;

    LibraryFolder targetFolder;
    if (folder is LibraryFolder) {
      if (folder.id == null) {
        targetFolder = await repository.addFolder(folder.path);
      } else {
        targetFolder = folder;
      }
    } else if (folder is String) {
      targetFolder = await repository.addFolder(folder);
    } else {
      throw ArgumentError.value(folder, 'folder', 'Must be a LibraryFolder or String path');
    }

    final folderId = targetFolder.id!;
    final existing = await repository.existingFiles(folderId);

    // Resolve covers directory if not provided.
    final effectiveCoversDir =
        coversDirectory ?? await CoverCache.resolveDefaultDirectory();

    var progress = const ScanProgress();
    yield progress;

    if (_isCancelled) {
      yield progress.copyWith(done: true);
      return;
    }

    final receivePort = ReceivePort();
    _activeReceivePort = receivePort;

    // Convert map to plain records/maps sendable across isolates with normalized paths.
    final existingStats = <String, ({int mtimeMs, int sizeBytes})>{};
    for (final entry in existing.entries) {
      existingStats[p.normalize(entry.key)] = entry.value;
    }

    final config = _WorkerConfig(
      sendPort: receivePort.sendPort,
      folderPath: p.normalize(targetFolder.path),
      folderId: folderId,
      existingFiles: existingStats,
      tagReader: tagReader,
      coversDirectory: effectiveCoversDir,
      batchSize: batchSize,
      unreadablePaths: unreadablePaths.map(p.normalize).toList(),
    );

    _activeIsolate = await Isolate.spawn(_scanWorkerEntry, config);

    final corruptPaths = <String>[];
    int totalAdded = 0;
    int totalUpdated = 0;
    int totalRemoved = 0;
    bool linksRebuilt = false;

    Future<void> ensureLinksRebuilt() async {
      if (linksRebuilt) return;
      linksRebuilt = true;
      try {
        await repository.rebuildArtistLinks();
      } catch (_) {}
    }

    try {
      await for (final message in receivePort) {
        if (_isCancelled) break;

        if (message is _WorkerControlPortMessage) {
          _workerControlPort = message.controlPort;
        } else if (message is _BatchMessage) {
          // Build Track models and batch upsert in one transaction.
          final tracks = message.items.map((item) {
            return Track(
              path: item.path,
              folderId: folderId,
              title: item.title,
              artist: item.artist,
              albumArtist: item.albumArtist,
              album: item.album,
              trackNo: item.trackNo,
              discNo: item.discNo,
              year: item.year,
              durationMs: item.durationMs,
              mtimeMs: item.mtimeMs,
              sizeBytes: item.sizeBytes,
              coverKey: item.coverKey,
              addedAt: DateTime.now().toUtc(),
            );
          }).toList();

          await repository.upsertTracks(tracks);

          totalAdded += message.addedInBatch;
          totalUpdated += message.updatedInBatch;

          progress = progress.copyWith(
            added: totalAdded,
            updated: totalUpdated,
            processed: message.totalProcessed,
            found: message.totalFound,
            errors: message.totalErrors,
          );
          yield progress;
        } else if (message is _ProgressUpdateMessage) {
          if (message.newCorruptPath != null) {
            corruptPaths.add(message.newCorruptPath!);
          }
          progress = progress.copyWith(
            found: message.found,
            processed: message.processed,
            errors: message.errors,
            corruptPaths: List.unmodifiable(corruptPaths),
          );
          yield progress;
        } else if (message is _ScanCompleteMessage) {
          if (message.unreadableDirs == 0 && message.missingPaths.isNotEmpty) {
            await repository.removeTracksByPath(message.missingPaths);
            totalRemoved = message.missingPaths.length;
          }

          if (!_isCancelled) {
            await repository.markFolderScanned(folderId, DateTime.now().toUtc());
          }

          await ensureLinksRebuilt();

          progress = progress.copyWith(
            found: message.totalFound,
            processed: message.totalProcessed,
            added: totalAdded,
            updated: totalUpdated,
            removed: totalRemoved,
            errors: message.totalErrors,
            unreadableDirs: message.unreadableDirs,
            corruptPaths: List.unmodifiable(message.corruptPaths),
            done: true,
          );
          yield progress;
          break;
        }
      }
    } finally {
      _cleanupIsolate();
      await ensureLinksRebuilt();
    }

    if (_isCancelled && !progress.done) {
      yield progress.copyWith(done: true);
    }
  }

  void _cleanupIsolate() {
    _workerControlPort = null;
    _activeReceivePort?.close();
    _activeReceivePort = null;
    _activeIsolate = null;
  }
}

// ── Background Isolate Implementation ──────────────────────────────────────

class _WorkerConfig {
  final SendPort sendPort;
  final String folderPath;
  final int folderId;
  final Map<String, ({int mtimeMs, int sizeBytes})> existingFiles;
  final TagReader tagReader;
  final String coversDirectory;
  final int batchSize;
  final List<String> unreadablePaths;

  const _WorkerConfig({
    required this.sendPort,
    required this.folderPath,
    required this.folderId,
    required this.existingFiles,
    required this.tagReader,
    required this.coversDirectory,
    required this.batchSize,
    this.unreadablePaths = const [],
  });
}

class _WorkerControlPortMessage {
  final SendPort controlPort;
  const _WorkerControlPortMessage(this.controlPort);
}

class _ScannedTrackItem {
  final String path;
  final String title;
  final String artist;
  final String? albumArtist;
  final String album;
  final int? trackNo;
  final int? discNo;
  final int? year;
  final int durationMs;
  final int mtimeMs;
  final int sizeBytes;
  final String? coverKey;

  const _ScannedTrackItem({
    required this.path,
    required this.title,
    required this.artist,
    this.albumArtist,
    required this.album,
    this.trackNo,
    this.discNo,
    this.year,
    required this.durationMs,
    required this.mtimeMs,
    required this.sizeBytes,
    this.coverKey,
  });
}

class _BatchMessage {
  final List<_ScannedTrackItem> items;
  final int addedInBatch;
  final int updatedInBatch;
  final int totalProcessed;
  final int totalFound;
  final int totalErrors;

  const _BatchMessage({
    required this.items,
    required this.addedInBatch,
    required this.updatedInBatch,
    required this.totalProcessed,
    required this.totalFound,
    required this.totalErrors,
  });
}

class _ProgressUpdateMessage {
  final int found;
  final int processed;
  final int errors;
  final String? newCorruptPath;

  const _ProgressUpdateMessage({
    required this.found,
    required this.processed,
    required this.errors,
    this.newCorruptPath,
  });
}

class _ScanCompleteMessage {
  final List<String> missingPaths;
  final int totalFound;
  final int totalProcessed;
  final int totalErrors;
  final int unreadableDirs;
  final List<String> corruptPaths;

  const _ScanCompleteMessage({
    required this.missingPaths,
    required this.totalFound,
    required this.totalProcessed,
    required this.totalErrors,
    this.unreadableDirs = 0,
    required this.corruptPaths,
  });
}

class _CancelSignal {
  const _CancelSignal();
}

void _scanWorkerEntry(_WorkerConfig config) async {
  final controlPort = ReceivePort();
  config.sendPort.send(_WorkerControlPortMessage(controlPort.sendPort));

  var isCancelled = false;
  controlPort.listen((message) {
    if (message is _CancelSignal) {
      isCancelled = true;
    }
  });

  final rootDir = Directory(config.folderPath);
  if (!rootDir.existsSync()) {
    config.sendPort.send(const _ScanCompleteMessage(
      missingPaths: [],
      totalFound: 0,
      totalProcessed: 0,
      totalErrors: 0,
      corruptPaths: [],
    ));
    controlPort.close();
    return;
  }

  final dirQueue = <Directory>[rootDir];
  final scannedPaths = <String>{};
  final corruptPaths = <String>[];
  final currentBatch = <_ScannedTrackItem>[];

  int foundCount = 0;
  int processedCount = 0;
  int addedInBatch = 0;
  int updatedInBatch = 0;
  int errorCount = 0;
  int unreadableDirsCount = 0;

  // Track albums that already have a cover key saved.
  final knownCoverKeys = <String, String>{};

  while (dirQueue.isNotEmpty && !isCancelled) {
    final currentDir = dirQueue.removeLast();
    List<FileSystemEntity> entities;

    try {
      if (config.unreadablePaths.contains(p.normalize(currentDir.path))) {
        throw const FileSystemException('Directory unreadable (simulated permission/IO error)');
      }
      entities = currentDir.listSync(followLinks: false);
    } catch (_) {
      unreadableDirsCount++;
      continue;
    }

    for (final entity in entities) {
      if (isCancelled) break;

      if (entity is Directory) {
        final dirName = p.basename(entity.path);
        if (_isIgnoredDirectory(dirName)) continue;
        dirQueue.add(entity);
      } else if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (!LibraryScanner.supportedExtensions.contains(ext)) continue;

        foundCount++;
        final filePath = p.normalize(entity.path);
        scannedPaths.add(filePath);

        FileStat stat;
        try {
          stat = entity.statSync();
        } catch (_) {
          errorCount++;
          corruptPaths.add(filePath);
          processedCount++;
          config.sendPort.send(_ProgressUpdateMessage(
            found: foundCount,
            processed: processedCount,
            errors: errorCount,
            newCorruptPath: filePath,
          ));
          continue;
        }

        final mtimeMs = stat.modified.millisecondsSinceEpoch;
        final sizeBytes = stat.size;
        final existing = config.existingFiles[filePath];

        if (existing != null &&
            existing.mtimeMs == mtimeMs &&
            existing.sizeBytes == sizeBytes) {
          // File unchanged: skip reading tags.
          processedCount++;
          if (processedCount % 50 == 0) {
            config.sendPort.send(_ProgressUpdateMessage(
              found: foundCount,
              processed: processedCount,
              errors: errorCount,
            ));
          }
          continue;
        }

        final isUpdate = existing != null;

        // Read tags with per-file try/catch.
        try {
          final tags = await config.tagReader.readTags(filePath, readCover: true);

          // Fallbacks when tags are missing:
          // title = file name without extension
          // album = parent folder name
          // artist = 'Unknown artist'
          final rawTitle = tags.title?.trim();
          final title = (rawTitle != null && rawTitle.isNotEmpty)
              ? rawTitle
              : p.basenameWithoutExtension(filePath);

          final rawAlbum = tags.album?.trim();
          final parentDirName = p.basename(p.dirname(filePath)).trim();
          final album = (rawAlbum != null && rawAlbum.isNotEmpty)
              ? rawAlbum
              : (parentDirName.isNotEmpty ? parentDirName : 'Unknown Album');

          final rawArtist = tags.artist?.trim();
          final artist = (rawArtist != null && rawArtist.isNotEmpty)
              ? rawArtist
              : 'Unknown artist';

          final rawAlbumArtist = tags.albumArtist?.trim();
          final albumArtist = (rawAlbumArtist != null && rawAlbumArtist.isNotEmpty)
              ? rawAlbumArtist
              : null;

          final durationMs = tags.durationMs ?? 0;

          // Cover art handling: save ONE embedded cover per album to covers folder.
          final albumKey = CoverCache.computeCoverKey(
            albumArtist: albumArtist,
            album: album,
          );

          String? coverKey;
          if (tags.embeddedCover != null && tags.embeddedCover!.isNotEmpty) {
            coverKey = CoverCache.saveCoverSync(
              albumArtist: albumArtist,
              album: album,
              bytes: tags.embeddedCover!,
              coversDirectory: config.coversDirectory,
            );
            knownCoverKeys[albumKey] = coverKey;
          } else {
            if (knownCoverKeys.containsKey(albumKey)) {
              coverKey = knownCoverKeys[albumKey];
            } else if (CoverCache.hasCover(
              albumKey,
              coversDirectory: config.coversDirectory,
            )) {
              coverKey = albumKey;
              knownCoverKeys[albumKey] = albumKey;
            }
          }

          currentBatch.add(_ScannedTrackItem(
            path: filePath,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            trackNo: tags.trackNo,
            discNo: tags.discNo,
            year: tags.year,
            durationMs: durationMs,
            mtimeMs: mtimeMs,
            sizeBytes: sizeBytes,
            coverKey: coverKey,
          ));

          processedCount++;
          if (isUpdate) {
            updatedInBatch++;
          } else {
            addedInBatch++;
          }

          if (currentBatch.length >= config.batchSize) {
            config.sendPort.send(_BatchMessage(
              items: List.of(currentBatch),
              addedInBatch: addedInBatch,
              updatedInBatch: updatedInBatch,
              totalProcessed: processedCount,
              totalFound: foundCount,
              totalErrors: errorCount,
            ));
            currentBatch.clear();
            addedInBatch = 0;
            updatedInBatch = 0;
          }
        } catch (e) {
          // Per-file try/catch: a corrupt file never stops the scan; count it and record the path.
          errorCount++;
          corruptPaths.add(filePath);
          processedCount++;
          config.sendPort.send(_ProgressUpdateMessage(
            found: foundCount,
            processed: processedCount,
            errors: errorCount,
            newCorruptPath: filePath,
          ));
        }
      }
    }
  }

  // Flush remaining batch.
  if (currentBatch.isNotEmpty && !isCancelled) {
    config.sendPort.send(_BatchMessage(
      items: List.of(currentBatch),
      addedInBatch: addedInBatch,
      updatedInBatch: updatedInBatch,
      totalProcessed: processedCount,
      totalFound: foundCount,
      totalErrors: errorCount,
    ));
    currentBatch.clear();
  }

  // Detect removed files: tracks in database whose files are no longer on disk.
  // If any directory listing failed (permission/IO error), skip the removal of
  // missing tracks for that scan to protect existing library tracks.
  final missingPaths = unreadableDirsCount > 0
      ? const <String>[]
      : config.existingFiles.keys
          .where((path) => !scannedPaths.contains(path))
          .toList();

  config.sendPort.send(_ScanCompleteMessage(
    missingPaths: missingPaths,
    totalFound: foundCount,
    totalProcessed: processedCount,
    totalErrors: errorCount,
    unreadableDirs: unreadableDirsCount,
    corruptPaths: corruptPaths,
  ));

  controlPort.close();
}

bool _isIgnoredDirectory(String name) {
  final lower = name.toLowerCase();
  return lower.startsWith('.') ||
      lower.startsWith(r'$') ||
      lower == 'system volume information';
}
