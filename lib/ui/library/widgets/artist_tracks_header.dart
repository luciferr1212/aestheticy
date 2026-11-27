import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../diagnostics/app_logger.dart';
import '../../../library/library_repository.dart';
import '../../../library/models.dart';
import '../../../library/user_data_access_mode.dart';
import '../../glass/glass_button.dart';
import '../../glass/glass_surface.dart';
import '../../l10n/app_strings.dart';
import '../../settings/app_settings.dart';
import '../../settings/settings_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../library_view_controls.dart';
import '../sort_direction_button.dart';
import '../track_table.dart';
import 'artist_album_section.dart';

/// Header for the artist's tracks table with shuffle, sort controls, and search field.
class ArtistTracksSectionHeader extends StatelessWidget {
  /// Available horizontal width.
  final double availableWidth;

  /// Currently visible filtered/sorted tracks.
  final List<Track> visibleTracks;

  /// Current application settings.
  final AppSettings settings;

  /// Persistent settings store.
  final SettingsStore settingsStore;

  /// Whether animations should be reduced.
  final bool reduceMotion;

  /// Search text controller.
  final TextEditingController searchController;

  /// Current track search query.
  final String trackSearchQuery;

  /// Called when the search query changes.
  final ValueChanged<String> onSearchChanged;

  /// Called when the shuffle button is pressed.
  final VoidCallback onShuffle;

  /// Creates an [ArtistTracksSectionHeader].
  const ArtistTracksSectionHeader({
    super.key,
    required this.availableWidth,
    required this.visibleTracks,
    required this.settings,
    required this.settingsStore,
    required this.reduceMotion,
    required this.searchController,
    required this.trackSearchQuery,
    required this.onSearchChanged,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    final searchWidth = math.min(240.0, availableWidth);

    return Column(
      key: const Key('artist_section_tracks'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ArtistSectionHeaderRow(
          title: context.t('artist.section.tracks'),
          count: visibleTracks.length,
          countKey: const Key('artist_section_count_tracks'),
          trailing: GlassPillButton(
            key: const Key('artist_tracks_shuffle_button'),
            label: context.t('common.shuffle'),
            leadingIcon: Icons.shuffle,
            size: GlassButtonSize.small,
            onPressed: visibleTracks.isEmpty ? null : onShuffle,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            LibraryViewControls(
              sortOptions: const [
                'title',
                'album',
                'mostPlayed',
                'recentlyAdded',
                'duration',
              ],
              currentSort: settings.artistDetailTrackSort,
              onSortChanged: (newSort) {
                final newReversed = SortDirection.defaultReversedFor(newSort);
                settingsStore.update(
                  (s) => s.copyWith(
                    artistDetailTrackSort: newSort,
                    artistDetailTrackSortReversed: newReversed,
                  ),
                );
              },
              sortDirection: SortDirection.fromReversed(
                settings.artistDetailTrackSortReversed,
              ),
              onSortDirectionChanged: (newDir) {
                settingsStore.update(
                  (s) => s.copyWith(
                    artistDetailTrackSortReversed: newDir.isReversed,
                  ),
                );
              },
              reduceMotion: reduceMotion,
            ),
            SizedBox(
              width: searchWidth,
              height: 36,
              child: GlassSurface(
                density: GlassDensity.regular,
                borderRadius: AppSpacing.r12,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search,
                      color: AppColors.textMuted,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('artist_tracks_search_field'),
                        controller: searchController,
                        onChanged: onSearchChanged,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.text,
                        ),
                        decoration: InputDecoration(
                          hintText: context.t('artist.tracksSearchHint'),
                          hintStyle: AppTypography.caption.copyWith(
                            color: AppColors.textMuted,
                          ),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (trackSearchQuery.isNotEmpty)
                      IconButton(
                        key: const Key('artist_tracks_search_clear'),
                        icon: const Icon(Icons.close, size: 14),
                        color: AppColors.textMuted,
                        tooltip: context.t('common.clear'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged('');
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const TrackTableHeader(
          showTrackNumber: true,
          showCover: true,
          showAlbum: true,
          showArtist: false,
          hasActions: true,
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// Overflow menu button for an individual track row on the Artist Detail screen.
class ArtistTrackActionMenu extends StatelessWidget {
  /// Track item.
  final Track track;

  /// Library repository used to persist no-split rules.
  final LibraryRepository repository;

  /// Called after adding a no-split rule so the artist page refreshes.
  final Future<void> Function() onReload;

  /// Creates an [ArtistTrackActionMenu].
  const ArtistTrackActionMenu({
    super.key,
    required this.track,
    required this.repository,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: Key('track_menu_${track.id}'),
      padding: EdgeInsets.zero,
      icon: const Icon(
        Icons.more_horiz,
        size: 16,
        color: AppColors.textMuted,
      ),
      tooltip: context.t('artists.optionsTooltip'),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.r12),
        side: const BorderSide(color: AppColors.border),
      ),
      onSelected: (val) async {
        if (val == 'no_split' && track.artist != null) {
          final messenger = ScaffoldMessenger.of(context);
          final treatedMsg = context.t(
            'artist.treatingAsOne',
            args: {'artist': track.artist!},
          );
          try {
            await repository.addNoSplit(track.artist!);
            if (context.mounted) {
              messenger.showSnackBar(
                SnackBar(content: Text(treatedMsg)),
              );
              await onReload();
            }
          } on UserDataReadOnlyException catch (e, st) {
            AppLogger.instance.warn(
              'ArtistTracks',
              'addNoSplit blocked in safe read-only mode',
              e,
              st,
            );
            if (context.mounted) {
              messenger.showSnackBar(
                SnackBar(content: Text(context.t(e.messageKey))),
              );
            }
          }
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'no_split',
          child: Text(
            ctx.t('artist.treatAsOne', args: {'artist': track.artist!}),
          ),
        ),
      ],
    );
  }
}
