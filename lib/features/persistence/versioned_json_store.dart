import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../diagnostics/app_logger.dart';

/// A single ordered schema migration step from version `v` to `v + 1`.
typedef JsonMigrationStep = Map<String, Object?> Function(
  Map<String, Object?> data,
);

/// Result returned when loading a versioned JSON document from disk.
class VersionedJsonLoadResult {
  /// Migrated JSON map ready for deserialization, or `null` if missing/corrupt.
  final Map<String, Object?>? data;

  /// Top-level keys from the file that were not recognized by the current schema.
  final Map<String, Object?> unknownFields;

  /// Whether the on-disk file was corrupt and quarantined.
  final bool wasQuarantined;

  /// Original schema version found on disk (`0` when unversioned).
  final int loadedSchemaVersion;

  /// Creates a [VersionedJsonLoadResult].
  const VersionedJsonLoadResult({
    this.data,
    this.unknownFields = const {},
    this.wasQuarantined = false,
    this.loadedSchemaVersion = 0,
  });
}

/// Shared versioned JSON helper providing schema migrations, unknown-key
/// preservation, corrupt quarantine, and rolling backups for settings stores.
class VersionedJsonStoreHelper {
  /// Maximum rolling backup files retained per store.
  static const int defaultMaxBackups = 3;

  final String storeName;
  final String fileName;
  final int currentSchemaVersion;
  final bool Function(String key) isKnownKey;
  final Map<int, JsonMigrationStep> migrations;
  final Map<String, Object?> Function(Object? decoded)? legacyRootAdapter;
  final DateTime Function() clock;
  final int maxBackups;
  final AppLogger? logger;

  late final String _stem = p.basenameWithoutExtension(fileName);
  late final RegExp _backupFilePattern = RegExp(
    '^${RegExp.escape(_stem)}-(\\d{8}-\\d{6})(?:-(\\d+))?\\.json\$',
  );

  /// Creates a [VersionedJsonStoreHelper] for [fileName].
  VersionedJsonStoreHelper({
    required this.storeName,
    required this.fileName,
    this.currentSchemaVersion = 1,
    Set<String>? knownKeys,
    bool Function(String key)? isKnownKey,
    this.migrations = const {},
    this.legacyRootAdapter,
    DateTime Function()? clock,
    this.maxBackups = defaultMaxBackups,
    this.logger,
  })  : assert(knownKeys != null || isKnownKey != null),
        isKnownKey = isKnownKey ?? ((key) => knownKeys!.contains(key)),
        clock = clock ?? DateTime.now;

