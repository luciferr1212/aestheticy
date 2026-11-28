import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Explicit allowlist of `lib/` files permitted to use filesystem write APIs,
/// mapped to a one-line reason explaining why user audio files are never touched.
const Map<String, String> kWriteApiAllowlist = {
  'lib/features/persistence/atomic_file_writer.dart':
      'Shared atomic temp-file/rename helper used only for app-data files.',
  'lib/features/persistence/versioned_json_store.dart':
      'Quarantines corrupt config JSON and rotates rolling backups inside app-support.',
  'lib/ui/settings/settings_store.dart':
      'Persists app settings JSON inside the app-support directory only.',
  'lib/ui/audio_panels/eq_store.dart':
      'Persists equalizer presets JSON inside the app-support directory only.',
  'lib/ui/artist_names/artist_name_store.dart':
      'Persists display-only artist name rules JSON inside app-support only.',
  'lib/features/lyrics/lyrics_offset_store.dart':
      'Persists per-track lyrics timing offsets JSON inside app-support only.',
  'lib/features/session/session_store.dart':
      'Persists playback session restore JSON inside the app-support directory only.',
  'lib/library/cover_cache.dart':
      'Caches extracted album cover images inside the app-cache directory only.',
  'lib/features/lyrics/lyrics_cache.dart':
      'Caches fetched/parsed lyrics files inside the app-cache directory only.',
  'lib/diagnostics/app_logger.dart':
      'Writes rotating diagnostic log files inside the app-support logs directory.',
  'lib/platform/windows/windows_tray_service.dart':
      'Extracts bundled tray icon bytes into a temporary app-cache .ico file.',
  'lib/features/collections/m3u.dart':
      'Exports playlists atomically only to user-selected validated .m3u/.m3u8 paths.',
  'lib/features/wrapped/wrapped_image_exporter.dart':
      'Exports Wrapped/weekly recap PNGs atomically only to user-selected validated .png paths.',
  'lib/library/sqlite/legacy_userdata_migrator.dart':
      'Creates pre-split backups of library.db inside the app-support backups directory.',
  'lib/library/sqlite/database_protection.dart':
      'Quarantines corrupt database files and restores userdata backups inside app-support.',
  'lib/platform/windows/folder_opener.dart':
      'Launches Windows Explorer on the app-support logs or backups directory.',
  'lib/library/sqlite/userdata_backup_service.dart':
      'Writes and rotates verified userdata.db backups inside app-support/backups/userdata.',
};

final List<_WriteApiPattern> _writeApiPatterns = [
  _WriteApiPattern('writeAsBytes', RegExp(r'\bwriteAsBytes\s*\(')),
  _WriteApiPattern('writeAsBytesSync', RegExp(r'\bwriteAsBytesSync\s*\(')),
  _WriteApiPattern('writeAsString', RegExp(r'\bwriteAsString\s*\(')),
  _WriteApiPattern('writeAsStringSync', RegExp(r'\bwriteAsStringSync\s*\(')),
  _WriteApiPattern('openWrite', RegExp(r'\bopenWrite\s*\(')),
  _WriteApiPattern(
    'RandomAccessFile write mode',
    RegExp(
      r'RandomAccessFile[\s\S]{0,300}FileMode\.(?:write|append|writeOnly|writeOnlyAppend)\b',
    ),
  ),
  _WriteApiPattern(
    'FileMode.write/append',
    RegExp(r'\bFileMode\.(?:write|append|writeOnly|writeOnlyAppend)\b'),
  ),
  _WriteApiPattern('.rename(', RegExp(r'\.rename\s*\(')),
  _WriteApiPattern('.renameSync(', RegExp(r'\.renameSync\s*\(')),
  _WriteApiPattern('.copy(', RegExp(r'\.copy\s*\(')),
  _WriteApiPattern('.copySync(', RegExp(r'\.copySync\s*\(')),
  _WriteApiPattern('.delete(', RegExp(r'\.delete\s*\(')),
  _WriteApiPattern('.deleteSync(', RegExp(r'\.deleteSync\s*\(')),
  _WriteApiPattern(
    'Process.run/start',
    RegExp(r'\bProcess\.(?:run|runSync|start)\s*\('),
  ),
];

