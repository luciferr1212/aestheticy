import 'dart:io';

import 'package:flutter/material.dart';

import '../../audio/audio_engine.dart';
import '../../features/integration/tray_window_controller.dart';
import '../../library/library_repository.dart';
import '../artist_names/artist_name_store.dart';
import '../audio_panels/eq_controller.dart';
import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../shell/app_navigator.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/font_manager.dart';
import 'app_shortcuts.dart';
import 'audio_settings_applier.dart';
import 'settings_store.dart';
import 'widgets/settings_general_sections.dart';
import 'widgets/settings_playback_sections.dart';
import 'widgets/settings_system_sections.dart';

/// Full Settings screen organizing application preferences into 8 structured sections.
class SettingsView extends StatefulWidget {
  /// The audio engine instance.
  final AudioEngine engine;

  /// The library storage repository.
  final LibraryRepository repository;

  /// The persistent settings store.
  final SettingsStore settingsStore;

  /// The navigation coordinator.
  final AppNavigator navigator;

  /// Audio applier for transactional audio setting changes.
  final AudioSettingsApplier? audioSettingsApplier;

  /// Artist display names store.
  final ArtistNameStore? artistNameStore;

  /// Optional EQ controller to reflect real EQ enabled state.
  final EqController? eqController;

  /// Optional callback to open folder management sheet directly.
  final VoidCallback? onOpenFolders;

  /// Optional override for platform detection (for testing non-Windows behavior).
  final bool? isWindowsOverride;

  /// Optional tray controller to observe tray icon creation failures.
  final TrayWindowController? trayWindowController;

  /// Optional test override for whether the tray icon is unavailable.
  final bool? trayUnavailableOverride;

