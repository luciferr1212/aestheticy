import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/audio_engine.dart';
import '../../audio/audio_models.dart';
import '../../diagnostics/app_logger.dart';
import '../../diagnostics/diagnostic_report.dart';
import '../../library/library_repository.dart';
import '../../library/migrations.dart';
import '../artist_names/artist_name_scope.dart';
import '../artist_names/artist_name_store.dart';
import '../glass/glass_button.dart';
import '../glass/glass_quality.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/font_manager.dart';
import 'app_settings.dart';
import 'app_shortcuts.dart';
import 'audio_settings_applier.dart';
import 'settings_store.dart';

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

  /// Optional callback to open folder management sheet directly.
  final VoidCallback? onOpenFolders;

  /// Optional override for platform detection (for testing non-Windows behavior).
  final bool? isWindowsOverride;

  /// Creates a [SettingsView].
  const SettingsView({
    super.key,
    required this.engine,
    required this.repository,
    required this.settingsStore,
    required this.navigator,
    this.audioSettingsApplier,
    this.artistNameStore,
    this.onOpenFolders,
    this.isWindowsOverride,
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
          listenable: widget.settingsStore,
          builder: (context, _) {
            final settings = widget.settingsStore.settings;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: GlassSurface(
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                            _buildLanguageSection(context, settings),
                            const SizedBox(height: 20),

                            // 2. Appearance
                            _buildAppearanceSection(context, settings),
                            const SizedBox(height: 20),

                            // 3. Fonts
                            _buildFontsSection(context, settings),
                            const SizedBox(height: 20),

                            // 4. Artist names
                            _buildArtistNamesSection(context, settings),
                            const SizedBox(height: 20),

                            // 5. Audio
                            _buildAudioSection(context, settings),
                            const SizedBox(height: 20),

                            // 6. Playback
                            _buildPlaybackSection(context, settings),
                            const SizedBox(height: 20),

                            // Windows integration (hidden off Windows)
                            if (_isWindows) ...[
                              _buildWindowsSection(context, settings),
                              const SizedBox(height: 20),
                            ],

                            // 7. Library
                            _buildLibrarySection(context),
                            const SizedBox(height: 20),

                            // 8. Listening history
                            _buildHistorySection(context),
                            const SizedBox(height: 20),

                            // 9. Shortcuts
                            _buildShortcutsSection(context),
                            const SizedBox(height: 20),

                            // 10. Diagnostics
                            _buildDiagnosticsSection(context, settings),
                            const SizedBox(height: 20),

                            // 11. About
                            _buildAboutSection(context),
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

  // ── 1. Language and Profile ───────────────────────────────────────────
  Widget _buildLanguageSection(BuildContext context, AppSettings settings) {
    final isArabic = settings.language == 'ar';

    return _SettingsCard(
      title: context.t('settings.sectionLanguageProfile'),
      children: [
        // Interface language
        _SettingsRow(
          title: context.t('settings.interfaceLanguage'),
          control: _SegmentedControl<String>(
            value: settings.language,
            options: const [
              _SegmentedOption(value: 'en', label: 'English'),
              _SegmentedOption(value: 'ar', label: 'العربية'),
            ],
            onChanged: (val) {
              widget.settingsStore.update((s) => s.copyWith(language: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Arabic numerals
        _SettingsRow(
          title: context.t('settings.arabicNumerals'),
          description: context.t('settings.arabicNumeralsHint'),
          control: Switch(
            key: const Key('settings_arabic_numerals_switch'),
            value: settings.arabicNumerals,
            activeThumbColor: AppColors.accent,
            onChanged: isArabic
                ? (val) {
                    widget.settingsStore
                        .update((s) => s.copyWith(arabicNumerals: val));
                  }
                : null,
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // User name
        _SettingsRow(
          title: context.t('settings.yourName'),
          description: context.t('settings.yourNameHint'),
          control: SizedBox(
            width: 220,
            child: TextField(
              controller: _nameController,
              maxLength: 40,
              style: AppTypography.body,
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                filled: true,
                fillColor: AppColors.fillControl,
                hintText: context.t('welcome.namePlaceholder'),
                hintStyle: AppTypography.caption,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.r10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.r10),
                  borderSide: const BorderSide(color: AppColors.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.r10),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
              onChanged: _onNameSubmitted,
            ),
          ),
        ),
      ],
    );
  }

  // ── 2. Appearance ─────────────────────────────────────────────────────
  Widget _buildAppearanceSection(BuildContext context, AppSettings settings) {
    final qualityHint = switch (settings.glassQuality) {
      GlassQuality.full => context.t('settings.glassQualityFullHint'),
      GlassQuality.light => context.t('settings.glassQualityLightHint'),
      GlassQuality.off => context.t('settings.glassQualityOffHint'),
    };

    return _SettingsCard(
      title: context.t('settings.sectionAppearance'),
      children: [
        // Glass quality
        _SettingsRow(
          title: context.t('settings.glassQuality'),
          description: qualityHint,
          control: _SegmentedControl<GlassQuality>(
            value: settings.glassQuality,
            options: [
              _SegmentedOption(
                value: GlassQuality.full,
                label: context.t('settings.glassQualityFull'),
              ),
              _SegmentedOption(
                value: GlassQuality.light,
                label: context.t('settings.glassQualityLight'),
              ),
              _SegmentedOption(
                value: GlassQuality.off,
                label: context.t('settings.glassQualityOff'),
              ),
            ],
            onChanged: (val) {
              widget.settingsStore.update((s) => s.copyWith(glassQuality: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Reduce motion
        _SettingsRow(
          title: context.t('settings.reduceMotion'),
          description: context.t('settings.reduceMotionHint'),
          control: Switch(
            value: settings.reduceMotion,
            activeThumbColor: AppColors.accent,
            onChanged: (val) {
              widget.settingsStore.update((s) => s.copyWith(reduceMotion: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Glass shapes in full screen
        _SettingsRow(
          title: context.t('settings.fullScreenGlassShapes'),
          description: context.t('settings.fullScreenGlassShapesHint'),
          control: Switch(
            value: settings.fullScreenGlassShapes,
            activeThumbColor: AppColors.accent,
            onChanged: (val) {
              widget.settingsStore
                  .update((s) => s.copyWith(fullScreenGlassShapes: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Text size
        _SettingsRow(
          title: context.t('settings.textSize'),
          control: _SegmentedControl<String>(
            value: settings.textScale,
            options: [
              _SegmentedOption(
                value: 'small',
                label: context.t('settings.textSizeSmall'),
              ),
              _SegmentedOption(
                value: 'normal',
                label: context.t('settings.textSizeNormal'),
              ),
              _SegmentedOption(
                value: 'large',
                label: context.t('settings.textSizeLarge'),
              ),
            ],
            onChanged: (val) {
              widget.settingsStore.update((s) => s.copyWith(textScale: val));
            },
          ),
        ),
      ],
    );
  }

  // ── 3. Fonts ──────────────────────────────────────────────────────────
  Widget _buildFontsSection(BuildContext context, AppSettings settings) {
    return _SettingsCard(
      title: context.t('settings.sectionFonts'),
      children: [
        for (final font in _fontOptions) ...[
          InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.r10),
            onTap: () {
              widget.settingsStore.update((s) => s.copyWith(uiFont: font.id));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: settings.uiFont == font.id
                    ? AppColors.accentFill
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppSpacing.r10),
                border: Border.all(
                  color: settings.uiFont == font.id
                      ? AppColors.accent
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      font.id == 'system'
                          ? context.t('settings.font.system')
                          : (font.displayName ?? font.id),
                      style: AppTypography.bodyStrong,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: Text(
                      FontManager.previewSample,
                      style: TextStyle(
                        fontFamily:
                            font.id == 'system' ? 'Segoe UI Variable' : font.id,
                        fontFamilyFallback: AppTypography.fontFamilyFallback,
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (settings.uiFont == font.id)
                    const Icon(Icons.check, color: AppColors.accent, size: 18),
                ],
              ),
            ),
          ),
          if (font != _fontOptions.last) const SizedBox(height: 6),
        ],
      ],
    );
  }

  // ── 4. Artist Names ───────────────────────────────────────────────────
  Widget _buildArtistNamesSection(
      BuildContext context, AppSettings settings) {
    final nameStore =
        widget.artistNameStore ?? ArtistNameScope.maybeOf(context);

    return _SettingsCard(
      title: context.t('settings.sectionArtistNames'),
      description: context.t('settings.artistNamesHint'),
      children: [
        // Mode segmented
        _SegmentedControl<String>(
          value: settings.artistNameMode,
          options: [
            _SegmentedOption(
              value: 'asTagged',
              label: context.t('settings.artistModeAsTagged'),
            ),
            _SegmentedOption(
              value: 'followLanguage',
              label: context.t('settings.artistModeFollowLanguage'),
            ),
            _SegmentedOption(
              value: 'alwaysArabic',
              label: context.t('settings.artistModeAlwaysArabic'),
            ),
          ],
          onChanged: (val) {
            widget.settingsStore
                .update((s) => s.copyWith(artistNameMode: val));
          },
        ),
        const SizedBox(height: 16),

        // Virtualized entries / suggestions list capped at 200
        if (nameStore != null) ...[
          ListenableBuilder(
            listenable: nameStore,
            builder: (context, _) {
              final allEntries = nameStore.entries;
              final cappedEntries = allEntries.take(200).toList();

              if (cappedEntries.isEmpty) {
                return const SizedBox.shrink();
              }

              return SizedBox(
                height: 180,
                child: ListView.builder(
                  itemCount: cappedEntries.length,
                  itemExtent: 44.0,
                  itemBuilder: (context, index) {
                    final entry = cappedEntries[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.fillControl,
                        borderRadius: BorderRadius.circular(AppSpacing.r10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.original,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.body,
                            ),
                          ),
                          if (entry.ar.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Text(
                              entry.ar,
                              style: AppTypography.body.copyWith(
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  // ── 5. Audio ──────────────────────────────────────────────────────────
  Widget _buildAudioSection(BuildContext context, AppSettings settings) {
    final capabilities = widget.engine.capabilities;

    return _SettingsCard(
      title: context.t('settings.sectionAudio'),
      children: [
        if (_audioError != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.danger.withAlpha(35),
              borderRadius: BorderRadius.circular(AppSpacing.r10),
              border: Border.all(color: AppColors.danger),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.danger, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    switch (_audioError!) {
                      AudioSettingsError.unsupported =>
                        context.t('settings.audio.errorUnsupported'),
                      AudioSettingsError.failed =>
                        context.t('settings.audio.errorFailed'),
                    },
                    style: AppTypography.caption
                        .copyWith(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Output device
        StreamBuilder<List<AudioDevice>>(
          stream: widget.engine.devicesStream,
          initialData: widget.engine.devices,
          builder: (context, snapshot) {
            final devices = snapshot.data ?? [AudioDevice.auto];
            final currentId = settings.outputDeviceId;
            final selectedDevice = devices.any((d) => d.id == currentId)
                ? currentId
                : AudioDevice.auto.id;

            return _SettingsRow(
              title: context.t('settings.outputDevice'),
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.fillControl,
                      borderRadius: BorderRadius.circular(AppSpacing.r10),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedDevice,
                        dropdownColor: AppColors.surface,
                        style: AppTypography.body,
                        items: devices.map((d) {
                          return DropdownMenuItem<String>(
                            value: d.id,
                            child: Text(d.name),
                          );
                        }).toList(),
                        onChanged: (val) async {
                          if (val == null) return;
                          final err = await _applier.setDevice(val);
                          setState(() => _audioError = err);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    icon: Icons.refresh,
                    tooltip: context.t('settings.refreshDevices'),
                    semanticLabel: context.t('settings.refreshDevices'),
                    onPressed: () async {
                      await widget.engine.refreshDevices();
                    },
                  ),
                ],
              ),
            );
          },
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Exclusive mode
        _SettingsRow(
          title: context.t('settings.exclusiveMode'),
          description: capabilities.exclusiveMode
              ? null
              : context.t('settings.exclusiveUnsupported'),
          control: Switch(
            value: settings.exclusiveMode,
            activeThumbColor: AppColors.accent,
            onChanged: capabilities.exclusiveMode
                ? (val) async {
                    final err = await _applier.setExclusive(val);
                    setState(() => _audioError = err);
                  }
                : null,
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // ReplayGain mode
        _SettingsRow(
          title: context.t('settings.replayGainMode'),
          control: _SegmentedControl<String>(
            value: settings.replayGainMode,
            options: [
              _SegmentedOption(
                value: 'off',
                label: context.t('settings.replayGainOff'),
              ),
              _SegmentedOption(
                value: 'track',
                label: context.t('settings.replayGainTrack'),
              ),
              _SegmentedOption(
                value: 'album',
                label: context.t('settings.replayGainAlbum'),
              ),
            ],
            onChanged: (val) async {
              final mode = switch (val) {
                'track' => ReplayGainMode.track,
                'album' => ReplayGainMode.album,
                _ => ReplayGainMode.off,
              };
              final err = await _applier.setReplayGainMode(mode);
              setState(() => _audioError = err);
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // ReplayGain preamp slider (-15 to +15 dB)
        _SettingsRow(
          title: context.t('settings.replayGainPreamp'),
          description:
              '${settings.replayGainPreampDb > 0 ? '+' : ''}${settings.replayGainPreampDb.toStringAsFixed(1)} dB',
          control: SizedBox(
            width: 220,
            child: SliderTheme(
              data: const SliderThemeData(
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3,
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: AppColors.border,
                thumbColor: AppColors.accent,
              ),
              child: Slider(
                value: settings.replayGainPreampDb.clamp(-15.0, 15.0),
                min: -15.0,
                max: 15.0,
                divisions: 30,
                onChanged: (val) async {
                  final err = await _applier.setReplayGainPreamp(val);
                  setState(() => _audioError = err);
                },
              ),
            ),
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Crossfade (disabled Soon)
        _SettingsRow(
          title: context.t('settings.crossfade'),
          control: GlassPillButton(
            label: context.t('common.soon'),
            onPressed: null,
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Equalizer and signal path
        _SettingsRow(
          title: context.t('settings.audio.panelsRow'),
          control: GlassPillButton(
            key: const Key('settings_open_audio_panels_button'),
            label: context.t('settings.audio.panelsOpen'),
            onPressed: () => widget.navigator.openAudioPanels(),
          ),
        ),
      ],
    );
  }

  // ── 6. Playback ───────────────────────────────────────────────────────
  Widget _buildPlaybackSection(BuildContext context, AppSettings settings) {
    return _SettingsCard(
      title: context.t('settings.sectionPlayback'),
      children: [
        _SettingsRow(
          title: context.t('settings.resumeSession'),
          description: context.t('settings.resumeSessionHint'),
          control: Switch(
            key: const Key('settings_resume_session_switch'),
            value: settings.resumeSession,
            activeThumbColor: AppColors.accent,
            onChanged: (val) {
              widget.settingsStore
                  .update((s) => s.copyWith(resumeSession: val));
            },
          ),
        ),
      ],
    );
  }

  // ── Windows Integration ───────────────────────────────────────────────
  Widget _buildWindowsSection(BuildContext context, AppSettings settings) {
    return _SettingsCard(
      title: context.t('settings.sectionWindows'),
      children: [
        // Media controls
        _SettingsRow(
          title: context.t('settings.mediaControls'),
          description: context.t('settings.mediaControlsSubtitle'),
          control: Switch(
            key: const Key('settings_media_controls_switch'),
            value: settings.mediaControls,
            activeThumbColor: AppColors.accent,
            onChanged: (val) {
              widget.settingsStore
                  .update((s) => s.copyWith(mediaControls: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Prevent sleep while playing
        _SettingsRow(
          title: context.t('settings.preventSleep'),
          description: context.t('settings.preventSleepSubtitle'),
          control: Switch(
            key: const Key('settings_prevent_sleep_switch'),
            value: settings.preventSleepWhilePlaying,
            activeThumbColor: AppColors.accent,
            onChanged: (val) {
              widget.settingsStore
                  .update((s) => s.copyWith(preventSleepWhilePlaying: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // When closing the window
        _SettingsRow(
          title: context.t('settings.closeBehavior'),
          description: context.t('settings.closeBehaviorSubtitle'),
          control: _SegmentedControl<String>(
            key: const Key('settings_close_behavior_segmented'),
            value: settings.closeBehavior,
            options: [
              _SegmentedOption(
                value: 'quit',
                label: context.t('settings.closeBehaviorQuit'),
              ),
              _SegmentedOption(
                value: 'tray',
                label: context.t('settings.closeBehaviorTray'),
              ),
            ],
            onChanged: (val) {
              widget.settingsStore
                  .update((s) => s.copyWith(closeBehavior: val));
            },
          ),
        ),
      ],
    );
  }

  // ── 7. Library ────────────────────────────────────────────────────────
  Widget _buildLibrarySection(BuildContext context) {
    return _SettingsCard(
      title: context.t('settings.sectionLibrary'),
      children: [
        _SettingsRow(
          title: context.t('settings.musicFolders'),
          description: _isLoadingStats
              ? '…'
              : context.t('settings.libraryStats', args: {
                  'folders': context.formatCountLocalized(_folderCount),
                  'tracks': context.formatCountLocalized(_trackCount),
                }),
          control: GlassPillButton(
            label: context.t('settings.manage'),
            onPressed: () {
              if (widget.onOpenFolders != null) {
                widget.onOpenFolders!();
              } else {
                widget.navigator.navigateTo(AppDestination.folders);
              }
            },
          ),
        ),
      ],
    );
  }

  // ── 8. Listening History ──────────────────────────────────────────────
  Widget _buildHistorySection(BuildContext context) {
    return _SettingsCard(
      title: context.t('settings.sectionHistory'),
      children: [
        _SettingsRow(
          title: context.t('settings.playsRecorded'),
          description: _isLoadingStats
              ? '…'
              : context.formatCountLocalized(_playEventCount),
          control: _isConfirmingClear
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.t('settings.clearHistoryConfirm'),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GlassPillButton(
                      key: const Key('settings_clear_history_cancel_button'),
                      label: context.t('common.cancel'),
                      onPressed: () {
                        setState(() => _isConfirmingClear = false);
                      },
                    ),
                    const SizedBox(width: 8),
                    GlassPillButton(
                      key: const Key('settings_clear_history_confirm_button'),
                      label: context.t('settings.clearHistoryAction'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final clearedText = context.t('settings.historyCleared');
                        try {
                          await widget.repository.clearPlayEvents();
                          if (mounted) {
                            setState(() {
                              _playEventCount = 0;
                              _isConfirmingClear = false;
                            });
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(clearedText),
                              ),
                            );
                          }
                        } catch (_) {
                          if (mounted) {
                            setState(() => _isConfirmingClear = false);
                          }
                        }
                      },
                    ),
                  ],
                )
              : GlassPillButton(
                  key: const Key('settings_clear_history_button'),
                  label: context.t('settings.clearHistory'),
                  onPressed: () {
                    setState(() => _isConfirmingClear = true);
                  },
                ),
        ),
      ],
    );
  }

  // ── 9. Shortcuts ──────────────────────────────────────────────────────
  Widget _buildShortcutsSection(BuildContext context) {
    return _SettingsCard(
      title: context.t('settings.sectionShortcuts'),
      children: [
        for (final shortcut in kAppShortcuts) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.t(shortcut.descriptionKey),
                    style: AppTypography.body,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.fillGlass,
                    borderRadius: BorderRadius.circular(AppSpacing.r10),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Text(
                    context.t(shortcut.scope == AppShortcutScope.global
                        ? 'shortcuts.scopeGlobal'
                        : 'shortcuts.scopeNowPlaying'),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.fillControl,
                    borderRadius: BorderRadius.circular(AppSpacing.r10),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Text(
                    shortcut.keyCombination,
                    style: AppTypography.micro.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (shortcut != kAppShortcuts.last)
            const Divider(color: AppColors.borderSubtle, height: 16),
        ],
      ],
    );
  }

  // ── 10. Diagnostics ───────────────────────────────────────────────────
  Widget _buildDiagnosticsSection(BuildContext context, AppSettings settings) {
    return _SettingsCard(
      title: context.t('settings.sectionDiagnostics'),
      children: [
        _SettingsRow(
          title: context.t('settings.copyDiagnostics'),
          control: GlassPillButton(
            key: const Key('settings_copy_diagnostics_button'),
            label: context.t('settings.copyDiagnostics'),
            onPressed: () async {
              try {
                final messenger = ScaffoldMessenger.of(context);
                final copiedText = context.t('settings.diagnosticsCopied');
                final logLines =
                    await AppLogger.instance.readRecentLines(limit: 100);
                final activeDevice = widget.engine.devices.firstWhere(
                  (d) => d.id == settings.outputDeviceId,
                  orElse: () => AudioDevice.auto,
                );
                final report = buildDiagnosticReport(
                  appName: 'Aestheticy',
                  osVersion: Platform.operatingSystemVersion,
                  dartVersion: Platform.version,
                  engineName: widget.engine.runtimeType.toString(),
                  capabilities: widget.engine.capabilities,
                  outputDeviceName: activeDevice.name,
                  exclusiveMode: settings.exclusiveMode,
                  eqEnabled: false,
                  replayGainMode: switch (settings.replayGainMode) {
                    'track' => ReplayGainMode.track,
                    'album' => ReplayGainMode.album,
                    _ => ReplayGainMode.off,
                  },
                  glassQuality: settings.glassQuality,
                  language: settings.language,
                  textScale: settings.textScale,
                  trackCount: _trackCount,
                  albumCount: _albumCount,
                  artistCount: _artistCount,
                  folderCount: _folderCount,
                  schemaVersion: kLibrarySchemaVersion,
                  resumeSession: settings.resumeSession,
                  playEventsCount: _playEventCount,
                  mediaSessionStatus: settings.mediaControls ? 'active' : 'disabled',
                  trayEnabled: settings.closeBehavior == 'tray',
                  sleepPreventionEnabled: settings.preventSleepWhilePlaying,
                  closeBehavior: settings.closeBehavior,
                  logLines: logLines,
                  userNameToScrub: settings.userName,
                );

                try {
                  await Clipboard.setData(ClipboardData(text: report));
                } catch (_) {}
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(copiedText),
                    ),
                  );
                }
              } catch (e, st) {
                AppLogger.instance.error(
                  'Settings',
                  'Copy diagnostics failed: $e',
                  e,
                  st,
                );
              }
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),
        _SettingsRow(
          title: context.t('settings.copyLogPath'),
          control: GlassPillButton(
            key: const Key('settings_copy_log_path_button'),
            label: context.t('settings.copyLogPath'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final copiedText = context.t('settings.logPathCopied');
              final logDir = AppLogger.instance.logDirectory?.path ?? '';
              try {
                await Clipboard.setData(ClipboardData(text: logDir));
              } catch (_) {}
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(copiedText),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  // ── 11. About ──────────────────────────────────────────────────────────
  Widget _buildAboutSection(BuildContext context) {
    return _SettingsCard(
      title: context.t('settings.sectionAbout'),
      children: const [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Aestheticy', style: AppTypography.title),
            Text('by mido', style: AppTypography.caption),
          ],
        ),
      ],
    );
  }
}

// ── Shared Settings Card & Row Components ────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget> children;

  const _SettingsCard({
    required this.title,
    this.description,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.fillGlass,
        borderRadius: BorderRadius.circular(AppSpacing.r16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTypography.title),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: AppTypography.caption),
          ],
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String title;
  final String? description;
  final Widget control;

  const _SettingsRow({
    required this.title,
    this.description,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.bodyStrong),
              if (description != null) ...[
                const SizedBox(height: 2),
                Text(
                  description!,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        control,
      ],
    );
  }
}

class _SegmentedOption<T> {
  final T value;
  final String label;

  const _SegmentedOption({required this.value, required this.label});
}

class _SegmentedControl<T> extends StatelessWidget {
  final T value;
  final List<_SegmentedOption<T>> options;
  final ValueChanged<T> onChanged;

  const _SegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.fillControl,
        borderRadius: BorderRadius.circular(AppSpacing.r10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final isSelected = opt.value == value;
          return InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.r10 - 2),
            onTap: () => onChanged(opt.value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accentFill : Colors.transparent,
                borderRadius: BorderRadius.circular(AppSpacing.r10 - 2),
                border: Border.all(
                  color: isSelected ? AppColors.accent : Colors.transparent,
                ),
              ),
              child: Text(
                opt.label,
                style: AppTypography.caption.copyWith(
                  color: isSelected ? AppColors.text : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
