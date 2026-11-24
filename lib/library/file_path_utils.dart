/// Pure Dart helpers for normalizing local filesystem paths and `file://` URIs
/// into canonical keys for cross-format comparison.
library;

import 'package:path/path.dart' as p;

/// Pure utilities for converting between `file://` URIs and filesystem paths.
abstract final class FilePathUtils {
  /// Returns `true` when [value] uses Windows drive/UNC syntax or backslashes.
  static bool isWindowsPath(String value) {
    final trimmed = value.trim();
    return RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(trimmed) ||
        trimmed.startsWith(r'\\') ||
        trimmed.contains(r'\');
  }

  /// Converts a `file://` URI into a plain filesystem path, or returns [raw]
  /// trimmed if it is already a plain path.
  static String fromUriOrPath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length >= 7 &&
        trimmed.substring(0, 7).toLowerCase() == 'file://') {
      final afterScheme = trimmed.substring(7);

      // Handle malformed 2-slash Windows drive URIs like "file://C:/song.mp3".
      if (RegExp(r'^[a-zA-Z]:($|[/\\])').hasMatch(afterScheme)) {
        var decoded = afterScheme;
        try {
          decoded = Uri.decodeFull(decoded);
        } catch (_) {}
        return decoded.replaceAll('/', r'\');
      }

      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.scheme.toLowerCase() == 'file') {
        try {
          if (uri.host.isNotEmpty) {
            return uri.toFilePath(windows: true);
          }
          if (RegExp(r'^/[a-zA-Z]:($|[/\\])').hasMatch(uri.path)) {
            return uri.toFilePath(windows: true);
          }
          return uri.toFilePath(windows: false);
        } catch (_) {
          // Fall through to best-effort manual decode below.
        }
      }

      var rest = afterScheme;
      try {
        rest = Uri.decodeFull(rest);
      } catch (_) {}
      if (RegExp(r'^/[a-zA-Z]:($|[/\\])').hasMatch(rest)) {
        return rest.substring(1).replaceAll('/', r'\');
      }
      if (!rest.startsWith('/')) {
        return '\\\\${rest.replaceAll('/', r'\')}';
      }
      return rest;
    }
    return trimmed;
  }

  /// Produces a canonical comparison key for [raw] (accepting plain Windows,
  /// POSIX, or `file://` URI inputs) so equivalent paths compare equal.
  static String canonicalKey(String raw) {
    final plain = fromUriOrPath(raw);
    if (plain.isEmpty) return '';

    final isUnc = plain.startsWith(r'\\') || plain.startsWith('//');
    var unified = plain.replaceAll(r'\', '/');

    if (RegExp(r'^/[a-zA-Z]:/').hasMatch(unified)) {
      unified = unified.substring(1);
    }

    if (isUnc) {
      final withoutPrefix = unified.replaceFirst(RegExp(r'^/+'), '');
      final normalized = p.posix.normalize(withoutPrefix);
      return '//$normalized'.toLowerCase();
    }

    final normalized = p.posix.normalize(unified);
    if (RegExp(r'^[a-zA-Z]:(/|$)').hasMatch(normalized)) {
      return normalized.toLowerCase();
    }
    return normalized;
  }
}