  /// Creates a [SettingsView].
  const SettingsView({
    super.key,
    required this.engine,
    required this.repository,
    required this.settingsStore,
    required this.navigator,
    this.audioSettingsApplier,
    this.artistNameStore,
    this.eqController,
    this.onOpenFolders,
    this.isWindowsOverride,
    this.trayWindowController,
    this.trayUnavailableOverride,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final AudioSettingsApplier _applier;
  late final TextEditingController _nameController;
  final FocusNode _focusNode = FocusNode();

  bool get _isWindows => widget.isWindowsOverride ?? Platform.isWindows;

  List<FontOption> _fontOptions = [FontOption.system];
  AudioSettingsError? _audioError;
  int _folderCount = 0;
  int _trackCount = 0;
  int _albumCount = 0;
  int _artistCount = 0;
  int _playEventCount = 0;
  bool _isConfirmingClear = false;
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _applier = widget.audioSettingsApplier ??
        AudioSettingsApplier(
          engine: widget.engine,
          settingsStore: widget.settingsStore,
        );
    _nameController = TextEditingController(
      text: widget.settingsStore.settings.userName,
    );
    _loadFonts();
    _loadLibraryStats();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadFonts() async {
    final fonts = await FontManager.loadAvailableFonts();
    if (mounted) {
      setState(() => _fontOptions = fonts);
    }
  }

  Future<void> _loadLibraryStats() async {
    try {
      final folders = await widget.repository.listFolders();
      final tracks = await widget.repository.trackCount();
      final albums = await widget.repository.albumCount();
      final artists = await widget.repository.artistCount();
      final plays = await widget.repository.playEventCount();
      if (mounted) {
        setState(() {
          _folderCount = folders.length;
          _trackCount = tracks;
          _albumCount = albums;
          _artistCount = artists;
          _playEventCount = plays;
          _isLoadingStats = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  void _onNameSubmitted(String text) {
    final trimmed = text.trim();
    final clamped = trimmed.length > 40 ? trimmed.substring(0, 40) : trimmed;
    widget.settingsStore.update((s) => s.copyWith(userName: clamped));
  }

  @override
  Widget build(BuildContext context) {
    final trayController = widget.trayWindowController;
    final Listenable listenable = trayController != null
        ? Listenable.merge([
            widget.settingsStore,
            trayController.trayUnavailableListenable,
          ])
        : widget.settingsStore;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        shortcutById(AppShortcutId.back).activator: () {
          widget.navigator.goBack();
        },
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: ListenableBuilder(
          listenable: listenable,
          builder: (context, _) {
            final settings = widget.settingsStore.settings;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: GlassSurface(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  padding: const EdgeInsets.all(28),
                  borderRadius: AppSpacing.r22,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header with Title and Back button
                      Row(
                        children: [
                          GlassIconButton(
                            key: const Key('settings_back_button'),
                            icon: Icons.arrow_back,
                            matchTextDirection: true,
                            tooltip: context.t('common.back'),
                            semanticLabel: context.t('common.back'),
                            onPressed: () => widget.navigator.goBack(),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            context.t('settings.title'),
                            style: AppTypography.display,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Scrollable content body
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 40),
                          children: [
                            // 1. Language and profile
                            SettingsLanguageSection(
                              settingsStore: widget.settingsStore,
                              settings: settings,
                              nameController: _nameController,
                              onNameSubmitted: _onNameSubmitted,
                            ),
                            const SizedBox(height: 20),

                            // 2. Appearance
                            SettingsAppearanceSection(
                              settingsStore: widget.settingsStore,
                              settings: settings,
                            ),
                            const SizedBox(height: 20),

                            // 3. Fonts
                            SettingsFontsSection(
                              settingsStore: widget.settingsStore,
                              settings: settings,
                              fontOptions: _fontOptions,
                            ),
                            const SizedBox(height: 20),

                            // 4. Artist names
                            SettingsArtistNamesSection(
                              settingsStore: widget.settingsStore,
                              settings: settings,
                              artistNameStore: widget.artistNameStore,
                            ),
                            const SizedBox(height: 20),

                            // 5. Audio
                            SettingsAudioSection(
                              engine: widget.engine,
                              navigator: widget.navigator,
                              applier: _applier,
                              settings: settings,
                              audioError: _audioError,
                              onAudioErrorChanged: (err) =>
                                  setState(() => _audioError = err),
                            ),
                            const SizedBox(height: 20),

                            // 6. Playback
                            SettingsPlaybackSection(
                              settingsStore: widget.settingsStore,
                              settings: settings,
                            ),
                            const SizedBox(height: 20),

                            // Lyrics
                            SettingsLyricsSection(
                              settingsStore: widget.settingsStore,
                              settings: settings,
                            ),
                            const SizedBox(height: 20),

                            // Windows integration (hidden off Windows)
                            if (_isWindows) ...[
                              SettingsWindowsSection(
                                settingsStore: widget.settingsStore,
                                settings: settings,
                                trayWindowController:
                                    widget.trayWindowController,
                                trayUnavailableOverride:
                                    widget.trayUnavailableOverride,
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Mini player
                            SettingsMiniPlayerSection(
                              settingsStore: widget.settingsStore,
                              settings: settings,
                            ),
                            const SizedBox(height: 20),

                            // 7. Library
                            SettingsLibrarySection(
                              isLoadingStats: _isLoadingStats,
                              folderCount: _folderCount,
                              trackCount: _trackCount,
                              navigator: widget.navigator,
                              onOpenFolders: widget.onOpenFolders,
                            ),
                            const SizedBox(height: 20),

                            // 8. Listening history
                            SettingsHistorySection(
                              repository: widget.repository,
                              isLoadingStats: _isLoadingStats,
                              playEventCount: _playEventCount,
                              isConfirmingClear: _isConfirmingClear,
                              onConfirmingClearChanged: (val) =>
                                  setState(() => _isConfirmingClear = val),
                              onHistoryCleared: () {
                                setState(() {
                                  _playEventCount = 0;
                                  _isConfirmingClear = false;
                                });
                              },
                            ),
                            const SizedBox(height: 20),

                            // 9. Shortcuts
                            const SettingsShortcutsSection(),
                            const SizedBox(height: 20),

                            // 10. Diagnostics
                            SettingsDiagnosticsSection(
                              engine: widget.engine,
                              settings: settings,
                              eqController: widget.eqController,
                              trackCount: _trackCount,
                              albumCount: _albumCount,
                              artistCount: _artistCount,
                              folderCount: _folderCount,
                              playEventCount: _playEventCount,
                            ),
                            const SizedBox(height: 20),

                            // 11. About
                            const SettingsAboutSection(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