  /// Formats [dt] as `yyyyMMdd-HHmmss` for quarantine and backup filenames.
  static String formatTimestamp(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}-'
        '${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
  }

  /// Loads, migrates, and extracts unknown keys from [fileName] inside [directory].
  ///
  /// Corrupt JSON or unrecognized root types are quarantined to
  /// `<fileName>.bad-<timestamp>` and reported as `wasQuarantined: true`.
  Future<VersionedJsonLoadResult> load(Directory directory) async {
    final file = File(p.join(directory.path, fileName));
    if (!file.existsSync()) {
      return const VersionedJsonLoadResult();
    }

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      Map<String, Object?> map;
      if (decoded is Map<String, Object?>) {
        map = Map<String, Object?>.from(decoded);
      } else if (decoded is Map) {
        map = Map<String, Object?>.from(decoded);
      } else if (legacyRootAdapter != null) {
        map = Map<String, Object?>.from(legacyRootAdapter!(decoded));
      } else {
        quarantineCorruptSync(directory, file);
        return const VersionedJsonLoadResult(wasQuarantined: true);
      }

      final rawVersion = map['schemaVersion'];
      var version = 0;
      if (rawVersion is int) {
        version = rawVersion < 0 ? 0 : rawVersion;
      } else if (rawVersion is num) {
        version = rawVersion < 0 ? 0 : rawVersion.toInt();
      } else if (rawVersion != null) {
        (logger ?? AppLogger.instance).warn(
          storeName,
          'Invalid schemaVersion in $fileName, treating as 0',
        );
      }

      final loadedVersion = version;
      while (version < currentSchemaVersion) {
        final step = migrations[version];
        if (step != null) {
          map = Map<String, Object?>.from(step(map));
        }
        version++;
        map['schemaVersion'] = version;
      }

      final unknown = <String, Object?>{};
      for (final entry in map.entries) {
        if (entry.key != 'schemaVersion' && !isKnownKey(entry.key)) {
          unknown[entry.key] = entry.value;
        }
      }

      return VersionedJsonLoadResult(
        data: map,
        unknownFields: unknown,
        loadedSchemaVersion: loadedVersion,
      );
    } catch (e, st) {
      (logger ?? AppLogger.instance).warn(
        storeName,
        'Failed reading $fileName',
        e,
        st,
      );
      quarantineCorruptSync(directory, file);
      return const VersionedJsonLoadResult(wasQuarantined: true);
    }
  }

  /// Quarantines a corrupt [file] to `<fileName>.bad-<timestamp>` in [directory].
  File? quarantineCorruptSync(Directory directory, File file) {
    final ts = formatTimestamp(clock());
    var candidate = File(p.join(directory.path, '$fileName.bad-$ts'));
    var counter = 1;
    while (candidate.existsSync()) {
      candidate = File(p.join(directory.path, '$fileName.bad-$ts-$counter'));
      counter++;
    }

    (logger ?? AppLogger.instance).warn(
      storeName,
      'Corrupt $fileName quarantined to ${p.basename(candidate.path)}',
    );
    try {
      if (!file.existsSync()) return null;
      return file.renameSync(candidate.path);
    } catch (e, st) {
      (logger ?? AppLogger.instance).warn(
        storeName,
        'Failed quarantining corrupt $fileName',
        e,
        st,
      );
      return null;
    }
  }

  /// Merges preserved [unknownFields], [canonicalJson], and `schemaVersion`.
  Map<String, Object?> preparePayload(
    Map<String, Object?> canonicalJson,
    Map<String, Object?> unknownFields,
  ) {
    return <String, Object?>{
      ...unknownFields,
      ...canonicalJson,
      'schemaVersion': currentSchemaVersion,
    };
  }

  /// Writes a rolling backup under `<directory>/backups/settings/` and prunes
  /// backups older than [maxBackups] matching this store's filename pattern.
  void writeRollingBackupSync(Directory directory, String encodedJson) {
    File? tmpFile;
    try {
      final backupDir = Directory(
        p.join(directory.path, 'backups', 'settings'),
      );
      if (!backupDir.existsSync()) {
        backupDir.createSync(recursive: true);
      }

      final ts = formatTimestamp(clock());
      var backupPath = p.join(backupDir.path, '$_stem-$ts.json');
      var seq = 1;
      while (File(backupPath).existsSync()) {
        final padded = seq.toString().padLeft(3, '0');
        backupPath = p.join(backupDir.path, '$_stem-$ts-$padded.json');
        seq++;
      }

      tmpFile = File('$backupPath.tmp');
      tmpFile.writeAsStringSync(encodedJson, flush: true);
      tmpFile.renameSync(backupPath);
      tmpFile = null;

      _pruneOldBackupsSync(backupDir);
    } catch (e, st) {
      (logger ?? AppLogger.instance).warn(
        storeName,
        'Failed writing rolling backup for $fileName',
        e,
        st,
      );
      if (tmpFile != null) {
        try {
          if (tmpFile.existsSync()) {
            tmpFile.deleteSync();
          }
        } catch (_) {
          // ignore-silent: deleting temporary backup file created by VersionedJsonStoreHelper
        }
      }
    }
  }

  void _pruneOldBackupsSync(Directory backupDir) {
    if (!backupDir.existsSync() || maxBackups < 1) return;
    final matched = <_BackupEntry>[];
    for (final entity in backupDir.listSync()) {
      if (entity is! File) continue;
      final base = p.basename(entity.path);
      final match = _backupFilePattern.firstMatch(base);
      if (match == null) continue;
      matched.add(
        _BackupEntry(
          file: entity,
          timestamp: match.group(1)!,
          sequence: int.tryParse(match.group(2) ?? '0') ?? 0,
        ),
      );
    }
    if (matched.length <= maxBackups) return;

    matched.sort((a, b) {
      final tsCmp = b.timestamp.compareTo(a.timestamp);
      if (tsCmp != 0) return tsCmp;
      return b.sequence.compareTo(a.sequence);
    });

    for (final obsolete in matched.skip(maxBackups)) {
      try {
        obsolete.file.deleteSync();
      } catch (e, st) {
        (logger ?? AppLogger.instance).warn(
          storeName,
          'Failed deleting old rolling backup ${p.basename(obsolete.file.path)}',
          e,
          st,
        );
      }
    }
  }
}

class _BackupEntry {
  final File file;
  final String timestamp;
  final int sequence;

  const _BackupEntry({
    required this.file,
    required this.timestamp,
    required this.sequence,
  });
}
