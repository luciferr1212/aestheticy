import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/features/lyrics/lrc_parser.dart';
import 'package:aestheticy/features/lyrics/lyrics_controller.dart';
import 'package:aestheticy/features/lyrics/lyrics_models.dart';
import 'package:aestheticy/features/lyrics/lyrics_offset_store.dart';
import 'package:aestheticy/features/lyrics/lyrics_repository.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/sqlite_library_repository.dart';
import 'package:aestheticy/ui/glass/glass_blur_budget.dart';
import 'package:aestheticy/ui/glass/glass_button.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/l10n/app_strings.dart';
import 'package:aestheticy/ui/lyrics/lyrics_view.dart';
import 'package:aestheticy/ui/queue/queue_view.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/app_shortcuts.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/settings/shortcuts_cheat_sheet_dialog.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/shell/app_shell.dart';
import 'package:aestheticy/ui/shell/side_panel_controller.dart';
import 'package:aestheticy/ui/shell/sidebar.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';

class _FakeLyricsRepository extends LyricsRepository {
  LyricsResult result = const LyricsResultNotFound();

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
    return result;
  }
}

AudioSource _track(String id, {String titlePrefix = 'Song'}) {
  return AudioSource(
    'C:\\Music\\$id.mp3',
    extras: {
      'title': '$titlePrefix $id',
      'artist': 'Artist $id',
      'album': 'Album $id',
      'durationMs': '180000',
    },
  );
}

