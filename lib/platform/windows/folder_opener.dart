/// Windows Explorer helper for opening diagnostic log and backup directories.
library;

import 'dart:io';

/// Callback signature for opening a local folder path in the OS file manager.
typedef FolderOpener = Future<void> Function(String path);

/// Opens [path] in Windows Explorer without blocking.
///
/// Creates [path] if missing when possible, and safely no-ops off Windows or
/// if the directory cannot be opened.
Future<void> openFolderInExplorer(String path) async {
  if (path.trim().isEmpty || !Platform.isWindows) return;
  try {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    await Process.start('explorer.exe', [dir.path]);
  } catch (_) {}
}
