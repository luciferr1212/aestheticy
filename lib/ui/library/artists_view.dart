import 'package:flutter/material.dart';

import '../../features/library/artist_rules_sheet.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'library_header.dart';

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
        const SnackBar(
          content: Text('No other artists available to merge into.'),
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
              title: Text('Merge "${sourceArtist.name}" into…'),
              content: SizedBox(
                width: 400,
                height: 350,
                child: Column(
                  children: [
                    TextField(
                      key: const Key('merge_artist_search_field'),
                      decoration: const InputDecoration(
                        hintText: 'Search target artist...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                      onChanged: (val) => setDialogState(() => filter = val),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No matching artists',
                                style: TextStyle(color: Colors.grey),
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
                                    '${target.trackCount} tracks',
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
                                        title: const Text('Confirm merge'),
                                        content: Text(
                                          'Merge "${sourceArtist.name}" into "${target.name}"?\n\n'
                                          'Tracks performed by "${sourceArtist.name}" will appear under "${target.name}". Files will not be modified.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(c).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            key: const Key(
                                              'confirm_merge_button',
                                            ),
                                            onPressed: () =>
                                                Navigator.of(c).pop(true),
                                            child: const Text('Merge'),
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
                                                'Merged ${sourceArtist.name} into ${target.name}',
                                              ),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text('Merge failed: $e'),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final artists = _searchQuery.isNotEmpty ? _searchResults : _artists;

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
            sortOptions: const ['title'],
            currentSort: 'title',
            onSortChanged: (_) {},
          ),
          const SizedBox(height: 20),
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
                : GridView.builder(
                    key: const Key('artists_grid_view'),
                    padding: const EdgeInsets.only(bottom: 120),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      mainAxisExtent: 220,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 20,
                    ),
                    itemCount: artists.length,
                    itemBuilder: (context, index) {
                      final artist = artists[index];
                      final isMerged =
                          _mergedCanonicalKeys.contains(artist.key);

                      return _ArtistTile(
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
                  ),
          ),
        ],
      ),
    );
  }
}

class _ArtistTile extends StatelessWidget {
  final ArtistSummary artist;
  final bool isMerged;
  final VoidCallback onTap;
  final VoidCallback onMerge;
  final VoidCallback onRules;

  const _ArtistTile({
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

    return RepaintBoundary(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.r12),
        onTap: onTap,
        child: Column(
          children: [
            // Circular avatar container
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
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
                  child: Text(
                    artist.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDirectionFor(artist.name),
                    style: AppTypography.bodyStrong.copyWith(
                      color: AppColors.text,
                    ),
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
      tooltip: 'Artist options',
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
                  'Merge into…',
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
