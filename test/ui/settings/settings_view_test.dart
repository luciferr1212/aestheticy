import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/artist_names/artist_name_scope.dart';
import 'package:aestheticy/ui/artist_names/artist_name_store.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/settings/app_settings.dart';
import 'package:aestheticy/ui/settings/app_shortcuts.dart';
import 'package:aestheticy/ui/settings/audio_settings_applier.dart';
import 'package:aestheticy/ui/settings/settings_scope.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/settings/settings_view.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';

class _FakeLibraryRepository extends Fake implements LibraryRepository {
  final List<LibraryFolder> folders;
  final int count;
  int playCount = 42;
  final int albums = 5;
  final int artists = 3;

  _FakeLibraryRepository({
    this.folders = const [],
    this.count = 1,
  });

  @override
  Future<List<LibraryFolder>> listFolders() async => folders;

  @override
  Future<int> trackCount() async => count;

  @override
  Future<int> albumCount() async => albums;

  @override
  Future<int> artistCount() async => artists;

  @override
  Future<int> playEventCount({bool countedOnly = false}) async => playCount;

  @override
  Future<void> clearPlayEvents() async {
    playCount = 0;
  }
}

class _FailingAudioEngine extends FakeAudioEngine {
  bool failDevice = false;

  @override
  Future<void> selectDevice(String id) async {
    if (failDevice) throw Exception('Device failed');
    return super.selectDevice(id);
  }
}

