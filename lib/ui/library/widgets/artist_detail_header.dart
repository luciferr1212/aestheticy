import 'dart:io';

import 'package:flutter/material.dart';

import '../../../features/library/artist_rules_sheet.dart';
import '../../../features/library_view/artist_page_model.dart';
import '../../../library/library_repository.dart';
import '../../../library/models.dart';
import '../../artist_names/artist_name_scope.dart';
import '../../glass/glass_button.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../shell/app_navigator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Calm deterministic gradients for artist avatar placeholders.
const List<List<Color>> _avatarGradients = [
  [Color(0xFF5A4D6B), Color(0xFF383145)],
  [Color(0xFF385A66), Color(0xFF233B44)],
  [Color(0xFF6B5848), Color(0xFF45362B)],
  [Color(0xFF48586B), Color(0xFF2B3745)],
  [Color(0xFF6B485A), Color(0xFF452B38)],
  [Color(0xFF4A6B52), Color(0xFF2B4532)],
];

List<Color> _gradientForArtist(String name) {
  final sum = name.codeUnits.fold(0, (acc, c) => acc + c);
  return _avatarGradients[sum % _avatarGradients.length];
}

String _initialForArtist(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

/// Top header for [ArtistDetailView] showing back button, avatar, stats, and actions.
class ArtistDetailHeader extends StatelessWidget {
  /// Artist summary model.
  final ArtistSummary artist;

  /// Loaded artist page model, if ready.
  final ArtistPageModel? model;

  /// Available horizontal content width.
  final double availableWidth;

  /// Sorted list of all artist tracks for Play and Shuffle actions.
  final List<Track> allTracks;

  /// Optional artist portrait image path.
  final String? artistImagePath;

  /// Library repository passed to [ArtistRulesSheet].
  final LibraryRepository repository;

  /// Application navigator.
  final AppNavigator navigator;

  /// Callback starting sequential playback of [allTracks].
  final VoidCallback onPlayAll;

  /// Callback starting shuffled playback of [allTracks].
  final VoidCallback onShuffleAll;

  /// Callback reloading artist data after rules changes.
  final VoidCallback onReload;

  /// Creates an [ArtistDetailHeader].
  const ArtistDetailHeader({
    super.key,
    required this.artist,
    required this.model,
    required this.availableWidth,
    required this.allTracks,
    required this.repository,
    required this.navigator,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onReload,
    this.artistImagePath,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = context.displayArtist(artist.name);
    final avatarSize = availableWidth < 520 ? 84.0 : 104.0;
    final albumCount = model?.albumCount ?? artist.albumCount;
    final trackCount = model?.trackCount ?? artist.trackCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GlassIconButton(
              key: const Key('artist_detail_back_button'),
              icon: Icons.arrow_back,
              matchTextDirection: true,
              tooltip: context.t('common.back'),
              semanticLabel: context.t('common.back'),
              size: GlassButtonSize.small,
              onPressed: () => navigator.goBack(),
            ),
            const SizedBox(width: 8),
            Text(
              context.t('common.back'),
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ArtistHeaderAvatar(
              key: const Key('artist_header_avatar'),
              artistName: displayName,
              rawName: artist.name,
              size: avatarSize,
              imagePath: artistImagePath,
            ),
            SizedBox(width: availableWidth < 520 ? 16 : 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDirectionFor(displayName),
                    style: AppTypography.display.copyWith(letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.t(
                      'artist.headerStats',
                      args: {
                        'albums': context.formatCountLocalized(albumCount),
                        'tracks': context.formatCountLocalized(trackCount),
                      },
                    ),
                    key: const Key('artist_header_stats'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      GlassPillButton(
                        key: const Key('artist_play_button'),
                        label: context.t('common.play'),
                        leadingIcon: Icons.play_arrow,
                        variant: GlassButtonVariant.primary,
                        size: GlassButtonSize.small,
                        onPressed: allTracks.isEmpty ? null : onPlayAll,
                      ),
                      GlassPillButton(
                        key: const Key('artist_shuffle_button'),
                        label: context.t('common.shuffle'),
                        leadingIcon: Icons.shuffle,
                        size: GlassButtonSize.small,
                        onPressed: allTracks.isEmpty ? null : onShuffleAll,
                      ),
                      GlassPillButton(
                        key: const Key('artist_rules_button'),
                        label: context.t('artist.rules'),
                        leadingIcon: Icons.rule,
                        size: GlassButtonSize.small,
                        onPressed: () {
                          ArtistRulesSheet.show(
                            context,
                            repository: repository,
                          ).then((_) => onReload());
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Circular artist portrait or monogram fallback avatar.
class ArtistHeaderAvatar extends StatelessWidget {
  /// Localized artist display name.
  final String artistName;

  /// Raw artist name used for deterministic gradient selection.
  final String rawName;

  /// Avatar diameter in logical pixels.
  final double size;

  /// Optional path to a portrait image file.
  final String? imagePath;

  /// Creates an [ArtistHeaderAvatar].
  const ArtistHeaderAvatar({
    super.key,
    required this.artistName,
    required this.rawName,
    required this.size,
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = _gradientForArtist(rawName);
    final initial = _initialForArtist(artistName);

    final monogram = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
        child: Text(
          initial,
          style: AppTypography.display.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    final path = imagePath?.trim();
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        final cacheSize = (size * 2).round();
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: ClipOval(
            child: Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: cacheSize,
              cacheHeight: cacheSize,
              errorBuilder: (_, _, _) => monogram,
            ),
          ),
        );
      }
    }

    return monogram;
  }
}
