import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../library/text_normalizer.dart';
import '../settings/app_settings.dart';

/// Entry mapping an artist name to localized display representations.
class ArtistDisplayNameEntry {
  /// The original artist name as tagged in files or shown in library.
  final String original;

  /// Localized Arabic display name (may be empty).
  final String ar;

  /// Localized English display name (may be empty).
  final String en;

  /// Creates an immutable [ArtistDisplayNameEntry].
  const ArtistDisplayNameEntry({
    required this.original,
    this.ar = '',
    this.en = '',
  });

  /// Serializes to a JSON map.
  Map<String, Object?> toJson() => {
        'original': original,
        'ar': ar,
        'en': en,
      };

  /// Deserializes from a JSON map with tolerant defaults.
  factory ArtistDisplayNameEntry.fromJson(Map<String, Object?>? json) {
    if (json == null) return const ArtistDisplayNameEntry(original: '');
    final original = json['original'] is String ? json['original'] as String : '';
    final ar = json['ar'] is String ? json['ar'] as String : '';
    final en = json['en'] is String ? json['en'] as String : '';
    return ArtistDisplayNameEntry(original: original, ar: ar, en: en);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtistDisplayNameEntry &&
          runtimeType == other.runtimeType &&
          original == other.original &&
          ar == other.ar &&
          en == other.en;

  @override
  int get hashCode => Object.hash(original, ar, en);

  @override
  String toString() =>
      'ArtistDisplayNameEntry(original: $original, ar: $ar, en: $en)';
}

/// Store managing artist display names, disk persistence, and name resolution.
class ArtistNameStore extends ChangeNotifier {
  Future<Directory> Function()? _directoryProvider;
  Directory? _directory;
  final Map<String, ArtistDisplayNameEntry> _entries = {};
  Timer? _debounceTimer;

  /// Creates an [ArtistNameStore].
  ArtistNameStore({
    Future<Directory> Function()? directoryProvider,
    Directory? directory,
    Map<String, ArtistDisplayNameEntry>? initialEntries,
  }) {
    _directoryProvider = directoryProvider;
    _directory = directory;
    if (initialEntries != null) {
      for (final entry in initialEntries.values) {
        _entries[TextNormalizer.normalize(entry.original)] = entry;
      }
    }
  }

  /// All entries currently held in memory.
  List<ArtistDisplayNameEntry> get entries =>
      List.unmodifiable(_entries.values);

  /// Total count of mapped artist names.
  int get count => _entries.length;

  /// Retrieves entry for [original] if one exists.
  ArtistDisplayNameEntry? getEntry(String original) {
    final key = TextNormalizer.normalize(original);
    return _entries[key];
  }

  /// Adds or updates display name entry for [original].
  void setEntry(String original, {String? ar, String? en}) {
    final trimmed = original.trim();
    if (trimmed.isEmpty) return;

    final key = TextNormalizer.normalize(trimmed);
    final existing = _entries[key];
    final entry = ArtistDisplayNameEntry(
      original: existing?.original ?? trimmed,
      ar: ar ?? existing?.ar ?? '',
      en: en ?? existing?.en ?? '',
    );
    _entries[key] = entry;
    notifyListeners();
    _scheduleWrite();
  }

  /// Removes entry for [original].
  void removeEntry(String original) {
    final key = TextNormalizer.normalize(original);
    if (_entries.remove(key) != null) {
      notifyListeners();
      _scheduleWrite();
    }
  }

  /// Resolves the display artist name using current [AppSettings] mode and language.
  String displayArtist(
    String original, {
    required AppSettings settings,
  }) {
    return resolve(
      original: original,
      mode: settings.artistNameMode,
      language: settings.language,
    );
  }

  /// Resolves [original] name according to [mode] and [language].
  ///
  /// - `asTagged`: returns [original].
  /// - `alwaysArabic`: returns `ar` translation if non-empty, else [original].
  /// - `followLanguage`: returns language-specific value ('ar' or 'en') if non-empty,
  ///   otherwise falls back to [original].
  ///
  /// Matching is strictly on the normalized original name (`TextNormalizer.normalize`),
  /// exact match of the whole string only.
  String resolve({
    required String original,
    required String mode,
    required String language,
  }) {
    if (mode == 'asTagged' || original.isEmpty) {
      return original;
    }

    final key = TextNormalizer.normalize(original);
    final entry = _entries[key];
    if (entry == null) {
      return original;
    }

    if (mode == 'alwaysArabic') {
      return entry.ar.isNotEmpty ? entry.ar : original;
    }

    // mode == 'followLanguage'
    if (language == 'ar') {
      return entry.ar.isNotEmpty ? entry.ar : original;
    } else {
      return entry.en.isNotEmpty ? entry.en : original;
    }
  }

  /// Initializes the store and loads display names from disk.
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
      // Keep empty defaults, never throw to the UI
    }
  }

  Future<void> _loadFromFile() async {
    if (_directory == null) return;
    final file = File(p.join(_directory!.path, 'artist_display_names.json'));
    if (!file.existsSync()) return;

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is List) {
        _entries.clear();
        for (final item in decoded) {
          if (item is Map<String, Object?>) {
            final entry = ArtistDisplayNameEntry.fromJson(item);
            if (entry.original.isNotEmpty) {
              _entries[TextNormalizer.normalize(entry.original)] = entry;
            }
          } else if (item is Map) {
            final entry = ArtistDisplayNameEntry.fromJson(
                Map<String, Object?>.from(item));
            if (entry.original.isNotEmpty) {
              _entries[TextNormalizer.normalize(entry.original)] = entry;
            }
          }
        }
      } else {
        _handleCorruptFile(file);
      }
    } catch (_) {
      _handleCorruptFile(file);
    }
  }

  void _handleCorruptFile(File file) {
    _entries.clear();
    try {
      final badPath =
          p.join(_directory!.path, 'artist_display_names.json.bad');
      final badFile = File(badPath);
      if (badFile.existsSync()) {
        badFile.deleteSync();
      }
      file.renameSync(badPath);
    } catch (_) {}
  }

  void _scheduleWrite() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _writeNow();
    });
  }

  /// Flushes any pending write immediately. Used for unit testing.
  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _writeNow();
  }

  Future<void> _writeNow() async {
    if (_directory == null) return;
    try {
      final targetPath =
          p.join(_directory!.path, 'artist_display_names.json');
      final tmpPath = '$targetPath.tmp';
      final tmpFile = File(tmpPath);

      final list = _entries.values.map((e) => e.toJson()).toList();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(list);
      await tmpFile.writeAsString(jsonStr, flush: true);

      // Atomic rename
      await tmpFile.rename(targetPath);
    } catch (_) {
      // Disk errors are ignored gracefully
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