final List<_WriteApiPattern> _metadataWritePatterns = [
  _WriteApiPattern('updateMetadata', RegExp(r'\bupdateMetadata\s*\(')),
  _WriteApiPattern('writeMetadata', RegExp(r'\bwriteMetadata\s*\(')),
  _WriteApiPattern('writeAllMetadata', RegExp(r'\bwriteAllMetadata\s*\(')),
  _WriteApiPattern('editMetadata', RegExp(r'\beditMetadata\s*\(')),
  _WriteApiPattern('MetadataGod.write', RegExp(r'\bMetadataGod\.write\s*\(')),
  _WriteApiPattern('writeTags', RegExp(r'\bwriteTags?\s*\(')),
  _WriteApiPattern('TagProcessor', RegExp(r'\bTagProcessor\b')),
  _WriteApiPattern('Audiotagger', RegExp(r'\bAudiotagger\b')),
];

final List<RegExp> _tagWriterPackageImports = [
  RegExp(r'package:metadata_god/'),
  RegExp(r'package:audiotagger/'),
  RegExp(r'package:dart_tags/'),
];

void main() {
  test('lib/ files do not use write-capable APIs outside the app-data allowlist', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue);

    final violations = <String>[];
    for (final file in _listDartFiles(libDir)) {
      final relativePath = _normalizePath(file.path);
      if (kWriteApiAllowlist.containsKey(relativePath)) {
        continue;
      }
      final source = _stripComments(file.readAsStringSync());
      for (final pattern in _writeApiPatterns) {
        if (pattern.regex.hasMatch(source)) {
          violations.add('$relativePath uses ${pattern.label}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Write-capable APIs in lib/ are only allowed in kWriteApiAllowlist '
          '(app-data files or validated .m3u/.m3u8 exports):\n'
          '${violations.join('\n')}',
    );
  });

  test('allowlist entries point to existing files with non-empty reasons', () {
    for (final entry in kWriteApiAllowlist.entries) {
      expect(
        File(entry.key).existsSync(),
        isTrue,
        reason: 'Missing allowlisted file: ${entry.key}',
      );
      expect(
        entry.value.trim(),
        isNotEmpty,
        reason: 'Allowlist entry ${entry.key} must have a one-line reason.',
      );
    }
  });

  test('lib/ files never call audio-metadata write APIs on library tracks', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue);

    final violations = <String>[];
    for (final file in _listDartFiles(libDir)) {
      final relativePath = _normalizePath(file.path);
      final source = _stripComments(file.readAsStringSync());

      for (final pkgRegex in _tagWriterPackageImports) {
        if (pkgRegex.hasMatch(source)) {
          violations.add('$relativePath imports ${pkgRegex.pattern}');
        }
      }

      if (source.contains('package:audio_metadata_reader/') &&
          RegExp(r'\bupdateMetadata\s*\(').hasMatch(source)) {
        violations.add(
          '$relativePath imports audio_metadata_reader and calls updateMetadata',
        );
      }

      for (final pattern in _metadataWritePatterns) {
        for (final match in pattern.regex.allMatches(source)) {
          // Windows SMTC integration updates the OS Now Playing overlay,
          // never audio file tags.
          if (pattern.label == 'updateMetadata' &&
              relativePath == 'lib/platform/windows/smtc_media_session.dart') {
            final prefix = source.substring(
              match.start >= 5 ? match.start - 5 : 0,
              match.start,
            );
            if (prefix.endsWith('smtc.') &&
                !source.contains('audio_metadata_reader')) {
              continue;
            }
          }
          violations.add('$relativePath calls ${pattern.label}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Aestheticy must never modify or write tags to user audio files:\n'
          '${violations.join('\n')}',
    );
  });
}

List<File> _listDartFiles(Directory root) {
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => _normalizePath(a.path).compareTo(_normalizePath(b.path)));
  return files;
}

String _normalizePath(String path) => path.replaceAll('\\', '/');

String _stripComments(String source) {
  final withoutBlockComments = source.replaceAll(
    RegExp(r'/\*[\s\S]*?\*/'),
    ' ',
  );
  return withoutBlockComments.replaceAll(RegExp(r'//.*$', multiLine: true), '');
}

class _WriteApiPattern {
  const _WriteApiPattern(this.label, this.regex);

  final String label;
  final RegExp regex;
}
