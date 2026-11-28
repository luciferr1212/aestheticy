import 'dart:async';

import 'package:flutter/material.dart';

import '../../../audio/audio_models.dart';
import '../../../audio/playback_controller.dart';
import '../../../library/album_identity.dart';
import '../../../library/file_path_utils.dart';
import '../../../library/models.dart';
import '../../../library/text_normalizer.dart';
import '../../../library/track_audio_source_mapper.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../library/library_data_cache.dart';
import '../../library/widgets/album_tiles.dart';
import '../../shell/app_navigator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../stats_formatters.dart';
import '../stats_models.dart';

/// Displays Top 10 tracks, artists, and albums with CoverCache thumbnails and
/// direct play / detail navigation actions.
class StatsRankedLists extends StatelessWidget {
  /// Active stats snapshot containing ranked lists.
  final StatsSnapshot snapshot;

  /// Shared library cache used to resolve covers and domain objects.
  final LibraryDataCache dataCache;

  /// Playback controller invoked when tapping a top track.
  final PlaybackController playbackController;

  /// App navigator invoked when tapping a top artist or album.
  final AppNavigator navigator;

  /// Creates a [StatsRankedLists].
  const StatsRankedLists({
    super.key,
    required this.snapshot,
    required this.dataCache,
    required this.playbackController,
    required this.navigator,
  });

  @override
  Widget build(BuildContext context) {
    final trackByKey = <String, Track>{};
    final albumCoverByKey = <String, String>{};
    final albumByKey = <String, AlbumSummary>{};
    final artistByKey = <String, ArtistSummary>{};

    final tracks = dataCache.tracks ?? const <Track>[];
    for (final t in tracks) {
      trackByKey[FilePathUtils.canonicalKey(t.path)] = t;
      final cover = t.coverKey;
      if (cover != null && cover.isNotEmpty) {
        albumCoverByKey.putIfAbsent(AlbumIdentity.forTrack(t), () => cover);
      }
    }
    for (final album in dataCache.albums ?? const <AlbumSummary>[]) {
      final key = AlbumIdentity.forSummary(album);
      albumByKey[key] = album;
      final cover = album.coverKey;
      if (cover != null && cover.isNotEmpty) {
        albumCoverByKey[key] = cover;
      }
    }
    for (final artist in dataCache.artists ?? const <ArtistSummary>[]) {
      artistByKey[TextNormalizer.normalize(artist.name)] = artist;
      artistByKey[artist.key] = artist;
    }

    final trackCard = _RankedCard(
      key: const Key('stats_top_tracks_card'),
      title: context.t('stats.ranked.topTracks'),
      emptyText: context.t('stats.ranked.emptySection'),
      itemCount: snapshot.topTracks.length,
      itemBuilder: (context, index) {
        final stat = snapshot.topTracks[index];
        final matchedTrack = trackByKey[FilePathUtils.canonicalKey(stat.uri)];
        final coverKey = matchedTrack?.coverKey;
        final title = (stat.title?.trim().isNotEmpty == true)
            ? stat.title!.trim()
            : (matchedTrack?.title?.trim().isNotEmpty == true
                  ? matchedTrack!.title!.trim()
                  : context.t('stats.ranked.unknownTrack'));
        final subtitle = (stat.artist?.trim().isNotEmpty == true)
            ? stat.artist!.trim()
            : (matchedTrack?.artist?.trim().isNotEmpty == true
                  ? matchedTrack!.artist!.trim()
                  : context.t('stats.ranked.unknownArtist'));

        return _RankedRow(
          key: Key('stats_top_track_$index'),
          rank: index + 1,
          coverKey: coverKey,
          title: title,
          subtitle: subtitle,
          trailingDuration: StatsFormatters.formatHoursMinutes(
            context,
            stat.totalListenedMs,
          ),
          trailingPlays: context.localizeDigitsText(
            context.t(
              'stats.ranked.plays',
              args: {'count': '${stat.playCount}'},
            ),
          ),
          onTap: () {
            final source = matchedTrack != null
                ? matchedTrack.toAudioSource()
                : AudioSource(
                    stat.uri,
                    extras: {
                      if (stat.title != null) 'title': stat.title!,
                      if (stat.artist != null) 'artist': stat.artist!,
                      if (stat.album != null) 'album': stat.album!,
                    },
                  );
            unawaited(playbackController.playQueue([source]));
          },
        );
      },
    );

    final artistCard = _RankedCard(
      key: const Key('stats_top_artists_card'),
      title: context.t('stats.ranked.topArtists'),
      emptyText: context.t('stats.ranked.emptySection'),
      itemCount: snapshot.topArtists.length,
      itemBuilder: (context, index) {
        final stat = snapshot.topArtists[index];
        final normKey = TextNormalizer.normalize(stat.artist);
        final matchedArtist = artistByKey[normKey];
        final fallbackAlbumCover = _findArtistAlbumCover(stat.artist);

        return _RankedRow(
          key: Key('stats_top_artist_$index'),
          rank: index + 1,
          coverKey: fallbackAlbumCover,
          isCircularCover: true,
          title: stat.artist,
          subtitle: context.localizeDigitsText(
            context.t(
              'stats.ranked.plays',
              args: {'count': '${stat.playCount}'},
            ),
          ),
          trailingDuration: StatsFormatters.formatHoursMinutes(
            context,
            stat.totalListenedMs,
          ),
          onTap: () {
            final artistSummary =
                matchedArtist ??
                ArtistSummary(
                  name: stat.artist,
                  albumCount: 0,
                  trackCount: 0,
                );
            navigator.openArtistDetail(
              artistSummary.key,
              artist: artistSummary,
            );
          },
        );
      },
    );

    final albumCard = _RankedCard(
      key: const Key('stats_top_albums_card'),
      title: context.t('stats.ranked.topAlbums'),
      emptyText: context.t('stats.ranked.emptySection'),
      itemCount: snapshot.topAlbums.length,
      itemBuilder: (context, index) {
        final stat = snapshot.topAlbums[index];
        final key = AlbumIdentity.key(album: stat.album, artist: stat.artist);
        final matchedAlbum = albumByKey[key] ?? _findAlbumByTitle(stat.album);
        final coverKey = matchedAlbum?.coverKey ?? albumCoverByKey[key];
        final subtitle = (stat.artist?.trim().isNotEmpty == true)
            ? stat.artist!.trim()
            : (matchedAlbum?.displayArtist ??
                  matchedAlbum?.albumArtist ??
                  context.t('stats.ranked.unknownArtist'));

        return _RankedRow(
          key: Key('stats_top_album_$index'),
          rank: index + 1,
          coverKey: coverKey,
          title: stat.album,
          subtitle: subtitle,
          trailingDuration: StatsFormatters.formatHoursMinutes(
            context,
            stat.totalListenedMs,
          ),
          trailingPlays: context.localizeDigitsText(
            context.t(
              'stats.ranked.plays',
              args: {'count': '${stat.playCount}'},
            ),
          ),
          onTap: () {
            final albumSummary =
                matchedAlbum ??
                AlbumSummary(
                  album: stat.album,
                  albumArtist: stat.artist,
                  trackCount: 0,
                  coverKey: coverKey,
                );
            navigator.openAlbumDetail(
              AlbumIdentity.forSummary(albumSummary),
              album: albumSummary,
            );
          },
        );
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 980) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: trackCard),
              const SizedBox(width: AppSpacing.s16),
              Expanded(child: artistCard),
              const SizedBox(width: AppSpacing.s16),
              Expanded(child: albumCard),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            trackCard,
            const SizedBox(height: AppSpacing.s16),
            artistCard,
            const SizedBox(height: AppSpacing.s16),
            albumCard,
          ],
        );
      },
    );
  }

  String? _findArtistAlbumCover(String artist) {
    final target = TextNormalizer.normalize(artist);
    for (final album in dataCache.albums ?? const <AlbumSummary>[]) {
      final albumArtist = TextNormalizer.normalize(
        album.displayArtist ?? album.albumArtist ?? '',
      );
      if (albumArtist == target &&
          album.coverKey != null &&
          album.coverKey!.isNotEmpty) {
        return album.coverKey;
      }
    }
    return null;
  }

  AlbumSummary? _findAlbumByTitle(String albumTitle) {
    final target = TextNormalizer.normalize(albumTitle);
    for (final album in dataCache.albums ?? const <AlbumSummary>[]) {
      if (TextNormalizer.normalize(album.album) == target) {
        return album;
      }
    }
    return null;
  }
}

