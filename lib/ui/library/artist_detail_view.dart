import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/library_view/artist_page_model.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/text_normalizer.dart';
import '../../library/track_audio_source_mapper.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'library_data_cache.dart';
import 'sort_direction_button.dart';
import 'track_table.dart';
import 'widgets/artist_album_section.dart';
import 'widgets/artist_detail_header.dart';
import 'widgets/artist_tracks_header.dart';

/// Apple Music-style artist detail screen with sectioned album cards and a
/// searchable, sortable tracks table.
class ArtistDetailView extends StatefulWidget {
  /// Fixed desktop width of each album release card.
  static const double kAlbumCardWidth = 172.0;

  /// Horizontal and vertical gap between album release cards.
  static const double kAlbumCardSpacing = 16.0;

  /// The artist summary model.
  final ArtistSummary artist;

  /// The library data repository.
  final LibraryRepository repository;

  /// The audio playback controller.
  final PlaybackController controller;

  /// The settings store for checking motion and sort preferences.
  final SettingsStore settingsStore;

  /// The application navigation coordinator.
  final AppNavigator navigator;

  /// Optional play count source for sorting tracks by most played.
  final TrackPlayCountSource? playCountSource;

  /// Optional artist image file path; falls back to a calm monogram when absent.
  final String? artistImagePath;

  /// Optional random generator for deterministic shuffle tests.
  final math.Random? random;

  /// Optional in-memory library data cache for automatic refresh after scans.
  final LibraryDataCache? dataCache;

  /// Creates an [ArtistDetailView].
  const ArtistDetailView({
    super.key,
    required this.artist,
    required this.repository,
    required this.controller,
    required this.settingsStore,
    required this.navigator,
    this.playCountSource,
    this.artistImagePath,
    this.random,
    this.dataCache,
  });

  @override
  State<ArtistDetailView> createState() => _ArtistDetailViewState();
}

class _ArtistDetailViewState extends State<ArtistDetailView> {
  ArtistPageModel? _model;
  Map<String, int> _playCounts = const {};
  bool _isLoading = true;
  int _loadRequestId = 0;

