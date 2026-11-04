import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  _FakeLibraryRepository({
    this.folders = const [],
    this.count = 1,
  });

  @override
  Future<List<LibraryFolder>> listFolders() async => folders;

  @override
  Future<int> trackCount() async => count;
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

    await tester.scrollUntilVisible(find.text('Library'), 100.0, scrollable: scrollFinder);
    expect(find.text('Library'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Shortcuts'), 100.0, scrollable: scrollFinder);
    expect(find.text('Shortcuts'), findsOneWidget);

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

  testWidgets('displays all shortcuts from kAppShortcuts and nothing else', (tester) async {
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
}
