import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aestheticy/features/wrapped/recap.dart';
import 'package:aestheticy/features/wrapped/wrapped_image_exporter.dart';
import 'package:aestheticy/library/history_models.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/library/library_data_cache.dart';
import 'package:aestheticy/ui/now_playing/cover_palette.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/wrapped/wrapped_controller.dart';
import 'package:aestheticy/ui/wrapped/wrapped_poster_renderer.dart';

Recap _sampleRecap({RecapPeriodKind kind = RecapPeriodKind.monthly}) {
  return Recap(
    kind: kind,
    year: 2026,
    month: 11,
    isoYear: 2026,
    isoWeek: 48,
    periodStart: DateTime(2026, 11, 1),
    periodEnd: DateTime(2026, 11, 30, 23, 59, 59, 999),
    totalListenedMs: 7500000, // 125 minutes
    playsCounted: 28,
    distinctTracks: 14,
    distinctArtists: 5,
    newTracksDiscovered: 9,
    topArtist: const RankedArtistStat(
      artist: 'Fairouz',
      playCount: 15,
      totalListenedMs: 4200000,
    ),
    topTracks: const [
      RankedTrackStat(
        uri: 'C:\\Music\\a.mp3',
        title: 'Kifak Inta',
        artist: 'Fairouz',
        album: 'Kifak Inta',
        playCount: 8,
        totalListenedMs: 1800000,
      ),
      RankedTrackStat(
        uri: 'C:\\Music\\b.mp3',
        title: 'Breeze',
        artist: 'Omar Khairat',
        album: 'Suite',
        playCount: 6,
        totalListenedMs: 1200000,
      ),
    ],
    topAlbum: const RankedAlbumStat(
      album: 'Kifak Inta',
      artist: 'Fairouz',
      playCount: 12,
      totalListenedMs: 3200000,
    ),
    busiestDay: RecapDayHighlight(
      date: DateTime(2026, 11, 18),
      playCount: 9,
      totalListenedMs: 2100000,
    ),
    longestListeningDay: RecapDayHighlight(
      date: DateTime(2026, 11, 19),
      playCount: 5,
      totalListenedMs: 2700000,
    ),
    personality: RecapPersonality.nightOwl,
    requiredCountedPlays: kind == RecapPeriodKind.monthly
        ? Recap.minMonthlyCountedPlays
        : Recap.minWeeklyCountedPlays,
  );
}

int _readBigEndianUint32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

