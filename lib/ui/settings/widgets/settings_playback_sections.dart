import 'package:flutter/material.dart';

import '../../../audio/audio_engine.dart';
import '../../../audio/audio_models.dart';
import '../../glass/glass_button.dart';
import '../../l10n/app_strings.dart';
import '../../shell/app_navigator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../app_settings.dart';
import '../audio_settings_applier.dart';
import '../settings_store.dart';
import 'settings_components.dart';

/// Audio output device, exclusive mode, ReplayGain, and audio panels card.
class SettingsAudioSection extends StatelessWidget {
  /// Audio engine instance.
  final AudioEngine engine;

  /// Application navigation coordinator.
  final AppNavigator navigator;

  /// Transactional audio settings applier.
  final AudioSettingsApplier applier;

  /// Current settings snapshot.
  final AppSettings settings;

  /// Current audio setting application error, if any.
  final AudioSettingsError? audioError;

  /// Callback updating the displayed audio error.
  final ValueChanged<AudioSettingsError?> onAudioErrorChanged;

  /// Creates a [SettingsAudioSection].
  const SettingsAudioSection({
    super.key,
    required this.engine,
    required this.navigator,
    required this.applier,
    required this.settings,
    required this.audioError,
    required this.onAudioErrorChanged,
  });

  @override
  Widget build(BuildContext context) {
    final capabilities = engine.capabilities;

    return SettingsCard(
      title: context.t('settings.sectionAudio'),
      children: [
        if (audioError != null) ...[
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
                    switch (audioError!) {
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
          stream: engine.devicesStream,
          initialData: engine.devices,
          builder: (context, snapshot) {
            final devices = snapshot.data ?? [AudioDevice.auto];
            final currentId = settings.outputDeviceId;
            final selectedDevice = devices.any((d) => d.id == currentId)
                ? currentId
                : AudioDevice.auto.id;

            return SettingsRow(
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
                          final err = await applier.setDevice(val);
                          onAudioErrorChanged(err);
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
                      await engine.refreshDevices();
                    },
                  ),
                ],
              ),
            );
          },
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Exclusive mode
        SettingsRow(
          title: context.t('settings.exclusiveMode'),
          description: capabilities.exclusiveMode
              ? null
              : context.t('settings.exclusiveUnsupported'),
          control: Switch(
            value: settings.exclusiveMode,
            activeThumbColor: AppColors.accent,
            onChanged: capabilities.exclusiveMode
                ? (val) async {
                    final err = await applier.setExclusive(val);
                    onAudioErrorChanged(err);
                  }
                : null,
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // ReplayGain mode
        SettingsRow(
          title: context.t('settings.replayGainMode'),
          control: SettingsSegmentedControl<String>(
            value: settings.replayGainMode,
            options: [
              SettingsSegmentedOption(
                value: 'off',
                label: context.t('settings.replayGainOff'),
              ),
              SettingsSegmentedOption(
                value: 'track',
                label: context.t('settings.replayGainTrack'),
              ),
              SettingsSegmentedOption(
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
              final err = await applier.setReplayGainMode(mode);
              onAudioErrorChanged(err);
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // ReplayGain preamp slider (-15 to +15 dB)
        SettingsRow(
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
                  final err = await applier.setReplayGainPreamp(val);
                  onAudioErrorChanged(err);
                },
              ),
            ),
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Crossfade (disabled Soon)
        SettingsRow(
          title: context.t('settings.crossfade'),
          control: GlassPillButton(
            label: context.t('common.soon'),
            onPressed: null,
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Equalizer and signal path
        SettingsRow(
          title: context.t('settings.audio.panelsRow'),
          control: GlassPillButton(
            key: const Key('settings_open_audio_panels_button'),
            label: context.t('settings.audio.panelsOpen'),
            onPressed: () => navigator.openAudioPanels(),
          ),
        ),
      ],
    );
  }
}

/// Session resume, smooth transitions, and seek step settings card.
class SettingsPlaybackSection extends StatelessWidget {
  /// Persistent settings store.
  final SettingsStore settingsStore;

  /// Current settings snapshot.
  final AppSettings settings;

  /// Creates a [SettingsPlaybackSection].
  const SettingsPlaybackSection({
    super.key,
    required this.settingsStore,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: context.t('settings.sectionPlayback'),
      children: [
        SettingsRow(
          title: context.t('settings.resumeSession'),
          description: context.t('settings.resumeSessionHint'),
          control: Switch(
            key: const Key('settings_resume_session_switch'),
            value: settings.resumeSession,
            activeThumbColor: AppColors.accent,
            onChanged: (val) {
              settingsStore.update((s) => s.copyWith(resumeSession: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),
        SettingsRow(
          title: context.t('settings.smoothTransitions'),
          description: context.t('settings.smoothTransitionsHint'),
          control: SettingsSegmentedControl<String>(
            key: const Key('settings_transition_smoothness_segmented'),
            value: settings.transitionSmoothness,
            options: [
              SettingsSegmentedOption(
                value: 'off',
                label: context.t('settings.transitionSmoothness.off'),
              ),
              SettingsSegmentedOption(
                value: 'soft',
                label: context.t('settings.transitionSmoothness.soft'),
              ),
              SettingsSegmentedOption(
                value: 'smooth',
                label: context.t('settings.transitionSmoothness.smooth'),
              ),
            ],
            onChanged: (val) {
              settingsStore
                  .update((s) => s.copyWith(transitionSmoothness: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),
        SettingsRow(
          title: context.t('settings.seekStep'),
          description: context.t('settings.seekStepHint'),
          control: SettingsSegmentedControl<int>(
            value: settings.seekStepSeconds,
            options: [
              SettingsSegmentedOption(
                value: 1,
                label: context.t('settings.seekStep.1s'),
              ),
              SettingsSegmentedOption(
                value: 2,
                label: context.t('settings.seekStep.2s'),
              ),
              SettingsSegmentedOption(
                value: 5,
                label: context.t('settings.seekStep.5s'),
              ),
            ],
            onChanged: (val) {
              settingsStore.update((s) => s.copyWith(seekStepSeconds: val));
            },
          ),
        ),
      ],
    );
  }
}

/// Lyrics source, highlight mode, and full-screen visibility card.
class SettingsLyricsSection extends StatelessWidget {
  /// Persistent settings store.
  final SettingsStore settingsStore;

  /// Current settings snapshot.
  final AppSettings settings;

  /// Creates a [SettingsLyricsSection].
  const SettingsLyricsSection({
    super.key,
    required this.settingsStore,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final currentSource = switch (settings.lyricsSource) {
      'onlineThenLocal' => 'onlineThenLocal',
      'localOnly' => 'localOnly',
      'onlineOnly' => 'onlineOnly',
      'off' => 'off',
      _ => 'localThenOnline',
    };

    return SettingsCard(
      title: context.t('settings.sectionLyrics'),
      children: [
        // Source
        SettingsRow(
          title: context.t('settings.lyricsSource'),
          description: context.t('settings.lyricsSourceHint'),
          control: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.fillControl,
              borderRadius: BorderRadius.circular(AppSpacing.r10),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('settings_lyrics_source_dropdown'),
                value: currentSource,
                dropdownColor: AppColors.surface,
                items: [
                  DropdownMenuItem(
                    value: 'localThenOnline',
                    child: Text(
                      context.t('settings.lyricsSource.localThenOnline'),
                      style: AppTypography.body,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'onlineThenLocal',
                    child: Text(
                      context.t('settings.lyricsSource.onlineThenLocal'),
                      style: AppTypography.body,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'localOnly',
                    child: Text(
                      context.t('settings.lyricsSource.localOnly'),
                      style: AppTypography.body,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'onlineOnly',
                    child: Text(
                      context.t('settings.lyricsSource.onlineOnly'),
                      style: AppTypography.body,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'off',
                    child: Text(
                      context.t('settings.lyricsSource.off'),
                      style: AppTypography.body,
                    ),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    settingsStore.update((s) => s.copyWith(lyricsSource: val));
                  }
                },
              ),
            ),
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Highlight mode
        SettingsRow(
          title: context.t('settings.lyricsHighlight'),
          description: context.t('settings.lyricsHighlightHint'),
          control: SettingsSegmentedControl<String>(
            value: settings.lyricsHighlight == 'line' ? 'line' : 'word',
            options: [
              SettingsSegmentedOption(
                value: 'line',
                label: context.t('settings.lyricsHighlight.line'),
              ),
              SettingsSegmentedOption(
                value: 'word',
                label: context.t('settings.lyricsHighlight.word'),
              ),
            ],
            onChanged: (val) {
              settingsStore.update((s) => s.copyWith(lyricsHighlight: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Show lyrics in full screen
        SettingsRow(
          title: context.t('settings.showLyricsInFullScreen'),
          description: context.t('settings.showLyricsInFullScreenHint'),
          control: Switch(
            key: const Key('settings_show_lyrics_full_screen_switch'),
            value: settings.showLyricsInFullScreen,
            activeThumbColor: AppColors.accent,
            onChanged: (val) {
              settingsStore
                  .update((s) => s.copyWith(showLyricsInFullScreen: val));
            },
          ),
        ),
      ],
    );
  }
}