class _RankedCard extends StatelessWidget {
  final String title;
  final String emptyText;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const _RankedCard({
    super.key,
    required this.title,
    required this.emptyText,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.78),
        borderRadius: AppSpacing.br22,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.title.copyWith(color: AppColors.text),
          ),
          const SizedBox(height: AppSpacing.s12),
          if (itemCount == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
              child: Text(
                emptyText,
                style: AppTypography.body.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            ),
        ],
      ),
    );
  }
}

class _RankedRow extends StatelessWidget {
  final int rank;
  final String? coverKey;
  final bool isCircularCover;
  final String title;
  final String subtitle;
  final String trailingDuration;
  final String? trailingPlays;
  final VoidCallback onTap;

  const _RankedRow({
    super.key,
    required this.rank,
    required this.coverKey,
    this.isCircularCover = false,
    required this.title,
    required this.subtitle,
    required this.trailingDuration,
    this.trailingPlays,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      hoverColor: const Color(0x14FFFFFF),
      borderRadius: AppSpacing.br10,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: 6,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                context.formatCountLocalized(rank),
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: rank <= 3 ? AppColors.accent : AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            SizedBox(
              width: 40,
              height: 40,
              child: AlbumCoverImage(
                coverKey: coverKey,
                borderRadius: isCircularCover ? 20.0 : AppSpacing.r10,
                cacheSize: 64,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDirectionFor(title),
                    style: AppTypography.bodyStrong.copyWith(
                      color: AppColors.text,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDirectionFor(subtitle),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  trailingDuration,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (trailingPlays != null)
                  Text(
                    trailingPlays!,
                    style: AppTypography.caption.copyWith(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
