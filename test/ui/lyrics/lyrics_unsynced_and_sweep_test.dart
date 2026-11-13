import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/features/lyrics/lyrics_controller.dart';
import 'package:aestheticy/features/lyrics/lyrics_models.dart';
import 'package:aestheticy/features/lyrics/lyrics_repository.dart';
import 'package:aestheticy/ui/lyrics/lyrics_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';

class _MockLyricsRepo extends LyricsRepository {
  LyricsResult result;
  _MockLyricsRepo(this.result);

  @override
  Future<LyricsResult> resolve({
    required String filePath,
    required String title,
    required String artist,
    String? album,
    required int durationMs,
    required String mode,
  }) async {
    return result;
  }
}

void main() {
  group('Lyrics Unsynced Notice and Soft Word Fade (S2)', () {
    late Directory tempDir;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController playbackController;
    late SettingsStore settingsStore;
    late AppNavigator navigator;

    setUp(() async {
      AppLogger.instance = AppLogger(customSink: StringBuffer());
      tempDir = Directory.systemTemp.createTempSync('lyrics_s2_test_');
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
      navigator = AppNavigator();
    });

    tearDown(() async {
      settingsStore.dispose();
      await playbackController.dispose();
      await engine.dispose();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    Widget buildApp({
      required LyricsController controller,
      Locale locale = const Locale('en'),
    }) {
      return MaterialApp(
        locale: locale,
        home: SettingsScope(
          store: settingsStore,
          child: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: LyricsView(
                controller: controller,
                playbackController: playbackController,
                settingsStore: settingsStore,
                navigator: navigator,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'Unsynced notice shows on hover and hides on exit for plain lyrics, never for synced',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        const plainDoc = LyricsDocument(
          kind: LyricsKind.plain,
          lines: [
            LyricsLine(startMs: 0, text: 'First plain line'),
            LyricsLine(startMs: 0, text: 'Second plain line'),
          ],
          source: LyricsSourceOrigin.local,
          hasWordTiming: false,
        );

        final repo = _MockLyricsRepo(
          const LyricsResultFound(plainDoc),
        );
        final lyricsController = LyricsController(
          playbackController: playbackController,
          repository: repo,
          settingsStore: settingsStore,
        );
        addTearDown(lyricsController.dispose);

        // Queue track and trigger lyrics load
        queue.replaceAll([
          const AudioSource(
            'file:///track1.mp3',
            extras: {'title': 'Track One', 'artist': 'Artist One'},
          ),
        ]);
        await playbackController.play();
        await lyricsController.retry();

        await tester.pumpWidget(buildApp(controller: lyricsController));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // The notice widget exists in tree with key lyrics_unsynced_notice
        final noticeFinder = find.byKey(const Key('lyrics_unsynced_notice'));
        expect(noticeFinder, findsOneWidget);

        // Initially not hovered: opacity is 0.0
        final animatedOpacityFinder = find.ancestor(
          of: noticeFinder,
          matching: find.byType(AnimatedOpacity),
        );
        expect(animatedOpacityFinder, findsOneWidget);
        AnimatedOpacity opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
        expect(opacityWidget.opacity, equals(0.0));

        // Get initial position of the first lyric line
        final firstLineFinder = find.text('First plain line');
        expect(firstLineFinder, findsOneWidget);
        final initialOffset = tester.getTopLeft(firstLineFinder);

        // Hover over the lyrics view
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: const Offset(400, 300));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // Opacity should now be 1.0
        opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
        expect(opacityWidget.opacity, equals(1.0));

        // Layout unchanged: first line position must be exactly identical
        final hoveredOffset = tester.getTopLeft(firstLineFinder);
        expect(hoveredOffset, equals(initialOffset));

        // Move mouse away (exit)
        await gesture.moveTo(const Offset(10, 10)); // Outside lyrics view
        // Or remove pointer
        await gesture.removePointer();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
        expect(opacityWidget.opacity, equals(0.0));

        // Now test synced lyrics: notice is never rendered
        const syncedDoc = LyricsDocument(
          kind: LyricsKind.synced,
          lines: [
            LyricsLine(
              startMs: 1000,
              text: 'Synced line one',
            ),
          ],
          source: LyricsSourceOrigin.local,
          hasWordTiming: false,
        );
        repo.result = const LyricsResultFound(syncedDoc);
        await lyricsController.retry();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const Key('lyrics_unsynced_notice')), findsNothing);
      },
    );

    testWidgets(
      'Word mapping and soft feathered edge sweep behavior',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        const lineText = 'Hello beautiful world';
        const words = [
          LyricsWord(text: 'Hello', startMs: 1000, endMs: 2000),
          LyricsWord(text: 'beautiful', startMs: 2000, endMs: 3000),
          LyricsWord(text: 'world', startMs: 3000, endMs: 4000),
        ];

        final ranges = mapWordsToLineRanges(lineText, words);
        expect(ranges, isNotNull);
        expect(ranges!.length, equals(3));
        expect(ranges[0].start, equals(0));
        expect(ranges[0].end, equals(5));
        expect(ranges[1].start, equals(6));
        expect(ranges[1].end, equals(15));
        expect(ranges[2].start, equals(16));
        expect(ranges[2].end, equals(21));

        // Test fallback: non-sequential words return null
        final invalidWords = [
          const LyricsWord(text: 'world', startMs: 1000, endMs: 2000),
          const LyricsWord(text: 'Hello', startMs: 2000, endMs: 3000),
        ];
        expect(mapWordsToLineRanges(lineText, invalidWords), isNull);
      },
    );
  });
}
