import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../library/file_path_utils.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/user_data_access_mode.dart';
import '../../ui/l10n/app_strings.dart';
import '../../ui/l10n/number_format.dart';
import 'user_collections.dart';

/// Function signature for picking a save file path and writing bytes.
typedef M3uSaveFilePicker = Future<String?> Function({
  required String fileName,
  required Uint8List bytes,
  String? dialogTitle,
});

/// Function signature for picking a destination folder when exporting M3U files.
typedef M3uDirectoryPicker = Future<String?> Function({
  String? dialogTitle,
});

/// Function signature for picking one or more playlist file paths.
typedef M3uPickFilesPicker = Future<List<String>?> Function({
  String? dialogTitle,
  List<String>? allowedExtensions,
  bool allowMultiple,
});

/// Function signature for reading the string content of a file.
typedef M3uFileContentReader = Future<String> Function(String filePath);

/// Reasons why an M3U export destination path is refused.
enum M3uExportRefusalReason {
  /// Target extension is a known audio file format.
  audioExtension,

  /// Target already exists and does not end in `.m3u` or `.m3u8`.
  existingNonPlaylistFile,
}

/// Result of validating an M3U export target path.
class M3uExportValidationResult {
  /// Whether export to [targetPath] is allowed.
  final bool isAllowed;

  /// Normalized target path with `.m3u`/`.m3u8` enforced when allowed.
  final String? targetPath;

  /// Whether an existing `.m3u`/`.m3u8` file will be overwritten.
  final bool requiresOverwriteConfirmation;

  /// Reason the export was refused, when [isAllowed] is `false`.
  final M3uExportRefusalReason? refusalReason;

  /// Conflicting extension (for [M3uExportRefusalReason.audioExtension]).
  final String? extension;

  /// Conflicting file name (for [M3uExportRefusalReason.existingNonPlaylistFile]).
  final String? fileName;

  const M3uExportValidationResult._({
    required this.isAllowed,
    this.targetPath,
    this.requiresOverwriteConfirmation = false,
    this.refusalReason,
    this.extension,
    this.fileName,
  });

  /// Creates an allowed validation result for [targetPath].
  const M3uExportValidationResult.allowed({
    required String targetPath,
    required bool requiresOverwriteConfirmation,
  }) : this._(
          isAllowed: true,
          targetPath: targetPath,
          requiresOverwriteConfirmation: requiresOverwriteConfirmation,
        );

  /// Creates a refused validation result.
  const M3uExportValidationResult.refused({
    required M3uExportRefusalReason reason,
    String? extension,
    String? fileName,
  }) : this._(
          isAllowed: false,
          refusalReason: reason,
          extension: extension,
          fileName: fileName,
        );
}

/// Result of parsing an M3U or M3U8 playlist file.
class M3uParseResult {
  /// Ordered list of resolved local file paths.
  final List<String> paths;

  /// Optional playlist name extracted from `#PLAYLIST:` header.
  final String? playlistName;

  /// Count of web streams (e.g. `http://` or `https://`) that were skipped.
  final int skippedWebLinks;

  /// Display titles parsed from `#EXTINF` lines, keyed by resolved track path.
  final Map<String, String> extinfTitles;

  /// Creates an [M3uParseResult].
  const M3uParseResult({
    required this.paths,
    this.playlistName,
    this.skippedWebLinks = 0,
    this.extinfTitles = const {},
  });
}

/// Summary of an M3U / M3U8 playlist import operation.
class M3uImportSummary {
  /// Newly created playlist summary, or `null` if cancelled/failed.
  final PlaylistSummary? playlist;

  /// Total imported entry count.
  final int addedCount;

  /// Number of imported paths missing from the indexed library.
  final int missingCount;

  /// Paths missing from the indexed library.
  final List<String> missingPaths;

  /// Count of skipped HTTP/HTTPS web links.
  final int skippedWebLinks;

  /// Creates an [M3uImportSummary].
  const M3uImportSummary({
    required this.playlist,
    required this.addedCount,
    required this.missingCount,
    required this.missingPaths,
    required this.skippedWebLinks,
  });
}

