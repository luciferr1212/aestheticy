import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../diagnostics/app_logger.dart';
import '../glass/glass_scope.dart';
import 'app_settings.dart';

/// Single source of truth managing UI settings persistence and in-memory state.
class SettingsStore extends ChangeNotifier {
  Future<Directory> Function()? _directoryProvider;
  Directory? _directory;
  AppSettings _settings;
  Timer? _debounceTimer;

  /// Creates a [SettingsStore] with an optional injected [directory] or [directoryProvider].
  SettingsStore({
    Future<Directory> Function()? directoryProvider,
    Directory? directory,
    AppSettings initialSettings = const AppSettings(),
  }) : _settings = initialSettings {
    _directoryProvider = directoryProvider;
    _directory = directory;
  }

  /// Current immutable application settings.
  AppSettings get settings => _settings;

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
      final badFile = File(badPath);
      if (badFile.existsSync()) {
        badFile.deleteSync();
      }
      file.renameSync(badPath);
    } catch (_) {
      // Ignore renaming errors, never crash
    }
  }

  void _scheduleWrite() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_writeToDisk());
    });
  }

  Future<void> _writeToDisk() async {
    if (_directory == null) return;
    try {
      final targetPath = p.join(_directory!.path, 'ui_settings.json');
      final tmpPath = p.join(_directory!.path, 'ui_settings.json.tmp');
      final tmpFile = File(tmpPath);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(_settings.toJson());

      await tmpFile.writeAsString(jsonStr, flush: true);

      if (tmpFile.existsSync()) {
        final targetFile = File(targetPath);
        if (targetFile.existsSync()) {
          try {
            await targetFile.delete();
          } catch (_) {}
        }
        await tmpFile.rename(targetPath);
      }
    } catch (_) {
      // In-memory value is preserved; failed write does not crash
    }
  }

  /// Immediately flushes pending writes to disk.
  Future<void> flush() async {
    _debounceTimer?.cancel();
    await _writeToDisk();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
