/// Windows Explorer helper for opening diagnostic log and backup directories.
library;

import 'dart:io';

import '../../core/result.dart';
import '../../diagnostics/app_logger.dart';

/// Callback signature for opening a local folder path in the OS file manager.
typedef FolderOpener = Future<void> Function(String path);

/// Opens [path] in Windows Explorer without blocking.
///
/// Creates [path] if missing when possible, logs failures via [AppLogger], and
/// invokes optional [onError] when launching Explorer fails.
Future<void> openFolderInExplorer(
  String path, {
  void Function(AppError error)? onError,
}) async {
  if (path.trim().isEmpty || !Platform.isWindows) return;
  try {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    await Process.start('explorer.exe', [dir.path]);
  } catch (e, st) {
    AppLogger.instance.warn(
      'FolderOpener',
      'Failed opening folder in Explorer',
      e,
      st,
    );
    onError?.call(AppError.fromException(e, st));
  }
}
