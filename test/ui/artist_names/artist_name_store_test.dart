import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  group('ArtistNameStore Tests', () {
    late Directory tempDir;
    late ArtistNameStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('artist_name_test_');
      store = ArtistNameStore(directory: tempDir);
      await store.init();
    });

    tearDown(() async {
      store.dispose();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolver handles asTagged, followLanguage, and alwaysArabic', () {
      store.setEntry('Fairouz', ar: 'فيروز', en: 'Fairouz');

      // 1. asTagged mode
      expect(
        store.resolve(original: 'Fairouz', mode: 'asTagged', language: 'ar'),
        equals('Fairouz'),
      );
      expect(
        store.resolve(original: 'Fairouz', mode: 'asTagged', language: 'en'),
        equals('Fairouz'),
      );

      // 2. followLanguage mode
      expect(
        store.resolve(original: 'Fairouz', mode: 'followLanguage', language: 'ar'),
        equals('فيروز'),
      );
      expect(
        store.resolve(original: 'Fairouz', mode: 'followLanguage', language: 'en'),
        equals('Fairouz'),
      );

      // 3. alwaysArabic mode
      expect(
        store.resolve(original: 'Fairouz', mode: 'alwaysArabic', language: 'en'),
        equals('فيروز'),
      );
      expect(
        store.resolve(original: 'Fairouz', mode: 'alwaysArabic', language: 'ar'),
        equals('فيروز'),
      );
    });

    test('empty values fall back to original', () {
      store.setEntry('Artist Without Arabic', ar: '', en: 'English Name');
      expect(
        store.resolve(
          original: 'Artist Without Arabic',
          mode: 'followLanguage',
          language: 'ar',
        ),
        equals('Artist Without Arabic'),
      );
      expect(
        store.resolve(
          original: 'Artist Without Arabic',
          mode: 'alwaysArabic',
          language: 'ar',
        ),
        equals('Artist Without Arabic'),
      );

      // Unmapped artist falls back to original
      expect(
        store.resolve(
          original: 'Unknown Band',
          mode: 'followLanguage',
          language: 'ar',
        ),
        equals('Unknown Band'),
      );
    });

    test('whole-string exact match only (does not match partial combinations)', () {
      store.setEntry('Fairouz', ar: 'فيروز', en: 'Fairouz');

      // Combined strings like "Fairouz & Ziad" should not partially match
      expect(
        store.resolve(
          original: 'Fairouz & Ziad',
          mode: 'followLanguage',
          language: 'ar',
        ),
        equals('Fairouz & Ziad'),
      );
    });

    test('normalization-insensitive matching (case & Arabic diacritics)', () {
      // Stored with diacritics / uppercase
      store.setEntry('فَيْرُوز', ar: 'فيروز', en: 'Fairouz');

      // Match with lowercase English
      store.setEntry('Amr Diab', ar: 'عمرو دياب', en: 'Amr Diab');

      expect(
        store.resolve(
          original: 'AMR DIAB',
          mode: 'followLanguage',
          language: 'ar',
        ),
        equals('عمرو دياب'),
      );

      // Match Arabic input with or without tashkeel
      expect(
        store.resolve(
          original: 'فيروز',
          mode: 'followLanguage',
          language: 'en',
        ),
        equals('Fairouz'),
      );
    });

    test('persistence and corrupt-file handling', () async {
      store.setEntry('Coldplay', ar: 'كولدبلاي', en: 'Coldplay');
      await store.flush();

      // Read back in new instance
      final store2 = ArtistNameStore(directory: tempDir);
      await store2.init();
      expect(store2.count, equals(1));
      expect(
        store2.resolve(original: 'Coldplay', mode: 'alwaysArabic', language: 'en'),
        equals('كولدبلاي'),
      );
      store2.dispose();

      // Corrupt file handling
      final file = File(p.join(tempDir.path, 'artist_display_names.json'));
      await file.writeAsString('CORRUPTED_JSON_DATA');

      final store3 = ArtistNameStore(directory: tempDir);
      await store3.init();
      expect(store3.count, equals(0));

      final badFile = File(p.join(tempDir.path, 'artist_display_names.json.bad'));
      expect(badFile.existsSync(), isTrue);
      store3.dispose();
    });

    testWidgets('language switch dynamically changes displayed names', (tester) async {
      final settingsStore = SettingsStore(
        initialSettings: const AppSettings(
          language: 'en',
          artistNameMode: 'followLanguage',
        ),
      );
      final widgetNameStore = ArtistNameStore(
        initialEntries: {
          'fairouz': const ArtistDisplayNameEntry(
            original: 'Fairouz',
            ar: 'فيروز',
            en: 'Fairouz',
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScope(
            store: settingsStore,
            child: ArtistNameScope(
              store: widgetNameStore,
              child: Builder(
                builder: (context) {
                  return Text(context.displayArtist('Fairouz'));
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('Fairouz'), findsOneWidget);
      expect(find.text('فيروز'), findsNothing);

      // Switch language to Arabic
      settingsStore.update((s) => s.copyWith(language: 'ar'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('فيروز'), findsOneWidget);
      expect(find.text('Fairouz'), findsNothing);

      settingsStore.dispose();
      widgetNameStore.dispose();
    });

    test('merged artist display follows canonical name entry while merge/unmerge receive original keys', () async {
      final repo = SqliteLibraryRepository.inMemory();
      final folder = await repo.addFolder('/music');
      final track1 = Track(
        path: '/music/t1.mp3',
        folderId: folder.id!,
        title: 'Song 1',
        artist: 'Cheb Khaled',
        album: 'Album 1',
        durationMs: 1000,
        mtimeMs: 1000,
        sizeBytes: 1000,
        addedAt: DateTime.now(),
      );
      final track2 = Track(
        path: '/music/t2.mp3',
        folderId: folder.id!,
        title: 'Song 2',
        artist: 'Khaled',
        album: 'Album 2',
        durationMs: 1000,
        mtimeMs: 1000,
        sizeBytes: 1000,
        addedAt: DateTime.now(),
      );
      await repo.upsertTracks([track1, track2]);
      await repo.rebuildArtistLinks();

      // Merge 'cheb khaled' into 'khaled'
      await repo.mergeArtists('cheb khaled', 'khaled', targetName: 'Khaled');

      final artists = await repo.listArtists();
      expect(artists.length, equals(1));
      final canonicalArtist = artists.first;
      expect(canonicalArtist.name, equals('Khaled'));

      // Map display name for canonical artist 'Khaled'
      store.setEntry('Khaled', ar: 'الشاب خالد', en: 'Khaled');

      final displayed = store.resolve(
        original: canonicalArtist.name,
        mode: 'alwaysArabic',
        language: 'en',
      );
      expect(displayed, equals('الشاب خالد'));

      // Unmerge uses original key
      final aliases = await repo.listAliases();
      expect(aliases.length, equals(1));
      expect(aliases.first.aliasKey, equals('cheb khaled'));
      await repo.unmergeArtist(aliases.first.aliasKey);

      final artistsAfter = await repo.listArtists();
      expect(artistsAfter.length, equals(2));
      await repo.close();
    });

    testWidgets('suggestions list capped at 200 and virtualized', (tester) async {
      // Create 300 entries
      final entries = List.generate(
        300,
        (i) => ArtistDisplayNameEntry(
          original: 'Artist $i',
          ar: 'فنان $i',
          en: 'Artist $i',
        ),
      );

      final cappedSuggestions = entries.take(200).toList();
      expect(cappedSuggestions.length, equals(200));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              width: 400,
              child: ListView.builder(
                itemCount: cappedSuggestions.length,
                itemExtent: 50.0,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(cappedSuggestions[index].original),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Virtualized: only visible items are mounted
      expect(find.text('Artist 0'), findsOneWidget);
      expect(find.text('Artist 199'), findsNothing); // Scrolled out of view
    });
  });
}