void main() {
  group('WrappedImageExporter & 1080x1350 PNG Export', () {
    test('validateTargetPath rejects non-.png targets and detects existing .png', () {
      final tempDir = Directory.systemTemp.createTempSync('wrapped_val_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final audioRes = WrappedImageExporter.validateTargetPath(
        p.join(tempDir.path, 'song.mp3'),
      );
      expect(audioRes.isAllowed, isFalse);

      final jpgRes = WrappedImageExporter.validateTargetPath(
        p.join(tempDir.path, 'cover.jpg'),
      );
      expect(jpgRes.isAllowed, isFalse);

      final newPng = p.join(tempDir.path, 'aestheticy-wrapped-2026-11.png');
      final freshRes = WrappedImageExporter.validateTargetPath(newPng);
      expect(freshRes.isAllowed, isTrue);
      expect(freshRes.requiresOverwriteConfirmation, isFalse);

      File(newPng).writeAsBytesSync(const [137, 80, 78, 71, 13, 10, 26, 10]);
      final existsRes = WrappedImageExporter.validateTargetPath(newPng);
      expect(existsRes.isAllowed, isTrue);
      expect(existsRes.requiresOverwriteConfirmation, isTrue);

      expect(
        () => WrappedImageExporter.writePngAtomically(
          p.join(tempDir.path, 'bad.flac'),
          Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10]),
        ),
        throwsArgumentError,
      );
    });

    testWidgets(
      'renders exact 1080x1350 PNG for monthly EN & weekly AR and verifies signature/dimensions',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final enBytes = await tester.runAsync(() async {
          return WrappedPosterRenderer.renderRecapPng(
            recap: _sampleRecap(kind: RecapPeriodKind.monthly),
            palette: CoverPalette.fallback,
            settings: const AppSettings(language: 'en', arabicNumerals: false),
          );
        });
        expect(enBytes, isNotNull);
        expect(
          enBytes!.sublist(0, 8),
          equals(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        );
        expect(_readBigEndianUint32(enBytes, 16), 1080);
        expect(_readBigEndianUint32(enBytes, 20), 1350);

        final arWeeklyBytes = await tester.runAsync(() async {
          return WrappedPosterRenderer.renderRecapPng(
            recap: _sampleRecap(kind: RecapPeriodKind.weekly),
            palette: CoverPalette.fallback,
            settings: const AppSettings(language: 'ar', arabicNumerals: true),
          );
        });
        expect(arWeeklyBytes, isNotNull);
        expect(
          arWeeklyBytes!.sublist(0, 8),
          equals(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        );
        expect(_readBigEndianUint32(arWeeklyBytes, 16), 1080);
        expect(_readBigEndianUint32(arWeeklyBytes, 20), 1350);
      },
    );

    testWidgets(
      'export UX writes atomically, offers Open folder, guards overwrites, cleans temp files, and surfaces errors via ErrorPresenter',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('wrapped_export_');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final repo = SqliteLibraryRepository.inMemory();
        addTearDown(repo.close);
        final settingsStore = SettingsStore(
          initialSettings: const AppSettings(language: 'en'),
        );
        addTearDown(settingsStore.dispose);
        final dataCache = LibraryDataCache(repository: repo);
        addTearDown(dataCache.dispose);
        final wrappedCtrl = WrappedController(
          repository: repo,
          settingsStore: settingsStore,
          dataCache: dataCache,
        );
        addTearDown(wrappedCtrl.dispose);

        String? openedFolder;
        late BuildContext capturedCtx;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  capturedCtx = ctx;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        final monthly = _sampleRecap(kind: RecapPeriodKind.monthly);
        final validBytes = Uint8List.fromList(
          const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 1],
        );

        // 1. Fresh export writes exact monthly PNG filename and attaches Open folder SnackBar
        final res1 = await tester.runAsync(() async {
          return WrappedPosterRenderer.exportRecapPng(
            capturedCtx,
            recap: monthly,
            controller: wrappedCtrl,
            settingsStore: settingsStore,
            directoryPicker: () async => tempDir.path,
            onOpenFolder: (path) async => openedFolder = path,
            renderBytes: ({
              required recap,
              required palette,
              required settings,
              coverKey,
            }) async => validBytes,
          );
        });
        await tester.pumpAndSettle();
        final expectedPath = p.join(tempDir.path, 'aestheticy-wrapped-2026-11.png');
        expect(res1!.valueOrNull, expectedPath);
        expect(File(expectedPath).readAsBytesSync(), validBytes);
        expect(
          tempDir
              .listSync()
              .where((e) => p.basename(e.path).endsWith('.tmp')),
          isEmpty,
        );

        expect(find.text('Open folder'), findsOneWidget);
        await tester.tap(find.text('Open folder'));
        await tester.pump();
        expect(openedFolder, tempDir.path);

        // 2. Existing file without confirmation preserves original bytes
        final originalSentinel = Uint8List.fromList(
          const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 9, 9, 9],
        );
        File(expectedPath).writeAsBytesSync(originalSentinel);

        final declined = await WrappedPosterRenderer.exportRecapPng(
          capturedCtx,
          recap: monthly,
          controller: wrappedCtrl,
          settingsStore: settingsStore,
          directoryPicker: () async => tempDir.path,
          confirmOverwrite: (_, _) async => false,
          renderBytes: ({
            required recap,
            required palette,
            required settings,
            coverKey,
          }) async => validBytes,
        );
        expect(declined.valueOrNull, isNull);
        expect(File(expectedPath).readAsBytesSync(), originalSentinel);

        // 3. Confirmed overwrite updates file cleanly
        final accepted = await tester.runAsync(() async {
          return WrappedPosterRenderer.exportRecapPng(
            capturedCtx,
            recap: monthly,
            controller: wrappedCtrl,
            settingsStore: settingsStore,
            directoryPicker: () async => tempDir.path,
            confirmOverwrite: (_, _) async => true,
            renderBytes: ({
              required recap,
              required palette,
              required settings,
              coverKey,
            }) async => validBytes,
          );
        });
        expect(accepted!.valueOrNull, expectedPath);
        expect(File(expectedPath).readAsBytesSync(), validBytes);

        // 4. Non-.png filename refused without writing
        final refused = await WrappedPosterRenderer.exportRecapPng(
          capturedCtx,
          recap: monthly,
          controller: wrappedCtrl,
          settingsStore: settingsStore,
          directoryPicker: () async => tempDir.path,
          targetFileNameOverride: 'should-not-write.mp3',
          renderBytes: ({
            required recap,
            required palette,
            required settings,
            coverKey,
          }) async => validBytes,
        );
        expect(refused.valueOrNull, isNull);
        expect(
          File(p.join(tempDir.path, 'should-not-write.mp3')).existsSync(),
          isFalse,
        );

        // 5. Render/IO failure routes through ErrorPresenter and leaves no .tmp files
        ScaffoldMessenger.of(capturedCtx).clearSnackBars();
        await tester.pumpAndSettle();
        final blockingFile = File(p.join(tempDir.path, 'not_a_directory'));
        blockingFile.writeAsStringSync('blocker');
        final failed = await tester.runAsync(() async {
          return WrappedPosterRenderer.exportRecapPng(
            capturedCtx,
            recap: monthly,
            controller: wrappedCtrl,
            settingsStore: settingsStore,
            directoryPicker: () async => blockingFile.path,
            renderBytes: ({
              required recap,
              required palette,
              required settings,
              coverKey,
            }) async => validBytes,
          );
        });
        await tester.pumpAndSettle();
        expect(failed!.isErr, isTrue);
        expect(
          tempDir
              .listSync()
              .where((e) => p.basename(e.path).endsWith('.tmp')),
          isEmpty,
        );
        expect(find.text('Could not export recap image.'), findsOneWidget);
      },
    );
  });
}