Widget _buildTestSettingsApp({
  required FakeAudioEngine engine,
  required LibraryRepository repository,
  required SettingsStore settingsStore,
  required AppNavigator navigator,
  required AudioSettingsApplier audioSettingsApplier,
  required ArtistNameStore artistNameStore,
  VoidCallback? onOpenFolders,
  Size size = const Size(1280, 800),
  bool isWindowsOverride = true,
}) {
  return ListenableBuilder(
    listenable: settingsStore,
    builder: (context, _) {
      final isArabic = settingsStore.settings.language == 'ar';
      final scaleFactor = switch (settingsStore.settings.textScale) {
        'small' => 0.92,
        'large' => 1.10,
        _ => 1.0,
      };

      return MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: size,
            textScaler: TextScaler.linear(scaleFactor),
          ),
          child: Directionality(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            child: SettingsScope(
              store: settingsStore,
              child: ArtistNameScope(
                store: artistNameStore,
                child: child!,
              ),
            ),
          ),
        ),
        home: Scaffold(
          body: SettingsView(
            engine: engine,
            repository: repository,
            settingsStore: settingsStore,
            navigator: navigator,
            audioSettingsApplier: audioSettingsApplier,
            artistNameStore: artistNameStore,
            onOpenFolders: onOpenFolders ?? () {},
            isWindowsOverride: isWindowsOverride,
          ),
        ),
      );
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SettingsStore settingsStore;
  late ArtistNameStore artistNameStore;
  late FakeAudioEngine engine;
  late _FakeLibraryRepository repository;
  late AppNavigator navigator;
  late AudioSettingsApplier audioSettingsApplier;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('aestheticy_settings_view_test_');
    settingsStore = SettingsStore(directory: tempDir, initialSettings: const AppSettings());
    artistNameStore = ArtistNameStore(directory: tempDir, initialEntries: const {});
    engine = FakeAudioEngine();
    repository = _FakeLibraryRepository(
      folders: [const LibraryFolder(id: 1, path: 'C:\\Music')],
      count: 1,
    );
    navigator = AppNavigator();
    navigator.navigateTo(AppDestination.settings);
    audioSettingsApplier = AudioSettingsApplier(
      engine: engine,
      settingsStore: settingsStore,
    );
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets('renders Settings title and all 8 sections in English', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: engine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: audioSettingsApplier,
        artistNameStore: artistNameStore,
      ),
    );
    await tester.pumpAndSettle();

    final scrollFinder = find.byType(Scrollable).first;

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Language and profile'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Fonts'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Artist names'), 100.0, scrollable: scrollFinder);
    expect(find.text('Artist names'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Audio'), 100.0, scrollable: scrollFinder);
    expect(find.text('Audio'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Playback'), 100.0, scrollable: scrollFinder);
    expect(find.text('Playback'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Windows integration'), 100.0, scrollable: scrollFinder);
    expect(find.text('Windows integration'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Library'), 100.0, scrollable: scrollFinder);
    expect(find.text('Library'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Listening history'), 100.0, scrollable: scrollFinder);
    expect(find.text('Listening history'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Shortcuts'), 100.0, scrollable: scrollFinder);
    expect(find.text('Shortcuts'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Diagnostics'), 100.0, scrollable: scrollFinder);
    expect(find.text('Diagnostics'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('About'), 100.0, scrollable: scrollFinder);
    expect(find.text('About'), findsOneWidget);

    // About section content
    expect(find.text('Aestheticy'), findsOneWidget);
    expect(find.text('by mido'), findsOneWidget);
  });

  testWidgets('renders without overflow at 1280x800 and 1000x700 with textScale large', (tester) async {
    settingsStore.update((s) => s.copyWith(textScale: 'large', language: 'ar'));
    await tester.pump(const Duration(milliseconds: 500));

    // Test 1280x800 RTL
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: engine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: audioSettingsApplier,
        artistNameStore: artistNameStore,
        size: const Size(1280, 800),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Test 1000x700 RTL
    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: engine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: audioSettingsApplier,
        artistNameStore: artistNameStore,
        size: const Size(1000, 700),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets('toggling language to Arabic switches text direction and strings live', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: engine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: audioSettingsApplier,
        artistNameStore: artistNameStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);

    // Tap Arabic language option
    final arBtn = find.text('العربية');
    expect(arBtn, findsOneWidget);
    await tester.tap(arBtn);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(settingsStore.settings.language, equals('ar'));
    expect(find.text('الإعدادات'), findsOneWidget);
    expect(find.text('اللغة والملف الشخصي'), findsOneWidget);
  });

  testWidgets('arabic numerals switch is disabled in English and enabled in Arabic', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: engine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: audioSettingsApplier,
        artistNameStore: artistNameStore,
      ),
    );
    await tester.pumpAndSettle();

    final numeralsSwitchFinder = find.byKey(const Key('settings_arabic_numerals_switch'));
    expect(numeralsSwitchFinder, findsOneWidget);
    final switchWidgetEn = tester.widget<Switch>(numeralsSwitchFinder);
    expect(switchWidgetEn.onChanged, isNull); // disabled in English

    // Switch to Arabic
    settingsStore.update((s) => s.copyWith(language: 'ar'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final switchWidgetAr = tester.widget<Switch>(numeralsSwitchFinder);
    expect(switchWidgetAr.onChanged, isNotNull); // enabled in Arabic

    // Toggle switch
    await tester.tap(numeralsSwitchFinder);
    await tester.pump(const Duration(milliseconds: 500));
    expect(settingsStore.settings.arabicNumerals, isTrue);
  });

  testWidgets('toggling glass quality updates settingsStore immediately', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: engine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: audioSettingsApplier,
        artistNameStore: artistNameStore,
      ),
    );
    await tester.pumpAndSettle();

    final lightBtn = find.text('Light');
    expect(lightBtn, findsOneWidget);
    await tester.tap(lightBtn);
    await tester.pump(const Duration(milliseconds: 500));

    expect(settingsStore.settings.glassQuality, equals(GlassQuality.light));
  });

  testWidgets('failure shows the localized message in both languages, nothing persisted', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final failingEngine = _FailingAudioEngine()..failDevice = true;
    await failingEngine.init();
    failingEngine.fakeDevices = [
      AudioDevice.auto,
      const AudioDevice(id: 'dev_1', name: 'Faulty Device'),
    ];

    final failingApplier = AudioSettingsApplier(
      engine: failingEngine,
      settingsStore: settingsStore,
    );

    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: failingEngine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: failingApplier,
        artistNameStore: artistNameStore,
      ),
    );
    await tester.pumpAndSettle();

    final scrollFinder = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Output device'), 100.0, scrollable: scrollFinder);
    await tester.ensureVisible(find.text('Auto'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Faulty Device').last);
    await tester.pumpAndSettle();

    expect(find.text('Could not apply the change. Your previous setting was kept.'), findsOneWidget);
    expect(settingsStore.settings.outputDeviceId, equals('auto'));

    settingsStore.update((s) => s.copyWith(language: 'ar'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('تعذّر تطبيق التغيير. تم الاحتفاظ بإعدادك السابق.'), findsOneWidget);
    expect(settingsStore.settings.outputDeviceId, equals('auto'));

    await failingEngine.dispose();
  });

  testWidgets('displays all shortcuts from kAppShortcuts with localized scope', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: engine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: audioSettingsApplier,
        artistNameStore: artistNameStore,
      ),
    );
    await tester.pumpAndSettle();

    final scrollFinder = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Shortcuts'), 100.0, scrollable: scrollFinder);

    for (final sc in kAppShortcuts) {
      await tester.scrollUntilVisible(find.text(sc.keyCombination), 50.0, scrollable: scrollFinder);
      expect(find.text(sc.keyCombination), findsOneWidget);
      final expectedScope = sc.scope == AppShortcutScope.global ? 'Global' : 'Now playing';
      expect(find.text(expectedScope), findsWidgets);
    }
  });

  testWidgets('navigates back on back button or Esc key', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    navigator.navigateTo(AppDestination.albums);
    navigator.navigateTo(AppDestination.settings);

    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: engine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: audioSettingsApplier,
        artistNameStore: artistNameStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(navigator.current, equals(AppDestination.settings));

    final backBtn = find.byKey(const Key('settings_back_button'));
    expect(backBtn, findsOneWidget);
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    expect(navigator.current, equals(AppDestination.albums));
  });

  testWidgets('S5: Playback resume switch toggles and persists', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: engine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: audioSettingsApplier,
        artistNameStore: artistNameStore,
      ),
    );
    await tester.pumpAndSettle();

    final scrollFinder = find.byType(Scrollable).first;
    final resumeSwitch = find.byKey(const Key('settings_resume_session_switch'));
    await tester.scrollUntilVisible(resumeSwitch, 100.0, scrollable: scrollFinder);
    await tester.ensureVisible(resumeSwitch);
    await tester.pumpAndSettle();

    expect(resumeSwitch, findsOneWidget);
    expect(settingsStore.settings.resumeSession, isTrue);

    // Toggle switch off
    await tester.tap(resumeSwitch);
    await tester.pumpAndSettle();
    expect(settingsStore.settings.resumeSession, isFalse);

    // Toggle switch on
    await tester.tap(resumeSwitch);
    await tester.pumpAndSettle();
    expect(settingsStore.settings.resumeSession, isTrue);
  });

  testWidgets('S5: Listening history count, cancel confirmation leaves count, confirm clears count to 0', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: engine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: audioSettingsApplier,
        artistNameStore: artistNameStore,
      ),
    );
    await tester.pumpAndSettle();

    final scrollFinder = find.byType(Scrollable).first;
    final clearBtn = find.byKey(const Key('settings_clear_history_button'));
    await tester.scrollUntilVisible(clearBtn, 100.0, scrollable: scrollFinder);
    await tester.ensureVisible(clearBtn);
    await tester.pumpAndSettle();

    // Initial count is 42
    expect(find.text('42'), findsOneWidget);

    // Tap clear button to enter inline confirmation
    await tester.tap(clearBtn);
    await tester.pumpAndSettle();

    expect(find.text('Are you sure?'), findsOneWidget);
    final cancelBtn = find.byKey(const Key('settings_clear_history_cancel_button'));
    final confirmBtn = find.byKey(const Key('settings_clear_history_confirm_button'));
    expect(cancelBtn, findsOneWidget);
    expect(confirmBtn, findsOneWidget);

    // Cancel leaves count unchanged
    await tester.tap(cancelBtn);
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
    expect(repository.playCount, equals(42));

    // Tap clear button again and confirm
    final clearAgainBtn = find.byKey(const Key('settings_clear_history_button'));
    await tester.ensureVisible(clearAgainBtn);
    await tester.tap(clearAgainBtn);
    await tester.pumpAndSettle();

    final confirmAgainBtn = find.byKey(const Key('settings_clear_history_confirm_button'));
    await tester.ensureVisible(confirmAgainBtn);
    await tester.tap(confirmAgainBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // Verify count is 0 and SnackBar is displayed
    expect(find.text('0'), findsOneWidget);
    expect(repository.playCount, equals(0));
    expect(find.text('Listening history cleared'), findsOneWidget);
  });

  testWidgets('S6: Diagnostics copy report and copy log path work with SnackBars', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    String? copiedClipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          copiedClipboardText = (methodCall.arguments as Map)['text'] as String?;
          return null;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: engine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: audioSettingsApplier,
        artistNameStore: artistNameStore,
      ),
    );
    await tester.pumpAndSettle();

    final scrollFinder = find.byType(Scrollable).first;
    final copyDiagBtn = find.byKey(const Key('settings_copy_diagnostics_button'));
    await tester.scrollUntilVisible(copyDiagBtn, 100.0, scrollable: scrollFinder);
    await tester.ensureVisible(copyDiagBtn);
    await tester.pumpAndSettle();

    expect(copyDiagBtn, findsOneWidget);
    await tester.tap(copyDiagBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Diagnostic report copied to clipboard'), findsOneWidget);
    expect(copiedClipboardText, contains('=== Aestheticy Diagnostic Report ==='));

    // Wait for first SnackBar to dismiss
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    final copyLogBtn = find.byKey(const Key('settings_copy_log_path_button'));
    await tester.scrollUntilVisible(copyLogBtn, 100.0, scrollable: scrollFinder);
    await tester.ensureVisible(copyLogBtn);
    await tester.pumpAndSettle();

    expect(copyLogBtn, findsOneWidget);
    await tester.tap(copyLogBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Log folder path copied to clipboard'), findsOneWidget);
  });

  testWidgets('Windows integration section hidden on non-Windows platform override', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: engine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: audioSettingsApplier,
        artistNameStore: artistNameStore,
        isWindowsOverride: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Windows integration'), findsNothing);
    expect(find.byKey(const Key('settings_media_controls_switch')), findsNothing);
    expect(find.byKey(const Key('settings_prevent_sleep_switch')), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Windows integration controls update store live', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _buildTestSettingsApp(
        engine: engine,
        repository: repository,
        settingsStore: settingsStore,
        navigator: navigator,
        audioSettingsApplier: audioSettingsApplier,
        artistNameStore: artistNameStore,
        isWindowsOverride: true,
      ),
    );
    await tester.pumpAndSettle();

    final scrollFinder = find.byType(Scrollable).first;
    final mediaSwitch = find.byKey(const Key('settings_media_controls_switch'));
    await tester.scrollUntilVisible(mediaSwitch, 100.0, scrollable: scrollFinder);
    await tester.ensureVisible(mediaSwitch);
    await tester.pumpAndSettle();

    // Toggle media controls off
    await tester.tap(mediaSwitch);
    await tester.pumpAndSettle();
    expect(settingsStore.settings.mediaControls, isFalse);

    // Toggle prevent sleep off
    final sleepSwitch = find.byKey(const Key('settings_prevent_sleep_switch'));
    await tester.tap(sleepSwitch);
    await tester.pumpAndSettle();
    expect(settingsStore.settings.preventSleepWhilePlaying, isFalse);

    // Change close behavior to tray
    final traySegment = find.text('Keep playing in tray');
    await tester.scrollUntilVisible(traySegment, 100.0, scrollable: scrollFinder);
    await tester.ensureVisible(traySegment);
    await tester.pumpAndSettle();
    await tester.tap(traySegment);
    await tester.pumpAndSettle();
    expect(settingsStore.settings.closeBehavior, equals('tray'));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
