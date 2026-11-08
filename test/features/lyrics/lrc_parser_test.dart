import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/features/lyrics/lrc_parser.dart';
import 'package:aestheticy/features/lyrics/lyrics_models.dart';

void main() {
  group('LRC Parser & Byte Decoder Tests (S2)', () {
    test('parses each timestamp form correctly', () {
      const lrc = '''
[01:23]Form no fractional
[1:23.4]Form single digit fraction
[01:23.45]Form two digits
[01:23.456]Form three digits
''';

      final doc = parseLrc(lrc);
      expect(doc.kind, equals(LyricsKind.synced));
      expect(doc.hasWordTiming, isFalse);
      expect(doc.lines.length, equals(4));

      expect(doc.lines[0].startMs, equals(83000));
      expect(doc.lines[0].text, equals('Form no fractional'));

      expect(doc.lines[1].startMs, equals(83400));
      expect(doc.lines[1].text, equals('Form single digit fraction'));

      expect(doc.lines[2].startMs, equals(83450));
      expect(doc.lines[2].text, equals('Form two digits'));

      expect(doc.lines[3].startMs, equals(83456));
      expect(doc.lines[3].text, equals('Form three digits'));
    });

    test('multi-timestamp on one line repeats line at each timestamp and sorts', () {
      const lrc = '''
[00:10.00][00:25.00][00:05.00]Chorus line repeats
''';

      final doc = parseLrc(lrc);
      expect(doc.lines.length, equals(3));
      expect(doc.lines[0].startMs, equals(5000));
      expect(doc.lines[0].text, equals('Chorus line repeats'));
      expect(doc.lines[1].startMs, equals(10000));
      expect(doc.lines[1].text, equals('Chorus line repeats'));
      expect(doc.lines[2].startMs, equals(25000));
      expect(doc.lines[2].text, equals('Chorus line repeats'));
    });

    test('offset both signs adjusts timestamps (positive = earlier, negative = later)', () {
      // Positive offset shifts lyrics earlier (subtracts ms)
      const lrcPos = '''
[offset:+1000]
[00:10.00]First line
''';
      final docPos = parseLrc(lrcPos);
      expect(docPos.lines.first.startMs, equals(9000));

      // Negative offset shifts lyrics later (adds ms)
      const lrcNeg = '''
[offset:-500]
[00:10.00]First line
''';
      final docNeg = parseLrc(lrcNeg);
      expect(docNeg.lines.first.startMs, equals(10500));
    });

    test('Enhanced LRC words extract timings and set hasWordTiming true only then', () {
      const lrc = '''
[00:02.00]<00:02.00>Hello <00:02.50>world <00:03.00>now
[00:05.00]Next normal line
''';

      final doc = parseLrc(lrc);
      expect(doc.hasWordTiming, isTrue);
      expect(doc.lines.length, equals(2));

      final line1 = doc.lines[0];
      expect(line1.text, equals('Hello world now'));
      expect(line1.words, isNotNull);
      expect(line1.words!.length, equals(3));

      expect(line1.words![0].text, equals('Hello'));
      expect(line1.words![0].startMs, equals(2000));
      expect(line1.words![0].endMs, equals(2500));

      expect(line1.words![1].text, equals('world'));
      expect(line1.words![1].startMs, equals(2500));
      expect(line1.words![1].endMs, equals(3000));

      expect(line1.words![2].text, equals('now'));
      expect(line1.words![2].startMs, equals(3000));
      // Last word in line links to start of next line (5000 ms)
      expect(line1.words![2].endMs, equals(5000));

      // Second line has no word timing
      expect(doc.lines[1].words, isNull);
    });

    test('plain text without timestamps produces plain document without word timing', () {
      const plain = '''
[ar:Artist]
[ti:Title]
First verse line
Second verse line
Third verse line
''';

      final doc = parseLrc(plain);
      expect(doc.kind, equals(LyricsKind.plain));
      expect(doc.hasWordTiming, isFalse);
      expect(doc.lines.length, equals(3));
      expect(doc.lines[0].text, equals('First verse line'));
      expect(doc.lines[1].text, equals('Second verse line'));
      expect(doc.lines[2].text, equals('Third verse line'));
    });

    test('handles UTF-8 BOM, CRLF, and empty lines cleanly', () {
      const content = '\uFEFF[00:01.00]Line 1\r\n\r\n[00:02.00]Line 2\r\n';
      final doc = parseLrc(content);
      expect(doc.lines.length, equals(2));
      expect(doc.lines[0].text, equals('Line 1'));
      expect(doc.lines[1].text, equals('Line 2'));
    });

    test('decodeLyricsBytes decodes strict UTF-8 and falls back to Windows-1256', () {
      // 1. Valid UTF-8 Arabic: "ميدو"
      const utf8Arabic = [0xD9, 0x85, 0xD9, 0x8A, 0xD8, 0xAF, 0xD9, 0x88];
      expect(decodeLyricsBytes(utf8Arabic), equals('ميدو'));

      // 2. Hand-encoded Windows-1256 Arabic: "ميدو"
      // In Windows-1256: م=0xE3, ي=0xED, د=0xCF, و=0xE6
      const cp1256Mido = [0xE3, 0xED, 0xCF, 0xE6];
      expect(decodeLyricsBytes(cp1256Mido), equals('ميدو'));

      // 3. Mixed Latin and CP1256 punctuation/letters
      // "Aestheticy - " + CP1256 for "ميدو"
      final mixed = [
        ...('Aestheticy - '.codeUnits),
        0xE3, 0xED, 0xCF, 0xE6,
      ];
      expect(decodeLyricsBytes(mixed), equals('Aestheticy - ميدو'));
    });

    test('invalid input never throws into caller', () {
      expect(decodeLyricsBytes(const []), equals(''));
      expect(() => parseLrc(''), returnsNormally);
      expect(() => parseLrc('[[[invalid]]]:::<<<>>>'), returnsNormally);
      expect(() => parseLrc('[offset:not_a_num]\n[9999:99.999]Huge line'), returnsNormally);
    });
  });
}
