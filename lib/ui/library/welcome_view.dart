import 'package:flutter/material.dart';

import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Centered first-launch onboarding panel displayed when the music library has
/// no configured folders.
class WelcomeView extends StatefulWidget {
  /// The settings store for checking and saving user name.
  final SettingsStore settingsStore;

  /// Callback to trigger folder selection.
  final VoidCallback onAddFolder;

  /// Creates a [WelcomeView].
  const WelcomeView({
    super.key,
    required this.settingsStore,
    required this.onAddFolder,
  });

  @override
  State<WelcomeView> createState() => _WelcomeViewState();
}

class _WelcomeViewState extends State<WelcomeView> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveNameAndAddFolder() {
    final rawName = _nameController.text.trim();
    if (rawName.isNotEmpty) {
      final trimmedName = rawName.length > 40 ? rawName.substring(0, 40) : rawName;
      widget.settingsStore.update((s) => s.copyWith(userName: trimmedName));
    }
    widget.onAddFolder();
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.settingsStore.settings.userName;
    final isNameEmpty = userName.isEmpty;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: GlassSurface(
          borderRadius: AppSpacing.r22,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // App mark
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.accentFill,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.graphic_eq,
                  color: AppColors.accent,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                context.t('welcome.title'),
                textAlign: TextAlign.center,
                style: AppTypography.title.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),

              // Description
              Text(
                context.t('welcome.description'),
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),

              // Name input field (only if userName is empty)
              if (isNameEmpty) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.t('welcome.prompt'),
                    style: AppTypography.bodyStrong.copyWith(
                      color: AppColors.text,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('welcome_name_field'),
                  controller: _nameController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveNameAndAddFolder(),
                  decoration: InputDecoration(
                    hintText: context.t('welcome.namePlaceholder'),
                    helperText: context.t('welcome.nameHelper'),
                    helperStyle: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                    ),
                    filled: true,
                    fillColor: AppColors.fillControl,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.r12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.r12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.r12),
                      borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Add music folder button
              GlassPillButton(
                key: const Key('welcome_add_folder_button'),
                label: context.t('welcome.addFolder'),
                leadingIcon: Icons.folder_open_outlined,
                variant: GlassButtonVariant.primary,
                size: GlassButtonSize.large,
                onPressed: _saveNameAndAddFolder,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
