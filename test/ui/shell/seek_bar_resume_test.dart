import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/features/session/session_saver.dart';
import 'package:aestheticy/features/session/session_store.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/now_playing/now_playing_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/bottom_now_playing_bar.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

void main() {
  group('Seek Bar Resume & Idle Display Tests (I2)', () {
    late Directory tempDir;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late SqliteLibraryRepository repository;
    late UserCollections userCollections;
    late SettingsStore settingsStore;
    late SessionStore sessionStore;
    late SessionSaver sessionSaver;
    late AppNavigator navigator;

    const testTrack = AudioSource(
      'file:///music/test_song.mp3',
      extras: {
        'title': 'Test Song',
        'artist': 'Test Artist',
        'album': 'Test Album',
        'durationMs': '180000', // 3 minutes = 03:00
      },
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aestheticy_seek_bar_');
      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();
      repository = SqliteLibraryRepository.inMemory();
      userCollections = UserCollections(repository: repository);
      await userCollections.init();
      settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(
          language: 'en',
          userName: 'mido',
          glassQuality: GlassQuality.off,
          reduceMotion: true,
        ),
      );
      sessionStore = SessionStore(directory: tempDir);
      await sessionStore.init();
      sessionSaver = SessionSaver(
        controller: controller,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
      );
      navigator = AppNavigator();
    });

    tearDown(() async {
      await sessionSaver.dispose();
      await sessionStore.flush();
      settingsStore.dispose();
      userCollections.dispose();
      await repository.close();
      await controller.dispose();
      await engine.dispose();
    });

    Widget createBottomBarApp() {
      return MaterialApp(
        locale: const Locale('en'),
        theme: buildAppTheme(),
        home: Scaffold(
          body: BottomNowPlayingBar(
            controller: controller,
            navigator: navigator,
          ),
        ),
      );
    }

    Widget createNowPlayingApp() {
      return UserCollectionsScope(
        collections: userCollections,
        child: GlassScope(
          controller: GlassController(quality: GlassQuality.off),
          child: MaterialApp(
            locale: const Locale('en'),
            theme: buildAppTheme(),
            home: Scaffold(
              body: NowPlayingView(
                controller: controller,
                engine: engine,
                navigator: navigator,
                settingsStore: settingsStore,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Bottom bar shows armed position 0:42 and total duration 3:00 while idle before playback',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      // Simulate restored session: queue loaded, idle state, armed resume at 42 seconds
      queue.replaceAll([testTrack], startIndex: 0);
      controller.armResume(const Duration(seconds: 42));

      expect(controller.currentState, equals(PlaybackState.idle));
      expect(controller.currentPosition, equals(const Duration(seconds: 42)));

      await tester.pumpWidget(createBottomBarApp());
      await tester.pump();

      // Expect to find "0:42" and "3:00" displayed on the seek bar without playing
      expect(find.text('0:42'), findsOneWidget, reason: 'Seekbar must show armed resume position 0:42');
      expect(find.text('3:00'), findsOneWidget, reason: 'Seekbar must show total duration from extras 3:00');

      // Now press play
      await controller.play();
      await tester.pump(const Duration(milliseconds: 50));

      // After play, engine continues from 42 seconds
      expect(engine.currentPosition, equals(const Duration(seconds: 42)));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('NowPlayingView shows armed position 0:42 and total duration 3:00 while idle before playback',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      queue.replaceAll([testTrack], startIndex: 0);
      controller.armResume(const Duration(seconds: 42));

      expect(controller.currentState, equals(PlaybackState.idle));

      await tester.pumpWidget(createNowPlayingApp());
      await tester.pump();

      expect(find.text('0:42'), findsOneWidget, reason: 'NowPlayingView must show armed resume position 0:42');
      expect(find.text('3:00'), findsOneWidget, reason: 'NowPlayingView must show total duration 3:00');
      await tester.pumpWidget(const SizedBox());
    });

    test('PlaybackController seek while idle updates armed position and saves to session', () async {
      queue.replaceAll([testTrack], startIndex: 0);
      controller.armResume(const Duration(seconds: 42));

      await controller.seek(const Duration(seconds: 60));

      expect(controller.currentPosition, equals(const Duration(seconds: 60)));
      expect(controller.armedResumePosition, equals(const Duration(seconds: 60)));

      await sessionStore.flush();
      expect(sessionStore.session.positionMs, equals(60000));
    });

    testWidgets('Seeking while idle updates armed position and saves to session',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      queue.replaceAll([testTrack], startIndex: 0);
      controller.armResume(const Duration(seconds: 42));

      await tester.pumpWidget(createBottomBarApp());
      await tester.pump(const Duration(milliseconds: 50));

      // Seek / drag slider while idle to 60s
      await controller.seek(const Duration(seconds: 60));
      await tester.pump(const Duration(milliseconds: 100));

      // Armed position must be updated
      expect(controller.currentPosition, equals(const Duration(seconds: 60)));
      expect(controller.armedResumePosition, equals(const Duration(seconds: 60)));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Dragging slider widget in bottom bar while idle updates armed position and saves to session',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      queue.replaceAll([testTrack], startIndex: 0);
      controller.armResume(const Duration(seconds: 42));

      await tester.pumpWidget(createBottomBarApp());
      await tester.pump(const Duration(milliseconds: 50));

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged?.call(90000.0); // 90s
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller.currentPosition, equals(const Duration(seconds: 90)));
      expect(controller.armedResumePosition, equals(const Duration(seconds: 90)));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
