import 'package:flutter/material.dart';

import '../../features/wrapped/recap.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../library/widgets/album_tiles.dart';
import '../now_playing/cover_palette.dart';
import '../stats/stats_formatters.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'wrapped_controller.dart';

/// Builds any of the 8 calm matte Wrapped / Weekly recap cards shared by the
/// interactive pager and summary preview.
class WrappedCardBody extends StatelessWidget {
  /// Card index `0..7`:
  /// 0 Intro, 1 Minutes, 2 Top artist, 3 Top 5 tracks, 4 Top album,
  /// 5 Discoveries, 6 Peak days, 7 Summary.
  final int pageIndex;

  /// Recap dataset to display.
  final Recap recap;

  /// Muted cover palette tinting the matte card surface.
  final CoverPalette palette;

  /// Controller providing CoverCache artwork lookups.
  final WrappedController controller;

  /// Optional callback triggered from the Summary card's "Share image" button.
  final VoidCallback? onShareImage;

  /// Whether image export is currently in progress.
  final bool isExporting;

  /// Creates a [WrappedCardBody].
  const WrappedCardBody({
    super.key,
    required this.pageIndex,
    required this.recap,
    required this.palette,
    required this.controller,
    this.onShareImage,
    this.isExporting = false,
  });

  /// Formats a localized period headline (e.g. `November 2026` or `23 Nov – 29 Nov`).
  static String formatPeriodLabel(BuildContext context, Recap recap) {
    if (recap.kind == RecapPeriodKind.monthly) {
      final monthName = context.t('wrapped.month.full.${recap.month}');
      final yearStr = context.formatCountLocalized(recap.year);
      return context.t(
        'wrapped.monthLabel',
        args: {'month': monthName, 'year': yearStr},
      );
    }
    final startStr = StatsFormatters.formatCalendarDay(
      context,
      recap.periodStart,
    );
    final endStr = StatsFormatters.formatCalendarDay(
      context,
      recap.periodEnd,
    );
    return context.t(
      'wrapped.weekRangeLabel',
      args: {'start': startStr, 'end': endStr},
    );
  }

