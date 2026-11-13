import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../diagnostics/app_logger.dart';
import '../../features/persistence/atomic_file_writer.dart';
import '../glass/glass_scope.dart';
import 'app_settings.dart';

/// Single source of truth managing UI settings persistence and in-memory state.
class SettingsStore extends ChangeNotifier {
  Future<Directory> Function()? _directoryProvider;
  Directory? _directory;
  AppSettings _settings;
  Timer? _debounceTimer;
  AtomicFileWriter? _writer;

  /// Creates a [SettingsStore] with an optional injected [directory] or [directoryProvider].
  SettingsStore({
    Future<Directory> Function()? directoryProvider,
    Directory? directory,
    AppSettings initialSettings = const AppSettings(),
  }) : _settings = initialSettings {
    _directoryProvider = directoryProvider;
    _directory = directory;
    if (directory != null) {
      _writer =
          AtomicFileWriter(File(p.join(directory.path, 'ui_settings.json')));
    }
  }

  /// Current immutable application settings.
  AppSettings get settings => _settings;

  AtomicFileWriter? _getWriter() {
    if (_writer != null) return _writer;
    if (_directory != null) {
      return _writer =
          AtomicFileWriter(File(p.join(_directory!.path, 'ui_settings.json')));
    }
    return null;
  }

  /// Initializes the store and loads settings from disk.
  Future<void> init() async {
    try {
      if (_directory == null) {
        final provider = _directoryProvider;
        if (provider != null) {
          _directory = await provider();
        } else {
          final supportDir = await getApplicationSupportDirectory();
          _directory = Directory(p.join(supportDir.path, 'Aestheticy'));
        }
      }
      if (!_directory!.existsSync()) {
        _directory!.createSync(recursive: true);
      }
      _writer ??=
          AtomicFileWriter(File(p.join(_directory!.path, 'ui_settings.json')));
      await _loadFromFile();
    } catch (_) {
      // Keep in-memory defaults, never throw to the UI
    }
  }

  /// Updates settings using [updater] and schedules a debounced atomic write.
  void update(AppSettings Function(AppSettings current) updater) {
    _settings = updater(_settings);
    notifyListeners();
    _scheduleWrite();
  }

  /// Binds [controller] to this store so the store remains the single source of truth.
  void bindGlassController(GlassController controller) {
    controller.quality = _settings.glassQuality;
    controller.reduceMotion = _settings.reduceMotion;
    addListener(() {
      controller.quality = _settings.glassQuality;
      controller.reduceMotion = _settings.reduceMotion;
    });
  }

  Future<void> _loadFromFile() async {
    if (_directory == null) return;
    final file = File(p.join(_directory!.path, 'ui_settings.json'));
    if (!file.existsSync()) {
      return;
    }

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, Object?>) {
        _settings = AppSettings.fromJson(decoded);
      } else if (decoded is Map) {
        _settings =
            AppSettings.fromJson(Map<String, Object?>.from(decoded));
      } else {
        _handleCorruptFile(file);
      }
    } catch (_) {
      _handleCorruptFile(file);
    }
  }

  void _handleCorruptFile(File file) {
    _settings = const AppSettings();
    AppLogger.instance.warning(
      'Settings',
      'Corrupt ui_settings.json backed up to ui_settings.json.bad',
    );
    try {
      final badPath = p.join(_directory!.path, 'ui_settings.json.bad');
      file.renameSync(badPath);
    } catch (_) {
      // Ignore renaming errors, never crash
    }
  }

  void _scheduleWrite() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _writeToDisk();
    });
  }

  Future<void> _writeToDisk() async {
    final writer = _getWriter();
    if (writer == null) return;
    try {
      final jsonStr =
          const JsonEncoder.withIndent('  ').convert(_settings.toJson());
      await writer.write(jsonStr);
    } catch (_) {
      // In-memory value is preserved; failed write does not crash
    }
  }

  /// Immediately flushes pending writes to disk.
  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _writeToDisk();
    await _writer?.flush();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _writer?.dispose();
    super.dispose();
  }
}
