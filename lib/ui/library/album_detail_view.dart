import 'dart:io';

import 'package:flutter/material.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../library/cover_cache.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/track_audio_source_mapper.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Album detail screen displaying large artwork, metadata header, Play & Shuffle buttons,
/// and full tracklist with currently-playing row animation.
class AlbumDetailView extends StatefulWidget {
  /// The album model summary.
  final AlbumSummary album;

  /// The library storage repository.
  final LibraryRepository repository;

  /// The audio playback controller.
  final PlaybackController controller;

  /// The settings store for checking reduceMotion.
  final SettingsStore settingsStore;

  /// The navigation coordinator.
  final AppNavigator navigator;

  /// Creates an [AlbumDetailView].
  const AlbumDetailView({
    super.key,
    required this.album,
    required this.repository,
    required this.controller,
    required this.settingsStore,
    required this.navigator,
  });

  @override
  State<AlbumDetailView> createState() => _AlbumDetailViewState();
}

class _AlbumDetailViewState extends State<AlbumDetailView> {
  List<Track> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    final tracks = await widget.repository.tracksOfAlbum(
      widget.album.album,
      albumArtist: widget.album.albumArtist,
    );
    if (mounted) {
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    }
  }

  Future<void> _playAlbum({bool shuffle = false, int startIndex = 0}) async {
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

  int get _totalDurationMs =>
      _tracks.fold<int>(0, (sum, t) => sum + t.durationMs);

  String get _totalDurationFormatted {
    final d = Duration(milliseconds: _totalDurationMs);
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) {
      return '$hours hr $minutes min';
    }
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = widget.settingsStore.settings.reduceMotion;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back navigation row
          Row(
            children: [
              GlassIconButton(
                key: const Key('album_detail_back_button'),
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

          // Header: Cover (220) + Title + Artist + Year + Stats + Play / Shuffle buttons
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 220x220 cover
              _buildLargeCover(widget.album.coverKey),
              const SizedBox(width: 24),

              // Metadata details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      widget.album.album,
                      textDirection: textDirectionFor(widget.album.album),
                      style: AppTypography.display.copyWith(letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.album.albumArtist ?? 'Unknown Artist',
                      textDirection:
                          textDirectionFor(widget.album.albumArtist ?? ''),
                      style: AppTypography.title.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.album.trackCount} ${context.t('album.tracksCount')}'
                      '${widget.album.year != null ? ' • ${widget.album.year}' : ''}'
                      '${_tracks.isNotEmpty ? ' • $_totalDurationFormatted' : ''}',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Play and Shuffle Buttons
                    Row(
                      children: [
                        GlassPillButton(
                          key: const Key('album_play_button'),
                          label: context.t('album.playAlbum'),
                          leadingIcon: Icons.play_arrow,
                          variant: GlassButtonVariant.primary,
                          size: GlassButtonSize.medium,
                          onPressed: _tracks.isEmpty ? null : () => _playAlbum(),
                        ),
                        const SizedBox(width: 12),
                        GlassPillButton(
                          key: const Key('album_shuffle_button'),
                          label: context.t('album.shuffleAlbum'),
                          leadingIcon: Icons.shuffle,
                          size: GlassButtonSize.medium,
                          onPressed: _tracks.isEmpty
                              ? null
                              : () => _playAlbum(shuffle: true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Tracklist
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<AudioSource?>(
                    stream: widget.controller.currentStream,
                    initialData: widget.controller.queue.current,
                    builder: (context, trackSnapshot) {
                      final activeSource = trackSnapshot.data;

                      return StreamBuilder<PlaybackState>(
                        stream: widget.controller.stateStream,
                        initialData: widget.controller.currentState,
                        builder: (context, stateSnapshot) {
                          final isPlaying =
                              stateSnapshot.data == PlaybackState.playing;

                          return ListView.builder(
                            key: const Key('album_tracks_list'),
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
                                    onTap: () => _playAlbum(startIndex: index),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 32,
                                            child: Center(
                                              child: isCurrent
                                                  ? _AnimatedEqualizerMini(
                                                      isPlaying: isPlaying,
                                                      reduceMotion: reduceMotion,
                                                    )
                                                  : Text(
                                                      '${track.trackNo ?? index + 1}',
                                                      style: AppTypography.caption
                                                          .copyWith(
                                                        color: AppColors.textMuted,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              track.title ?? 'Unknown Title',
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
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
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

  Widget _buildLargeCover(String? coverKey) {
    Widget imageWidget;
    if (coverKey != null && CoverCache.hasCover(coverKey)) {
      final file = File(CoverCache.pathFor(coverKey));
      imageWidget = Image.file(
        file,
        width: 220,
        height: 220,
        fit: BoxFit.cover,
        cacheWidth: 440,
        cacheHeight: 440,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else {
      imageWidget = _buildPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.r16),
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.r16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 18.0,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: imageWidget,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF22212C),
        borderRadius: BorderRadius.circular(AppSpacing.r16),
      ),
      child: const Center(
        child: Icon(Icons.album, size: 72, color: Colors.white24),
      ),
    );
  }
}

class _AnimatedEqualizerMini extends StatelessWidget {
  final bool isPlaying;
  final bool reduceMotion;

  const _AnimatedEqualizerMini({
    required this.isPlaying,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _bar(8),
        const SizedBox(width: 2),
        _bar(12),
        const SizedBox(width: 2),
        _bar(6),
      ],
    );
  }

  Widget _bar(double height) {
    return Container(
      width: 2.5,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
