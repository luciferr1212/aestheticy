import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../ui/l10n/app_strings.dart';
import '../../ui/l10n/number_format.dart';
import 'user_collections.dart';

/// Function signature for picking a save file path and writing bytes.
typedef M3uSaveFilePicker = Future<String?> Function({
  required String fileName,
  required Uint8List bytes,
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

/// Result of parsing an M3U or M3U8 playlist file.
class M3uParseResult {
  /// Ordered list of resolved local file paths.
  final List<String> paths;

  /// Optional playlist name extracted from `#PLAYLIST:` header.
  final String? playlistName;

  /// Count of web streams (e.g. `http://` or `https://`) that were skipped.
  final int skippedWebLinks;

  /// Creates an [M3uParseResult].
  const M3uParseResult({
    required this.paths,
    this.playlistName,
    this.skippedWebLinks = 0,
  });
}

/// Pure functions and service helpers for M3U / M3U8 serialization and parsing.
abstract final class M3u {
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
  /// [baseDirectory], and counting skipped web links.
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
    String? playlistName;
    var skippedWebLinks = 0;

    for (var rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#')) {
        if (line.toUpperCase().startsWith('#PLAYLIST:')) {
          final namePart = line.substring(10).trim();
          if (namePart.isNotEmpty && playlistName == null) {
            playlistName = namePart;
          }
        }
        continue;
      }

      // Check for web streams (http / https)
      final lower = line.toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://')) {
        skippedWebLinks++;
        continue;
      }

      // Resolve relative path against baseDirectory
      final resolved = _resolvePath(line, baseDirectory);
      paths.add(resolved);
    }

    return M3uParseResult(
      paths: paths,
      playlistName: playlistName,
      skippedWebLinks: skippedWebLinks,
    );
  }

  static String _resolvePath(String pathStr, String baseDirectory) {
    // If path is absolute on Windows or POSIX:
    // e.g. "C:\...", "\\server\...", "/..."
    final isAbsoluteWin = RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(pathStr) ||
        pathStr.startsWith(r'\\') ||
        pathStr.startsWith('/');
    final raw = isAbsoluteWin ? pathStr : p.join(baseDirectory, pathStr);
    return p.normalize(raw).replaceAll(r'\', '/');
  }

  /// Exports [playlist] to an M3U8 file with UTF-8 BOM.
  static Future<bool> exportPlaylist(
    BuildContext context, {
    required LibraryRepository repository,
    required PlaylistSummary playlist,
    M3uSaveFilePicker? saveFilePicker,
  }) async {
    try {
      final dialogTitle = context.t('playlist.exportM3u');
      final sanitizedName =
          playlist.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final entries = await repository.playlistEntries(playlist.id);
      final m3uContent = buildM3u(entries, playlistName: playlist.name);
      final bytes = Uint8List.fromList(utf8.encode('\uFEFF$m3uContent'));

      final String? targetPath;
      if (saveFilePicker != null) {
        targetPath = await saveFilePicker(
          fileName: '$sanitizedName.m3u8',
          bytes: bytes,
          dialogTitle: dialogTitle,
        );
      } else {
        final uri = await FilePicker.saveFile(
          dialogTitle: dialogTitle,
          fileName: '$sanitizedName.m3u8',
          bytes: bytes,
        );
        targetPath = uri?.toFilePath();
        if (targetPath != null) {
          final file = File(targetPath);
          if (!file.existsSync()) {
            await file.writeAsBytes(bytes, flush: true);
          }
        }
      }

      if (targetPath == null) return false;

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

  /// Imports an M3U / M3U8 playlist file and registers it in [collections].
  static Future<PlaylistSummary?> importPlaylist(
    BuildContext context, {
    required LibraryRepository repository,
    required UserCollections collections,
    M3uPickFilesPicker? pickFilesPicker,
    M3uFileContentReader? fileContentReader,
  }) async {
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
      final baseDir = p.dirname(filePath);

      final parseResult = parseM3u(content, baseDirectory: baseDir);

      // Determine unique playlist name
      var candidateName = (parseResult.playlistName != null &&
              parseResult.playlistName!.trim().isNotEmpty)
          ? parseResult.playlistName!.trim()
          : p.basenameWithoutExtension(filePath);

      if (candidateName.length > 60) {
        candidateName = candidateName.substring(0, 60).trim();
      }

      var uniqueName = candidateName;
      var counter = 2;
      while (collections.playlists.any(
        (p) => p.name.trim().toLowerCase() == uniqueName.toLowerCase(),
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
      final missingCount = entries.where((e) => e.track == null).length;
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

      return created;
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
}
