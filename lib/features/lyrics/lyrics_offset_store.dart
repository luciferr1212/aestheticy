import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/result.dart';
import '../../diagnostics/app_logger.dart';
import '../persistence/atomic_file_writer.dart';
import '../persistence/versioned_json_store.dart';

/// Minimum user-configurable lyrics offset in milliseconds (-15 seconds).
const int kMinLyricsOffsetMs = -15000;

/// Maximum user-configurable lyrics offset in milliseconds (+15 seconds).
const int kMaxLyricsOffsetMs = 15000;

/// UI step increment for lyrics offset adjustments in milliseconds.
const int kLyricsOffsetStepMs = 100;

/// Persistent per-track lyrics timing offset store backed by `lyrics_offsets.json`.
///
/// Keys entries by the MD5 hash of the track file path. Offsets never expire,
/// zero removes the entry, and writes are debounced (300 ms) and atomic.
class LyricsOffsetStore {
  static const int currentSchemaVersion = 1;
  static const String _fileName = 'lyrics_offsets.json';
  static final RegExp _md5KeyPattern = RegExp(r'^[a-f0-9]{32}$');

  final Future<Directory> Function()? _directoryProvider;
  Directory? _directory;
  final void Function(AppError error)? onError;
  final Map<String, int> _offsets = {};
  Map<String, Object?> _unknownFields = const {};
  bool _loaded = false;
  Future<void>? _loadFuture;
  Timer? _debounceTimer;
  Future<void>? _writeFuture;
  bool _disposed = false;
  AtomicFileWriter? _writer;
  final VersionedJsonStoreHelper _versionHelper = VersionedJsonStoreHelper(
    storeName: 'LyricsOffsetStore',
    fileName: _fileName,
    currentSchemaVersion: currentSchemaVersion,
    isKnownKey: (key) => key == 'schemaVersion' || _md5KeyPattern.hasMatch(key),
  );

  /// Creates a [LyricsOffsetStore] with an optional injectable [directory]
  /// or [directoryProvider].
  LyricsOffsetStore({
    this._directory,
    this._directoryProvider,
    this.onError,
  }) {
    if (_directory != null) {
      _writer = AtomicFileWriter(
        File(p.join(_directory!.path, _fileName)),
        onError: onError,
      );
    }
  }

  AtomicFileWriter? _getWriter() {
    if (_writer != null) return _writer;
    if (_directory != null) {
      return _writer = AtomicFileWriter(
        File(p.join(_directory!.path, _fileName)),
        onError: onError,
      );
    }
    return null;
  }

  /// Returns the canonical MD5 storage key for [trackPath].
  static String keyForPath(String trackPath) {
    return md5.convert(utf8.encode(trackPath)).toString();
  }

  /// Clamps [offsetMs] to the supported `[-15000, +15000]` ms range.
  static int clampOffsetMs(int offsetMs) {
    return offsetMs.clamp(kMinLyricsOffsetMs, kMaxLyricsOffsetMs);
  }

  /// Initializes the store and loads existing offsets from disk if present.
  Future<void> init() {
    if (_loaded) return Future<void>.value();
    return _loadFuture ??= _doInit();
  }

  Future<void> _doInit() async {
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
        File(p.join(_directory!.path, _fileName)),
        onError: onError,
      );
      await _loadFromDisk();
    } catch (e, st) {
      // Corrupt data or unavailable support dir falls back cleanly to empty.
      AppLogger.instance.warn(
        'LyricsOffsetStore',
        'Failed initializing lyrics offsets store',
        e,
        st,
      );
      _offsets.clear();
    } finally {
      _loaded = true;
    }
  }

  Future<void> _loadFromDisk() async {
    final dir = _directory;
    if (dir == null) return;
    final loaded = await _versionHelper.load(dir);
    if (loaded.wasQuarantined) {
      _offsets.clear();
      _unknownFields = const {};
      return;
    }
    final data = loaded.data;
    if (data == null) return;

    _unknownFields = loaded.unknownFields;
    _offsets.clear();
    for (final entry in data.entries) {
      final key = entry.key;
      final val = entry.value;
      if (_md5KeyPattern.hasMatch(key) && val is num) {
        final clamped = clampOffsetMs(val.round());
        if (clamped != 0) {
          _offsets[key] = clamped;
        }
      }
    }
  }

  /// Loads the saved offset in milliseconds for [trackPath], or `0` if none.
  Future<int> loadOffset(String trackPath) async {
    if (_disposed) return 0;
    await init();
    if (_disposed) return 0;
    return _offsets[keyForPath(trackPath)] ?? 0;
  }

  /// Updates the offset in milliseconds for [trackPath].
  ///
  /// Values are clamped to `[-15000, +15000]`. Setting `0` removes the entry.
  /// Schedules a 300 ms debounced atomic disk write.
  Future<void> setOffset(String trackPath, int offsetMs) async {
    if (_disposed) return;
    await init();
    if (_disposed) return;

    final key = keyForPath(trackPath);
    final clamped = clampOffsetMs(offsetMs);
    if (clamped == 0) {
      _offsets.remove(key);
    } else {
      _offsets[key] = clamped;
    }
    _scheduleWrite();
  }

  void _scheduleWrite() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _writeFuture =
          (_writeFuture ?? Future<void>.value()).then((_) => _writeToDisk());
    });
  }

  Future<void> _writeToDisk() async {
    final writer = _getWriter();
    if (writer == null) return;
    try {
      final payload = _versionHelper.preparePayload(
        _offsets.map((k, v) => MapEntry<String, Object?>(k, v)),
        _unknownFields,
      );
      final encoded = jsonEncode(payload);
      await writer.write(encoded);
      final dir = _directory;
      if (dir != null) {
        _versionHelper.writeRollingBackupSync(dir, encoded);
      }
    } catch (e, st) {
      // Preserve in-memory offsets if disk write fails.
      AppLogger.instance.error(
        'LyricsOffsetStore',
        'Failed writing lyrics_offsets.json',
        e,
        st,
      );
      onError?.call(AppError.fromException(e, st, 'error.settingsSaveFailed'));
    }
  }

  /// Immediately persists any pending debounced writes to disk.
  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (!_loaded) {
      await init();
    }
    _writeFuture =
        (_writeFuture ?? Future<void>.value()).then((_) => _writeToDisk());
    await _writeFuture;
    await _writer?.flush();
  }

  /// Cancels any pending debounce timer without writing if disposed.
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _writer?.dispose();
  }
}
