import 'package:flutter_test/flutter_test.dart';
import 'package:aestheticy/library/artist_splitter.dart';
import 'package:aestheticy/library/text_normalizer.dart';

void main() {
  group('ArtistSplitter Unit Tests', () {
    test('Unambiguous separators always split', () {
      // Semicolon
      var res = ArtistSplitter.split('Artist A; Artist B');
      expect(res.map((a) => a.name), ['Artist A', 'Artist B']);

      res = ArtistSplitter.split('Artist A;Artist B;Artist C');
      expect(res.map((a) => a.name), ['Artist A', 'Artist B', 'Artist C']);

      // feat. / feat / ft. / featuring (case-insensitive)
      res = ArtistSplitter.split('Artist A feat. Artist B');
      expect(res.map((a) => a.name), ['Artist A', 'Artist B']);

      res = ArtistSplitter.split('Artist A FEAT Artist B');
      expect(res.map((a) => a.name), ['Artist A', 'Artist B']);

      res = ArtistSplitter.split('Artist A ft. Artist B');
      expect(res.map((a) => a.name), ['Artist A', 'Artist B']);

      res = ArtistSplitter.split('Artist A featuring Artist B');
      expect(res.map((a) => a.name), ['Artist A', 'Artist B']);
    });

    test('Never split on "/" (e.g. AC/DC)', () {
      final res = ArtistSplitter.split('AC/DC');
      expect(res.length, 1);
      expect(res.first.name, 'AC/DC');
    });

    test('Ambiguous separators stay whole when neither part is standalone', () {
      // 'Simon & Garfunkel' without standalone Simon or Garfunkel
      final res = ArtistSplitter.split('Simon & Garfunkel');
      expect(res.length, 1);
      expect(res.first.name, 'Simon & Garfunkel');

      // 'Crosby, Stills, Nash & Young' stays whole when none exist alone
      final res2 = ArtistSplitter.split('Crosby, Stills, Nash & Young');
      expect(res2.length, 1);
      expect(res2.first.name, 'Crosby, Stills, Nash & Young');
    });

    test('Ambiguous separator splits when at least one part is standalone in library', () {
      final standalone = {
        TextNormalizer.normalize('fairouz'),
      };

      // 'fairouz and kaza kaza' splits because 'fairouz' is standalone
      final res = ArtistSplitter.split(
        'fairouz and kaza kaza',
        standaloneArtistKeys: standalone,
      );
      expect(res.length, 2);
      expect(res.map((a) => a.name), ['fairouz', 'kaza kaza']);
      expect(res.first.key, TextNormalizer.normalize('fairouz'));
      expect(res.last.key, TextNormalizer.normalize('kaza kaza'));
    });

    test('Arabic ambiguous separators split when standalone artists exist', () {
      final standalone = {
        TextNormalizer.normalize('عمرو دياب'),
        TextNormalizer.normalize('محمد منير'),
      };

      // 'عمرو دياب اند مُحَمَّدْ مُنير'
      final res = ArtistSplitter.split(
        'عمرو دياب اند مُحَمَّدْ مُنير',
        standaloneArtistKeys: standalone,
      );
      expect(res.length, 2);
      expect(res.map((a) => a.name), ['عمرو دياب', 'مُحَمَّدْ مُنير']);
      expect(res.first.key, TextNormalizer.normalize('عمرو دياب'));
      expect(res.last.key, TextNormalizer.normalize('محمد منير'));

      // Arabic waw ' و '
      final resWaw = ArtistSplitter.split(
        'عمرو دياب و محمد منير',
        standaloneArtistKeys: standalone,
      );
      expect(resWaw.length, 2);

      // Arabic comma '،'
      final resComma = ArtistSplitter.split(
        'عمرو دياب، محمد منير',
        standaloneArtistKeys: standalone,
      );
      expect(resComma.length, 2);

      // Plus ' + '
      final resPlus = ArtistSplitter.split(
        'عمرو دياب + محمد منير',
        standaloneArtistKeys: standalone,
      );
      expect(resPlus.length, 2);
    });

    test('Never-split list always wins and keeps whole string', () {
      final standalone = {
        TextNormalizer.normalize('Simon'),
      };
      final noSplit = {
        TextNormalizer.normalize('Simon & Garfunkel'),
      };

      final res = ArtistSplitter.split(
        'Simon & Garfunkel',
        standaloneArtistKeys: standalone,
        noSplitKeys: noSplit,
      );
      expect(res.length, 1);
      expect(res.first.name, 'Simon & Garfunkel');
    });

    test('Alias resolution is applied to resulting keys', () {
      final standalone = {
        TextNormalizer.normalize('fairouz'),
      };
      final aliases = {
        TextNormalizer.normalize('فيروز'): TextNormalizer.normalize('fairouz'),
      };

      final res = ArtistSplitter.split(
        'فيروز and kaza kaza',
        standaloneArtistKeys: standalone,
        resolveAlias: (key) => aliases[key] ?? key,
      );

      expect(res.length, 2);
      // 'فيروز' resolved to 'fairouz' key, which matched standalone
      expect(res.first.key, TextNormalizer.normalize('fairouz'));
    });

    test('Empty or null input defaults to Unknown Artist', () {
      final resNull = ArtistSplitter.split(null);
      expect(resNull.length, 1);
      expect(resNull.first.name, 'Unknown Artist');

      final resEmpty = ArtistSplitter.split('   ');
      expect(resEmpty.length, 1);
      expect(resEmpty.first.name, 'Unknown Artist');
    });

    test('Deduplicates artists on identical key within a track', () {
      final res = ArtistSplitter.split('Artist A; Artist A');
      expect(res.length, 1);
      expect(res.first.name, 'Artist A');
    });
  });
}
