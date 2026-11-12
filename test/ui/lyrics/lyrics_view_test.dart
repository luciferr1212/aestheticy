import 'dart:io';

import 'package:flutter/gestures.dart';
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
import 'package:aestheticy/features/lyrics/lyrics_offset_store.dart';
import 'package:aestheticy/features/lyrics/lyrics_repository.dart';
import 'package:aestheticy/ui/l10n/app_strings.dart';
import 'package:aestheticy/ui/lyrics/lyrics_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/bottom_now_playing_bar.dart';
import 'package:aestheticy/ui/theme/app_colors.dart';
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

    test('computeLineOpacity falls off with distance, dims past lines, and raises on hover', () {
      // Active line = 4
      expect(computeLineOpacity(index: 4, activeIndex: 4), equals(1.0));

      // Upcoming lines
      expect(computeLineOpacity(index: 5, activeIndex: 4), equals(0.55));
      expect(computeLineOpacity(index: 6, activeIndex: 4), equals(0.38));
      expect(computeLineOpacity(index: 7, activeIndex: 4), equals(0.26));
      expect(computeLineOpacity(index: 8, activeIndex: 4), equals(0.20));
      expect(computeLineOpacity(index: 12, activeIndex: 4), equals(0.20)); // floor

      // Past lines are dimmer than upcoming ones
      expect(computeLineOpacity(index: 3, activeIndex: 4), lessThan(0.55));
      expect(computeLineOpacity(index: 3, activeIndex: 4), equals(0.44));
      expect(computeLineOpacity(index: 2, activeIndex: 4), lessThan(0.38));
      expect(computeLineOpacity(index: 2, activeIndex: 4), equals(0.30));
      expect(computeLineOpacity(index: 1, activeIndex: 4), lessThan(0.26));
      expect(computeLineOpacity(index: 1, activeIndex: 4), equals(0.21));
      expect(computeLineOpacity(index: 0, activeIndex: 4), equals(0.20));

      // Hover interaction raises opacity
      expect(computeLineOpacity(index: 5, activeIndex: 4, isHovered: true), closeTo(0.73, 0.001));
      expect(computeLineOpacity(index: 4, activeIndex: 4, isHovered: true), equals(1.0));

      // Negative active index (before first line starts)
      expect(computeLineOpacity(index: 0, activeIndex: -1), equals(0.55));
      expect(computeLineOpacity(index: 1, activeIndex: -1), equals(0.38));
    });

    testWidgets(
      'constant layout 32/42 w700 height 1.3 and identical measured size across current, non-current, and word highlight',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        const synced = '''
[00:01.00]Line 0
[00:03.00]<00:03.00>Alpha <00:03.50>Beta
[00:06.00]Line 2
''';
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc(synced));
        queue.replaceAll([
          const AudioSource('file:///music/song.mp3', extras: {'title': 'Song'}),
        ]);
        await lyricsController.retry();

        // 1. Normal mode: Alpha Beta initially non-current
        settingsStore.update((s) => s.copyWith(lyricsHighlight: 'line'));
        await tester.pumpWidget(buildTestApp());
        lyricsController.updatePosition(const Duration(milliseconds: 1200));
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
          findsNothing,
        );

        final nonCurrentSize = tester.getSize(find.text('Alpha Beta'));
        final nonCurrentText = tester.widget<Text>(find.text('Alpha Beta'));
        expect(nonCurrentText.style?.fontSize, equals(32.0));
        expect(nonCurrentText.style?.fontWeight, equals(FontWeight.w700));
        expect(nonCurrentText.style?.height, equals(1.3));

        final scaleCurrentNormal = tester.widget<AnimatedScale>(
          find.ancestor(of: find.text('Line 0'), matching: find.byType(AnimatedScale)).first,
        );
        expect(scaleCurrentNormal.scale, equals(1.0));
        expect(scaleCurrentNormal.duration, equals(const Duration(milliseconds: 400)));

        final scaleOtherNormal = tester.widget<AnimatedScale>(
          find.ancestor(of: find.text('Alpha Beta'), matching: find.byType(AnimatedScale)).first,
        );
        expect(scaleOtherNormal.scale, equals(0.92));

        // Activate Alpha Beta as current line (line highlight)
        lyricsController.updatePosition(const Duration(milliseconds: 3250));
        await tester.pump();
        final currentLineSize = tester.getSize(find.text('Alpha Beta'));
        expect(currentLineSize, equals(nonCurrentSize));

        // Switch to word highlight while Alpha Beta is current
        settingsStore.update((s) => s.copyWith(lyricsHighlight: 'word'));
        await tester.pump();
        final wordHighlightSize = tester.getSize(find.text('Alpha Beta'));
        expect(wordHighlightSize, equals(nonCurrentSize));

        // 2. Full screen mode: constant 42.0 fontSize, max width 760, and identical sizes
        await tester.pumpWidget(buildTestApp(
          size: const Size(1400, 900),
          child: LyricsView(
            controller: lyricsController,
            playbackController: playbackController,
            settingsStore: settingsStore,
            navigator: navigator,
            isFullScreen: true,
            showHeader: false,
          ),
        ));
        lyricsController.updatePosition(const Duration(milliseconds: 1200));
        await tester.pump();

        final fsNonCurrentSize = tester.getSize(find.text('Alpha Beta'));
        expect(fsNonCurrentSize.width, lessThanOrEqualTo(760.0));
        final fsOtherText = tester.widget<Text>(find.text('Alpha Beta'));
        expect(fsOtherText.style?.fontSize, equals(42.0));
        expect(fsOtherText.style?.fontWeight, equals(FontWeight.w700));

        lyricsController.updatePosition(const Duration(milliseconds: 3250));
        await tester.pump();
        final fsWordSize = tester.getSize(find.text('Alpha Beta'));
        expect(fsWordSize, equals(fsNonCurrentSize));

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'reduce motion removes scale animations and sets all animation durations to zero',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        const synced = '''
[00:01.00]Line 0
[00:03.00]Line 1
''';
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc(synced));
        queue.replaceAll([
          const AudioSource('file:///music/song.mp3', extras: {'title': 'Song'}),
        ]);
        await lyricsController.retry();

        settingsStore.update((s) => s.copyWith(reduceMotion: true));
        await tester.pumpWidget(buildTestApp());
        lyricsController.updatePosition(const Duration(milliseconds: 3500));
        await tester.pump();

        final scale0 = tester.widget<AnimatedScale>(
          find.ancestor(of: find.text('Line 0'), matching: find.byType(AnimatedScale)).first,
        );
        final scale1 = tester.widget<AnimatedScale>(
          find.ancestor(of: find.text('Line 1'), matching: find.byType(AnimatedScale)).first,
        );

        expect(scale0.scale, equals(1.0));
        expect(scale1.scale, equals(1.0));
        expect(scale0.duration, equals(Duration.zero));
        expect(scale1.duration, equals(Duration.zero));

        final opacity0 = tester.widget<AnimatedOpacity>(
          find.ancestor(of: find.text('Line 0'), matching: find.byType(AnimatedOpacity)).first,
        );
        expect(opacity0.duration, equals(Duration.zero));

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'word sweep uses single Text.rich following real timing and falls back when unmappable',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        const enhanced = '''
[00:02.00]<00:02.00>Alpha <00:02.50>Beta <00:03.00>Gamma
[00:06.00]Line two
''';
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc(enhanced));
        queue.replaceAll([
          const AudioSource('file:///music/song.mp3', extras: {'title': 'Song'}),
        ]);
        await lyricsController.retry();

        await tester.pumpWidget(buildTestApp());
        lyricsController.updatePosition(const Duration(milliseconds: 2250));
        await tester.pump();

        // Rendered as one Text.rich / RichText with no Wrap inside the lyrics list
        expect(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Wrap),
          ),
          findsNothing,
        );
        final richFinder = find.text('Alpha Beta Gamma');
        expect(richFinder, findsOneWidget);

        // Alpha is at 50% progress -> gradient foreground paint, Gamma is dimmed
        final rich1 = tester.widget<Text>(richFinder);
        final children1 = (rich1.textSpan! as TextSpan).children!.cast<TextSpan>();
        final alphaSpan1 = children1.firstWhere((s) => s.text == 'Alpha');
        final gammaSpan1 = children1.firstWhere((s) => s.text == 'Gamma');
        expect(alphaSpan1.style?.foreground?.shader, isNotNull);
        expect(gammaSpan1.style?.color, isNot(equals(AppColors.text)));

        // Advance to 2600ms: Alpha solid AppColors.text, Beta has sweep shader
        lyricsController.updatePosition(const Duration(milliseconds: 2600));
        await tester.pump();
        final rich2 = tester.widget<Text>(richFinder);
        final children2 = (rich2.textSpan! as TextSpan).children!.cast<TextSpan>();
        final alphaSpan2 = children2.firstWhere((s) => s.text == 'Alpha');
        final betaSpan2 = children2.firstWhere((s) => s.text == 'Beta');
        expect(alphaSpan2.style?.color, equals(AppColors.text));
        expect(betaSpan2.style?.foreground?.shader, isNotNull);

        // Fallback test: unmappable word falls back cleanly to plain line Text
        expect(
          mapWordsToLineRanges(
            'Mismatched line',
            const [LyricsWord(startMs: 2000, endMs: 2500, text: 'MissingWord')],
          ),
          isNull,
        );
        fakeRepo.resultToReturn = const LyricsResultFound(
          LyricsDocument(
            kind: LyricsKind.synced,
            source: LyricsSourceOrigin.local,
            hasWordTiming: true,
            lines: [
              LyricsLine(
                startMs: 2000,
                text: 'Fallback display text',
                words: [LyricsWord(startMs: 2000, endMs: 2500, text: 'NotInLine')],
              ),
            ],
          ),
        );
        await lyricsController.retry();
        lyricsController.updatePosition(const Duration(milliseconds: 2100));
        await tester.pump();
        final fallbackFinder = find.text('Fallback display text');
        expect(fallbackFinder, findsOneWidget);
        expect(tester.widget<Text>(fallbackFinder).textSpan, isNull);
      },
    );

    testWidgets(
      'only affected lines rebuild on a line change and lines farther than 4 never rebuild',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final lrcLines = [
          for (var i = 0; i < 12; i++) '[00:${(i * 2 + 1).toString().padLeft(2, '0')}.00]Track line $i',
        ].join('\n');
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc(lrcLines));
        queue.replaceAll([
          const AudioSource('file:///music/song.mp3', extras: {'title': 'Song'}),
        ]);
        await lyricsController.retry();

        final builds = <int, int>{};
        await tester.pumpWidget(
          buildTestApp(
            size: const Size(1280, 1400),
            child: LyricsView(
              controller: lyricsController,
              playbackController: playbackController,
              settingsStore: settingsStore,
              navigator: navigator,
              onLineBuild: (idx) => builds[idx] = (builds[idx] ?? 0) + 1,
            ),
          ),
        );
        lyricsController.updatePosition(const Duration(milliseconds: 1500));
        await tester.pump();

        builds.clear();

        // Advance active line from 0 -> 1 (around 3000ms)
        lyricsController.updatePosition(const Duration(milliseconds: 3500));
        await tester.pump();

        // Lines within <=4 distance updated; lines farther than 4 (e.g. 6..11) had zero rebuilds
        expect(builds[0], greaterThanOrEqualTo(1));
        expect(builds[1], greaterThanOrEqualTo(1));
        for (var i = 6; i < 12; i++) {
          expect(builds[i] ?? 0, equals(0), reason: 'Line $i is >4 away and must not rebuild');
        }
      },
    );

    testWidgets(
      'synced lines are start-aligned in LTR and RTL while plain lyrics stay centered',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        const synced = '''
[00:01.00]Hello world LTR
[00:03.00]أهلا بكم بالعربية
''';
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc(synced));
        queue.replaceAll([
          const AudioSource('file:///music/mixed.mp3', extras: {'title': 'Mixed'}),
        ]);
        await lyricsController.retry();

        await tester.pumpWidget(buildTestApp());
        await tester.pump();

        final ltrText = tester.widget<Text>(find.text('Hello world LTR'));
        expect(ltrText.textAlign, equals(TextAlign.start));
        expect(ltrText.textDirection, equals(TextDirection.ltr));
        final ltrScale = tester.widget<AnimatedScale>(
          find.ancestor(of: find.text('Hello world LTR'), matching: find.byType(AnimatedScale)).first,
        );
        expect(ltrScale.alignment, equals(Alignment.centerLeft));

        final rtlText = tester.widget<Text>(find.text('أهلا بكم بالعربية'));
        expect(rtlText.textAlign, equals(TextAlign.start));
        expect(rtlText.textDirection, equals(TextDirection.rtl));
        final rtlScale = tester.widget<AnimatedScale>(
          find.ancestor(of: find.text('أهلا بكم بالعربية'), matching: find.byType(AnimatedScale)).first,
        );
        expect(rtlScale.alignment, equals(Alignment.centerRight));

        // Plain lyrics stay centered
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc('Plain verse one\nPlain verse two'));
        await lyricsController.retry();
        await tester.pump();
        final plainText = tester.widget<Text>(find.text('Plain verse one'));
        expect(plainText.textAlign, equals(TextAlign.center));
      },
    );

    testWidgets(
      'first paint starts at active line without animating from the top',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final lrcLines = [
          for (var i = 0; i < 30; i++)
            '[${(i ~/ 30).toString().padLeft(2, '0')}:${((i * 2) % 60).toString().padLeft(2, '0')}.00]Line $i',
        ].join('\n');
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc(lrcLines));
        queue.replaceAll([
          const AudioSource('file:///music/long.mp3', extras: {'title': 'Long'}),
        ]);
        await engine.seek(const Duration(seconds: 40));
        await lyricsController.retry();

        await tester.pumpWidget(buildTestApp(size: const Size(1280, 600)));
        await tester.pump();
        await tester.pump();

        expect(lyricsController.currentLineIndex, equals(20));
        expect(find.text('Line 20'), findsOneWidget);
      },
    );

    testWidgets(
      'manual scroll pauses auto-follow and no pending timers or tickers after dispose',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        const synced = '''
[00:01.00]Line 0
[00:03.00]Line 1
[00:05.00]Line 2
[00:07.00]Line 3
''';
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc(synced));
        queue.replaceAll([
          const AudioSource('file:///music/song.mp3', extras: {'title': 'Song'}),
        ]);
        await lyricsController.retry();

        await tester.pumpWidget(buildTestApp());
        lyricsController.updatePosition(const Duration(milliseconds: 1500));
        await tester.pump();

        // Simulate a manual user scroll gesture on the list
        await tester.drag(find.byType(ListView), const Offset(0, -100));
        await tester.pump();

        // Auto-follow is now paused for 4s
        // Advancing position should not crash or trigger premature scroll
        lyricsController.updatePosition(const Duration(milliseconds: 3500));
        await tester.pump();

        // Dispose the widget while the 4s auto-follow timer is still active
        await tester.pumpWidget(const SizedBox.shrink());

        // Verify clean dispose without pending timers or exceptions
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'sync offset control taps, hold repeat, reset state, tooltips, and RTL large text',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        final offsetStore = LyricsOffsetStore(directory: tempDir);
        await offsetStore.init();
        final offsetController = LyricsController(
          playbackController: playbackController,
          repository: fakeRepo,
          settingsStore: settingsStore,
          offsetStore: offsetStore,
        );
        addTearDown(() {
          offsetStore.dispose();
          offsetController.dispose();
        });

        const synced = '[00:01.00]Line 0\n[00:03.00]Line 1\n[00:05.00]Line 2';
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc(synced));
        queue.replaceAll([
          const AudioSource('file:///music/sync.mp3', extras: {'title': 'Sync Track'}),
        ]);
        await playbackController.play();
        await offsetController.retry();

        Widget buildWithOffsetCtrl({
          bool showHeader = true,
          TextDirection textDirection = TextDirection.ltr,
          double textScale = 1.0,
        }) {
          return buildTestApp(
            textDirection: textDirection,
            textScale: textScale,
            child: LyricsView(
              controller: offsetController,
              playbackController: playbackController,
              settingsStore: settingsStore,
              navigator: navigator,
              showHeader: showHeader,
            ),
          );
        }

        await tester.pumpWidget(buildWithOffsetCtrl());
        await tester.pump();

        expect(find.byKey(const Key('lyrics_sync_control')), findsOneWidget);
        expect(find.text('Sync'), findsOneWidget);
        expect(find.text('0 s'), findsOneWidget);

        // Tooltips on minus and plus
        final minusTooltip = tester.widget<Tooltip>(
          find.descendant(
            of: find.byKey(const Key('lyrics_sync_minus')),
            matching: find.byType(Tooltip),
          ),
        );
        final plusTooltip = tester.widget<Tooltip>(
          find.descendant(
            of: find.byKey(const Key('lyrics_sync_plus')),
            matching: find.byType(Tooltip),
          ),
        );
        expect(minusTooltip.message, equals('Show lyrics earlier'));
        expect(plusTooltip.message, equals('Show lyrics later'));

        // Reset button disabled at 0 s
        TextButton resetButton() => tester.widget<TextButton>(
              find.byKey(const Key('lyrics_sync_reset')),
            );
        expect(resetButton().onPressed, isNull);

        // Tap + advances by 100ms (+0.1 s) and enables Reset
        await tester.tap(find.byKey(const Key('lyrics_sync_plus')));
        await tester.pump();
        expect(offsetController.offsetMs, equals(100));
        expect(find.text('+0.1 s'), findsOneWidget);
        expect(resetButton().onPressed, isNotNull);

        // Hold + repeats after kPressTimeout (100ms) + initial delay (350ms) + ticks (80ms)
        final plusGesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('lyrics_sync_plus'))),
        );
        await tester.pump(const Duration(milliseconds: 650));
        await plusGesture.up();
        await tester.pump();
        expect(offsetController.offsetMs, greaterThanOrEqualTo(300));

        // Reset returns to 0 s and disables button
        await tester.tap(find.byKey(const Key('lyrics_sync_reset')));
        await tester.pump();
        expect(offsetController.offsetMs, equals(0));
        expect(find.text('0 s'), findsOneWidget);
        expect(resetButton().onPressed, isNull);

        // Tap - steps negative (-0.1 s) and hold - repeats further negative
        await tester.tap(find.byKey(const Key('lyrics_sync_minus')));
        await tester.pump();
        expect(offsetController.offsetMs, equals(-100));
        expect(find.text('-0.1 s'), findsOneWidget);

        final minusGesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('lyrics_sync_minus'))),
        );
        await tester.pump(const Duration(milliseconds: 650));
        await minusGesture.up();
        await tester.pump();
        expect(offsetController.offsetMs, lessThanOrEqualTo(-300));

        // Arabic RTL + large text scale renders without overflow
        await tester.pumpWidget(const SizedBox.shrink());
        settingsStore.update((s) => s.copyWith(language: 'ar'));
        await tester.pumpWidget(
          buildWithOffsetCtrl(textDirection: TextDirection.rtl, textScale: 1.5),
        );
        await tester.pump();
        expect(find.byKey(const Key('lyrics_sync_control')), findsOneWidget);
        expect(tester.takeException(), isNull);
        settingsStore.update((s) => s.copyWith(language: 'en'));

        // Hidden when showHeader == false (FullScreen / NowPlaying style)
        await tester.pumpWidget(buildWithOffsetCtrl(showHeader: false));
        await tester.pump();
        expect(find.byKey(const Key('lyrics_sync_control')), findsNothing);

        // Flush debounce timers cleanly before test exits
        await tester.pump(const Duration(milliseconds: 450));
      },
    );

    testWidgets(
      'sync offset control is hidden for plain and instrumental lyrics',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        // Plain lyrics
        fakeRepo.resultToReturn = const LyricsResultFound(
          LyricsDocument(
            kind: LyricsKind.plain,
            lines: [LyricsLine(startMs: 0, text: 'Plain verse')],
            source: LyricsSourceOrigin.local,
            hasWordTiming: false,
          ),
        );
        queue.replaceAll([
          const AudioSource('file:///music/plain.mp3', extras: {'title': 'Plain'}),
        ]);
        await lyricsController.retry();
        await tester.pumpWidget(buildTestApp());
        await tester.pump();
        expect(find.byKey(const Key('lyrics_sync_control')), findsNothing);

        // Instrumental lyrics
        fakeRepo.resultToReturn = LyricsResultFound(LyricsDocument.instrumental());
        await lyricsController.retry();
        await tester.pump();
        expect(find.byKey(const Key('lyrics_sync_control')), findsNothing);
      },
    );

    testWidgets(
      'S2: far seek forward and backward, >1.5s jump cancels manual pause, and reduceMotion uses zero durations',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final lines = List<LyricsLine>.generate(
          100,
          (i) => LyricsLine(
            startMs: (i + 1) * 1000,
            text: 'Synced line $i',
          ),
        );
        fakeRepo.resultToReturn = LyricsResultFound(
          LyricsDocument(
            kind: LyricsKind.synced,
            lines: lines,
            source: LyricsSourceOrigin.local,
            hasWordTiming: false,
          ),
        );
        final tracks = [
          const AudioSource(
            'file:///music/long.mp3',
            extras: {'title': 'Long Song', 'durationMs': '120000'},
          ),
        ];
        engine.fakeDuration = const Duration(seconds: 120);
        await tester.runAsync(() async {
          await playbackController.playQueue(tracks, startIndex: 0);
          await lyricsController.retry();
        });

        expect(lyricsController.state, isA<LyricsStateFound>());
        await tester.pumpWidget(buildTestApp());
        await tester.pump();
        await tester.pump();

        expect(find.text('Synced line 0'), findsOneWidget);
        expect(find.text('Synced line 99'), findsNothing);

        // Manually scroll to activate the 4s pause.
        await tester.drag(find.byType(ListView), const Offset(0, -120));
        await tester.pump();

        // Seek far forward to line 99 (while manual-scroll pause is active).
        await tester.runAsync(() => playbackController.seek(const Duration(seconds: 100)));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Synced line 99'), findsOneWidget);

        // Seek to middle line 50 and verify alignment near 0.38 of ListView viewport.
        await tester.runAsync(() => playbackController.seek(const Duration(seconds: 51)));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Synced line 50'), findsOneWidget);
        final listRect = tester.getRect(find.byType(ListView));
        final line50Rect = tester.getRect(find.text('Synced line 50'));
        final relTop = (line50Rect.top - listRect.top) / listRect.height;
        expect(relTop, closeTo(0.38, 0.15));

        // Direct position jump > 1.5s without seekStream cancels manual pause and follows back to line 0.
        await tester.drag(find.byType(ListView), const Offset(0, -80));
        await tester.pump();
        await tester.runAsync(() => engine.seek(const Duration(seconds: 1)));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Synced line 0'), findsOneWidget);

        // Enable reduceMotion and jump forward again: completes immediately without lingering timers.
        settingsStore.update((s) => s.copyWith(reduceMotion: true));
        await tester.pump();
        await tester.runAsync(() => playbackController.seek(const Duration(seconds: 80)));
        await tester.pump();
        await tester.pump();
        expect(find.text('Synced line 79'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
        await tester.runAsync(() => settingsStore.flush());
      },
    );

    testWidgets(
      'S3: user scrollbar appears only on wheel/drag and hides after 1s, never on programmatic scroll',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final lines = List<LyricsLine>.generate(
          60,
          (i) => LyricsLine(startMs: (i + 1) * 1000, text: 'Scroll line $i'),
        );
        fakeRepo.resultToReturn = LyricsResultFound(
          LyricsDocument(
            kind: LyricsKind.synced,
            lines: lines,
            source: LyricsSourceOrigin.local,
            hasWordTiming: false,
          ),
        );
        await tester.runAsync(() async {
          await playbackController.playQueue([
            const AudioSource(
              'file:///music/scroll.mp3',
              extras: {'title': 'Scroll', 'durationMs': '70000'},
            ),
          ], startIndex: 0);
          await lyricsController.retry();
        });

        expect(lyricsController.state, isA<LyricsStateFound>());
        await tester.pumpWidget(buildTestApp());
        await tester.pump();
        await tester.pump();

        RawScrollbar scrollbar() => tester.widget<RawScrollbar>(
              find.byKey(const Key('lyrics_user_scrollbar')),
            );

        expect(scrollbar().thumbVisibility, isFalse);

        // Programmatic animateTo / ensureVisible must NOT show scrollbar.
        final listView = tester.widget<ListView>(find.byType(ListView));
        listView.controller!.animateTo(
          300,
          duration: const Duration(milliseconds: 100),
          curve: Curves.linear,
        );
        await tester.pump(const Duration(milliseconds: 150));
        expect(scrollbar().thumbVisibility, isFalse);

        await tester.runAsync(() => playbackController.seek(const Duration(seconds: 40)));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(scrollbar().thumbVisibility, isFalse);

        // Mouse wheel over lyrics shows scrollbar and hides after 1s.
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(
          pointer.hover(tester.getCenter(find.byType(ListView))),
        );
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
        await tester.pump();
        expect(scrollbar().thumbVisibility, isTrue);

        await tester.pump(const Duration(milliseconds: 1100));
        expect(scrollbar().thumbVisibility, isFalse);

        // Dragging list shows scrollbar and hides 1s after drag.
        await tester.drag(find.byType(ListView), const Offset(0, -150));
        await tester.pump();
        expect(scrollbar().thumbVisibility, isTrue);

        await tester.pump(const Duration(milliseconds: 1100));
        expect(scrollbar().thumbVisibility, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
        await tester.runAsync(() => settingsStore.flush());
      },
    );
  });
}
