import 'package:flutter/material.dart';

import '../../features/library/artist_rules_sheet.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../artist_names/artist_name_scope.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'library_header.dart';
import 'library_view_controls.dart';
import 'sort_direction_button.dart';

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

/// Artists library screen displaying virtualized circular avatars with
/// deterministic calm gradients, merge badges, and contextual management menus.
class ArtistsView extends StatefulWidget {
  /// The library data repository.
  final LibraryRepository repository;

  /// The settings store for user preferences.
  final SettingsStore settingsStore;

  /// The application navigation coordinator.
  final AppNavigator navigator;

  /// Creates an [ArtistsView].
  const ArtistsView({
    super.key,
    required this.repository,
    required this.settingsStore,
    required this.navigator,
  });

  @override
  State<ArtistsView> createState() => _ArtistsViewState();
}

class _ArtistsViewState extends State<ArtistsView> {
  List<ArtistSummary> _artists = [];
  List<ArtistSummary> _searchResults = [];
  Set<String> _mergedCanonicalKeys = <String>{};
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadArtists();
  }

  Future<void> _loadArtists() async {
    final artists = await widget.repository.listArtists(limit: 5000);
    final aliases = await widget.repository.listAliases();
    final mergedKeys = aliases.map((a) => a.canonicalKey).toSet();

    if (mounted) {
      setState(() {
        _artists = artists;
        _mergedCanonicalKeys = mergedKeys;
        _isLoading = false;
      });
    }
  }

  Future<void> _onSearchChanged(String query) async {
    setState(() {
      _searchQuery = query.trim();
    });

    if (_searchQuery.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    final results = await widget.repository.searchArtists(_searchQuery);
    if (mounted) {
      setState(() {
        _searchResults = results;
      });
    }
  }

  Future<void> _openMergeDialog(ArtistSummary sourceArtist) async {
    final allArtists = await widget.repository.listArtists(limit: 500);
    final candidates =
        allArtists.where((a) => a.key != sourceArtist.key).toList();

    if (!mounted) return;

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t('artists.mergeNoOther')),
        ),
      );
      return;
    }

    String filter = '';
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (stateCtx, setDialogState) {
            final filtered = filter.trim().isEmpty
                ? candidates
                : candidates
                    .where((a) =>
                        a.name.toLowerCase().contains(filter.toLowerCase()))
                    .toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E22),
              title: Text(
                dialogCtx.t('artists.mergeIntoTitle', args: {'name': sourceArtist.name}),
              ),
              content: SizedBox(
                width: 400,
                height: 350,
                child: Column(
                  children: [
                    TextField(
                      key: const Key('merge_artist_search_field'),
                      decoration: InputDecoration(
                        hintText: dialogCtx.t('artists.searchTargetHint'),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                      onChanged: (val) => setDialogState(() => filter = val),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                dialogCtx.t('artists.noMatchingArtists'),
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (targetItemCtx, idx) {
                                final target = filtered[idx];
                                return ListTile(
                                  dense: true,
                                  key: Key('merge_target_${target.key}'),
                                  title: Text(target.name),
                                  subtitle: Text(
                                    '${target.trackCount} ${targetItemCtx.t('tracks.count')}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  onTap: () async {
                                    final dialogNav = Navigator.of(dialogCtx);
                                    final confirmed = await showDialog<bool>(
                                      context: stateCtx,
                                      builder: (c) => AlertDialog(
                                        backgroundColor:
                                            const Color(0xFF1E1E22),
                                        title: Text(c.t('artists.confirmMergeTitle')),
                                        content: Text(
                                          c.t('artists.confirmMergePrompt', args: {
                                            'source': sourceArtist.name,
                                            'target': target.name,
                                          }),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(c).pop(false),
                                            child: Text(c.t('common.cancel')),
                                          ),
                                          ElevatedButton(
                                            key: const Key(
                                              'confirm_merge_button',
                                            ),
                                            onPressed: () =>
                                                Navigator.of(c).pop(true),
                                            child: Text(c.t('artists.mergeAction')),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirmed == true && mounted) {
                                      dialogNav.pop();
                                      try {
                                        await widget.repository.mergeArtists(
                                          sourceArtist.key,
                                          target.key,
                                          targetName: target.name,
                                        );
                                        await _loadArtists();
                                        if (mounted) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                context.t('artists.mergeSuccess', args: {
                                                  'source': sourceArtist.name,
                                                  'target': target.name,
                                                }),
                                              ),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                context.t('artists.mergeFailed', args: {
                                                  'error': e.toString(),
                                                }),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  key: const Key('merge_dialog_cancel_button'),
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text(dialogCtx.t('common.cancel')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openRulesSheet() {
    ArtistRulesSheet.show(context, repository: widget.repository).then((_) {
      _loadArtists();
    });
  }

  List<ArtistSummary> _sortArtists(
    List<ArtistSummary> list,
    String sortKey,
    bool reversed,
  ) {
    final sorted = List<ArtistSummary>.from(list);
    sorted.sort((a, b) {
      int cmp;
      switch (sortKey) {
        case 'mostSongs':
          cmp = b.trackCount.compareTo(a.trackCount);
          if (cmp == 0) cmp = compareLocaleAware(a.name, b.name);
          break;
        case 'mostAlbums':
          cmp = b.albumCount.compareTo(a.albumCount);
          if (cmp == 0) cmp = compareLocaleAware(a.name, b.name);
          break;
        case 'recentlyAdded':
          final aTime = a.addedAt?.millisecondsSinceEpoch ?? 0;
          final bTime = b.addedAt?.millisecondsSinceEpoch ?? 0;
          cmp = bTime.compareTo(aTime);
          if (cmp == 0) cmp = compareLocaleAware(a.name, b.name);
          break;
        case 'name':
        default:
          cmp = compareLocaleAware(a.name, b.name);
          break;
      }
      return reversed ? -cmp : cmp;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final rawArtists = _searchQuery.isNotEmpty ? _searchResults : _artists;
    final settings = widget.settingsStore.settings;
    final artists = _sortArtists(
      rawArtists,
      settings.artistsSort,
      settings.artistsSortReversed,
    );
    final currentShape = settings.artistsViewMode;
    final reduceMotion = settings.reduceMotion;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LibraryHeader(
            title: context.t('nav.artists'),
            settingsStore: widget.settingsStore,
            itemCount: artists.length,
            itemCountLabel: context.t('artists.count'),
            searchQuery: _searchQuery,
            onSearchChanged: _onSearchChanged,
            showControls: false,
          ),
          const SizedBox(height: 12),
          LibraryViewControls(
            allowedShapes: const ['circle', 'square', 'list'],
            currentShape: currentShape,
            onShapeChanged: (newShape) {
              widget.settingsStore.update((s) => s.copyWith(artistsViewMode: newShape));
            },
            sortOptions: const ['name', 'mostSongs', 'mostAlbums', 'recentlyAdded'],
            currentSort: settings.artistsSort,
            onSortChanged: (newSort) {
              widget.settingsStore.update((s) => s.copyWith(artistsSort: newSort));
            },
            sortDirection: SortDirection.fromReversed(settings.artistsSortReversed),
            onSortDirectionChanged: (newDir) {
              widget.settingsStore.update((s) => s.copyWith(artistsSortReversed: newDir.isReversed));
            },
            reduceMotion: reduceMotion,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: artists.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isNotEmpty
                          ? 'No artists match "$_searchQuery"'
                          : 'No artists in library',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                : AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeOut,
                    child: KeyedSubtree(
                      key: ValueKey('artists_view_mode_$currentShape'),
                      child: _buildShapeContent(artists, currentShape),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildShapeContent(List<ArtistSummary> artists, String shape) {
    if (shape == 'list') {
      return ListView.builder(
        key: const Key('artists_list_view'),
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: artists.length,
        itemBuilder: (context, index) {
          final artist = artists[index];
          final isMerged = _mergedCanonicalKeys.contains(artist.key);

          return _ArtistListTile(
            artist: artist,
            isMerged: isMerged,
            onTap: () => widget.navigator.openArtistDetail(
              artist.key,
              artist: artist,
            ),
            onMerge: () => _openMergeDialog(artist),
            onRules: _openRulesSheet,
          );
        },
      );
    }

    return GridView.builder(
      key: const Key('artists_grid_view'),
      padding: const EdgeInsets.only(bottom: 120),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisExtent: 220,
        crossAxisSpacing: 16,
        mainAxisSpacing: 20,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        final isMerged = _mergedCanonicalKeys.contains(artist.key);

        return _ArtistTile(
          artist: artist,
          shape: shape,
          isMerged: isMerged,
          onTap: () => widget.navigator.openArtistDetail(
            artist.key,
            artist: artist,
          ),
          onMerge: () => _openMergeDialog(artist),
          onRules: _openRulesSheet,
        );
      },
    );
  }
}

class _ArtistListTile extends StatelessWidget {
  final ArtistSummary artist;
  final bool isMerged;
  final VoidCallback onTap;
  final VoidCallback onMerge;
  final VoidCallback onRules;

  const _ArtistListTile({
    required this.artist,
    required this.isMerged,
    required this.onTap,
    required this.onMerge,
    required this.onRules,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = _gradientForArtist(artist.name);
    final initial = _initialForArtist(artist.name);
    final displayName = context.displayArtist(artist.name);

    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.r10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
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
                  style: AppTypography.title.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: textDirectionFor(displayName),
                          style: AppTypography.bodyStrong.copyWith(
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      if (isMerged) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(AppSpacing.r10),
                          ),
                          child: Text(
                            context.t('artist.mergedBadge'),
                            style: AppTypography.micro.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                              fontSize: 9.0,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${artist.albumCount} ${context.t('albums.count')} • ${artist.trackCount} ${context.t('tracks.count')}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            _ArtistContextMenuButton(
              artist: artist,
              onMerge: onMerge,
              onRules: onRules,
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistTile extends StatelessWidget {
  final ArtistSummary artist;
  final String shape;
  final bool isMerged;
  final VoidCallback onTap;
  final VoidCallback onMerge;
  final VoidCallback onRules;

  const _ArtistTile({
    required this.artist,
    this.shape = 'circle',
    required this.isMerged,
    required this.onTap,
    required this.onMerge,
    required this.onRules,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = _gradientForArtist(artist.name);
    final initial = _initialForArtist(artist.name);

    return RepaintBoundary(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.r12),
        onTap: onTap,
        child: Column(
          children: [
            // Circular or square avatar container
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    shape: shape == 'circle' ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: shape == 'square'
                        ? BorderRadius.circular(AppSpacing.r12)
                        : null,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 12.0,
                        offset: Offset(0, 4),
                      ),
                    ],
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
                // Small merge badge
                if (isMerged)
                  PositionedDirectional(
                    end: 4,
                    bottom: 4,
                    child: Container(
                      key: Key('artist_merged_badge_${artist.key}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppSpacing.r10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.call_merge,
                            size: 11,
                            color: Colors.black,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            context.t('artist.mergedBadge'),
                            style: AppTypography.micro.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Artist name & Menu
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 24),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final displayName = context.displayArtist(artist.name);
                      return Text(
                        displayName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: textDirectionFor(displayName),
                        style: AppTypography.bodyStrong.copyWith(
                          color: AppColors.text,
                        ),
                      );
                    },
                  ),
                ),
                // Context menu button "..."
                _ArtistContextMenuButton(
                  artist: artist,
                  onMerge: onMerge,
                  onRules: onRules,
                ),
              ],
            ),
            const SizedBox(height: 2),

            // Track count
            Text(
              '${artist.trackCount} ${context.t('tracks.count')}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistContextMenuButton extends StatelessWidget {
  final ArtistSummary artist;
  final VoidCallback onMerge;
  final VoidCallback onRules;

  const _ArtistContextMenuButton({
    required this.artist,
    required this.onMerge,
    required this.onRules,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: Key('artist_menu_${artist.key}'),
      icon: const Icon(
        Icons.more_horiz,
        size: 18,
        color: AppColors.textMuted,
      ),
      tooltip: context.t('artists.optionsTooltip'),
      color: const Color(0xFF1D1C25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.r12),
        side: const BorderSide(color: AppColors.border),
      ),
      onSelected: (val) {
        if (val == 'merge') {
          onMerge();
        } else if (val == 'rules') {
          onRules();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'merge',
          child: Row(
            children: [
              const Icon(Icons.call_merge, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t('artist.mergeInto'),
                  style: AppTypography.body.copyWith(color: AppColors.text),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'rules',
          child: Row(
            children: [
              const Icon(Icons.rule, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t('artist.rules'),
                  style: AppTypography.body.copyWith(color: AppColors.text),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          enabled: false,
          value: 'choose_picture',
          child: Row(
            children: [
              const Icon(Icons.image_outlined, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${context.t('artist.choosePicture')} (${context.t('common.soon')})',
                  style: AppTypography.body.copyWith(color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          enabled: false,
          value: 'refresh_picture',
          child: Row(
            children: [
              const Icon(Icons.refresh, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${context.t('artist.refreshPicture')} (${context.t('common.soon')})',
                  style: AppTypography.body.copyWith(color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
