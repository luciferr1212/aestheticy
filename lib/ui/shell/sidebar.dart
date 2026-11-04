import 'package:flutter/material.dart';

import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_navigator.dart';

/// Navigation sidebar providing destination switching, brand header,
/// and responsive compact mode toggle.
class Sidebar extends StatelessWidget {
  /// The application navigation coordinator.
  final AppNavigator navigator;

  /// The settings store for persisting compact state.
  final SettingsStore settingsStore;

  /// Optional callback to trigger folder management sheet.
  final VoidCallback onOpenFolders;

  /// Creates a [Sidebar].
  const Sidebar({
    super.key,
    required this.navigator,
    required this.settingsStore,
    required this.onOpenFolders,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settingsStore,
      builder: (context, _) {
        final settings = settingsStore.settings;
        final isCompact = settings.sidebarCompact;
        final reduceMotion = settings.reduceMotion;

        final width = isCompact ? 64.0 : 208.0;
        final animDuration =
            reduceMotion ? Duration.zero : const Duration(milliseconds: 150);

        return AnimatedContainer(
          duration: animDuration,
          width: width,
          child: GlassSurface(
            borderRadius: AppSpacing.r16,
            margin: const EdgeInsetsDirectional.only(start: 12, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Brand header and compact toggle
                _SidebarHeader(
                  isCompact: isCompact,
                  onToggleCompact: () {
                    settingsStore.update(
                      (s) => s.copyWith(sidebarCompact: !s.sidebarCompact),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Navigation sections
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Library section
                        if (!isCompact)
                          _SectionHeader(title: context.t('nav.library')),
                        _SidebarTile(
                          key: const Key('sidebar_albums'),
                          icon: Icons.album_outlined,
                          selectedIcon: Icons.album,
                          title: context.t('nav.albums'),
                          isCompact: isCompact,
                          isSelected:
                              navigator.current == AppDestination.albums ||
                              navigator.current == AppDestination.albumDetail,
                          onTap: () => navigator.navigateTo(AppDestination.albums),
                        ),
                        _SidebarTile(
                          key: const Key('sidebar_artists'),
                          icon: Icons.person_outline,
                          selectedIcon: Icons.person,
                          title: context.t('nav.artists'),
                          isCompact: isCompact,
                          isSelected:
                              navigator.current == AppDestination.artists ||
                              navigator.current == AppDestination.artistDetail,
                          onTap: () => navigator.navigateTo(AppDestination.artists),
                        ),
                        _SidebarTile(
                          key: const Key('sidebar_tracks'),
                          icon: Icons.music_note_outlined,
                          selectedIcon: Icons.music_note,
                          title: context.t('nav.tracks'),
                          isCompact: isCompact,
                          isSelected: navigator.current == AppDestination.tracks,
                          onTap: () => navigator.navigateTo(AppDestination.tracks),
                        ),

                        const SizedBox(height: 16),
                        // Yours section
                        if (!isCompact)
                          _SectionHeader(title: context.t('nav.yours')),
                        _SidebarTile(
                          key: const Key('sidebar_playlists'),
                          icon: Icons.queue_music_outlined,
                          title: context.t('nav.playlists'),
                          isCompact: isCompact,
                          isSoon: true,
                          onTap: null,
                        ),
                        _SidebarTile(
                          key: const Key('sidebar_favorites'),
                          icon: Icons.favorite_border,
                          title: context.t('nav.favorites'),
                          isCompact: isCompact,
                          isSoon: true,
                          onTap: null,
                        ),
                        _SidebarTile(
                          key: const Key('sidebar_recent'),
                          icon: Icons.history,
                          title: context.t('nav.recent'),
                          isCompact: isCompact,
                          isSoon: true,
                          onTap: null,
                        ),

                        const SizedBox(height: 16),
                        // Tools section
                        if (!isCompact)
                          _SectionHeader(title: context.t('nav.tools')),
                        _SidebarTile(
                          key: const Key('sidebar_audio_lab'),
                          icon: Icons.science_outlined,
                          selectedIcon: Icons.science,
                          title: context.t('nav.audioLab'),
                          isCompact: isCompact,
                          isSelected: navigator.current == AppDestination.audioLab,
                          onTap: () => navigator.navigateTo(AppDestination.audioLab),
                        ),
                        _SidebarTile(
                          key: const Key('sidebar_last_fm'),
                          icon: Icons.graphic_eq,
                          title: 'Last.fm',
                          isCompact: isCompact,
                          isSoon: true,
                          onTap: null,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                // Bottom items: Folders and Settings
                _SidebarTile(
                  key: const Key('sidebar_folders'),
                  icon: Icons.folder_outlined,
                  selectedIcon: Icons.folder,
                  title: context.t('nav.folders'),
                  isCompact: isCompact,
                  isSelected: navigator.current == AppDestination.folders,
                  onTap: onOpenFolders,
                ),
                _SidebarTile(
                  key: const Key('sidebar_settings'),
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings,
                  title: context.t('nav.settings'),
                  isCompact: isCompact,
                  isSelected: navigator.current == AppDestination.settings,
                  onTap: () => navigator.navigateTo(AppDestination.settings),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final bool isCompact;
  final VoidCallback onToggleCompact;

  const _SidebarHeader({
    required this.isCompact,
    required this.onToggleCompact,
  });

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return Center(
        child: IconButton(
          key: const Key('sidebar_toggle_compact'),
          tooltip: context.t('app.name'),
          icon: const Icon(
            Icons.menu_outlined,
            color: AppColors.textSecondary,
            size: 20,
          ),
          onPressed: onToggleCompact,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Aestheticy',
                  style: AppTypography.title.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'by mido',
                  style: AppTypography.micro.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('sidebar_toggle_compact'),
            tooltip: context.t('sidebar.toggleTooltip'),
            icon: const Icon(
              Icons.menu_open_outlined,
              color: AppColors.textSecondary,
              size: 20,
            ),
            onPressed: onToggleCompact,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: 16,
        top: 8,
        bottom: 4,
        end: 16,
      ),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.micro.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final IconData icon;
  final IconData? selectedIcon;
  final String title;
  final bool isCompact;
  final bool isSelected;
  final bool isSoon;
  final VoidCallback? onTap;

  const _SidebarTile({
    super.key,
    required this.icon,
    this.selectedIcon,
    required this.title,
    required this.isCompact,
    this.isSelected = false,
    this.isSoon = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null && !isSoon;
    final effectiveIcon =
        (isSelected && selectedIcon != null) ? selectedIcon! : icon;

    final Color iconColor;
    final Color textColor;
    if (!isEnabled) {
      iconColor = AppColors.textMuted.withAlpha(120);
      textColor = AppColors.textMuted.withAlpha(120);
    } else if (isSelected) {
      iconColor = AppColors.accent;
      textColor = AppColors.accent;
    } else {
      iconColor = AppColors.textSecondary;
      textColor = AppColors.text;
    }

    final tileContent = Container(
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: EdgeInsetsDirectional.only(
        start: isCompact ? 0 : 12,
        end: isCompact ? 0 : 8,
      ),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0x3DD3C9EA) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.r10),
      ),
      child: isCompact
          ? Center(
              child: Icon(
                effectiveIcon,
                color: iconColor,
                size: 20,
              ),
            )
          : Row(
              children: [
                Icon(
                  effectiveIcon,
                  color: iconColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(
                      color: textColor,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (isSoon)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF),
                      borderRadius: BorderRadius.circular(AppSpacing.r10),
                    ),
                    child: Text(
                      context.t('common.soon'),
                      style: AppTypography.micro.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 9.5,
                      ),
                    ),
                  ),
              ],
            ),
    );

    return Semantics(
      button: true,
      enabled: isEnabled,
      selected: isSelected,
      label: title,
      child: Tooltip(
        message: title,
        waitDuration: isCompact ? const Duration(milliseconds: 300) : const Duration(seconds: 1),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.r10),
          onTap: isEnabled ? onTap : null,
          child: tileContent,
        ),
      ),
    );
  }
}
