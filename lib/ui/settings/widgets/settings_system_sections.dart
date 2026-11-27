import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../audio/audio_engine.dart';
import '../../../audio/audio_models.dart';
import '../../../core/result.dart';
import '../../../diagnostics/app_logger.dart';
import '../../../diagnostics/diagnostic_report.dart';
import '../../../features/integration/tray_window_controller.dart';
import '../../../library/library_repository.dart';
import '../../../library/migrations.dart';
import '../../../library/user_data_access_mode.dart';
import '../../audio_panels/eq_controller.dart';
import '../../audio_panels/eq_scope.dart';
import '../../common/error_presenter.dart';
import '../../glass/glass_button.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../shell/app_navigator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../app_settings.dart';
import '../app_shortcuts.dart';
import '../settings_store.dart';
import '../shortcuts_cheat_sheet_dialog.dart';
import 'settings_components.dart';

/// Windows media controls, sleep prevention, and close-to-tray settings card.
class SettingsWindowsSection extends StatelessWidget {
  /// Persistent settings store.
  final SettingsStore settingsStore;

  /// Current settings snapshot.
  final AppSettings settings;

  /// Optional tray controller for tray availability state.
  final TrayWindowController? trayWindowController;

  /// Optional test override for whether the tray icon is unavailable.
  final bool? trayUnavailableOverride;