  /// Localized personality badge key for [personality].
  static String personalityTitleKey(RecapPersonality personality) {
    switch (personality) {
      case RecapPersonality.nightOwl:
        return 'wrapped.personality.nightOwl';
      case RecapPersonality.earlyBird:
        return 'wrapped.personality.earlyBird';
      case RecapPersonality.albumListener:
        return 'wrapped.personality.albumListener';
      case RecapPersonality.explorer:
        return 'wrapped.personality.explorer';
      case RecapPersonality.steadyListener:
        return 'wrapped.personality.steadyListener';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgTop = Color.lerp(AppColors.surface, palette.tertiary, 0.36)!;
    final bgBottom = Color.lerp(AppColors.base, palette.secondary, 0.22)!;

    return Container(
      key: Key('wrapped_card_$pageIndex'),
      padding: const EdgeInsets.all(AppSpacing.s24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [bgTop, bgBottom],
        ),
        borderRadius: AppSpacing.br26,
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (pageIndex) {
      case 0:
        return _buildIntro(context);
      case 1:
        return _buildMinutes(context);
      case 2:
        return _buildTopArtist(context);
      case 3:
        return _buildTopTracks(context);
      case 4:
        return _buildTopAlbum(context);
      case 5:
        return _buildDiscoveries(context);
      case 6:
        return _buildPeakDays(context);
      default:
        return _buildSummary(context);
    }
  }

  Widget _buildIntro(BuildContext context) {
    final eyebrow = recap.kind == RecapPeriodKind.monthly
        ? context.t('wrapped.card.introMonthlyEyebrow')
        : context.t('wrapped.card.introWeeklyEyebrow');
    final periodLabel = formatPeriodLabel(context, recap);
    final personalityKey = personalityTitleKey(recap.personality);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: AppTypography.caption.copyWith(
            color: AppColors.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        Text(
          periodLabel,
          textDirection: textDirectionFor(periodLabel),
          style: AppTypography.display.copyWith(color: AppColors.text),
        ),
        const SizedBox(height: AppSpacing.s12),
        Text(
          context.localizeDigitsText(
            context.t(
              'wrapped.card.introSubtitle',
              args: {
                'plays': '${recap.playsCounted}',
                'artists': '${recap.distinctArtists}',
              },
            ),
          ),
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s24),
        Container(
          padding: const EdgeInsets.all(AppSpacing.s16),
          decoration: BoxDecoration(
            color: AppColors.fillControl,
            borderRadius: AppSpacing.br16,
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(personalityKey),
                key: const Key('wrapped_personality_title'),
                style: AppTypography.title.copyWith(color: AppColors.accent),
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                context.t('$personalityKey.caption'),
                key: const Key('wrapped_personality_caption'),
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMinutes(BuildContext context) {
    final formattedDuration = StatsFormatters.formatHoursMinutes(
      context,
      recap.totalListenedMs,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('wrapped.card.minutesTitle'),
          style: AppTypography.title.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s24),
        Text(
          context.localizeDigitsText(
            context.t(
              'wrapped.card.minutesValue',
              args: {'minutes': '${recap.totalMinutes}'},
            ),
          ),
          key: const Key('wrapped_total_minutes_value'),
          style: AppTypography.display.copyWith(
            fontSize: 40,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        Text(
          context.localizeDigitsText(
            context.t(
              'wrapped.card.minutesSubtitle',
              args: {
                'formatted': formattedDuration,
                'tracks': '${recap.distinctTracks}',
              },
            ),
          ),
          style: AppTypography.body.copyWith(color: AppColors.text),
        ),
      ],
    );
  }

  Widget _buildTopArtist(BuildContext context) {
    final topArtist = recap.topArtist;
    final coverKey = controller.resolveArtistCoverKey(topArtist?.artist);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('wrapped.card.topArtistTitle'),
          style: AppTypography.title.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s24),
        if (topArtist == null)
          Text(
            context.t('stats.summary.none'),
            style: AppTypography.display.copyWith(color: AppColors.textMuted),
          )
        else
          Row(
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: AlbumCoverImage(
                  coverKey: coverKey,
                  borderRadius: 48,
                  cacheSize: 160,
                ),
              ),
              const SizedBox(width: AppSpacing.s24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topArtist.artist,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: textDirectionFor(topArtist.artist),
                      style: AppTypography.display.copyWith(
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      context.localizeDigitsText(
                        context.t(
                          'wrapped.card.topArtistSubtitle',
                          args: {
                            'duration': StatsFormatters.formatHoursMinutes(
                              context,
                              topArtist.totalListenedMs,
                            ),
                            'plays': '${topArtist.playCount}',
                          },
                        ),
                      ),
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildTopTracks(BuildContext context) {
    final tracks = recap.topTracks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('wrapped.card.topTracksTitle'),
          style: AppTypography.title.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s16),
        if (tracks.isEmpty)
          Text(
            context.t('stats.ranked.emptySection'),
            style: AppTypography.body.copyWith(color: AppColors.textMuted),
          )
        else
          for (var i = 0; i < tracks.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.s8),
            _WrappedTrackRow(
              rank: i + 1,
              title: (tracks[i].title?.trim().isNotEmpty == true)
                  ? tracks[i].title!.trim()
                  : context.t('stats.ranked.unknownTrack'),
              artist: (tracks[i].artist?.trim().isNotEmpty == true)
                  ? tracks[i].artist!.trim()
                  : context.t('stats.ranked.unknownArtist'),
              coverKey: controller.resolveTrackCoverKey(tracks[i]),
              duration: StatsFormatters.formatHoursMinutes(
                context,
                tracks[i].totalListenedMs,
              ),
            ),
          ],
      ],
    );
  }

  Widget _buildTopAlbum(BuildContext context) {
    final album = recap.topAlbum;
    final coverKey = controller.resolveAlbumCoverKey(album);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('wrapped.card.topAlbumTitle'),
          style: AppTypography.title.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s24),
        if (album == null)
          Text(
            context.t('stats.summary.none'),
            style: AppTypography.display.copyWith(color: AppColors.textMuted),
          )
        else
          Row(
            children: [
              SizedBox(
                width: 112,
                height: 112,
                child: AlbumCoverImage(
                  coverKey: coverKey,
                  borderRadius: AppSpacing.r16,
                  cacheSize: 180,
                ),
              ),
              const SizedBox(width: AppSpacing.s24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.album,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: textDirectionFor(album.album),
                      style: AppTypography.display.copyWith(
                        fontSize: 26,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      context.localizeDigitsText(
                        context.t(
                          'wrapped.card.topAlbumSubtitle',
                          args: {
                            'artist':
                                album.artist?.trim().isNotEmpty == true
                                    ? album.artist!.trim()
                                    : context.t('stats.ranked.unknownArtist'),
                            'duration': StatsFormatters.formatHoursMinutes(
                              context,
                              album.totalListenedMs,
                            ),
                          },
                        ),
                      ),
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildDiscoveries(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('wrapped.card.discoveriesTitle'),
          style: AppTypography.title.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s24),
        Text(
          context.localizeDigitsText(
            context.t(
              'wrapped.card.discoveriesValue',
              args: {'count': '${recap.newTracksDiscovered}'},
            ),
          ),
          style: AppTypography.display.copyWith(
            fontSize: 38,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        Text(
          context.localizeDigitsText(
            context.t(
              'wrapped.card.discoveriesSubtitle',
              args: {'tracks': '${recap.distinctTracks}'},
            ),
          ),
          style: AppTypography.body.copyWith(color: AppColors.text),
        ),
      ],
    );
  }

  Widget _buildPeakDays(BuildContext context) {
    final includeYear = recap.kind == RecapPeriodKind.monthly;
    final busiest = recap.busiestDay;
    final longest = recap.longestListeningDay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('wrapped.card.daysTitle'),
          style: AppTypography.title.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s24),
        _DayHighlightBlock(
          label: context.t('wrapped.card.busiestDayLabel'),
          dateText: busiest != null
              ? StatsFormatters.formatCalendarDay(
                  context,
                  busiest.date,
                  includeYear: includeYear,
                )
              : context.t('stats.summary.none'),
          statText: busiest != null
              ? context.localizeDigitsText(
                  context.t(
                    'wrapped.card.busiestDayStat',
                    args: {
                      'plays': '${busiest.playCount}',
                      'duration': StatsFormatters.formatHoursMinutes(
                        context,
                        busiest.totalListenedMs,
                      ),
                    },
                  ),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.s16),
        _DayHighlightBlock(
          label: context.t('wrapped.card.longestDayLabel'),
          dateText: longest != null
              ? StatsFormatters.formatCalendarDay(
                  context,
                  longest.date,
                  includeYear: includeYear,
                )
              : context.t('stats.summary.none'),
          statText: longest != null
              ? context.localizeDigitsText(
                  context.t(
                    'wrapped.card.longestDayStat',
                    args: {
                      'duration': StatsFormatters.formatHoursMinutes(
                        context,
                        longest.totalListenedMs,
                      ),
                      'plays': '${longest.playCount}',
                    },
                  ),
                )
              : null,
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    final periodLabel = formatPeriodLabel(context, recap);
    final personalityKey = personalityTitleKey(recap.personality);
    final albumCover = controller.resolveAlbumCoverKey(recap.topAlbum);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('wrapped.card.summaryTitle'),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    periodLabel,
                    textDirection: textDirectionFor(periodLabel),
                    style: AppTypography.title.copyWith(color: AppColors.text),
                  ),
                ],
              ),
            ),
            if (albumCover != null)
              SizedBox(
                width: 56,
                height: 56,
                child: AlbumCoverImage(
                  coverKey: albumCover,
                  borderRadius: AppSpacing.r12,
                  cacheSize: 100,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        Wrap(
          spacing: AppSpacing.s16,
          runSpacing: AppSpacing.s12,
          children: [
            _MiniStat(
              label: context.t('stats.summary.totalListening'),
              value: StatsFormatters.formatHoursMinutes(
                context,
                recap.totalListenedMs,
              ),
            ),
            _MiniStat(
              label: context.t('wrapped.card.topArtistTitle'),
              value: recap.topArtist?.artist ?? context.t('stats.summary.none'),
            ),
            _MiniStat(
              label: context.t('wrapped.card.topAlbumTitle'),
              value: recap.topAlbum?.album ?? context.t('stats.summary.none'),
            ),
            _MiniStat(
              label: context.t('wrapped.card.discoveriesTitle'),
              value: context.formatCountLocalized(recap.newTracksDiscovered),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        Text(
          context.t(personalityKey),
          style: AppTypography.bodyStrong.copyWith(color: AppColors.accent),
        ),
        if (onShareImage != null) ...[
          const SizedBox(height: AppSpacing.s24),
          GlassPillButton(
            key: const Key('wrapped_summary_share_button'),
            leadingIcon: Icons.ios_share_outlined,
            label: isExporting
                ? context.t('wrapped.exporting')
                : context.t('wrapped.shareImage'),
            onPressed: isExporting ? null : onShareImage,
          ),
        ],
      ],
    );
  }
}

class _WrappedTrackRow extends StatelessWidget {
  final int rank;
  final String title;
  final String artist;
  final String? coverKey;
  final String duration;

  const _WrappedTrackRow({
    required this.rank,
    required this.title,
    required this.artist,
    required this.coverKey,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            context.formatCountLocalized(rank),
            style: AppTypography.caption.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        SizedBox(
          width: 36,
          height: 36,
          child: AlbumCoverImage(
            coverKey: coverKey,
            borderRadius: AppSpacing.r10,
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
                style: AppTypography.bodyStrong.copyWith(color: AppColors.text),
              ),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: textDirectionFor(artist),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Text(
          duration,
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _DayHighlightBlock extends StatelessWidget {
  final String label;
  final String dateText;
  final String? statText;

  const _DayHighlightBlock({
    required this.label,
    required this.dateText,
    this.statText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: AppColors.fillControl,
        borderRadius: AppSpacing.br16,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            dateText,
            style: AppTypography.title.copyWith(color: AppColors.text),
          ),
          if (statText != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              statText!,
              style: AppTypography.body.copyWith(color: AppColors.accent),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: textDirectionFor(value),
            style: AppTypography.bodyStrong.copyWith(color: AppColors.text),
          ),
        ],
      ),
    );
  }
}