  final Set<ArtistPageSectionKind> _expandedSections = {};
  String _trackSearchQuery = '';
  late final TextEditingController _searchController;
  late final math.Random _random;
  LibraryDataCache? _activeCache;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _random = widget.random ?? math.Random();
    widget.settingsStore.addListener(_onSettingsChanged);
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cache = widget.dataCache ?? LibraryDataCacheScope.maybeOf(context);
    if (cache != _activeCache) {
      _activeCache?.removeListener(_onCacheChanged);
      _activeCache = cache;
      _activeCache?.addListener(_onCacheChanged);
    }
  }

  @override
  void didUpdateWidget(ArtistDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataCache != widget.dataCache) {
      final cache = widget.dataCache ?? LibraryDataCacheScope.maybeOf(context);
      if (cache != _activeCache) {
        _activeCache?.removeListener(_onCacheChanged);
        _activeCache = cache;
        _activeCache?.addListener(_onCacheChanged);
      }
    }
    if (oldWidget.settingsStore != widget.settingsStore) {
      oldWidget.settingsStore.removeListener(_onSettingsChanged);
      widget.settingsStore.addListener(_onSettingsChanged);
    }
    if (oldWidget.artist.key != widget.artist.key ||
        oldWidget.artist.name != widget.artist.name ||
        oldWidget.repository != widget.repository ||
        oldWidget.playCountSource != widget.playCountSource) {
      _expandedSections.clear();
      _trackSearchQuery = '';
      _searchController.clear();
      _isLoading = true;
      _model = null;
      _loadData();
    }
  }

  @override
  void dispose() {
    _activeCache?.removeListener(_onCacheChanged);
    widget.settingsStore.removeListener(_onSettingsChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onCacheChanged() {
    if (!mounted) return;
    _loadData();
  }

  void _onSettingsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadData() async {
    final reqId = ++_loadRequestId;
    final effectiveKey = widget.artist.key.trim().isNotEmpty
        ? widget.artist.key
        : widget.artist.name;
    final countSource =
        widget.playCountSource ?? RepositoryPlayCountSource(widget.repository);

    final results = await Future.wait<Object?>([
      widget.repository.tracksOfArtist(
        widget.artist.name,
        artistKey: widget.artist.key,
      ),
      widget.repository.listAlbumsByArtistKey(effectiveKey),
      widget.repository.listAliases(),
      countSource.getPlayCounts(),
    ]);

    if (!mounted || reqId != _loadRequestId) return;

    final tracks = results[0]! as List<Track>;
    final albums = results[1]! as List<AlbumSummary>;
    final aliases = results[2]! as List<ArtistAlias>;
    final playCounts = results[3]! as Map<String, int>;

    final normalizedKey = TextNormalizer.normalize(effectiveKey);
    final normalizedName = TextNormalizer.normalize(widget.artist.name);
    final aliasKeys = <String>{};
    for (final alias in aliases) {
      final canonical = TextNormalizer.normalize(alias.canonicalKey);
      final aliasKey = TextNormalizer.normalize(alias.aliasKey);
      if (canonical == normalizedKey ||
          canonical == normalizedName ||
          aliasKey == normalizedKey ||
          aliasKey == normalizedName) {
        if (alias.aliasKey.isNotEmpty) aliasKeys.add(alias.aliasKey);
        if (alias.canonicalKey.isNotEmpty) aliasKeys.add(alias.canonicalKey);
      }
    }

    final model = ArtistPageModel.fromData(
      artistName: widget.artist.name,
      artistKey: effectiveKey,
      albums: albums,
      tracks: tracks,
      aliasKeys: aliasKeys,
    );

    setState(() {
      _model = model;
      _playCounts = playCounts;
      _isLoading = false;
    });
  }

  List<Track> _sortArtistTracks(
    List<Track> list,
    String sortKey,
    bool reversed,
  ) {
    final sorted = List<Track>.from(list);
    sorted.sort((a, b) {
      int cmp;
      switch (sortKey) {
        case 'album':
          cmp = compareLocaleAware(a.album ?? '', b.album ?? '');
          if (cmp == 0) cmp = compareLocaleAware(a.title ?? '', b.title ?? '');
          break;
        case 'mostPlayed':
          final aCount = _playCounts[a.path] ?? 0;
          final bCount = _playCounts[b.path] ?? 0;
          cmp = aCount.compareTo(bCount);
          if (cmp == 0) cmp = compareLocaleAware(a.title ?? '', b.title ?? '');
          break;
        case 'recentlyAdded':
          cmp = a.addedAt.compareTo(b.addedAt);
          if (cmp == 0) cmp = compareLocaleAware(a.title ?? '', b.title ?? '');
          break;
        case 'duration':
          cmp = a.durationMs.compareTo(b.durationMs);
          if (cmp == 0) cmp = compareLocaleAware(a.title ?? '', b.title ?? '');
          break;
        case 'title':
        default:
          cmp = compareLocaleAware(a.title ?? '', b.title ?? '');
          break;
      }
      return reversed ? -cmp : cmp;
    });
    return sorted;
  }

  Future<void> _playTracks(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    final sources = tracks.map((t) => t.toAudioSource()).toList();
    final safeIndex = startIndex.clamp(0, sources.length - 1);
    await widget.controller.playQueue(
      sources,
      startIndex: safeIndex,
      source: 'artist',
    );
  }

  Future<void> _shuffleTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final sources = tracks.map((t) => t.toAudioSource()).toList();
    await widget.controller.playShuffled(
      sources,
      random: _random,
      source: 'artist',
    );
  }

  Widget? _buildTrackActionWidget(Track track) {
    final trackArtist = track.artist?.trim();
    if (track.id == null || trackArtist == null || trackArtist.isEmpty) {
      return null;
    }
    return ArtistTrackActionMenu(
      track: track,
      repository: widget.repository,
      onReload: _loadData,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settingsStore.settings;
    final reduceMotion = settings.reduceMotion;
    final model = _model;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rawWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final availableWidth = math.max(120.0, rawWidth - 48.0);
        final cardsPerRow = availableWidth <= ArtistDetailView.kAlbumCardWidth
            ? 1
            : ((availableWidth + ArtistDetailView.kAlbumCardSpacing) /
                    (ArtistDetailView.kAlbumCardWidth +
                        ArtistDetailView.kAlbumCardSpacing))
                .floor()
                .clamp(1, 12);
        final cardWidth = availableWidth < ArtistDetailView.kAlbumCardWidth
            ? availableWidth
            : ArtistDetailView.kAlbumCardWidth;

        final allTracks = model == null
            ? const <Track>[]
            : _sortArtistTracks(
                model.tracks,
                settings.artistDetailTrackSort,
                settings.artistDetailTrackSortReversed,
              );

        final visibleTracks = model == null
            ? const <Track>[]
            : _sortArtistTracks(
                model.filterTracks(_trackSearchQuery),
                settings.artistDetailTrackSort,
                settings.artistDetailTrackSortReversed,
              );

        return CustomScrollView(
          key: const Key('artist_detail_scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsetsDirectional.only(
                start: 24,
                end: 24,
                top: 16,
              ),
              sliver: SliverToBoxAdapter(
                child: ArtistDetailHeader(
                  artist: widget.artist,
                  model: model,
                  availableWidth: availableWidth,
                  allTracks: allTracks,
                  artistImagePath: widget.artistImagePath,
                  repository: widget.repository,
                  navigator: widget.navigator,
                  onPlayAll: () => _playTracks(allTracks),
                  onShuffleAll: () => _shuffleTracks(allTracks),
                  onReload: _loadData,
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (model != null) ...[
              for (final section in model.albumSections)
                SliverPadding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 24,
                    end: 24,
                    top: 24,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: ArtistAlbumSectionView(
                      section: section,
                      cardsPerRow: cardsPerRow,
                      cardWidth: cardWidth,
                      cardSpacing: ArtistDetailView.kAlbumCardSpacing,
                      isExpanded: _expandedSections.contains(section.kind),
                      reduceMotion: reduceMotion,
                      navigator: widget.navigator,
                      onToggleExpanded: () {
                        setState(() {
                          if (!_expandedSections.remove(section.kind)) {
                            _expandedSections.add(section.kind);
                          }
                        });
                      },
                    ),
                  ),
                ),
              if (model.hasTracks) ...[
                SliverPadding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 24,
                    end: 24,
                    top: 28,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: ArtistTracksSectionHeader(
                      availableWidth: availableWidth,
                      visibleTracks: visibleTracks,
                      settings: settings,
                      settingsStore: widget.settingsStore,
                      reduceMotion: reduceMotion,
                      searchController: _searchController,
                      trackSearchQuery: _trackSearchQuery,
                      onSearchChanged: (value) {
                        setState(() => _trackSearchQuery = value);
                      },
                      onShuffle: () => _shuffleTracks(visibleTracks),
                    ),
                  ),
                ),
                if (visibleTracks.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 24,
                      end: 24,
                      top: 24,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: Text(
                          context.t(
                            'artist.tracksNoMatches',
                            args: {'query': _trackSearchQuery.trim()},
                          ),
                          style: AppTypography.body.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 24,
                      end: 24,
                    ),
                    sliver: StreamBuilder<AudioSource?>(
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

                            return SliverFixedExtentList(
                              key: const Key('artist_tracks_list'),
                              itemExtent: 52.0,
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final track = visibleTracks[index];
                                  final isCurrent = activeSource != null &&
                                      (activeSource.uri == track.path ||
                                          activeSource.uri ==
                                              'file://${track.path}');

                                  return TrackTableRowTile(
                                    index: index,
                                    row: TrackTableRow.fromTrack(track),
                                    isCurrent: isCurrent,
                                    isPlaying: isCurrent && isPlaying,
                                    reduceMotion: reduceMotion,
                                    showTrackNumber: true,
                                    showCover: true,
                                    showAlbum: true,
                                    showArtist: false,
                                    showActions: true,
                                    controller: widget.controller,
                                    onPlay: () => _playTracks(
                                      visibleTracks,
                                      startIndex: index,
                                    ),
                                    actionWidget: _buildTrackActionWidget(track),
                                  );
                                },
                                childCount: visibleTracks.length,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ] else if (model.albumSections.isEmpty)
                SliverPadding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 24,
                    end: 24,
                    top: 32,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: Text(
                        context.t('artist.tracksEmpty'),
                        style: AppTypography.body.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
          ],
        );
      },
    );
  }
}