  /// Creates a [SettingsWindowsSection].
  const SettingsWindowsSection({
    super.key,
    required this.settingsStore,
    required this.settings,
    this.trayWindowController,
    this.trayUnavailableOverride,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: context.t('settings.sectionWindows'),
      children: [
        // Media controls
        SettingsRow(
          title: context.t('settings.mediaControls'),
          description: context.t('settings.mediaControlsSubtitle'),
          control: Switch(
            key: const Key('settings_media_controls_switch'),
            value: settings.mediaControls,
            activeThumbColor: AppColors.accent,
            onChanged: (val) {
              settingsStore.update((s) => s.copyWith(mediaControls: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Prevent sleep while playing
        SettingsRow(
          title: context.t('settings.preventSleep'),
          description: context.t('settings.preventSleepSubtitle'),
          control: Switch(
            key: const Key('settings_prevent_sleep_switch'),
            value: settings.preventSleepWhilePlaying,
            activeThumbColor: AppColors.accent,
            onChanged: (val) {
              settingsStore
                  .update((s) => s.copyWith(preventSleepWhilePlaying: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // When closing the window
        SettingsRow(
          title: context.t('settings.closeBehavior'),
          description: context.t('settings.closeBehaviorSubtitle'),
          control: SettingsSegmentedControl<String>(
            key: const Key('settings_close_behavior_segmented'),
            value: settings.closeBehavior,
            options: [
              SettingsSegmentedOption(
                value: 'quit',
                label: context.t('settings.closeBehaviorQuit'),
              ),
              SettingsSegmentedOption(
                value: 'tray',
                label: context.t('settings.closeBehaviorTray'),
              ),
            ],
            onChanged: (val) {
              settingsStore.update((s) => s.copyWith(closeBehavior: val));
            },
          ),
        ),
        if (trayUnavailableOverride ??
            (trayWindowController?.isTrayUnavailable ?? false))
          Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpacing.s8),
            child: Row(
              key: const Key('settings_tray_unavailable_hint'),
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(
                    context.t('settings.trayUnavailableHint'),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Mini Player shape, position, and always-on-top settings card.
class SettingsMiniPlayerSection extends StatelessWidget {
  /// Persistent settings store.
  final SettingsStore settingsStore;

  /// Current settings snapshot.
  final AppSettings settings;

  /// Creates a [SettingsMiniPlayerSection].
  const SettingsMiniPlayerSection({
    super.key,
    required this.settingsStore,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: context.t('settings.sectionMiniPlayer'),
      children: [
        // Shape
        SettingsRow(
          title: context.t('settings.miniPlayerShape'),
          control: SettingsSegmentedControl<String>(
            key: const Key('settings_mini_player_shape_segmented'),
            value: settings.miniPlayerShape,
            options: [
              SettingsSegmentedOption(
                value: 'wide',
                label: context.t('miniPlayer.shapeWide'),
              ),
              SettingsSegmentedOption(
                value: 'square',
                label: context.t('miniPlayer.shapeSquare'),
              ),
            ],
            onChanged: (val) {
              settingsStore.update((s) => s.copyWith(miniPlayerShape: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Position
        SettingsRow(
          title: context.t('settings.miniPlayerPosition'),
          control: SettingsSegmentedControl<String>(
            key: const Key('settings_mini_player_position_segmented'),
            value: settings.miniPlayerPosition,
            options: [
              SettingsSegmentedOption(
                value: 'bottomRight',
                label: context.t('miniPlayer.posBottomRight'),
              ),
              SettingsSegmentedOption(
                value: 'topCenter',
                label: context.t('miniPlayer.posTopCenter'),
              ),
              SettingsSegmentedOption(
                value: 'remember',
                label: context.t('miniPlayer.posRemember'),
              ),
            ],
            onChanged: (val) {
              settingsStore.update((s) => s.copyWith(miniPlayerPosition: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Always on top
        SettingsRow(
          title: context.t('settings.miniPlayerAlwaysOnTop'),
          control: Switch(
            key: const Key('settings_mini_player_always_on_top_switch'),
            value: settings.miniPlayerAlwaysOnTop,
            activeThumbColor: AppColors.accent,
            onChanged: (val) {
              settingsStore
                  .update((s) => s.copyWith(miniPlayerAlwaysOnTop: val));
            },
          ),
        ),
      ],
    );
  }
}

/// Library folder count and folder management navigation card.
class SettingsLibrarySection extends StatelessWidget {
  /// Whether library stats are still loading.
  final bool isLoadingStats;

  /// Number of configured library folders.
  final int folderCount;

  /// Number of indexed tracks.
  final int trackCount;

  /// Application navigator.
  final AppNavigator navigator;

  /// Optional override callback to open folder management directly.
  final VoidCallback? onOpenFolders;

  /// Creates a [SettingsLibrarySection].
  const SettingsLibrarySection({
    super.key,
    required this.isLoadingStats,
    required this.folderCount,
    required this.trackCount,
    required this.navigator,
    this.onOpenFolders,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: context.t('settings.sectionLibrary'),
      children: [
        SettingsRow(
          title: context.t('settings.musicFolders'),
          description: isLoadingStats
              ? '…'
              : context.t('settings.libraryStats', args: {
                  'folders': context.formatCountLocalized(folderCount),
                  'tracks': context.formatCountLocalized(trackCount),
                }),
          control: GlassPillButton(
            label: context.t('settings.manage'),
            onPressed: () {
              if (onOpenFolders != null) {
                onOpenFolders!();
              } else {
                navigator.navigateTo(AppDestination.folders);
              }
            },
          ),
        ),
      ],
    );
  }
}

/// Listening history count and clear confirmation card.
class SettingsHistorySection extends StatelessWidget {
  /// Library repository used to clear play events.
  final LibraryRepository repository;

  /// Whether stats are still loading.
  final bool isLoadingStats;

  /// Current number of recorded play events.
  final int playEventCount;

  /// Whether the inline clear confirmation controls are visible.
  final bool isConfirmingClear;

  /// Updates [isConfirmingClear].
  final ValueChanged<bool> onConfirmingClearChanged;

  /// Called after play events are successfully cleared.
  final VoidCallback onHistoryCleared;

  /// Creates a [SettingsHistorySection].
  const SettingsHistorySection({
    super.key,
    required this.repository,
    required this.isLoadingStats,
    required this.playEventCount,
    required this.isConfirmingClear,
    required this.onConfirmingClearChanged,
    required this.onHistoryCleared,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: context.t('settings.sectionHistory'),
      children: [
        SettingsRow(
          title: context.t('settings.playsRecorded'),
          description: isLoadingStats
              ? '…'
              : context.formatCountLocalized(playEventCount),
          control: isConfirmingClear
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
                      onPressed: () => onConfirmingClearChanged(false),
                    ),
                    const SizedBox(width: 8),
                    GlassPillButton(
                      key: const Key('settings_clear_history_confirm_button'),
                      label: context.t('settings.clearHistoryAction'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final clearedText = context.t('settings.historyCleared');
                        try {
                          await repository.clearPlayEvents();
                          if (context.mounted) {
                            onHistoryCleared();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(clearedText),
                              ),
                            );
                          }
                        } on UserDataReadOnlyException catch (e, st) {
                          AppLogger.instance.warn(
                            'Settings',
                            'Clear history blocked in safe read-only mode',
                            e,
                            st,
                          );
                          if (context.mounted) {
                            onConfirmingClearChanged(false);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(context.t(e.messageKey)),
                              ),
                            );
                          }
                        } catch (e, st) {
                          AppLogger.instance.error(
                            'Settings',
                            'Failed clearing play history',
                            e,
                            st,
                          );
                          if (context.mounted) {
                            onConfirmingClearChanged(false);
                            ErrorPresenter.show(
                              context,
                              AppError.fromException(
                                e,
                                st,
                                'error.userDataActionFailed',
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                )
              : GlassPillButton(
                  key: const Key('settings_clear_history_button'),
                  label: context.t('settings.clearHistory'),
                  onPressed: () => onConfirmingClearChanged(true),
                ),
        ),
      ],
    );
  }
}

/// Keyboard shortcuts list and cheat-sheet button card.
class SettingsShortcutsSection extends StatelessWidget {
  /// Creates a [SettingsShortcutsSection].
  const SettingsShortcutsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: context.t('settings.sectionShortcuts'),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: GlassPillButton(
            key: const Key('settings_open_shortcuts_cheat_sheet'),
            label: context.t('settings.openShortcutsCheatSheet'),
            leadingIcon: Icons.keyboard_outlined,
            size: GlassButtonSize.small,
            onPressed: () => showShortcutsCheatSheetDialog(context),
          ),
        ),
        const SizedBox(height: 12),
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
                    context.t(shortcutScopeLabelKey(shortcut.scope)),
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
}

/// Diagnostics report copy and log directory copy card.
class SettingsDiagnosticsSection extends StatelessWidget {
  /// Audio engine instance.
  final AudioEngine engine;

  /// Current settings snapshot.
  final AppSettings settings;

  /// Optional explicit EQ controller.
  final EqController? eqController;

  /// Library statistics included in the diagnostic report.
  final int trackCount;
  final int albumCount;
  final int artistCount;
  final int folderCount;
  final int playEventCount;

  /// Creates a [SettingsDiagnosticsSection].
  const SettingsDiagnosticsSection({
    super.key,
    required this.engine,
    required this.settings,
    this.eqController,
    required this.trackCount,
    required this.albumCount,
    required this.artistCount,
    required this.folderCount,
    required this.playEventCount,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: context.t('settings.sectionDiagnostics'),
      children: [
        SettingsRow(
          title: context.t('settings.copyDiagnostics'),
          control: GlassPillButton(
            key: const Key('settings_copy_diagnostics_button'),
            label: context.t('settings.copyDiagnostics'),
            onPressed: () async {
              try {
                final messenger = ScaffoldMessenger.of(context);
                final copiedText = context.t('settings.diagnosticsCopied');
                final eqEnabled =
                    (eqController ?? EqScope.maybeOf(context))?.enabled ??
                        engine.isEqEnabled;
                final logLines =
                    await AppLogger.instance.readRecentLines(limit: 100);
                final activeDevice = engine.devices.firstWhere(
                  (d) => d.id == settings.outputDeviceId,
                  orElse: () => AudioDevice.auto,
                );
                final report = buildDiagnosticReport(
                  appName: 'Aestheticy',
                  osVersion: Platform.operatingSystemVersion,
                  dartVersion: Platform.version,
                  engineName: engine.runtimeType.toString(),
                  capabilities: engine.capabilities,
                  outputDeviceName: activeDevice.name,
                  exclusiveMode: settings.exclusiveMode,
                  eqEnabled: eqEnabled,
                  replayGainMode: switch (settings.replayGainMode) {
                    'track' => ReplayGainMode.track,
                    'album' => ReplayGainMode.album,
                    _ => ReplayGainMode.off,
                  },
                  glassQuality: settings.glassQuality,
                  language: settings.language,
                  textScale: settings.textScale,
                  trackCount: trackCount,
                  albumCount: albumCount,
                  artistCount: artistCount,
                  folderCount: folderCount,
                  schemaVersion: kLibrarySchemaVersion,
                  resumeSession: settings.resumeSession,
                  playEventsCount: playEventCount,
                  mediaSessionStatus:
                      settings.mediaControls ? 'active' : 'disabled',
                  trayEnabled: settings.closeBehavior == 'tray',
                  sleepPreventionEnabled: settings.preventSleepWhilePlaying,
                  closeBehavior: settings.closeBehavior,
                  lyricsSource: settings.lyricsSource,
                  miniPlayerShape: settings.miniPlayerShape,
                  miniPlayerPosition: settings.miniPlayerPosition,
                  logLines: logLines,
                  userNameToScrub: settings.userName,
                );

                var copied = false;
                try {
                  await Clipboard.setData(ClipboardData(text: report));
                  copied = true;
                } catch (e, st) {
                  AppLogger.instance.warn(
                    'Settings',
                    'Clipboard.setData failed for diagnostics report',
                    e,
                    st,
                  );
                  if (context.mounted) {
                    ErrorPresenter.show(context, AppError.fromException(e, st));
                  }
                }
                if (copied && context.mounted) {
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
                if (context.mounted) {
                  ErrorPresenter.show(context, AppError.fromException(e, st));
                }
              }
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),
        SettingsRow(
          title: context.t('settings.copyLogPath'),
          control: GlassPillButton(
            key: const Key('settings_copy_log_path_button'),
            label: context.t('settings.copyLogPath'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final copiedText = context.t('settings.logPathCopied');
              final logDir = AppLogger.instance.logDirectory?.path ?? '';
              var copied = false;
              try {
                await Clipboard.setData(ClipboardData(text: logDir));
                copied = true;
              } catch (e, st) {
                AppLogger.instance.warn(
                  'Settings',
                  'Clipboard.setData failed for log path',
                  e,
                  st,
                );
                if (context.mounted) {
                  ErrorPresenter.show(context, AppError.fromException(e, st));
                }
              }
              if (copied && context.mounted) {
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
}

/// About card showing app name and credit.
class SettingsAboutSection extends StatelessWidget {
  /// Creates a [SettingsAboutSection].
  const SettingsAboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
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