/// Pure functions and service helpers for M3U / M3U8 serialization and parsing.
abstract final class M3u {
  /// Audio extensions that M3U export must always refuse to write or overwrite.
  static const Set<String> knownAudioExtensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.wav',
    '.ogg',
    '.opus',
    '.wma',
    '.aac',
    '.alac',
    '.ape',
    '.wv',
    '.aiff',
    '.dsf',
    '.dff',
  };

  /// File extensions allowed for M3U playlist export.
  static const Set<String> allowedPlaylistExtensions = {'.m3u', '.m3u8'};

  /// Builds an extended M3U string from [entries] and optional [playlistName].
  static String buildM3u(
    List<PlaylistEntry> entries, {
    String? playlistName,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('#EXTM3U');
    if (playlistName != null && playlistName.trim().isNotEmpty) {
      buffer.writeln('#PLAYLIST:${playlistName.trim()}');
    }

    for (final entry in entries) {
      final track = entry.track;
      if (track != null) {
        final seconds = (track.durationMs / 1000).round();
        final rawArtist = track.artist;
        final rawTitle = track.title;
        final title = (rawTitle != null && rawTitle.isNotEmpty)
            ? rawTitle
            : p.basenameWithoutExtension(entry.path);
        final artist = (rawArtist != null && rawArtist.isNotEmpty) ? rawArtist : '';

        final display = artist.isNotEmpty ? '$artist - $title' : title;
        buffer.writeln('#EXTINF:$seconds,$display');
      } else {
        final filename = p.basenameWithoutExtension(entry.path);
        buffer.writeln('#EXTINF:-1,$filename');
      }
      buffer.writeln(entry.path);
    }

    return buffer.toString();
  }

  /// Parses an M3U string, stripping BOM, resolving relative paths against
  /// [baseDirectory], handling `file://` URIs and `#EXTINF`, and counting
  /// skipped web links.
  static M3uParseResult parseM3u(
    String content, {
    required String baseDirectory,
  }) {
    var text = content;
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }

    final lines = const LineSplitter().convert(text);
    final paths = <String>[];
    final extinfTitles = <String, String>{};
    String? playlistName;
    String? pendingExtinfTitle;
    var skippedWebLinks = 0;

    for (var rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#')) {
        final upper = line.toUpperCase();
        if (upper.startsWith('#PLAYLIST:')) {
          final namePart = line.substring(10).trim();
          if (namePart.isNotEmpty && playlistName == null) {
            playlistName = namePart;
          }
          pendingExtinfTitle = null;
        } else if (upper.startsWith('#EXTINF:')) {
          final commaIdx = line.indexOf(',');
          if (commaIdx != -1) {
            final title = line.substring(commaIdx + 1).trim();
            pendingExtinfTitle = title.isNotEmpty ? title : null;
          }
        }
        continue;
      }

      // Check for web streams (http / https)
      final lower = line.toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://')) {
        skippedWebLinks++;
        pendingExtinfTitle = null;
        continue;
      }

      // Resolve relative or file:// URI path against baseDirectory
      final resolved = _resolvePath(line, baseDirectory);
      paths.add(resolved);
      if (pendingExtinfTitle != null) {
        extinfTitles[resolved] = pendingExtinfTitle;
        pendingExtinfTitle = null;
      }
    }

    return M3uParseResult(
      paths: paths,
      playlistName: playlistName,
      skippedWebLinks: skippedWebLinks,
      extinfTitles: extinfTitles,
    );
  }

  static String _resolvePath(String pathStr, String baseDirectory) {
    final decoded = FilePathUtils.fromUriOrPath(pathStr);
    final isWinAbsolute = RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(decoded) ||
        decoded.startsWith(r'\\');
    final isPosixAbsolute = !isWinAbsolute && decoded.startsWith('/');

    if (isWinAbsolute) {
      if (decoded.contains(r'\')) {
        return p.windows.normalize(decoded);
      }
      return p.posix.normalize(decoded);
    }

    if (isPosixAbsolute) {
      return p.posix.normalize(decoded);
    }

    final useWindowsStyle =
        decoded.contains(r'\') || baseDirectory.contains(r'\');
    if (useWindowsStyle) {
      return p.windows.normalize(p.windows.join(baseDirectory, decoded));
    }
    return p.posix.normalize(p.posix.join(baseDirectory, decoded));
  }

  /// Validates an M3U export target path before writing anything to disk.
  ///
  /// - Refuses any known audio extension in [knownAudioExtensions].
  /// - Refuses any existing file whose extension is not `.m3u`/`.m3u8`.
  /// - Forces a `.m3u8` extension when [rawPath] does not already end in `.m3u`/`.m3u8`.
  /// - Marks [M3uExportValidationResult.requiresOverwriteConfirmation] when the
  ///   final `.m3u`/`.m3u8` file already exists.
  static M3uExportValidationResult validateExportTarget(
    String rawPath, {
    bool Function(String path)? fileExists,
  }) {
    final trimmed = rawPath.trim();
    final ext = p.extension(trimmed).toLowerCase();
    final exists = fileExists ?? (path) => File(path).existsSync();

    if (knownAudioExtensions.contains(ext)) {
      return M3uExportValidationResult.refused(
        reason: M3uExportRefusalReason.audioExtension,
        extension: ext,
      );
    }

    if (!allowedPlaylistExtensions.contains(ext) && exists(trimmed)) {
      return M3uExportValidationResult.refused(
        reason: M3uExportRefusalReason.existingNonPlaylistFile,
        fileName: p.basename(trimmed),
      );
    }

    final finalPath = allowedPlaylistExtensions.contains(ext)
        ? trimmed
        : (trimmed.endsWith('.') ? '${trimmed}m3u8' : '$trimmed.m3u8');

    return M3uExportValidationResult.allowed(
      targetPath: finalPath,
      requiresOverwriteConfirmation: exists(finalPath),
    );
  }

  /// Atomically writes [bytes] to a `.m3u`/`.m3u8` file at [targetPath] using a
  /// temporary sibling file, `flush: true`, and `rename`.
  static Future<void> writeM3uAtomically(
    String targetPath,
    Uint8List bytes,
  ) async {
    final ext = p.extension(targetPath).toLowerCase();
    if (!allowedPlaylistExtensions.contains(ext)) {
      throw ArgumentError.value(
        targetPath,
        'targetPath',
        'M3U export may only write .m3u or .m3u8 files.',
      );
    }

    final targetFile = File(targetPath);
    final parent = targetFile.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }

    final tmpFile = File(
      p.join(
        parent.path,
        '.${p.basename(targetPath)}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );

    try {
      tmpFile.writeAsBytesSync(bytes, flush: true);
      tmpFile.renameSync(targetFile.path);
    } catch (_) {
      try {
        if (tmpFile.existsSync()) {
          tmpFile.deleteSync();
        }
      } catch (_) {}
      rethrow;
    }
  }

  static Future<bool> _defaultConfirmOverwrite(
    BuildContext context,
    String fileName,
  ) async {
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E22),
          title: Text(dialogCtx.t('m3u.overwriteTitle')),
          content: Text(
            dialogCtx.t('m3u.overwriteMessage', args: {'name': fileName}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(dialogCtx.t('common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(dialogCtx.t('m3u.overwriteConfirm')),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  /// Exports [playlist] to a validated `.m3u`/`.m3u8` file with UTF-8 BOM.
  static Future<bool> exportPlaylist(
    BuildContext context, {
    required LibraryRepository repository,
    required PlaylistSummary playlist,
    M3uSaveFilePicker? saveFilePicker,
    M3uDirectoryPicker? pickDirectory,
    Future<bool> Function(BuildContext context, String fileName)?
        confirmOverwrite,
  }) async {
    try {
      final dialogTitle = context.t('playlist.exportM3u');
      final sanitizedName =
          playlist.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final entries = await repository.playlistEntries(playlist.id);
      final m3uContent = buildM3u(entries, playlistName: playlist.name);
      final bytes = Uint8List.fromList(utf8.encode('\uFEFF$m3uContent'));

      final String? rawTargetPath;
      if (saveFilePicker != null) {
        rawTargetPath = await saveFilePicker(
          fileName: '$sanitizedName.m3u8',
          bytes: bytes,
          dialogTitle: dialogTitle,
        );
      } else {
        final dir = await (pickDirectory ??
            ({String? dialogTitle}) => FilePicker.getDirectoryPath(
                  dialogTitle: dialogTitle,
                ))(dialogTitle: dialogTitle);
        rawTargetPath = (dir != null && dir.trim().isNotEmpty)
            ? p.join(dir, '$sanitizedName.m3u8')
            : null;
      }

      if (rawTargetPath == null || rawTargetPath.trim().isEmpty) return false;

      final validation = validateExportTarget(rawTargetPath);
      if (!validation.isAllowed) {
        if (context.mounted) {
          final String message =
              validation.refusalReason == M3uExportRefusalReason.audioExtension
                  ? context.t(
                      'm3u.exportRefusedAudio',
                      args: {'ext': validation.extension ?? ''},
                    )
                  : context.t(
                      'm3u.exportRefusedOtherFile',
                      args: {'name': validation.fileName ?? ''},
                    );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return false;
      }

      final targetPath = validation.targetPath!;
      if (validation.requiresOverwriteConfirmation) {
        if (!context.mounted) return false;
        final confirmed = await (confirmOverwrite ?? _defaultConfirmOverwrite)(
          context,
          p.basename(targetPath),
        );
        if (!confirmed) return false;
      }

      await writeM3uAtomically(targetPath, bytes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t('m3u.exportSuccess')),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return true;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t('m3u.exportFailed')),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
  }

  /// Imports an M3U / M3U8 playlist file, registers it in [collections], and
  /// returns a structured [M3uImportSummary] containing missing file details.
  static Future<M3uImportSummary?> importPlaylistWithSummary(
    BuildContext context, {
    required LibraryRepository repository,
    required UserCollections collections,
    M3uPickFilesPicker? pickFilesPicker,
    M3uFileContentReader? fileContentReader,
  }) async {
    if (repository.userDataAccessMode == UserDataAccessMode.safeReadOnly) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t('userdata.safeReadOnlyBlocked')),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    }
    try {
      List<String>? pickedPaths;
      if (pickFilesPicker != null) {
        pickedPaths = await pickFilesPicker(
          dialogTitle: context.t('playlist.importM3u'),
          allowedExtensions: const ['m3u', 'm3u8'],
          allowMultiple: false,
        );
      } else {
        final files = await FilePicker.pickFiles(
          dialogTitle: context.t('playlist.importM3u'),
          type: FileType.custom,
          allowedExtensions: const ['m3u', 'm3u8'],
        );
        if (files.isNotEmpty) {
          pickedPaths = files.map((f) => f.path).whereType<String>().toList();
        }
      }

      if (pickedPaths == null || pickedPaths.isEmpty) return null;
      final filePath = pickedPaths.first;

      final String content;
      if (fileContentReader != null) {
        content = await fileContentReader(filePath);
      } else {
        final file = File(filePath);
        content = await file.readAsString(encoding: utf8);
      }
      final baseDir = filePath.contains(r'\')
          ? p.windows.dirname(filePath)
          : p.dirname(filePath);

      final parseResult = parseM3u(content, baseDirectory: baseDir);

      // Determine unique playlist name
      final fallbackName = filePath.contains(r'\')
          ? p.windows.basenameWithoutExtension(filePath)
          : p.basenameWithoutExtension(filePath);
      var candidateName = (parseResult.playlistName != null &&
              parseResult.playlistName!.trim().isNotEmpty)
          ? parseResult.playlistName!.trim()
          : fallbackName;

      if (candidateName.length > 60) {
        candidateName = candidateName.substring(0, 60).trim();
      }

      var uniqueName = candidateName;
      var counter = 2;
      while (collections.playlists.any(
        (pl) => pl.name.trim().toLowerCase() == uniqueName.toLowerCase(),
      )) {
        final suffix = ' ($counter)';
        final maxBaseLen = 60 - suffix.length;
        final base = candidateName.length > maxBaseLen
            ? candidateName.substring(0, maxBaseLen).trim()
            : candidateName;
        uniqueName = '$base$suffix';
        counter++;
      }

      final created = await collections.createPlaylist(uniqueName);
      if (parseResult.paths.isNotEmpty) {
        await collections.addToPlaylist(created.id, parseResult.paths);
      }

      final entries = await repository.playlistEntries(created.id);
      final missingPaths =
          entries.where((e) => e.track == null).map((e) => e.path).toList();
      final missingCount = missingPaths.length;
      final addedCount = parseResult.paths.length;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t(
                'm3u.importResult',
                args: {
                  'added': context.formatCountLocalized(addedCount),
                  'missing': context.formatCountLocalized(missingCount),
                  'skipped':
                      context.formatCountLocalized(parseResult.skippedWebLinks),
                },
              ),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }

      return M3uImportSummary(
        playlist: created,
        addedCount: addedCount,
        missingCount: missingCount,
        missingPaths: missingPaths,
        skippedWebLinks: parseResult.skippedWebLinks,
      );
    } on UserDataReadOnlyException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t(e.messageKey)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t('m3u.importFailed')),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    }
  }

  /// Imports an M3U / M3U8 playlist file and registers it in [collections].
  static Future<PlaylistSummary?> importPlaylist(
    BuildContext context, {
    required LibraryRepository repository,
    required UserCollections collections,
    M3uPickFilesPicker? pickFilesPicker,
    M3uFileContentReader? fileContentReader,
  }) async {
    final summary = await importPlaylistWithSummary(
      context,
      repository: repository,
      collections: collections,
      pickFilesPicker: pickFilesPicker,
      fileContentReader: fileContentReader,
    );
    return summary?.playlist;
  }
}
