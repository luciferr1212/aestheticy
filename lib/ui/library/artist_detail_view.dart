import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../features/library/artist_rules_sheet.dart';
import '../../features/library_view/artist_page_model.dart';
import '../../library/cover_cache.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/text_normalizer.dart';
import '../../library/track_audio_source_mapper.dart';
import '../artist_names/artist_name_scope.dart';
import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'library_data_cache.dart';
import 'library_view_controls.dart';
import 'sort_direction_button.dart';
import 'track_table.dart';

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
    await widget.controller.playQueue(sources, startIndex: safeIndex);
  }

  Future<void> _shuffleTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final sources = tracks.map((t) => t.toAudioSource()).toList();
    await widget.controller.playShuffled(sources, random: _random);
  }

  String _sectionTitle(BuildContext context, ArtistPageSectionKind kind) {
    return switch (kind) {
      ArtistPageSectionKind.albums => context.t('artist.section.albums'),
      ArtistPageSectionKind.singlesAndEps =>
        context.t('artist.section.singlesAndEps'),
      ArtistPageSectionKind.compilations =>
        context.t('artist.section.compilations'),
      ArtistPageSectionKind.appearsOn => context.t('artist.section.appearsOn'),
      ArtistPageSectionKind.tracks => context.t('artist.section.tracks'),
    };
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
                child: _buildHeader(
                  context,
                  availableWidth: availableWidth,
                  model: model,
                  allTracks: allTracks,
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
                    child: _buildAlbumSection(
                      context,
                      section: section,
                      cardsPerRow: cardsPerRow,
                      cardWidth: cardWidth,
                      reduceMotion: reduceMotion,
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
                    child: _buildTracksSectionHeader(
                      context,
                      availableWidth: availableWidth,
                      visibleTracks: visibleTracks,
                      settings: settings,
                      reduceMotion: reduceMotion,
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
                                    actionWidget: _buildTrackActionWidget(
                                      context,
                                      track,
                                    ),
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

  Widget _buildHeader(
    BuildContext context, {
    required double availableWidth,
    required ArtistPageModel? model,
    required List<Track> allTracks,
  }) {
    final displayName = context.displayArtist(widget.artist.name);
    final avatarSize = availableWidth < 520 ? 84.0 : 104.0;
    final albumCount = model?.albumCount ?? widget.artist.albumCount;
    final trackCount = model?.trackCount ?? widget.artist.trackCount;

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
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ArtistHeaderAvatar(
              key: const Key('artist_header_avatar'),
              artistName: displayName,
              rawName: widget.artist.name,
              size: avatarSize,
              imagePath: widget.artistImagePath,
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
                        onPressed: allTracks.isEmpty
                            ? null
                            : () => _playTracks(allTracks),
                      ),
                      GlassPillButton(
                        key: const Key('artist_shuffle_button'),
                        label: context.t('common.shuffle'),
                        leadingIcon: Icons.shuffle,
                        size: GlassButtonSize.small,
                        onPressed: allTracks.isEmpty
                            ? null
                            : () => _shuffleTracks(allTracks),
                      ),
                      GlassPillButton(
                        key: const Key('artist_rules_button'),
                        label: context.t('artist.rules'),
                        leadingIcon: Icons.rule,
                        size: GlassButtonSize.small,
                        onPressed: () {
                          ArtistRulesSheet.show(
                            context,
                            repository: widget.repository,
                          ).then((_) => _loadData());
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

  Widget _buildAlbumSection(
    BuildContext context, {
    required ArtistAlbumSection section,
    required int cardsPerRow,
    required double cardWidth,
    required bool reduceMotion,
  }) {
    final isExpanded = _expandedSections.contains(section.kind);
    final hasOverflowRows = section.albums.length > cardsPerRow;
    final visibleAlbums =
        isExpanded ? section.albums : section.albums.take(cardsPerRow).toList();

    return Column(
      key: Key('artist_section_${section.kind.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeaderRow(
          title: _sectionTitle(context, section.kind),
          count: section.albums.length,
          countKey: Key('artist_section_count_${section.kind.name}'),
          trailing: hasOverflowRows
              ? GlassPillButton(
                  key: Key('artist_section_toggle_${section.kind.name}'),
                  label: isExpanded
                      ? context.t('artist.showLess')
                      : context.t('artist.showAll'),
                  size: GlassButtonSize.small,
                  onPressed: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedSections.remove(section.kind);
                      } else {
                        _expandedSections.add(section.kind);
                      }
                    });
                  },
                )
              : null,
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeOut,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: AlignmentDirectional.topStart,
            children: [
              ...previousChildren,
              ?currentChild,
            ],
          ),
          child: KeyedSubtree(
            key: ValueKey<bool>(isExpanded),
            child: Wrap(
              spacing: ArtistDetailView.kAlbumCardSpacing,
              runSpacing: ArtistDetailView.kAlbumCardSpacing,
              children: [
                for (final album in visibleAlbums)
                  _ArtistAlbumCard(
                    key: ValueKey<String>(
                      'artist_album_card_${section.kind.name}_${album.album}|${album.albumArtist ?? ''}',
                    ),
                    album: album,
                    width: cardWidth,
                    reduceMotion: reduceMotion,
                    onTap: () => widget.navigator.openAlbumDetail(
                      album.album,
                      album: album,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTracksSectionHeader(
    BuildContext context, {
    required double availableWidth,
    required List<Track> visibleTracks,
    required dynamic settings,
    required bool reduceMotion,
  }) {
    final searchWidth = math.min(240.0, availableWidth);

    return Column(
      key: const Key('artist_section_tracks'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeaderRow(
          title: context.t('artist.section.tracks'),
          count: visibleTracks.length,
          countKey: const Key('artist_section_count_tracks'),
          trailing: GlassPillButton(
            key: const Key('artist_tracks_shuffle_button'),
            label: context.t('common.shuffle'),
            leadingIcon: Icons.shuffle,
            size: GlassButtonSize.small,
            onPressed: visibleTracks.isEmpty
                ? null
                : () => _shuffleTracks(visibleTracks),
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
              currentSort: settings.artistDetailTrackSort as String,
              onSortChanged: (newSort) {
                final newReversed = SortDirection.defaultReversedFor(newSort);
                widget.settingsStore.update(
                  (s) => s.copyWith(
                    artistDetailTrackSort: newSort,
                    artistDetailTrackSortReversed: newReversed,
                  ),
                );
              },
              sortDirection: SortDirection.fromReversed(
                settings.artistDetailTrackSortReversed as bool,
              ),
              onSortDirectionChanged: (newDir) {
                widget.settingsStore.update(
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
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() => _trackSearchQuery = value);
                        },
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
                    if (_trackSearchQuery.isNotEmpty)
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
                          _searchController.clear();
                          setState(() => _trackSearchQuery = '');
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

  Widget? _buildTrackActionWidget(BuildContext context, Track track) {
    final trackArtist = track.artist?.trim();
    if (track.id == null || trackArtist == null || trackArtist.isEmpty) {
      return null;
    }

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
          await widget.repository.addNoSplit(track.artist!);
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(content: Text(treatedMsg)),
            );
            await _loadData();
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

class _ArtistHeaderAvatar extends StatelessWidget {
  final String artistName;
  final String rawName;
  final double size;
  final String? imagePath;

  const _ArtistHeaderAvatar({
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

class _SectionHeaderRow extends StatelessWidget {
  final String title;
  final int count;
  final Key countKey;
  final Widget? trailing;

  const _SectionHeaderRow({
    required this.title,
    required this.count,
    required this.countKey,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.title.copyWith(color: AppColors.text),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  key: countKey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.fillControl,
                    borderRadius: AppSpacing.brPill,
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Text(
                    context.formatCountLocalized(count),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

class _ArtistAlbumCard extends StatefulWidget {
  final AlbumSummary album;
  final double width;
  final bool reduceMotion;
  final VoidCallback onTap;

  const _ArtistAlbumCard({
    super.key,
    required this.album,
    required this.width,
    required this.reduceMotion,
    required this.onTap,
  });

  @override
  State<_ArtistAlbumCard> createState() => _ArtistAlbumCardState();
}

class _ArtistAlbumCardState extends State<_ArtistAlbumCard> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final hasYear = album.year != null && album.year! > 0;
    final tracksStr = context.formatCountLocalized(album.trackCount);
    final metaText = hasYear
        ? context.t(
            'artist.albumCardMeta',
            args: {
              'year': context.localizeDigitsText(album.year.toString()),
              'tracks': tracksStr,
            },
          )
        : context.t(
            'artist.albumCardTracksOnly',
            args: {'tracks': tracksStr},
          );

    return Semantics(
      button: true,
      label: '${album.album}, $metaText',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (hovered) {
          if (_isHovered != hovered) {
            setState(() => _isHovered = hovered);
          }
        },
        onShowFocusHighlight: (focused) {
          if (_isFocused != focused) {
            setState(() => _isFocused = focused);
          }
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: widget.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 120),
            width: widget.width,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _isHovered ? AppColors.fillControl : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.r12),
              border: Border.all(
                color: _isFocused
                    ? AppColors.accent
                    : (_isHovered
                        ? AppColors.borderSubtle
                        : Colors.transparent),
                width: 2.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 1.0,
                  child: _ArtistAlbumCover(
                    coverKey: album.coverKey,
                    cacheWidth: 320,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  album.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: textDirectionFor(album.album),
                  style: AppTypography.bodyStrong.copyWith(
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metaText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtistAlbumCover extends StatelessWidget {
  final String? coverKey;
  final int cacheWidth;

  const _ArtistAlbumCover({
    required this.coverKey,
    required this.cacheWidth,
  });

  File? _resolveCoverFile() {
    final key = coverKey;
    if (key == null || key.isEmpty) return null;
    try {
      if (!CoverCache.hasCover(key)) return null;
      return File(CoverCache.pathFor(key));
    } on StateError {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _resolveCoverFile();
    final Widget imageWidget;
    if (file != null) {
      imageWidget = Image.file(
        file,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        cacheWidth: cacheWidth,
        cacheHeight: cacheWidth,
        frameBuilder: (context, child, frame, wasSync) {
          if (wasSync || frame != null) return child;
          return _buildPlaceholder();
        },
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else {
      imageWidget = _buildPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.r10),
      child: imageWidget,
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF22212C),
        borderRadius: BorderRadius.circular(AppSpacing.r10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: const Center(
        child: Icon(Icons.album_outlined, color: Colors.white24, size: 32),
      ),
    );
  }
}
