import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  static const String _fileName = 'lyrics_offsets.json';

  final Future<Directory> Function()? _directoryProvider;
  Directory? _directory;
  final Map<String, int> _offsets = {};
  bool _loaded = false;
  Future<void>? _loadFuture;
  Timer? _debounceTimer;
  Future<void>? _writeFuture;
  bool _disposed = false;

  /// Creates a [LyricsOffsetStore] with an optional injectable [directory]
  /// or [directoryProvider].
  LyricsOffsetStore({
    this._directory,
    this._directoryProvider,
  });

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
      await _loadFromDisk();
    } catch (_) {
      // Corrupt data or unavailable support dir falls back cleanly to empty.
      _offsets.clear();
    } finally {
      _loaded = true;
    }
  }

  Future<void> _loadFromDisk() async {
    final dir = _directory;
    if (dir == null) return;
    final file = File(p.join(dir.path, _fileName));
    if (!file.existsSync()) return;

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _offsets.clear();
        return;
      }
      _offsets.clear();
      for (final entry in decoded.entries) {
        final key = entry.key;
        final val = entry.value;
        if (key is String && val is num) {
          final clamped = clampOffsetMs(val.round());
          if (clamped != 0) {
            _offsets[key] = clamped;
          }
        }
      }
    } catch (_) {
      _offsets.clear();
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
    final dir = _directory;
    if (dir == null) return;
    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final targetPath = p.join(dir.path, _fileName);
      final tmpPath = p.join(dir.path, '$_fileName.tmp');
      final tmpFile = File(tmpPath);
      final encoded = jsonEncode(_offsets);
      await tmpFile.writeAsString(encoded, flush: true);
      await tmpFile.rename(targetPath);
    } catch (_) {
      // Preserve in-memory offsets if disk write fails.
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
  }

  /// Cancels any pending debounce timer without writing if disposed.
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}
