import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../audio/playback_controller.dart';
import '../../library/cover_cache.dart';
import '../../library/library_repository.dart';
import '../../library/models.dart';
import '../../library/text_normalizer.dart';
import '../../library/track_audio_source_mapper.dart';
import '../artist_names/artist_name_scope.dart';
import '../artist_names/artist_name_store.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/app_shortcuts.dart';
import '../settings/settings_scope.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Single active overlay entry tracker for toggling.
OverlayEntry? _activeQuickSearchEntry;

/// Toggles the quick search overlay.
void toggleQuickSearch({
  required BuildContext context,
  required LibraryRepository repository,
  required PlaybackController controller,
  required AppNavigator navigator,
  required SettingsStore settingsStore,
  required ArtistNameStore artistNameStore,
}) {
  if (_activeQuickSearchEntry != null) {
    _activeQuickSearchEntry!.remove();
    _activeQuickSearchEntry = null;
    return;
  }

  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => QuickSearchOverlay(
      repository: repository,
      controller: controller,
      navigator: navigator,
      settingsStore: settingsStore,
      artistNameStore: artistNameStore,
      onClose: () {
        if (_activeQuickSearchEntry == entry) {
          entry.remove();
          _activeQuickSearchEntry = null;
        }
      },
    ),
  );

  _activeQuickSearchEntry = entry;
  overlay.insert(entry);
}

/// Closes the active quick search overlay if one is currently visible.
void closeQuickSearch() {
  _activeQuickSearchEntry?.remove();
  _activeQuickSearchEntry = null;
}

/// Abstract item for unified keyboard navigation across sections.
sealed class QuickSearchResultItem {}

/// Artist result item in quick search.
class ArtistResultItem extends QuickSearchResultItem {
  /// The artist summary.
  final ArtistSummary artist;

  /// Creates an [ArtistResultItem].
  ArtistResultItem(this.artist);
}

/// Album result item in quick search.
class AlbumResultItem extends QuickSearchResultItem {
  /// The album summary.
  final AlbumSummary album;

  /// Creates an [AlbumResultItem].
  AlbumResultItem(this.album);
}

/// Track result item in quick search.
class TrackResultItem extends QuickSearchResultItem {
  /// The track record.
  final Track track;

  /// Creates a [TrackResultItem].
  TrackResultItem(this.track);
}

/// Floating Quick Search (Ctrl+K) overlay with debounced parallel queries,
/// translated artist matching, and keyboard navigation.
class QuickSearchOverlay extends StatefulWidget {
  /// The library storage repository.
  final LibraryRepository repository;

  /// The audio playback controller.
  final PlaybackController controller;

  /// The application navigator.
  final AppNavigator navigator;

  /// The persistent settings store.
  final SettingsStore settingsStore;

  /// The artist display names store.
  final ArtistNameStore artistNameStore;

  /// Callback when the overlay is dismissed.
  final VoidCallback onClose;

  /// Creates a [QuickSearchOverlay].
  const QuickSearchOverlay({
    super.key,
    required this.repository,
    required this.controller,
    required this.navigator,
    required this.settingsStore,
    required this.artistNameStore,
    required this.onClose,
  });

  @override
  State<QuickSearchOverlay> createState() => _QuickSearchOverlayState();
}