void main() {
  group('SidePanel Controls, Shortcuts, Navigation, and RTL (S2)', () {
    late Directory tempDir;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController playbackController;
    late SqliteLibraryRepository repository;
    late ScanService scanService;
    late SettingsStore settingsStore;
    late GlassController glassController;
    late AppNavigator navigator;
    late UserCollections userCollections;
    late _FakeLyricsRepository lyricsRepository;
    late LyricsOffsetStore offsetStore;
    late LyricsController lyricsController;
    late SidePanelController sidePanelController;

    setUp(() async {
      AppLogger.instance = AppLogger(customSink: StringBuffer());
      GlassBlurBudget.instance.resetForTesting();
      tempDir = await Directory.systemTemp.createTemp('aestheticy_panel_s2_');
      engine = FakeAudioEngine();
      await engine.init();
      queue = PlaybackQueue();
      playbackController = PlaybackController(engine: engine, queue: queue);
      await playbackController.init();
      repository = SqliteLibraryRepository.inMemory();
      await repository.addFolder('C:\\Music');
      scanService = ScanService(repository: repository);
      settingsStore = SettingsStore(
        directory: tempDir,
        initialSettings: const AppSettings(
          language: 'en',
          glassQuality: GlassQuality.off,
          reduceMotion: true,
        ),
      );
      await settingsStore.init();
      glassController = GlassController();
      settingsStore.bindGlassController(glassController);
      navigator = AppNavigator();
      userCollections = UserCollections(repository: repository);
      await userCollections.init();
      lyricsRepository = _FakeLyricsRepository();
      offsetStore = LyricsOffsetStore(directory: tempDir);
      await offsetStore.init();
      lyricsController = LyricsController(
        playbackController: playbackController,
        repository: lyricsRepository,
        settingsStore: settingsStore,
        offsetStore: offsetStore,
      );
      sidePanelController = SidePanelController(settingsStore: settingsStore);
    });

    tearDown(() async {
      sidePanelController.dispose();
      lyricsController.dispose();
      offsetStore.dispose();
      userCollections.dispose();
      settingsStore.dispose();
      scanService.dispose();
      await repository.close();
      await playbackController.dispose();
      await engine.dispose();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    void setViewport(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    Widget buildShell({
      String language = 'en',
      TextDirection textDirection = TextDirection.ltr,
    }) {
      return GlassScope(
        controller: glassController,
        child: SettingsScope(
          store: settingsStore,
          child: MaterialApp(
            locale: Locale(language),
            theme: buildAppTheme(),
            builder: (context, child) => Directionality(
              textDirection: textDirection,
              child: child!,
            ),
            home: AppShell(
              engine: engine,
              controller: playbackController,
              repository: repository,
              scanService: scanService,
              settingsStore: settingsStore,
              navigator: navigator,
              userCollections: userCollections,
              lyricsController: lyricsController,
              sidePanelController: sidePanelController,
            ),
          ),
        ),
      );
    }

    GlassIconButton findGlassIcon(WidgetTester tester, String keyName) {
      return tester.widget<GlassIconButton>(find.byKey(Key(keyName)));
    }

    testWidgets(
      'bottom bar queue and lyrics buttons toggle panel, switch tabs, and reflect selected state',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 800));
        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        expect(sidePanelController.isOpen, isFalse);
        expect(find.byKey(const Key('side_panel_surface')), findsNothing);
        expect(
          findGlassIcon(tester, 'player_queue_button').variant,
          GlassButtonVariant.normal,
        );
        expect(
          findGlassIcon(tester, 'player_lyrics_button').variant,
          GlassButtonVariant.normal,
        );

        // 1. Tap Queue -> opens panel on Queue tab
        await tester.tap(find.byKey(const Key('player_queue_button')));
        await tester.pumpAndSettle();
        expect(sidePanelController.isOpen, isTrue);
        expect(sidePanelController.activeTab, SidePanelTab.queue);
        expect(find.byKey(const ValueKey('side_panel_queue_content')), findsOneWidget);
        expect(
          findGlassIcon(tester, 'player_queue_button').variant,
          GlassButtonVariant.selected,
        );
        expect(
          findGlassIcon(tester, 'player_lyrics_button').variant,
          GlassButtonVariant.normal,
        );

        // 2. Tap Lyrics while Queue active -> switches to Lyrics tab
        await tester.tap(find.byKey(const Key('player_lyrics_button')));
        await tester.pumpAndSettle();
        expect(sidePanelController.isOpen, isTrue);
        expect(sidePanelController.activeTab, SidePanelTab.lyrics);
        expect(find.byKey(const ValueKey('side_panel_lyrics_content')), findsOneWidget);
        expect(
          findGlassIcon(tester, 'player_queue_button').variant,
          GlassButtonVariant.normal,
        );
        expect(
          findGlassIcon(tester, 'player_lyrics_button').variant,
          GlassButtonVariant.selected,
        );

        // 3. Tap Lyrics again while active -> closes panel
        await tester.tap(find.byKey(const Key('player_lyrics_button')));
        await tester.pumpAndSettle();
        expect(sidePanelController.isOpen, isFalse);
        expect(find.byKey(const Key('side_panel_surface')), findsNothing);
        expect(
          findGlassIcon(tester, 'player_lyrics_button').variant,
          GlassButtonVariant.normal,
        );

        // 4. Tap Lyrics when closed -> opens directly on Lyrics
        await tester.tap(find.byKey(const Key('player_lyrics_button')));
        await tester.pumpAndSettle();
        expect(sidePanelController.isOpen, isTrue);
        expect(sidePanelController.activeTab, SidePanelTab.lyrics);

        // 5. Tap Queue -> switches to Queue, then Queue again -> closes
        await tester.tap(find.byKey(const Key('player_queue_button')));
        await tester.pumpAndSettle();
        expect(sidePanelController.activeTab, SidePanelTab.queue);
        await tester.tap(find.byKey(const Key('player_queue_button')));
        await tester.pumpAndSettle();
        expect(sidePanelController.isOpen, isFalse);

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'panel header is symmetric and Close/Expand buttons navigate cleanly without auto-reopening on return',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 800));
        await playbackController.playQueue([_track('One'), _track('Two')]);
        sidePanelController.open(tab: SidePanelTab.queue);

        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        final cardRect = tester.getRect(
          find
              .descendant(
                of: find.byKey(const Key('side_panel_surface')),
                matching: find.byType(Column),
              )
              .first,
        );
        final expandRect = tester.getRect(find.byKey(const Key('side_panel_expand_button')));
        final closeRect = tester.getRect(find.byKey(const Key('side_panel_close_button')));
        final queueTabRect = tester.getRect(find.byKey(const Key('side_panel_tab_queue')));
        final lyricsTabRect = tester.getRect(find.byKey(const Key('side_panel_tab_lyrics')));

        // Symmetry check: equal outer button widths and centered tab pill within card
        expect(expandRect.width, closeTo(closeRect.width, 0.5));
        expect(
          expandRect.left - cardRect.left,
          closeTo(cardRect.right - closeRect.right, 1.5),
        );
        final tabGroupCenterX = (queueTabRect.left + lyricsTabRect.right) / 2.0;
        expect(tabGroupCenterX, closeTo(cardRect.center.dx, 2.0));

        // Tab switch in header
        await tester.tap(find.byKey(const Key('side_panel_tab_lyrics')));
        await tester.pumpAndSettle();
        expect(sidePanelController.activeTab, SidePanelTab.lyrics);
        expect(find.byKey(const ValueKey('side_panel_lyrics_content')), findsOneWidget);

        // Expand on Lyrics -> opens full LyricsView & closes panel; leaving does NOT reopen
        await tester.tap(find.byKey(const Key('side_panel_expand_button')));
        await tester.pumpAndSettle();
        expect(navigator.current, AppDestination.lyrics);
        expect(sidePanelController.isOpen, isFalse);
        expect(find.byType(LyricsView), findsOneWidget);

        navigator.goBack();
        await tester.pumpAndSettle();
        expect(navigator.current, AppDestination.albums);
        expect(sidePanelController.isOpen, isFalse);
        expect(find.byKey(const Key('side_panel_surface')), findsNothing);

        // Open panel on Queue -> Expand opens full QueueView & closes panel; leaving keeps closed
        sidePanelController.open(tab: SidePanelTab.queue);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('side_panel_expand_button')));
        await tester.pumpAndSettle();
        expect(navigator.current, AppDestination.queue);
        expect(sidePanelController.isOpen, isFalse);
        expect(find.byType(QueueView), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(navigator.current, AppDestination.albums);
        expect(sidePanelController.isOpen, isFalse);
        expect(find.byKey(const Key('side_panel_surface')), findsNothing);

        // Close button in panel header closes panel
        sidePanelController.open(tab: SidePanelTab.queue);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('side_panel_close_button')));
        await tester.pumpAndSettle();
        expect(sidePanelController.isOpen, isFalse);
        expect(find.byKey(const Key('side_panel_surface')), findsNothing);

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'Ctrl+Shift+Q and Ctrl+Shift+L toggle panel via kAppShortcuts, respect EditableText, and appear in shortcuts help (en + ar)',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        expect(
          shortcutById(AppShortcutId.toggleQueuePanel).keyCombination,
          equals('Ctrl + Shift + Q'),
        );
        expect(
          shortcutById(AppShortcutId.toggleLyricsPanel).keyCombination,
          equals('Ctrl + Shift + L'),
        );
        expect(
          shortcutById(AppShortcutId.toggleQueuePanel).scope,
          AppShortcutScope.global,
        );
        expect(
          shortcutById(AppShortcutId.toggleLyricsPanel).scope,
          AppShortcutScope.global,
        );

        setViewport(tester, const Size(1280, 800));
        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        Future<void> sendCtrlShiftKey(LogicalKeyboardKey key) async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(key);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pumpAndSettle();
        }

        // Ctrl+Shift+Q opens Queue tab
        await sendCtrlShiftKey(LogicalKeyboardKey.keyQ);
        expect(sidePanelController.isOpen, isTrue);
        expect(sidePanelController.activeTab, SidePanelTab.queue);

        // Ctrl+Shift+L switches to Lyrics tab
        await sendCtrlShiftKey(LogicalKeyboardKey.keyL);
        expect(sidePanelController.isOpen, isTrue);
        expect(sidePanelController.activeTab, SidePanelTab.lyrics);

        // Ctrl+Shift+L again closes panel
        await sendCtrlShiftKey(LogicalKeyboardKey.keyL);
        expect(sidePanelController.isOpen, isFalse);

        // Navigate to Tracks where there is a search EditableText and verify shortcut ignored while typing
        navigator.navigateTo(AppDestination.tracks);
        await tester.pumpAndSettle();
        final searchField = find.byType(TextField).first;
        await tester.tap(searchField);
        await tester.pump();
        await sendCtrlShiftKey(LogicalKeyboardKey.keyQ);
        expect(sidePanelController.isOpen, isFalse);

        // Restore focus inside AppShell's Focus tree before opening Shortcuts cheat sheet via Ctrl + /
        await tester.tap(find.byKey(const Key('sidebar_albums')));
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        final dialogFinder = find.byKey(const Key('shortcuts_cheat_sheet_dialog'));
        expect(dialogFinder, findsOneWidget);
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text(AppStrings.t('shortcuts.toggleQueuePanel')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text(AppStrings.t('shortcuts.toggleLyricsPanel')),
          ),
          findsOneWidget,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        // Arabic cheat sheet check
        settingsStore.update((s) => s.copyWith(language: 'ar'));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          SettingsScope(
            store: settingsStore,
            child: const MaterialApp(
              locale: Locale('ar'),
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: ShortcutsCheatSheetDialog(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(AppStrings.t('shortcuts.toggleQueuePanel', language: 'ar')),
          findsOneWidget,
        );
        expect(
          find.text(AppStrings.t('shortcuts.toggleLyricsPanel', language: 'ar')),
          findsOneWidget,
        );

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'tooltips/semantics are localized (en + ar), hover cursors are click, and Tab navigates panel header controls',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        setViewport(tester, const Size(1280, 800));
        sidePanelController.open(tab: SidePanelTab.queue);
        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        // Localized tooltips in EN
        expect(
          findGlassIcon(tester, 'player_queue_button').tooltip,
          equals(AppStrings.t('sidePanel.closeQueue', language: 'en')),
        );
        expect(
          findGlassIcon(tester, 'player_lyrics_button').tooltip,
          equals(AppStrings.t('sidePanel.openLyrics', language: 'en')),
        );
        expect(
          findGlassIcon(tester, 'side_panel_expand_button').tooltip,
          equals(AppStrings.t('sidePanel.expandQueue', language: 'en')),
        );
        expect(
          findGlassIcon(tester, 'side_panel_close_button').tooltip,
          equals(AppStrings.t('sidePanel.close', language: 'en')),
        );

        // Hover cursor checks across header buttons and tabs
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);
        await tester.pump();
        for (final key in [
          const Key('side_panel_expand_button'),
          const Key('side_panel_tab_queue'),
          const Key('side_panel_tab_lyrics'),
          const Key('side_panel_close_button'),
        ]) {
          await gesture.moveTo(tester.getCenter(find.byKey(key)));
          await tester.pump();
          expect(
            RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
            equals(SystemMouseCursors.click),
            reason: 'Expected click cursor on $key',
          );
        }
        await gesture.removePointer();
        await tester.pump();

        // Keyboard focus order across header controls
        FocusNode focusNodeFor(Key parentKey) {
          final gestureEl = tester.element(
            find.descendant(
              of: find.byKey(parentKey),
              matching: find.byType(GestureDetector),
            ),
          );
          return Focus.of(gestureEl);
        }

        final expandFocusNode =
            focusNodeFor(const Key('side_panel_expand_button'));
        expandFocusNode.requestFocus();
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, equals(expandFocusNode));

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus,
          equals(focusNodeFor(const Key('side_panel_tab_queue'))),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus,
          equals(focusNodeFor(const Key('side_panel_tab_lyrics'))),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(sidePanelController.activeTab, SidePanelTab.lyrics);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus,
          equals(focusNodeFor(const Key('side_panel_close_button'))),
        );

        // Localized tooltips in AR
        settingsStore.update((s) => s.copyWith(language: 'ar'));
        await tester.pumpWidget(buildShell(language: 'ar', textDirection: TextDirection.rtl));
        await tester.pumpAndSettle();
        expect(
          findGlassIcon(tester, 'player_lyrics_button').tooltip,
          equals(AppStrings.t('sidePanel.closeLyrics', language: 'ar')),
        );
        expect(
          findGlassIcon(tester, 'side_panel_expand_button').tooltip,
          equals(AppStrings.t('sidePanel.expandLyrics', language: 'ar')),
        );
        expect(
          findGlassIcon(tester, 'side_panel_close_button').tooltip,
          equals(AppStrings.t('sidePanel.close', language: 'ar')),
        );

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'RTL Arabic build renders without overflow across 3 widths (900, 1120, 1440), mirrors panel opposite Sidebar, and keeps LTR transport row',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
        settingsStore.update((s) => s.copyWith(language: 'ar', reduceMotion: true));
        lyricsRepository.result = LyricsResultFound(
          LyricsDocument(
            kind: LyricsKind.synced,
            lines: parseLrc('[00:01.00]أغنية عربية رائعة\n[00:05.00]سطر ثاني للتجربة').lines,
            source: LyricsSourceOrigin.local,
            hasWordTiming: false,
          ),
        );
        await tester.runAsync(() async {
          await playbackController.playQueue([
            _track('واحد', titlePrefix: 'أغنية'),
            _track('اثنان', titlePrefix: 'أغنية'),
          ]);
          await lyricsController.retry();
        });

        sidePanelController.open(tab: SidePanelTab.queue);

        for (final width in [900.0, 1120.0, 1440.0]) {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;

          for (final tab in [SidePanelTab.queue, SidePanelTab.lyrics]) {
            sidePanelController.setTab(tab);
            await tester.pumpWidget(
              buildShell(language: 'ar', textDirection: TextDirection.rtl),
            );
            await tester.pumpAndSettle();

            expect(
              tester.takeException(),
              isNull,
              reason: 'No overflow at width=$width tab=$tab in RTL',
            );

            // Transport row MUST stay LTR: prev < play/pause < next
            final prevDx = tester.getCenter(find.byKey(const Key('bottom_bar_prev_button'))).dx;
            final playDx =
                tester.getCenter(find.byKey(const Key('bottom_bar_play_pause_button'))).dx;
            final nextDx = tester.getCenter(find.byKey(const Key('bottom_bar_next_button'))).dx;
            expect(prevDx, lessThan(playDx));
            expect(playDx, lessThan(nextDx));

            if (width < SidePanelController.kAutoHideWidthThreshold) {
              expect(find.byKey(const Key('side_panel_surface')), findsNothing);
              expect(sidePanelController.isOpen, isTrue);
            } else {
              expect(find.byKey(const Key('side_panel_surface')), findsOneWidget);
              final sidebarCenter = tester.getCenter(find.byType(Sidebar));
              final contentCenter =
                  tester.getCenter(find.byKey(const Key('app_shell_content_area')));
              final panelCenter =
                  tester.getCenter(find.byKey(const Key('side_panel_surface')));
              // In RTL: Sidebar is on the right edge; docked SidePanel mirrors onto the left edge
              expect(sidebarCenter.dx, greaterThan(contentCenter.dx));
              expect(panelCenter.dx, lessThan(contentCenter.dx));
            }
          }
        }

        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.pump(const Duration(milliseconds: 500));
      },
    );
  });
}
