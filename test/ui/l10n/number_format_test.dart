import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/l10n/number_format.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';

void main() {
  group('NumberFormat Pure Helper Tests', () {
    test('localizeDigits only converts when arabicIndic is true', () {
      expect(localizeDigits('Track 123 - 45:00', arabicIndic: false),
          equals('Track 123 - 45:00'));
      expect(localizeDigits('Track 123 - 45:00', arabicIndic: true),
          equals('Track ١٢٣ - ٤٥:٠٠'));
      expect(localizeDigits('', arabicIndic: true), equals(''));
      expect(localizeDigits('No digits here', arabicIndic: true),
          equals('No digits here'));
    });

    test('formatDuration edge cases (0, 59 s, 60 s, 3599 s, 3600 s)', () {
      expect(formatDuration(Duration.zero), equals('0:00'));
      expect(formatDuration(const Duration(seconds: -10)), equals('0:00'));
      expect(formatDuration(const Duration(seconds: 59)), equals('0:59'));
      expect(formatDuration(const Duration(seconds: 60)), equals('1:00'));
      expect(formatDuration(const Duration(seconds: 3599)), equals('59:59'));
      expect(formatDuration(const Duration(seconds: 3600)), equals('1:00:00'));
      expect(formatDuration(const Duration(seconds: 3661)), equals('1:01:01'));
    });

    test('formatCount formats integers correctly', () {
      expect(formatCount(0), equals('0'));
      expect(formatCount(42), equals('42'));
      expect(formatCount(12345), equals('12345'));
    });
  });

  group('Arabic Numerals Widget Tests', () {
    testWidgets('tracks table in Arabic with setting ON converts duration but preserves title',
        (tester) async {
      final store = SettingsStore(
        initialSettings: const AppSettings(
          language: 'ar',
          arabicNumerals: true,
        ),
      );

      final track = Track(
        id: 1,
        path: '/music/song1.mp3',
        folderId: 1,
        title: 'Song 123 Forever',
        artist: 'Artist 456',
        album: 'Album 789',
        durationMs: 75000, // 1:15 -> in arabic numerals: ١:١٥
        mtimeMs: 0,
        sizeBytes: 1024,
        addedAt: DateTime(2024, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScope(
            store: store,
            child: Builder(
              builder: (context) {
                final formatted = context.formatDurationLocalized(
                  Duration(milliseconds: track.durationMs),
                );
                return Scaffold(
                  body: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Column(
                      children: [
                        Text(track.title!),
                        Text(formatted, key: const Key('duration_text')),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Verify title is untouched (still Western digits 123)
      expect(find.text('Song 123 Forever'), findsOneWidget);
      // Verify duration uses Arabic-Indic digits
      expect(find.text('١:١٥'), findsOneWidget);
      expect(find.text('1:15'), findsNothing);
    });
  });
}
