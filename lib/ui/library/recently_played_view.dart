import 'package:flutter/material.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/collections/user_collections.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/track_audio_source_mapper.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/settings_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'track_table.dart';

/// Screen displaying recently played tracks (up to 200) based on play events.
class RecentlyPlayedView extends StatefulWidget {
  /// Library repository for loading history.
  final LibraryRepository repository;

  /// Audio controller.
  final PlaybackController controller;

  /// Settings store.
  final SettingsStore settingsStore;

  /// User collections store.
  final UserCollections collections;

  /// Creates a [RecentlyPlayedView].
  const RecentlyPlayedView({
    super.key,
    required this.repository,
    required this.controller,
    required this.settingsStore,
    required this.collections,
  });

  @override
  State<RecentlyPlayedView> createState() => _RecentlyPlayedViewState();
}

class _RecentlyPlayedViewState extends State<RecentlyPlayedView> {
  List<Track> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecentTracks();
  }

  Future<void> _loadRecentTracks() async {
    final tracks = await widget.repository.recentlyPlayedTracks(limit: 200);
    if (mounted) {
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    }
  }

  Future<void> _playTracks({int startIndex = 0}) async {
    if (_tracks.isEmpty) return;
    final sources = _tracks.map((t) => t.toAudioSource()).toList();
    final safeIndex = (startIndex >= 0 && startIndex < sources.length)
        ? startIndex
        : 0;
    await widget.controller.playQueue(sources, startIndex: safeIndex);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = widget.settingsStore.settings.reduceMotion;
    final rows = _tracks.map((t) => TrackTableRow.fromTrack(t)).toList();

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('nav.recent'),
                      style: AppTypography.display
                          .copyWith(letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${context.formatCountLocalized(_tracks.length)} ${context.t('tracks.count')}',
                      style: AppTypography.body
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              GlassPillButton(
                key: const Key('recent_play_button'),
                label: context.t('album.playAlbum'),
                leadingIcon: Icons.play_arrow,
                variant: GlassButtonVariant.primary,
                size: GlassButtonSize.medium,
                onPressed: _tracks.isEmpty ? null : () => _playTracks(),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // TrackTable
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

                          return TrackTable(
                            rows: rows,
                            currentPlayingPath: activeSource?.uri,
                            isPlaying: isPlaying,
                            reduceMotion: reduceMotion,
                            controller: widget.controller,
                            userCollections: widget.collections,
                            listViewKey: const Key('recent_tracks_list'),
                            onPlay: (index, row) {
                              _playTracks(startIndex: index);
                            },
                            emptyPlaceholder: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.history,
                                    size: 64,
                                    color: AppColors.textMuted,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    context.t('recent.empty'),
                                    style: AppTypography.title
                                        .copyWith(color: AppColors.text),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    context.t('recent.emptyDescription'),
                                    style: AppTypography.body
                                        .copyWith(color: AppColors.textMuted),
                                  ),
                                ],
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
