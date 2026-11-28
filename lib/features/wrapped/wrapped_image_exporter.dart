import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../diagnostics/app_logger.dart';

/// Result of validating a target export file path before writing PNG bytes.
class WrappedExportValidationResult {
  /// Whether [targetPath] is a valid `.png` export destination.
  final bool isAllowed;

  /// Canonicalized target `.png` file path when [isAllowed] is true.
  final String? targetPath;

  /// True when an existing `.png` file already exists at [targetPath] and must
  /// not be overwritten without explicit user confirmation.
  final bool requiresOverwriteConfirmation;

  /// Rejected file extension (for error reporting/logging) when not `.png`.
  final String? rejectedExtension;

  const WrappedExportValidationResult._({
    required this.isAllowed,
    this.targetPath,
    this.requiresOverwriteConfirmation = false,
    this.rejectedExtension,
  });

  /// Creates an allowed validation result.
  const WrappedExportValidationResult.allowed({
    required String targetPath,
    required bool requiresOverwriteConfirmation,
  }) : this._(
         isAllowed: true,
         targetPath: targetPath,
         requiresOverwriteConfirmation: requiresOverwriteConfirmation,
       );

  /// Creates a refused validation result for non-`.png` targets.
  const WrappedExportValidationResult.refused({String? rejectedExtension})
    : this._(isAllowed: false, rejectedExtension: rejectedExtension);
}

/// Validates share-image export paths and writes `.png` files atomically using
/// a temporary sibling file, `flush: true`, and `renameSync`.
///
/// Audio files and any non-`.png` target paths are unconditionally refused.
abstract final class WrappedImageExporter {
  /// Validates that [rawPath] targets strictly a `.png` file and checks whether
  /// an existing `.png` file requires explicit overwrite confirmation.
  static WrappedExportValidationResult validateTargetPath(
    String rawPath, {
    bool Function(String path)? fileExists,
  }) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return const WrappedExportValidationResult.refused(rejectedExtension: '');
    }
    final ext = p.extension(trimmed).toLowerCase();
    if (ext != '.png') {
      return WrappedExportValidationResult.refused(rejectedExtension: ext);
    }
    final exists = fileExists ?? (path) => File(path).existsSync();
    return WrappedExportValidationResult.allowed(
      targetPath: trimmed,
      requiresOverwriteConfirmation: exists(trimmed),
    );
  }

  /// Atomically writes [bytes] to a `.png` file at [targetPath] via a temporary
  /// sibling file, `flush: true`, and atomic rename.
  static Future<void> writePngAtomically(
    String targetPath,
    Uint8List bytes,
  ) async {
    final ext = p.extension(targetPath).toLowerCase();
    if (ext != '.png') {
      throw ArgumentError.value(
        targetPath,
        'targetPath',
        'Recap image export may only write .png files.',
      );
    }
    if (bytes.length < 8) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'PNG payload is empty or invalid.',
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
    } catch (e, st) {
      AppLogger.instance.error(
        'WrappedExport',
        'Atomic PNG write failed for ${p.basename(targetPath)}',
        e,
        st,
      );
      try {
        if (tmpFile.existsSync()) {
          tmpFile.deleteSync();
        }
      } catch (delErr, delSt) {
        // ignore-silent: deleting temporary .tmp file created by writePngAtomically
        AppLogger.instance.debug(
          'WrappedExport',
          'Failed cleaning up temporary PNG export file',
          delErr,
          delSt,
        );
      }
      rethrow;
    }
  }
}
