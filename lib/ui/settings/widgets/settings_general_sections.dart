import 'package:flutter/material.dart';

import '../../artist_names/artist_name_scope.dart';
import '../../artist_names/artist_name_store.dart';
import '../../glass/glass_quality.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../theme/font_manager.dart';
import '../app_settings.dart';
import '../artist_name_translations_panel.dart';
import '../settings_store.dart';
import 'settings_components.dart';

/// Language, Arabic numerals, and user profile name settings card.
class SettingsLanguageSection extends StatelessWidget {
  /// Persistent settings store.
  final SettingsStore settingsStore;

  /// Current settings snapshot.
  final AppSettings settings;

  /// Controller for the user name field.
  final TextEditingController nameController;

  /// Called when the user name changes.
  final ValueChanged<String> onNameSubmitted;

  /// Creates a [SettingsLanguageSection].
  const SettingsLanguageSection({
    super.key,
    required this.settingsStore,
    required this.settings,
    required this.nameController,
    required this.onNameSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = settings.language == 'ar';

    return SettingsCard(
      title: context.t('settings.sectionLanguageProfile'),
      children: [
        // Interface language
        SettingsRow(
          title: context.t('settings.interfaceLanguage'),
          control: SettingsSegmentedControl<String>(
            value: settings.language,
            options: const [
              SettingsSegmentedOption(value: 'en', label: 'English'),
              SettingsSegmentedOption(value: 'ar', label: 'العربية'),
            ],
            onChanged: (val) {
              settingsStore.update((s) => s.copyWith(language: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Arabic numerals
        SettingsRow(
          title: context.t('settings.arabicNumerals'),
          description: context.t('settings.arabicNumeralsHint'),
          control: Switch(
            key: const Key('settings_arabic_numerals_switch'),
            value: settings.arabicNumerals,
            activeThumbColor: AppColors.accent,
            onChanged: isArabic
                ? (val) {
                    settingsStore.update((s) => s.copyWith(arabicNumerals: val));
                  }
                : null,
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // User name
        SettingsRow(
          title: context.t('settings.yourName'),
          description: context.t('settings.yourNameHint'),
          control: SizedBox(
            width: 220,
            child: TextField(
              key: const Key('settings_name_field'),
              controller: nameController,
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
              onChanged: onNameSubmitted,
            ),
          ),
        ),
      ],
    );
  }
}

/// Glass quality, reduce motion, full-screen glass shapes, and text scale card.
class SettingsAppearanceSection extends StatelessWidget {
  /// Persistent settings store.
  final SettingsStore settingsStore;

  /// Current settings snapshot.
  final AppSettings settings;

  /// Creates a [SettingsAppearanceSection].
  const SettingsAppearanceSection({
    super.key,
    required this.settingsStore,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final qualityHint = switch (settings.glassQuality) {
      GlassQuality.full => context.t('settings.glassQualityFullHint'),
      GlassQuality.light => context.t('settings.glassQualityLightHint'),
      GlassQuality.off => context.t('settings.glassQualityOffHint'),
    };

    return SettingsCard(
      title: context.t('settings.sectionAppearance'),
      children: [
        // Glass quality
        SettingsRow(
          title: context.t('settings.glassQuality'),
          description: qualityHint,
          control: SettingsSegmentedControl<GlassQuality>(
            value: settings.glassQuality,
            options: [
              SettingsSegmentedOption(
                value: GlassQuality.full,
                label: context.t('settings.glassQualityFull'),
              ),
              SettingsSegmentedOption(
                value: GlassQuality.light,
                label: context.t('settings.glassQualityLight'),
              ),
              SettingsSegmentedOption(
                value: GlassQuality.off,
                label: context.t('settings.glassQualityOff'),
              ),
            ],
            onChanged: (val) {
              settingsStore.update((s) => s.copyWith(glassQuality: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Reduce motion
        SettingsRow(
          title: context.t('settings.reduceMotion'),
          description: context.t('settings.reduceMotionHint'),
          control: Switch(
            value: settings.reduceMotion,
            activeThumbColor: AppColors.accent,
            onChanged: (val) {
              settingsStore.update((s) => s.copyWith(reduceMotion: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Glass shapes in full screen
        SettingsRow(
          title: context.t('settings.fullScreenGlassShapes'),
          description: context.t('settings.fullScreenGlassShapesHint'),
          control: Switch(
            value: settings.fullScreenGlassShapes,
            activeThumbColor: AppColors.accent,
            onChanged: (val) {
              settingsStore
                  .update((s) => s.copyWith(fullScreenGlassShapes: val));
            },
          ),
        ),
        const Divider(color: AppColors.borderSubtle, height: 24),

        // Text size
        SettingsRow(
          title: context.t('settings.textSize'),
          control: SettingsSegmentedControl<String>(
            value: settings.textScale,
            options: [
              SettingsSegmentedOption(
                value: 'small',
                label: context.t('settings.textSizeSmall'),
              ),
              SettingsSegmentedOption(
                value: 'normal',
                label: context.t('settings.textSizeNormal'),
              ),
              SettingsSegmentedOption(
                value: 'large',
                label: context.t('settings.textSizeLarge'),
              ),
            ],
            onChanged: (val) {
              settingsStore.update((s) => s.copyWith(textScale: val));
            },
          ),
        ),
      ],
    );
  }
}

/// UI font selection settings card.
class SettingsFontsSection extends StatelessWidget {
  /// Persistent settings store.
  final SettingsStore settingsStore;

  /// Current settings snapshot.
  final AppSettings settings;

  /// Available font options.
  final List<FontOption> fontOptions;

  /// Creates a [SettingsFontsSection].
  const SettingsFontsSection({
    super.key,
    required this.settingsStore,
    required this.settings,
    required this.fontOptions,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: context.t('settings.sectionFonts'),
      children: [
        for (final font in fontOptions) ...[
          InkWell(
            mouseCursor: SystemMouseCursors.click,
            hoverColor: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(AppSpacing.r10),
            onTap: () {
              settingsStore.update((s) => s.copyWith(uiFont: font.id));
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
          if (font != fontOptions.last) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

/// Display-only artist name mode and custom translations card.
class SettingsArtistNamesSection extends StatelessWidget {
  /// Persistent settings store.
  final SettingsStore settingsStore;

  /// Current settings snapshot.
  final AppSettings settings;

  /// Optional explicit artist display names store.
  final ArtistNameStore? artistNameStore;

  /// Creates a [SettingsArtistNamesSection].
  const SettingsArtistNamesSection({
    super.key,
    required this.settingsStore,
    required this.settings,
    this.artistNameStore,
  });

  @override
  Widget build(BuildContext context) {
    final nameStore = artistNameStore ?? ArtistNameScope.maybeOf(context);

    return SettingsCard(
      title: context.t('settings.sectionArtistNames'),
      description: context.t('settings.artistNamesHint'),
      children: [
        // Mode segmented
        SettingsSegmentedControl<String>(
          value: settings.artistNameMode,
          options: [
            SettingsSegmentedOption(
              value: 'asTagged',
              label: context.t('settings.artistModeAsTagged'),
            ),
            SettingsSegmentedOption(
              value: 'followLanguage',
              label: context.t('settings.artistModeFollowLanguage'),
            ),
            SettingsSegmentedOption(
              value: 'alwaysArabic',
              label: context.t('settings.artistModeAlwaysArabic'),
            ),
          ],
          onChanged: (val) {
            settingsStore.update((s) => s.copyWith(artistNameMode: val));
          },
        ),
        const SizedBox(height: 16),

        if (nameStore != null)
          ArtistNameTranslationsPanel(nameStore: nameStore),
      ],
    );
  }
}
