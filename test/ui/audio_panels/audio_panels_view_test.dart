import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_engine.dart';
import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/audio_panels/audio_panels_view.dart';
import 'package:aestheticy/ui/audio_panels/eq_controller.dart';
import 'package:aestheticy/ui/audio_panels/eq_store.dart';
import 'package:aestheticy/ui/glass/glass_blur_budget.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/glass/glass_surface.dart';
import 'package:aestheticy/ui/now_playing/now_playing_view.dart';
import 'package:aestheticy/ui/settings/audio_settings_applier.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/settings/settings_view.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';

class _NoEqEngine extends FakeAudioEngine {
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        exclusiveMode: true,
        gapless: true,
        equalizer: false,
        replayGain: true,
      );
}

void main() {
  late Directory tempDir;
  late FakeAudioEngine engine;
  late SettingsStore settingsStore;
  late EqStore eqStore;
  late EqController eqController;
  late AudioSettingsApplier applier;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audio_panels_view_test_');
    engine = FakeAudioEngine();
    settingsStore = SettingsStore(directoryProvider: () async => tempDir);
    await settingsStore.init();

    eqStore = EqStore(directoryProvider: () async => tempDir);
    await eqStore.init();

    eqController = EqController(engine: engine, store: eqStore);
    await eqController.applyAll();

    applier = AudioSettingsApplier(
      engine: engine,
      settingsStore: settingsStore,
    );
    await applier.applyAll();
  });

  tearDown(() async {
    eqController.dispose();
    eqStore.dispose();
    settingsStore.dispose();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Widget buildTestWidget({
    Size size = const Size(1280, 800),
    double textScale = 1.0,
    Locale locale = const Locale('en'),
    AudioEngine? customEngine,
    EqController? customEqController,
    AppNavigator? navigator,
  }) {
    final effectiveEngine = customEngine ?? engine;
    final effectiveEq = customEqController ?? eqController;
    final effectiveNav = navigator ?? AppNavigator();

    return MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(
        textDirection:
            locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: GlassScope(
          controller: GlassController(),
          child: SettingsScope(
            store: settingsStore,
            child: MaterialApp(
              locale: locale,
              home: Scaffold(
                body: AudioPanelsView(
                  engine: effectiveEngine,
                  eqController: effectiveEq,
                  audioSettingsApplier: applier,
                  settingsStore: settingsStore,
                  navigator: effectiveNav,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('AudioPanelsView Widget & Interaction Tests', () {
    testWidgets('renders side-by-side at 1280x800 and vertical stacked at 1000x700 without overflow',
        (tester) async {
      // 1. Wide viewport
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(buildTestWidget(size: const Size(1280, 800)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Equalizer'), findsWidgets);
      expect(find.text('Signal Path'), findsOneWidget);

      // 2. Narrow viewport + Large text scale
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      await tester.pumpWidget(buildTestWidget(
        size: const Size(1000, 700),
        textScale: 1.10,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Equalizer'), findsWidgets);
      expect(find.text('Signal Path'), findsOneWidget);
    });

    testWidgets('renders correctly in Arabic (RTL) and band sliders stay low-to-high LTR',
        (tester) async {
      settingsStore.update((s) => s.copyWith(language: 'ar'));
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(buildTestWidget(
        locale: const Locale('ar'),
        size: const Size(1280, 800),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Arabic titles
      expect(find.text('معادل الصوت'), findsWidgets);
      expect(find.text('مسار الإشارة'), findsOneWidget);

      // Verify band sliders order low-to-high left-to-right
      final slider31 = find.text('31');
      final slider16k = find.text('16k');
      expect(slider31, findsOneWidget);
      expect(slider16k, findsOneWidget);

      final pos31 = tester.getCenter(slider31);
      final pos16k = tester.getCenter(slider16k);
      // 31 Hz should be to the left of 16 kHz even in RTL!
      expect(pos31.dx < pos16k.dx, isTrue);

      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('arrow keys change focused band and double tap resets',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Find the first band slider (31 Hz)
      final band0Finder = find.bySemanticsLabel(RegExp(r'31Hz'));
      expect(band0Finder, findsOneWidget);

      // Focus the band
      Focus.of(tester.element(band0Finder)).requestFocus();
      await tester.pumpAndSettle();

      // Send ArrowUp key
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(eqController.gains[0], 0.5);

      // Send ArrowDown key
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(eqController.gains[0], 0.0);

      // Double-tap to reset
      await eqController.setBand(0, 4.0);
      await tester.pumpAndSettle();
      expect(eqController.gains[0], 4.0);

      await tester.tap(band0Finder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(band0Finder);
      await tester.pumpAndSettle();
      expect(eqController.gains[0], 0.0);

      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('disabled state when equalizer capability is false',
        (tester) async {
      final noEqEngine = _NoEqEngine();
      final noEqController = EqController(engine: noEqEngine, store: eqStore);

      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(buildTestWidget(
        customEngine: noEqEngine,
        customEqController: noEqController,
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('Equalizer is not supported by your audio engine.'),
        findsOneWidget,
      );
      // Switch is disabled
      final switchFinder = find.byKey(const Key('eq_enabled_switch'));
      expect(tester.widget<Switch>(switchFinder).onChanged, isNull);

      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('turn off processing turns off EQ and ReplayGain',
        (tester) async {
      await eqController.setEnabled(true);
      await applier.setReplayGainMode(ReplayGainMode.album);
      await applier.setReplayGainPreamp(3.0);

      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(eqController.enabled, isTrue);
      expect(engine.replayGainMode, ReplayGainMode.album);

      final turnOffButton = find.text('Turn off processing');
      expect(turnOffButton, findsOneWidget);
      await tester.ensureVisible(turnOffButton);
      await tester.pumpAndSettle();
      await tester.tap(turnOffButton);
      await tester.pumpAndSettle();

      expect(eqController.enabled, isFalse);
      expect(engine.replayGainMode, ReplayGainMode.off);
      expect(engine.replayGainPreamp, 0.0);

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('blurred surfaces count stays within budget (<= 6)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final surfaces = tester.widgetList<GlassSurface>(find.byType(GlassSurface)).toList();
      // On AudioPanelsView there are at most 2 glass surface cards
      expect(surfaces.length <= kMaxBlurredSurfaces, isTrue);

      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('entry points: Now Playing icon buttons and stream info pill navigate to audioPanels',
        (tester) async {
      final nav = AppNavigator();
      final controller = PlaybackController(engine: engine, queue: PlaybackQueue());
      await controller.init();

      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NowPlayingView(
              controller: controller,
              engine: engine,
              navigator: nav,
              settingsStore: settingsStore,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap stream info pill
      final pillFinder = find.byKey(const Key('now_playing_stream_info_pill'));
      expect(pillFinder, findsOneWidget);
      await tester.tap(pillFinder);
      await tester.pumpAndSettle();
      expect(nav.current, AppDestination.audioPanels);

      // Reset
      nav.navigateTo(AppDestination.nowPlaying);

      // Tap EQ icon button
      final eqIconFinder = find.byKey(const Key('now_playing_eq_button'));
      expect(eqIconFinder, findsOneWidget);
      await tester.tap(eqIconFinder);
      await tester.pumpAndSettle();
      expect(nav.current, AppDestination.audioPanels);

      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('entry points: Settings row opens audioPanels and Esc navigates back',
        (tester) async {
      final nav = AppNavigator();
      nav.navigateTo(AppDestination.settings);

      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsView(
              settingsStore: settingsStore,
              audioSettingsApplier: applier,
              engine: engine,
              repository: SqliteLibraryRepository.inMemory(),
              navigator: nav,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure open button is visible and tap it
      final openBtn = find.byKey(const Key('settings_open_audio_panels_button'));
      await tester.scrollUntilVisible(
        openBtn,
        100.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(openBtn);
      await tester.pumpAndSettle();
      expect(nav.current, AppDestination.audioPanels);

      // Esc navigates back
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(nav.current, AppDestination.settings);

      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
