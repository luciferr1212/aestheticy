import 'package:flutter/material.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/library/artist_rules_sheet.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/track_audio_source_mapper.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

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

/// Artist detail screen displaying large artist avatar, track list, and Play/Shuffle.
class ArtistDetailView extends StatefulWidget {
  /// The artist summary model.
  final ArtistSummary artist;

  /// The library data repository.
  final LibraryRepository repository;

  /// The audio playback controller.
  final PlaybackController controller;

  /// The settings store for checking motion options.
  final SettingsStore settingsStore;

  /// The application navigation coordinator.
  final AppNavigator navigator;

  /// Creates an [ArtistDetailView].
  const ArtistDetailView({
    super.key,
    required this.artist,
    required this.repository,
    required this.controller,
    required this.settingsStore,
    required this.navigator,
  });

  @override
  State<ArtistDetailView> createState() => _ArtistDetailViewState();
}

class _ArtistDetailViewState extends State<ArtistDetailView> {
  List<Track> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    final tracks = await widget.repository.tracksOfArtist(
      widget.artist.name,
      artistKey: widget.artist.key,
    );
    if (mounted) {
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    }
  }

  Future<void> _playArtist({bool shuffle = false, int startIndex = 0}) async {
    if (_tracks.isEmpty) return;
    final sources = _tracks.map((t) => t.toAudioSource()).toList();
    if (shuffle) {
      sources.shuffle();
      await widget.controller.playQueue(sources, startIndex: 0);
    } else {
      await widget.controller.playQueue(sources, startIndex: startIndex);
    }
  }

  String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _gradientForArtist(widget.artist.name);
    final initial = _initialForArtist(widget.artist.name);

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back button
          Row(
            children: [
              GlassIconButton(
                key: const Key('artist_detail_back_button'),
                icon: Icons.arrow_back,
                tooltip: context.t('common.back'),
                semanticLabel: context.t('common.back'),
                size: GlassButtonSize.small,
                onPressed: () => widget.navigator.goBack(),
              ),
              const SizedBox(width: 8),
              Text(
                context.t('common.back'),
                style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                width: 100,
                height: 100,
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
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(
                      builder: (context) {
                        final displayName = context.displayArtist(widget.artist.name);
                        return Text(
                          displayName,
                          textDirection: textDirectionFor(displayName),
                          style: AppTypography.display.copyWith(letterSpacing: -0.5),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_tracks.length} ${context.t('tracks.count')}',
                      style: AppTypography.body.copyWith(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        GlassPillButton(
                          key: const Key('artist_play_button'),
                          label: context.t('common.play'),
                          leadingIcon: Icons.play_arrow,
                          variant: GlassButtonVariant.primary,
                          size: GlassButtonSize.small,
                          onPressed: _tracks.isEmpty ? null : () => _playArtist(),
                        ),
                        const SizedBox(width: 12),
                        GlassPillButton(
                          key: const Key('artist_shuffle_button'),
                          label: context.t('common.shuffle'),
                          leadingIcon: Icons.shuffle,
                          size: GlassButtonSize.small,
                          onPressed: _tracks.isEmpty
                              ? null
                              : () => _playArtist(shuffle: true),
                        ),
                        const SizedBox(width: 12),
                        GlassPillButton(
                          label: context.t('artist.rules'),
                          leadingIcon: Icons.rule,
                          size: GlassButtonSize.small,
                          onPressed: () {
                            ArtistRulesSheet.show(
                              context,
                              repository: widget.repository,
                            ).then((_) => _loadTracks());
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Tracks list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<AudioSource?>(
                    stream: widget.controller.currentStream,
                    initialData: widget.controller.queue.current,
                    builder: (context, trackSnapshot) {
                      final activeSource = trackSnapshot.data;

                      return ListView.builder(
                        key: const Key('artist_tracks_list'),
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: _tracks.length,
                        itemExtent: 48.0,
                        itemBuilder: (context, index) {
                          final track = _tracks[index];
                          final isCurrent = activeSource != null &&
                              (activeSource.uri == track.path ||
                                  activeSource.uri == 'file://${track.path}');

                          return RepaintBoundary(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 1),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? AppColors.accentFill
                                    : Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.r10),
                              ),
                              child: InkWell(
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.r10),
                                onTap: () => _playArtist(startIndex: index),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 32,
                                        child: Text(
                                          '${index + 1}',
                                          textAlign: TextAlign.center,
                                          style: AppTypography.caption.copyWith(
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          track.title ??
                                              context.t('library.unknownTitle'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textDirection: textDirectionFor(
                                              track.title ?? ''),
                                          style: AppTypography.body.copyWith(
                                            color: isCurrent
                                                ? AppColors.accent
                                                : AppColors.text,
                                            fontWeight: isCurrent
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          track.album ??
                                              context.t('library.unknownAlbum'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textDirection: textDirectionFor(
                                              track.album ?? ''),
                                          style: AppTypography.body.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 56,
                                        child: Text(
                                          _formatDuration(track.durationMs),
                                          textAlign: TextAlign.end,
                                          style: AppTypography.caption.copyWith(
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                      ),
                                      if (track.id != null &&
                                          track.artist != null &&
                                          track.artist!.trim().isNotEmpty)
                                        PopupMenuButton<String>(
                                          key: Key('track_menu_${track.id}'),
                                          icon: const Icon(
                                            Icons.more_horiz,
                                            size: 16,
                                            color: AppColors.textMuted,
                                          ),
                                          tooltip: context.t('artists.optionsTooltip'),
                                          color: const Color(0xFF1D1C25),
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
                                              await widget.repository.addNoSplit(track.artist!);
                                              if (mounted) {
                                                messenger.showSnackBar(
                                                  SnackBar(
                                                    content: Text(treatedMsg),
                                                  ),
                                                );
                                                await _loadTracks();
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
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
