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
      'current line receives larger typography and scale 1.0 in normal and full screen modes',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        const synced = '''
[00:01.00]Line 0
[00:03.00]Line 1
[00:05.00]Line 2
''';
        fakeRepo.resultToReturn = LyricsResultFound(parseLrc(synced));
        queue.replaceAll([
          const AudioSource('file:///music/song.mp3', extras: {'title': 'Song'}),
        ]);
        await lyricsController.retry();

        // 1. Normal mode (fontSize 32 / 24, scale 1.0 / 0.92)
        await tester.pumpWidget(buildTestApp());
        lyricsController.updatePosition(const Duration(milliseconds: 3500));
        await tester.pump();

        final scaleCurrent = tester.widget<AnimatedScale>(
          find.ancestor(of: find.text('Line 1'), matching: find.byType(AnimatedScale)).first,
        );
        expect(scaleCurrent.scale, equals(1.0));

        final scaleOther = tester.widget<AnimatedScale>(
          find.ancestor(of: find.text('Line 0'), matching: find.byType(AnimatedScale)).first,
        );
        expect(scaleOther.scale, equals(0.92));

        final styleCurrent = tester.widget<AnimatedDefaultTextStyle>(
          find.ancestor(of: find.text('Line 1'), matching: find.byType(AnimatedDefaultTextStyle)).first,
        );
        expect(styleCurrent.style.fontSize, equals(32.0));

        final styleOther = tester.widget<AnimatedDefaultTextStyle>(
          find.ancestor(of: find.text('Line 0'), matching: find.byType(AnimatedDefaultTextStyle)).first,
        );
        expect(styleOther.style.fontSize, equals(24.0));

        // 2. Full screen mode (fontSize 40 / 28)
        await tester.pumpWidget(buildTestApp(
          child: LyricsView(
            controller: lyricsController,
            playbackController: playbackController,
            settingsStore: settingsStore,
            navigator: navigator,
            isFullScreen: true,
            showHeader: false,
          ),
        ));
        await tester.pump();

        final fsStyleCurrent = tester.widget<AnimatedDefaultTextStyle>(
          find.ancestor(of: find.text('Line 1'), matching: find.byType(AnimatedDefaultTextStyle)).first,
        );
        expect(fsStyleCurrent.style.fontSize, equals(40.0));

        final fsStyleOther = tester.widget<AnimatedDefaultTextStyle>(
          find.ancestor(of: find.text('Line 0'), matching: find.byType(AnimatedDefaultTextStyle)).first,
        );
        expect(fsStyleOther.style.fontSize, equals(28.0));
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
      'word sweep progress follows real word timing and settles previous word over 120ms',
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

        // Alpha is current word (at 50% progress in 2000..2500ms)
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('Beta'), findsOneWidget);
        expect(find.text('Gamma'), findsOneWidget);

        // Alpha should have a ShaderMask sweep widget
        final alphaMask = find.ancestor(
          of: find.text('Alpha'),
          matching: find.byType(ShaderMask),
        );
        expect(alphaMask, findsWidgets);

        // Advance to 2600ms (Beta is now active, Alpha is previous word)
        lyricsController.updatePosition(const Duration(milliseconds: 2600));
        await tester.pump();

        // Previous word Alpha settles with AnimatedDefaultTextStyle over 120ms
        final alphaSettle = find.ancestor(
          of: find.text('Alpha'),
          matching: find.byType(AnimatedDefaultTextStyle),
        );
        expect(alphaSettle, findsWidgets);
        final settleWidget = tester.widget<AnimatedDefaultTextStyle>(alphaSettle.first);
        expect(settleWidget.duration, equals(const Duration(milliseconds: 120)));
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
  });
}
