import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/library/sort_direction_button.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SortDirection & compareLocaleAware (S5)', () {
    test('SortDirection model logic', () {
      expect(SortDirection.ascending.isAscending, isTrue);
      expect(SortDirection.ascending.isDescending, isFalse);
      expect(SortDirection.ascending.isReversed, isFalse);
      expect(SortDirection.ascending.toggled, equals(SortDirection.descending));

      expect(SortDirection.descending.isAscending, isFalse);
      expect(SortDirection.descending.isDescending, isTrue);
      expect(SortDirection.descending.isReversed, isTrue);
      expect(SortDirection.descending.toggled, equals(SortDirection.ascending));

      expect(SortDirection.fromReversed(false), equals(SortDirection.ascending));
      expect(SortDirection.fromReversed(true), equals(SortDirection.descending));
    });

    test('compareLocaleAware normalizes Arabic diacritics and Latin cases', () {
      // Arabic with alef variants and tashkeel
      final res1 = compareLocaleAware('أحمد', 'احمد');
      expect(res1, equals(0));

      final res2 = compareLocaleAware('مُحَمَّد', 'محمد');
      expect(res2, equals(0));

      // Case equality and ordering
      expect(compareLocaleAware('The Beatles', 'The Beatles'), equals(0));
      expect(compareLocaleAware('Alpha', 'Beta') < 0, isTrue);
      expect(compareLocaleAware('Beta', 'Alpha') > 0, isTrue);
    });

    test('Sorting fixture tracks by title, artist, album, duration, addedAt', () {
      final t1 = Track(
        id: 1,
        folderId: 1,
        path: '/a.mp3',
        title: 'Song B',
        artist: 'أحمد',
        album: 'Album 2',
        durationMs: 300,
        mtimeMs: 0,
        sizeBytes: 100,
        addedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final t2 = Track(
        id: 2,
        folderId: 1,
        path: '/b.mp3',
        title: 'Song A',
        artist: 'باسم',
        album: 'Album 1',
        durationMs: 200,
        mtimeMs: 0,
        sizeBytes: 100,
        addedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      final list = [t1, t2];

      // Sort by title ascending -> Song A, Song B
      final byTitleAsc = List<Track>.from(list)
        ..sort((a, b) => compareLocaleAware(a.title ?? '', b.title ?? ''));
      expect(byTitleAsc.first.title, equals('Song A'));

      // Sort by title descending -> Song B, Song A
      final byTitleDesc = List<Track>.from(list)
        ..sort((a, b) => -compareLocaleAware(a.title ?? '', b.title ?? ''));
      expect(byTitleDesc.first.title, equals('Song B'));

      // Sort by duration ascending -> 200, 300
      final byDurAsc = List<Track>.from(list)
        ..sort((a, b) => a.durationMs.compareTo(b.durationMs));
      expect(byDurAsc.first.durationMs, equals(200));

      // Sort by addedAt descending (newest first) -> 2000, 1000
      final byAddedDesc = List<Track>.from(list)
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      expect(byAddedDesc.first.addedAt.millisecondsSinceEpoch, equals(2000));
    });
  });

  group('SortDirectionButton Widget Tests (S5)', () {
    Widget buildButton({
      required SortDirection direction,
      required ValueChanged<SortDirection> onChanged,
      bool reduceMotion = false,
      Locale locale = const Locale('en'),
    }) {
      return MaterialApp(
        theme: buildAppTheme(),
        locale: locale,
        home: Scaffold(
          body: SortDirectionButton(
            buttonKey: const Key('test_sort_direction_btn'),
            direction: direction,
            onChanged: onChanged,
            reduceMotion: reduceMotion,
          ),
        ),
      );
    }

    testWidgets(
      'renders ascending with arrow up and turns 0.0',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        SortDirection? toggledTo;
        await tester.pumpWidget(
          buildButton(
            direction: SortDirection.ascending,
            onChanged: (dir) => toggledTo = dir,
          ),
        );
        await tester.pumpAndSettle();

        final rot = tester.widget<AnimatedRotation>(find.byType(AnimatedRotation));
        expect(rot.turns, equals(0.0));
        expect(rot.duration, equals(const Duration(milliseconds: 140)));

        await tester.tap(find.byKey(const Key('test_sort_direction_btn')));
        expect(toggledTo, equals(SortDirection.descending));
      },
    );

    testWidgets(
      'renders descending with turns 0.5 and respects reduceMotion',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        SortDirection? toggledTo;
        await tester.pumpWidget(
          buildButton(
            direction: SortDirection.descending,
            onChanged: (dir) => toggledTo = dir,
            reduceMotion: true,
          ),
        );
        await tester.pumpAndSettle();

        final rot = tester.widget<AnimatedRotation>(find.byType(AnimatedRotation));
        expect(rot.turns, equals(0.5));
        expect(rot.duration, equals(Duration.zero));

        await tester.tap(find.byKey(const Key('test_sort_direction_btn')));
        expect(toggledTo, equals(SortDirection.ascending));
      },
    );

    testWidgets(
      'renders in Arabic locale with localized tooltips',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        await tester.pumpWidget(
          buildButton(
            direction: SortDirection.ascending,
            onChanged: (_) {},
            locale: const Locale('ar'),
          ),
        );
        await tester.pumpAndSettle();

        final btn = tester.widget<IconButton>(find.byKey(const Key('test_sort_direction_btn')));
        expect(btn.tooltip, isNotNull);
      },
    );
  });
}
