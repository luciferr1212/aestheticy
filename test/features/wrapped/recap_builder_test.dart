import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/features/wrapped/recap.dart';
import 'package:aestheticy/features/wrapped/recap_builder.dart';
import 'package:aestheticy/library/history_models.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';

void main() {
  group('RecapBuilder & Recap rules', () {
    test('enforces 20 counted-play eligibility threshold and ignores uncounted plays', () async {
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);

      // Seed 19 counted plays + 5 uncounted skips in November 2026
      for (var i = 0; i < 19; i++) {
        await repo.insertPlayEvent(
          PlayEvent(
            uri: 'C:\\Music\\track_${i % 6}.mp3',
            title: 'Track ${i % 6}',
            artist: 'Artist ${i % 3}',
            album: 'Album ${i % 2}',
            startedAt: DateTime(2026, 11, 1 + (i % 15), 14, i),
            listenedMs: 180000,
            counted: true,
            completed: true,
          ),
        );
      }
      for (var i = 0; i < 5; i++) {
        await repo.insertPlayEvent(
          PlayEvent(
            uri: 'C:\\Music\\skip_$i.mp3',
            title: 'Skip $i',
            artist: 'Skip Artist',
            album: 'Skip Album',
            startedAt: DateTime(2026, 11, 20, 12, i),
            listenedMs: 3000,
            counted: false,
            completed: false,
          ),
        );
      }

      final builder = RecapBuilder(
        repository: repo,
        clock: () => DateTime(2026, 11, 28, 12, 0),
      );

      final months = await builder.availableMonths();
      expect(months.length, 1);
      expect(months.first.playsCounted, 19);
      expect(months.first.isEligible, isFalse);

      final ineligible = await builder.buildMonth(year: 2026, month: 11);
      expect(ineligible.playsCounted, 19);
      expect(ineligible.isEligible, isFalse);
      expect(ineligible.suggestedExportFileName, 'aestheticy-wrapped-2026-11.png');

      // 20th counted play unlocks eligibility
      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\track_0.mp3',
          title: 'Track 0',
          artist: 'Artist 0',
          album: 'Album 0',
          startedAt: DateTime(2026, 11, 21, 14, 0),
          listenedMs: 240000,
          counted: true,
          completed: true,
        ),
      );

      final eligible = await builder.buildMonth(year: 2026, month: 11);
      expect(eligible.playsCounted, 20);
      expect(eligible.isEligible, isTrue);
      expect(eligible.topTracks.length, 5);
    });

    test('distinguishes busiestDay (most plays) vs longestListeningDay (most ms) and month/week boundaries', () async {
      final repo = SqliteLibraryRepository.inMemory();
      addTearDown(repo.close);

      // Day A (Nov 23 Mon): 4 short plays (4 x 1m = 4m total) -> busiestDay
      for (var i = 0; i < 4; i++) {
        await repo.insertPlayEvent(
          PlayEvent(
            uri: 'C:\\Music\\short_$i.mp3',
            title: 'Short $i',
            artist: 'Artist Short',
            album: 'Album Short',
            startedAt: DateTime(2026, 11, 23, 15, i * 5),
            listenedMs: 60000,
            counted: true,
            completed: true,
          ),
        );
      }

      // Day B (Nov 24 Tue): 2 long plays (2 x 15m = 30m total) -> longestListeningDay
      for (var i = 0; i < 2; i++) {
        await repo.insertPlayEvent(
          PlayEvent(
            uri: 'C:\\Music\\epic_$i.mp3',
            title: 'Epic $i',
            artist: 'Artist Epic',
            album: 'Album Epic',
            startedAt: DateTime(2026, 11, 24, 15, i * 20),
            listenedMs: 900000,
            counted: true,
            completed: true,
          ),
        );
      }

      // Oct 31 event must not bleed into November; Nov 22 Sun in AR week vs EN week
      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\oct.mp3',
          title: 'Oct Track',
          artist: 'Artist Oct',
          album: 'Album Oct',
          startedAt: DateTime(2026, 10, 31, 23, 55),
          listenedMs: 300000,
          counted: true,
          completed: true,
        ),
      );
      await repo.insertPlayEvent(
        PlayEvent(
          uri: 'C:\\Music\\sun.mp3',
          title: 'Sun Track',
          artist: 'Artist Sun',
          album: 'Album Sun',
          startedAt: DateTime(2026, 11, 22, 18, 0),
          listenedMs: 300000,
          counted: true,
          completed: true,
        ),
      );

      final builder = RecapBuilder(
        repository: repo,
        clock: () => DateTime(2026, 11, 27, 12, 0),
      );

      final months = await builder.availableMonths();
      expect(months.map((m) => m.key).toList(), ['2026-11', '2026-10']);

      final enWeek = await builder.buildWeek(languageCode: 'en');
      expect(enWeek.playsCounted, 6); // Nov 23..24 only
      expect(enWeek.busiestDay?.date, DateTime(2026, 11, 23));
      expect(enWeek.busiestDay?.playCount, 4);
      expect(enWeek.longestListeningDay?.date, DateTime(2026, 11, 24));
      expect(enWeek.longestListeningDay?.totalMinutes, 30);
      expect(enWeek.topArtist?.artist, 'Artist Epic');
      expect(enWeek.topAlbum?.album, 'Album Epic');
      expect(enWeek.suggestedExportFileName, 'aestheticy-week-2026-W48.png');

      final arWeek = await builder.buildWeek(languageCode: 'ar');
      expect(arWeek.playsCounted, 7); // Includes Sunday Nov 22
    });

    test('personality rules and ISO week filenames are deterministic across cases', () {
      expect(
        RecapBuilder.classifyPersonality(
          playsCounted: 20,
          totalListenedMs: 100000,
          distinctTracks: 10,
          newTracksDiscovered: 2,
          topAlbum: null,
          weekdayHourActivity: const [
            WeekdayHourListeningStat(
              weekday: 1,
              hour: 23,
              totalListenedMs: 60000,
              playCount: 12,
            ),
          ],
        ),
        RecapPersonality.nightOwl,
      );

      expect(
        RecapBuilder.classifyPersonality(
          playsCounted: 20,
          totalListenedMs: 100000,
          distinctTracks: 10,
          newTracksDiscovered: 2,
          topAlbum: null,
          weekdayHourActivity: const [
            WeekdayHourListeningStat(
              weekday: 1,
              hour: 8,
              totalListenedMs: 55000,
              playCount: 10,
            ),
          ],
        ),
        RecapPersonality.earlyBird,
      );

      expect(
        RecapBuilder.classifyPersonality(
          playsCounted: 20,
          totalListenedMs: 100000,
          distinctTracks: 10,
          newTracksDiscovered: 2,
          topAlbum: const RankedAlbumStat(
            album: 'Deep LP',
            artist: 'Artist',
            playCount: 6,
            totalListenedMs: 50000,
          ),
          weekdayHourActivity: const [
            WeekdayHourListeningStat(
              weekday: 2,
              hour: 15,
              totalListenedMs: 100000,
              playCount: 20,
            ),
          ],
        ),
        RecapPersonality.albumListener,
      );

      expect(
        RecapBuilder.classifyPersonality(
          playsCounted: 20,
          totalListenedMs: 100000,
          distinctTracks: 16,
          newTracksDiscovered: 12,
          topAlbum: null,
          weekdayHourActivity: const [
            WeekdayHourListeningStat(
              weekday: 3,
              hour: 14,
              totalListenedMs: 100000,
              playCount: 20,
            ),
          ],
        ),
        RecapPersonality.explorer,
      );

      expect(
        RecapBuilder.classifyPersonality(
          playsCounted: 20,
          totalListenedMs: 100000,
          distinctTracks: 20,
          newTracksDiscovered: 2,
          topAlbum: null,
          weekdayHourActivity: const [
            WeekdayHourListeningStat(
              weekday: 3,
              hour: 14,
              totalListenedMs: 100000,
              playCount: 20,
            ),
          ],
        ),
        RecapPersonality.steadyListener,
      );

      // ISO year boundary check: 2026-01-01 (Thursday) belongs to 2026-W01
      expect(
        RecapBuilder.isoWeekForDate(DateTime(2026, 1, 1)),
        (isoYear: 2026, isoWeek: 1),
      );
    });
  });
}
