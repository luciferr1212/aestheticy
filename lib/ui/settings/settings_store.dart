import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/result.dart';
import '../../diagnostics/app_logger.dart';
import '../../features/persistence/atomic_file_writer.dart';
import '../../features/persistence/versioned_json_store.dart';
import '../glass/glass_scope.dart';
import 'app_settings.dart';

/// Single source of truth managing UI settings persistence and in-memory state.
class SettingsStore extends ChangeNotifier {
  static const int currentSchemaVersion = 1;
  static final Set<String> _knownKeys = const AppSettings().toJson().keys.toSet();

  Future<Directory> Function()? _directoryProvider;
  Directory? _directory;
  final void Function(AppError error)? onError;
  AppSettings _settings;
  Timer? _debounceTimer;
  AtomicFileWriter? _writer;
  Map<String, Object?> _unknownFields = const {};
  final VersionedJsonStoreHelper _versionHelper = VersionedJsonStoreHelper(
    storeName: 'Settings',
    fileName: 'ui_settings.json',
    currentSchemaVersion: currentSchemaVersion,
    knownKeys: _knownKeys,
    migrations: {
      0: (data) {
        final migrated = Map<String, Object?>.from(data);
        if (!migrated.containsKey('transitionSmoothness') &&
            migrated['smoothTransitions'] is bool) {
          migrated['transitionSmoothness'] =
              (migrated['smoothTransitions'] as bool) ? 'smooth' : 'off';
        }
        return migrated;
      },
    },
  );

  /// Creates a [SettingsStore] with an optional injected [directory] or [directoryProvider].
  SettingsStore({
    Future<Directory> Function()? directoryProvider,
    Directory? directory,
    this.onError,
    AppSettings initialSettings = const AppSettings(),
  }) : _settings = initialSettings {
    _directoryProvider = directoryProvider;
    _directory = directory;
    if (directory != null) {
      _writer = AtomicFileWriter(
        File(p.join(directory.path, 'ui_settings.json')),
        onError: onError,
      );
    }
  }

  /// Current immutable application settings.
  AppSettings get settings => _settings;

  AtomicFileWriter? _getWriter() {
    if (_writer != null) return _writer;
    if (_directory != null) {
      return _writer = AtomicFileWriter(
        File(p.join(_directory!.path, 'ui_settings.json')),
        onError: onError,
      );
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
      _writer ??= AtomicFileWriter(
        File(p.join(_directory!.path, 'ui_settings.json')),
        onError: onError,
      );
      await _loadFromFile();
    } catch (e, st) {
      // Keep in-memory defaults, never throw to the UI
      AppLogger.instance.warn(
        'Settings',
        'SettingsStore.init failed, keeping defaults',
        e,
        st,
      );
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
    final dir = _directory;
    if (dir == null) return;
    final loaded = await _versionHelper.load(dir);
    if (loaded.wasQuarantined) {
      _settings = const AppSettings();
      _unknownFields = const {};
      return;
    }
    if (loaded.data != null) {
      _settings = AppSettings.fromJson(loaded.data);
      _unknownFields = loaded.unknownFields;
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
      final payload = _versionHelper.preparePayload(
        _settings.toJson(),
        _unknownFields,
      );
      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
      await writer.write(jsonStr);
      final dir = _directory;
      if (dir != null) {
        _versionHelper.writeRollingBackupSync(dir, jsonStr);
      }
    } catch (e, st) {
      // In-memory value is preserved; failed write does not crash
      AppLogger.instance.error(
        'Settings',
        'Failed writing ui_settings.json',
        e,
        st,
      );
      onError?.call(AppError.fromException(e, st, 'error.settingsSaveFailed'));
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
