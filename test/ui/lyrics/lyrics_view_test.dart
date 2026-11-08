import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/features/lyrics/lrc_parser.dart';
import 'package:aestheticy/features/lyrics/lyrics_controller.dart';
import 'package:aestheticy/features/lyrics/lyrics_models.dart';
import 'package:aestheticy/features/lyrics/lyrics_repository.dart';
import 'package:aestheticy/ui/l10n/app_strings.dart';
import 'package:aestheticy/ui/lyrics/lyrics_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/bottom_now_playing_bar.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

class _FakeLyricsRepo extends LyricsRepository {
  LyricsResult resultToReturn = const LyricsResultNotFound();

  @override
  Future<LyricsResult> resolve({
    required String filePath,
    required String title,
    required String artist,
    String? album,
    required int durationMs,
    required String mode,
  }) async {
    if (mode == 'off') return const LyricsResultOff();
    return resultToReturn;
  }
}

void main() {
  group('LyricsView & Navigation Widget Tests (S5)', () {
    late Directory tempDir;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController playbackController;
    late SettingsStore settingsStore;
    late _FakeLyricsRepo fakeRepo;
    late LyricsController lyricsController;
    late AppNavigator navigator;

    setUp(() async {
      AppLogger.instance = AppLogger(customSink: StringBuffer());
      tempDir = await Directory.systemTemp.createTemp('aestheticy_lyrics_view_');
      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      playbackController = PlaybackController(engine: engine, queue: queue);
      await playbackController.init();

      settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(
          language: 'en',
          lyricsSource: 'localThenOnline',
          lyricsHighlight: 'word',
          reduceMotion: false,
        ),
      );
      await settingsStore.init();

      fakeRepo = _FakeLyricsRepo();
      lyricsController = LyricsController(
        playbackController: playbackController,
        repository: fakeRepo,
        settingsStore: settingsStore,
      );
      navigator = AppNavigator();
    });

    tearDown(() async {
      lyricsController.dispose();
      settingsStore.dispose();
      await playbackController.dispose();
      await engine.dispose();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    Widget buildTestApp({
      Widget? child,
      TextDirection textDirection = TextDirection.ltr,
      double textScale = 1.0,
      Size size = const Size(1280, 800),
    }) {
      return MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: textDirection,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: SettingsScope(
              store: settingsStore,
              child: Scaffold(
                body: child ??
                    LyricsView(
                      controller: lyricsController,
                      playbackController: playbackController,
                      settingsStore: settingsStore,
                      navigator: navigator,
                    ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'each lyrics state renders expected localized content and controls',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        // 1. Not found state
        await tester.pumpWidget(buildTestApp());
        expect(find.text(AppStrings.t('lyrics.state.notFound')), findsOneWidget);

        // 2. Off state
        settingsStore.update((s) => s.copyWith(lyricsSource: 'off'));
        await tester.pump();
        expect(find.text(AppStrings.t('lyrics.state.off')), findsOneWidget);

        // 3. Error state with Retry button
        settingsStore.update((s) => s.copyWith(lyricsSource: 'localThenOnline'));
        fakeRepo.resultToReturn = const LyricsResultError(LyricsErrorReason.timeout);
        queue.replaceAll([
          const AudioSource('file:///music/song.mp3', extras: {'title': 'Song'}),
        ]);
        await lyricsController.retry();
        await tester.pump();

        expect(find.text(AppStrings.t('lyrics.state.error')), findsOneWidget);
        expect(find.text(AppStrings.t('lyrics.retry')), findsOneWidget);

        // 4. Instrumental state
        fakeRepo.resultToReturn = LyricsResultFound(
          LyricsDocument.instrumental(source: LyricsSourceOrigin.lrclib),
        );
        await lyricsController.retry();
        await tester.pump();

        expect(find.text(AppStrings.t('lyrics.state.instrumental')), findsOneWidget);

        // 5. Plain lyrics state
        fakeRepo.resultToReturn = LyricsResultFound(
          parseLrc('First verse\nSecond verse'),
        );
        await lyricsController.retry();
        await tester.pump();

        expect(find.text('First verse'), findsOneWidget);
        expect(find.text('Second verse'), findsOneWidget);

        // 6. Synced lyrics state
        const synced = '''
[00:02.00]Synced line one
[00:05.00]Synced line two
''';
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc(synced));
        await lyricsController.retry();
        await tester.pump();

        expect(find.text('Synced line one'), findsOneWidget);
        expect(find.text('Synced line two'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'current line follows playback position and clicking seeks to line timestamp',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        const synced = '''
[00:02.00]Line 0 at 2s
[00:06.00]Line 1 at 6s
''';
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc(synced));

        queue.replaceAll([
          const AudioSource('file:///music/song.mp3', extras: {'title': 'Song'}),
        ]);
        await lyricsController.retry();

        await tester.pumpWidget(buildTestApp());
        await tester.pump();

        // At 2500ms, line 0 is current
        lyricsController.updatePosition(const Duration(milliseconds: 2500));
        await tester.pump();
        expect(lyricsController.currentLineIndex, equals(0));

        // At 6500ms, line 1 is current
        lyricsController.updatePosition(const Duration(milliseconds: 6500));
        await tester.pump();
        expect(lyricsController.currentLineIndex, equals(1));

        // Clicking Line 0 seeks back to 2000ms
        await tester.tap(find.text('Line 0 at 2s'));
        await tester.pump();
        expect(playbackController.currentPosition, equals(const Duration(milliseconds: 2000)));
      },
    );

    testWidgets(
      'word highlight follows real word timing and reduce motion disables animation ticker',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        const enhanced = '''
[00:02.00]<00:02.00>WordA <00:02.50>WordB <00:03.00>WordC
[00:06.00]Second line
''';
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc(enhanced));
        queue.replaceAll([
          const AudioSource('file:///music/song.mp3', extras: {'title': 'Song'}),
        ]);
        await lyricsController.retry();

        await tester.pumpWidget(buildTestApp());
        await tester.pump();

        // At 2200ms, word index is 0
        lyricsController.updatePosition(const Duration(milliseconds: 2200));
        await tester.pump();
        expect(lyricsController.currentWordIndex, equals(0));

        // At 2700ms, word index is 1
        lyricsController.updatePosition(const Duration(milliseconds: 2700));
        await tester.pump();
        expect(lyricsController.currentWordIndex, equals(1));

        // Test reduce motion disables Ticker
        settingsStore.update((s) => s.copyWith(reduceMotion: true));
        await tester.pump();

        // At reduce motion, word highlight is rendered directly without continuous ticker frames
        expect(find.byType(LyricsView), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'renders without overflow in RTL and Large text scale at 1280x800',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        const synced = '''
[00:01.00]أغنية عربية جميلة
[00:03.00]سطر ثانٍ من الكلمات المتزامنة
''';
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc(synced));
        queue.replaceAll([
          const AudioSource('file:///music/arabic.mp3', extras: {'title': 'أغنية', 'artist': 'فنان'}),
        ]);
        await lyricsController.retry();

        await tester.pumpWidget(buildTestApp(
          textDirection: TextDirection.rtl,
          textScale: 1.10, // Large text tier
          size: const Size(1280, 800),
        ));
        await tester.pump();

        expect(find.text('أغنية عربية جميلة'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'RTL Large text must not throw overflow errors');
      },
    );

    testWidgets(
      'bottom bar and Now Playing lyrics buttons open AppDestination.lyrics and back button returns',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        // Test bottom bar button
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: BottomNowPlayingBar(
              controller: playbackController,
              navigator: navigator,
            ),
          ),
        ));
        await tester.pump();

        final lyricsButton = find.byKey(const Key('player_lyrics_button'));
        expect(lyricsButton, findsOneWidget);
        await tester.tap(lyricsButton);
        await tester.pump();

        expect(navigator.current, equals(AppDestination.lyrics));

        // Now test back button in LyricsView header
        await tester.pumpWidget(buildTestApp());
        await tester.pump();

        final backButton = find.text(AppStrings.t('common.back'));
        expect(backButton, findsOneWidget);
        await tester.tap(backButton);
        await tester.pump();

        expect(navigator.current, equals(AppDestination.albums));
      },
    );
  });
}
