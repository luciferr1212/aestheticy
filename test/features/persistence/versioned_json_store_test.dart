import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/features/lyrics/lyrics_offset_store.dart';
import 'package:aestheticy/features/persistence/versioned_json_store.dart';
import 'package:aestheticy/features/session/saved_session.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/audio_panels/eq_store.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('aestheticy_vjson_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('VersionedJsonStoreHelper (S4)', () {
    test('ordered migrations run step-by-step v0 -> v1 -> v2 and bump schemaVersion', () async {
      final target = File(p.join(tempDir.path, 'sample.json'));
      await target.writeAsString(jsonEncode({'legacyKey': 'hello'}));

      final order = <int>[];
      final helper = VersionedJsonStoreHelper(
        storeName: 'Sample',
        fileName: 'sample.json',
        currentSchemaVersion: 2,
        knownKeys: {'v2Key'},
        migrations: {
          0: (m) {
            order.add(0);
            return {
              ...m,
              'v1Key': '${m['legacyKey']}_v1',
            }..remove('legacyKey');
          },
          1: (m) {
            order.add(1);
            return {
              ...m,
              'v2Key': '${m['v1Key']}_v2',
            }..remove('v1Key');
          },
        },
      );

      final result = await helper.load(tempDir);
      expect(order, equals([0, 1]));
      expect(result.wasQuarantined, isFalse);
      expect(result.loadedSchemaVersion, equals(0));
      expect(result.data?['schemaVersion'], equals(2));
      expect(result.data?['v2Key'], equals('hello_v1_v2'));
    });

    test('rolling backup keeps newest 3 matching files and preserves unrelated files', () {
      var tick = 0;
      final helper = VersionedJsonStoreHelper(
        storeName: 'Sample',
        fileName: 'sample.json',
        knownKeys: {'a'},
        clock: () => DateTime(2026, 11, 27, 2, 0, tick++),
      );

      final backupDir = Directory(p.join(tempDir.path, 'backups', 'settings'))
        ..createSync(recursive: true);
      final unrelated = File(p.join(backupDir.path, 'other_store-note.txt'))
        ..writeAsStringSync('keep me');

      for (var i = 0; i < 5; i++) {
        helper.writeRollingBackupSync(
          tempDir,
          jsonEncode({'schemaVersion': 1, 'a': i}),
        );
      }

      expect(unrelated.existsSync(), isTrue);
      final matching = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('sample-'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      expect(matching, hasLength(3));
      expect(p.basename(matching[0].path), equals('sample-20261127-020002.json'));
      expect(p.basename(matching[1].path), equals('sample-20261127-020003.json'));
      expect(p.basename(matching[2].path), equals('sample-20261127-020004.json'));
      expect(
        backupDir.listSync().whereType<File>().where((f) => f.path.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('corrupt JSON logs WARN and quarantines to .bad-<timestamp>', () async {
      final logged = <String>[];
      final logger = AppLogger(customSink: _MemorySink(logged));
      final target = File(p.join(tempDir.path, 'corrupt.json'));
      await target.writeAsString('{not valid json!!!');

      final helper = VersionedJsonStoreHelper(
        storeName: 'SampleCorrupt',
        fileName: 'corrupt.json',
        knownKeys: {'a'},
        logger: logger,
        clock: () => DateTime(2026, 11, 27, 2, 45, 0),
      );

      final result = await helper.load(tempDir);
      expect(result.wasQuarantined, isTrue);
      expect(result.data, isNull);
      expect(target.existsSync(), isFalse);
      expect(
        File(p.join(tempDir.path, 'corrupt.json.bad-20261127-024500')).existsSync(),
        isTrue,
      );
      expect(
        logged.any((l) => l.contains('[WARN]') && l.contains('SampleCorrupt')),
        isTrue,
      );
    });
  });

  group('Versioned persistence across all 5 stores (S4)', () {
    test('SettingsStore loads unversioned JSON, preserves unknown keys on save, rotates 3 backups', () async {
      final file = File(p.join(tempDir.path, 'ui_settings.json'));
      await file.writeAsString(jsonEncode({
        'language': 'ar',
        'smoothTransitions': false,
        'futureFeatureEnabled': true,
        'futurePayload': {'nested': 99},
      }));

      final store = SettingsStore(directory: tempDir);
      try {
        await store.init();
        expect(store.settings.language, equals('ar'));
        expect(store.settings.transitionSmoothness, equals('off'));

        for (var i = 0; i < 4; i++) {
          store.update((s) => s.copyWith(volume: 0.2 + i * 0.1));
          await store.flush();
        }

        final saved = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        expect(saved['schemaVersion'], equals(SettingsStore.currentSchemaVersion));
        expect(saved['futureFeatureEnabled'], isTrue);
        expect(saved['futurePayload'], equals({'nested': 99}));

        final backupDir = Directory(p.join(tempDir.path, 'backups', 'settings'));
        final backups = backupDir
            .listSync()
            .whereType<File>()
            .where((f) => p.basename(f.path).startsWith('ui_settings-'))
            .toList();
        expect(backups, hasLength(3));
      } finally {
        store.dispose();
      }
    });

    test('EqStore writes schemaVersion and preserves unknown keys on save', () async {
      final file = File(p.join(tempDir.path, 'eq_settings.json'));
      await file.writeAsString(jsonEncode({
        'schemaVersion': 9,
        'enabled': true,
        'futureBandMode': 'linearPhase',
      }));

      final store = EqStore(directory: tempDir);
      try {
        await store.init();
        expect(store.settings.enabled, isTrue);

        store.update((s) => s.copyWith(preampDb: 2.5));
        await store.flush();

        final saved = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        expect(saved['schemaVersion'], equals(EqStore.currentSchemaVersion));
        expect(saved['futureBandMode'], equals('linearPhase'));
        expect(saved['preampDb'], equals(2.5));
      } finally {
        store.dispose();
      }
    });

    test('ArtistNameStore migrates unversioned List to v1 map and preserves unknown keys', () async {
      final file = File(p.join(tempDir.path, 'artist_display_names.json'));
      await file.writeAsString(jsonEncode([
        {'original': 'Fairuz', 'ar': 'فيروز', 'en': 'Fairuz'},
      ]));

      final store1 = ArtistNameStore(directory: tempDir);
      await store1.init();
      expect(store1.count, equals(1));
      await store1.flush();
      store1.dispose();

      final migrated = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(migrated['schemaVersion'], equals(ArtistNameStore.currentSchemaVersion));
      expect(migrated['entries'], isA<List<Object?>>());

      migrated['futureSortMode'] = 'manual';
      await file.writeAsString(jsonEncode(migrated));

      final store2 = ArtistNameStore(directory: tempDir);
      await store2.init();
      store2.setEntry('Amr Diab', ar: 'عمرو دياب', en: 'Amr Diab');
      await store2.flush();
      store2.dispose();

      final saved2 = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(saved2['schemaVersion'], equals(ArtistNameStore.currentSchemaVersion));
      expect(saved2['futureSortMode'], equals('manual'));
      expect((saved2['entries'] as List<Object?>), hasLength(2));
    });

    test('LyricsOffsetStore writes schemaVersion, preserves unknown keys, and quarantines corrupt JSON', () async {
      final trackKey = LyricsOffsetStore.keyForPath('/music/song.mp3');
      final file = File(p.join(tempDir.path, 'lyrics_offsets.json'));
      await file.writeAsString(jsonEncode({
        trackKey: 350,
        'futureLyricsScale': 1.25,
      }));

      final store = LyricsOffsetStore(directory: tempDir);
      await store.init();
      expect(await store.loadOffset('/music/song.mp3'), equals(350));
      await store.setOffset('/music/other.mp3', -200);
      await store.flush();
      store.dispose();

      final saved = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(saved['schemaVersion'], equals(LyricsOffsetStore.currentSchemaVersion));
      expect(saved['futureLyricsScale'], equals(1.25));
      expect(saved[trackKey], equals(350));

      await file.writeAsString('{corrupt!!!');
      final store2 = LyricsOffsetStore(directory: tempDir);
      await store2.init();
      expect(await store2.loadOffset('/music/song.mp3'), equals(0));
      store2.dispose();

      final badFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => RegExp(r'lyrics_offsets\.json\.bad-\d{8}-\d{6}(?:-\d+)?$').hasMatch(f.path))
          .toList();
      expect(badFiles, hasLength(1));
    });

    test('SessionStore writes schemaVersion and preserves unknown keys across sync & async saves', () async {
      final file = File(p.join(tempDir.path, 'session.json'));
      await file.writeAsString(jsonEncode({
        'queue': [
          {'uri': 'file:///a.mp3', 'entryId': 1, 'isUserQueued': false},
        ],
        'currentIndex': 0,
        'positionMs': 1234,
        'futureQueueFilter': 'liked',
      }));

      final store = SessionStore(directory: tempDir);
      try {
        await store.init();
        expect(store.session.positionMs, equals(1234));

        store.saveSync(const SavedSession(
          queue: [SavedSessionItem(uri: 'file:///a.mp3', entryId: 1)],
          currentIndex: 0,
          positionMs: 5678,
        ));

        final saved = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        expect(saved['schemaVersion'], equals(SessionStore.currentSchemaVersion));
        expect(saved['futureQueueFilter'], equals('liked'));
        expect(saved['positionMs'], equals(5678));
      } finally {
        store.dispose();
      }
    });
  });
}

class _MemorySink implements StringSink {
  final List<String> lines;
  _MemorySink(this.lines);

  @override
  void write(Object? obj) {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = '']) {
    lines.add(object.toString());
  }
}