class _QuickSearchOverlayState extends State<QuickSearchOverlay> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;
  int _activeQueryToken = 0;

  String _query = '';
  List<ArtistSummary> _artists = [];
  List<AlbumSummary> _albums = [];
  List<Track> _tracks = [];
  bool _isLoading = false;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = _handleKeyEvent;
    _queryController.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final text = _queryController.text;
    _debounceTimer?.cancel();
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _query = '';
        _artists = [];
        _albums = [];
        _tracks = [];
        _isLoading = false;
        _selectedIndex = 0;
      });
      return;
    }

    setState(() => _query = text);

    _debounceTimer = Timer(const Duration(milliseconds: 120), () {
      _executeSearch(trimmed);
    });
  }

  Future<void> _executeSearch(String query) async {
    final token = ++_activeQueryToken;
    setState(() => _isLoading = true);

    try {
      final artistFuture = widget.repository.searchArtists(query, limit: 4);
      final albumFuture = widget.repository.searchAlbums(query, limit: 4);
      final trackFuture = widget.repository.search(query);

      // Translated artist names matching
      final matchingOriginals =
          widget.artistNameStore.findOriginalNamesMatching(query, limit: 5);

      final translatedFutures = matchingOriginals.map((orig) async {
        final matches = await widget.repository.searchArtists(orig, limit: 3);
        final normOrig = TextNormalizer.normalize(orig);
        return matches
            .where((a) => TextNormalizer.normalize(a.name) == normOrig)
            .toList();
      });

      final results = await Future.wait([
        artistFuture,
        albumFuture,
        trackFuture,
        Future.wait(translatedFutures),
      ]);

      if (token != _activeQueryToken || !mounted) return;

      final directArtists = results[0] as List<ArtistSummary>;
      final albums = results[1] as List<AlbumSummary>;
      final rawTracks = results[2] as List<Track>;
      final translatedGroups = results[3] as List<List<ArtistSummary>>;

      final mergedArtists = <ArtistSummary>[];
      final seenKeys = <String>{};

      for (final a in directArtists) {
        if (seenKeys.add(TextNormalizer.normalize(a.name))) {
          mergedArtists.add(a);
          if (mergedArtists.length >= 4) break;
        }
      }

      if (mergedArtists.length < 4) {
        for (final group in translatedGroups) {
          for (final a in group) {
            if (seenKeys.add(TextNormalizer.normalize(a.name))) {
              mergedArtists.add(a);
              if (mergedArtists.length >= 4) break;
            }
          }
          if (mergedArtists.length >= 4) break;
        }
      }

      final tracks = rawTracks.take(8).toList();

      setState(() {
        _artists = mergedArtists;
        _albums = albums;
        _tracks = tracks;
        _isLoading = false;
        _selectedIndex = 0;
      });
    } catch (_) {
      if (token == _activeQueryToken && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<QuickSearchResultItem> _buildFlatItems() {
    final list = <QuickSearchResultItem>[];
    for (final a in _artists) {
      list.add(ArtistResultItem(a));
    }
    for (final al in _albums) {
      list.add(AlbumResultItem(al));
    }
    for (final t in _tracks) {
      list.add(TrackResultItem(t));
    }
    return list;
  }

  void _activateItem(QuickSearchResultItem item) {
    widget.onClose();

    switch (item) {
      case ArtistResultItem(:final artist):
        widget.navigator.openArtistDetail(artist.name, artist: artist);
      case AlbumResultItem(:final album):
        widget.navigator.openAlbumDetail(album.album, album: album);
      case TrackResultItem(:final track):
        widget.controller.playQueue([track.toAudioSource()], startIndex: 0);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (matchesShortcut(event, AppShortcutId.back) ||
        matchesShortcut(event, AppShortcutId.quickSearch)) {
      widget.onClose();
      return KeyEventResult.handled;
    }

    final items = _buildFlatItems();
    if (items.isEmpty) return KeyEventResult.ignored;

    if (isArrowDownKey(event)) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, items.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (isArrowUpKey(event)) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, items.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (isEnterKey(event)) {
      if (_selectedIndex >= 0 && _selectedIndex < items.length) {
        _activateItem(items[_selectedIndex]);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.settingsStore.settings.language == 'ar';
    final queryDirection =
        _query.isEmpty ? null : textDirectionFor(_query);

    return SettingsScope(
      store: widget.settingsStore,
      child: ArtistNameScope(
        store: widget.artistNameStore,
        child: Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Stack(
            children: [
              // Dim scrim
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('quick_search_scrim'),
                  onTap: widget.onClose,
                  child: Container(
                    color: Colors.black.withAlpha(140),
                  ),
                ),
              ),

              // Centered search card
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).size.height * 0.14,
                    left: 24,
                    right: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 640,
                      maxHeight: 520,
                    ),
                    child: GlassSurface(
                      density: GlassDensity.regular,
                      borderRadius: AppSpacing.r16,
                      child: Material(
                        color: Colors.transparent,
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Text input row
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.search,
                                      color: AppColors.accent,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        key: const Key('quick_search_input'),
                                        focusNode: _focusNode,
                                        controller: _queryController,
                                        autofocus: true,
                                        textDirection: queryDirection,
                                        style: AppTypography.bodyStrong,
                                        decoration: InputDecoration(
                                          hintText: context
                                              .t('quickSearch.placeholder'),
                                          hintStyle: AppTypography.body
                                              .copyWith(color: AppColors.textMuted),
                                          border: InputBorder.none,
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    if (_isLoading)
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.accent,
                                        ),
                                      )
                                    else if (_query.isNotEmpty)
                                      InkWell(
                                        onTap: () => _queryController.clear(),
                                        child: const Icon(
                                          Icons.close,
                                          size: 18,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              const Divider(
                                color: AppColors.borderSubtle,
                                height: 1,
                              ),

                              // Results or Empty body
                              Flexible(
                                child: _buildResultsList(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList(BuildContext context) {
    if (_query.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Center(
          child: Text(
            context.t('quickSearch.hint'),
            style: AppTypography.body.copyWith(color: AppColors.textMuted),
          ),
        ),
      );
    }

    final flatItems = _buildFlatItems();
    if (flatItems.isEmpty && !_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Center(
          child: Text(
            context.t('quickSearch.noResults'),
            style: AppTypography.body.copyWith(color: AppColors.textMuted),
          ),
        ),
      );
    }

    int currentFlatIndex = 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Artists Section
          if (_artists.isNotEmpty) ...[
            _buildSectionHeader(context.t('quickSearch.sectionArtists')),
            for (final artist in _artists) ...[
              _buildArtistRow(
                context,
                artist,
                flatIndex: currentFlatIndex++,
              ),
            ],
          ],

          // 2. Albums Section
          if (_albums.isNotEmpty) ...[
            _buildSectionHeader(context.t('quickSearch.sectionAlbums')),
            for (final album in _albums) ...[
              _buildAlbumRow(
                context,
                album,
                flatIndex: currentFlatIndex++,
              ),
            ],
          ],

          // 3. Tracks Section
          if (_tracks.isNotEmpty) ...[
            _buildSectionHeader(context.t('quickSearch.sectionTracks')),
            for (final track in _tracks) ...[
              _buildTrackRow(
                context,
                track,
                flatIndex: currentFlatIndex++,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        title,
        style: AppTypography.micro.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildArtistRow(
    BuildContext context,
    ArtistSummary artist, {
    required int flatIndex,
  }) {
    final isSelected = _selectedIndex == flatIndex;
    final displayName = context.displayArtist(artist.name);

    return InkWell(
      key: Key('quick_search_artist_${artist.name}'),
      onTap: () => _activateItem(ArtistResultItem(artist)),
      onHover: (hovered) {
        if (hovered && _selectedIndex != flatIndex) {
          setState(() => _selectedIndex = flatIndex);
        }
      },
      child: Container(
        color: isSelected ? AppColors.accentFill : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withAlpha(100),
                    AppColors.surface,
                  ],
                ),
              ),
              child: const Icon(
                Icons.person,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayName,
                style: AppTypography.bodyStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              context.t('artists.albumsAndTracks', args: {
                'albums': context.formatCountLocalized(artist.albumCount),
                'tracks': context.formatCountLocalized(artist.trackCount),
              }),
              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumRow(
    BuildContext context,
    AlbumSummary album, {
    required int flatIndex,
  }) {
    final isSelected = _selectedIndex == flatIndex;
    final displayArtist = context
        .displayArtist(album.displayArtist ?? album.albumArtist);

    return InkWell(
      key: Key('quick_search_album_${album.album}'),
      onTap: () => _activateItem(AlbumResultItem(album)),
      onHover: (hovered) {
        if (hovered && _selectedIndex != flatIndex) {
          setState(() => _selectedIndex = flatIndex);
        }
      },
      child: Container(
        color: isSelected ? AppColors.accentFill : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Cover thumbnail
            _buildCoverThumb(album.coverKey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.album,
                    style: AppTypography.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (displayArtist.isNotEmpty)
                    Text(
                      displayArtist,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              context.formatCountLocalized(album.trackCount),
              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackRow(
    BuildContext context,
    Track track, {
    required int flatIndex,
  }) {
    final isSelected = _selectedIndex == flatIndex;
    final displayTitle = track.title ?? p.basename(track.path);
    final displayArtist = context.displayArtist(track.artist ?? '—');
    final albumName = track.album ?? '';

    final subtitle = albumName.isNotEmpty
        ? '$displayArtist · $albumName'
        : displayArtist;

    return InkWell(
      key: Key('quick_search_track_${track.path}'),
      onTap: () => _activateItem(TrackResultItem(track)),
      onHover: (hovered) {
        if (hovered && _selectedIndex != flatIndex) {
          setState(() => _selectedIndex = flatIndex);
        }
      },
      child: Container(
        color: isSelected ? AppColors.accentFill : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Cover thumbnail
            _buildCoverThumb(track.coverKey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    style: AppTypography.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              context.formatDurationLocalized(
                Duration(milliseconds: track.durationMs),
              ),
              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverThumb(String? coverKey) {
    if (coverKey != null && CoverCache.hasCover(coverKey)) {
      final file = File(CoverCache.pathFor(coverKey));
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.r10),
        child: Image.file(
          file,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildFallbackThumb(),
        ),
      );
    }
    return _buildFallbackThumb();
  }

  Widget _buildFallbackThumb() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: const Icon(
        Icons.music_note,
        size: 18,
        color: AppColors.textMuted,
      ),
    );
  }
}
