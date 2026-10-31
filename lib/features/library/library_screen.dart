/// Main music library screen with Albums, Artists, Tracks tabs,
/// paged lazy lists, search, folder management, and audio playback wiring.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:aestheticy/audio/audio_engine.dart';
import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/features/audio_lab/audio_lab_screen.dart';
import 'package:aestheticy/features/library/album_detail_screen.dart';
import 'package:aestheticy/features/library/artist_detail_screen.dart';
import 'package:aestheticy/features/library/artist_rules_sheet.dart';
import 'package:aestheticy/features/library/folder_management_sheet.dart';
import 'package:aestheticy/library/cover_cache.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';
import 'package:aestheticy/library/track_audio_source_mapper.dart';

/// Primary music library screen.
class LibraryScreen extends StatefulWidget {
  /// The audio engine instance.
  final AudioEngine engine;

  /// The playback controller coordinating queue and playback.
  final PlaybackController controller;

  /// The library storage repository.
  final LibraryRepository repository;

  /// The active scanner application service.
  final ScanService scanService;

  /// Optional injected directory picker for tests.
  final Future<String?> Function()? directoryPicker;

  /// Creates a [LibraryScreen].
  const LibraryScreen({
    super.key,
    required this.engine,
    required this.controller,
    required this.repository,
    required this.scanService,
    this.directoryPicker,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _tracksScrollController = ScrollController();
  final ScrollController _albumsScrollController = ScrollController();
  final ScrollController _artistsScrollController = ScrollController();

  // Search state
  String _searchQuery = '';
  List<Track> _searchResults = [];
  List<AlbumSummary> _searchAlbums = [];
  List<ArtistSummary> _searchArtists = [];
  bool _isSearching = false;
  Timer? _searchDebounceTimer;
  int _searchSequence = 0;

  // Paged tracks
  final List<Track> _tracks = [];
  int _totalTrackCount = 0;
  bool _isLoadingTracks = false;
  static const int _trackPageSize = 50;

  // Paged albums
  final List<AlbumSummary> _albums = [];
  int _totalAlbumCount = 0;
  bool _isLoadingAlbums = false;
  static const int _albumPageSize = 40;

  // Paged artists
  final List<ArtistSummary> _artists = [];
  int _totalArtistCount = 0;
  bool _isLoadingArtists = false;
  static const int _artistPageSize = 50;

  bool _initialLoadDone = false;

  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tracksScrollController.addListener(_onTracksScroll);
    _albumsScrollController.addListener(_onAlbumsScroll);
    _artistsScrollController.addListener(_onArtistsScroll);

    widget.scanService.addListener(_onScanUpdate);

    _refreshAll();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _searchDebounceTimer?.cancel();
    widget.scanService.removeListener(_onScanUpdate);
    _tabController.dispose();
    _searchController.dispose();
    _tracksScrollController.dispose();
    _albumsScrollController.dispose();
    _artistsScrollController.dispose();
    super.dispose();
  }

  void _onScanUpdate() {
    if (!mounted || _isDisposed) return;
    if (!widget.scanService.isScanning) {
      _refreshAll();
    } else {
      setState(() {});
    }
  }

  Future<void> _refreshAll() async {
    if (!mounted || _isDisposed) return;
    try {
      await Future.wait([
        _loadInitialTracks(),
        _loadInitialAlbums(),
        _loadInitialArtists(),
      ]);
      if (_searchQuery.isNotEmpty) {
        await _performSearch(_searchQuery);
      }
      if (mounted && !_isDisposed) {
        setState(() {
          _initialLoadDone = true;
        });
      }
    } catch (_) {}
  }

  // ── Tracks Paging ──────────────────────────────────────────────────

  Future<void> _loadInitialTracks() async {
    if (!mounted || _isDisposed) return;
    _isLoadingTracks = true;
    try {
      final total = await widget.repository.trackCount();
      final tracks = await widget.repository.listTracks(
        limit: _trackPageSize,
        offset: 0,
      );
      if (mounted && !_isDisposed) {
        setState(() {
          _totalTrackCount = total;
          _tracks.clear();
          _tracks.addAll(tracks);
          _isLoadingTracks = false;
        });
      }
    } catch (_) {}
  }

  void _onTracksScroll() {
    if (_isSearching) return;
    if (_tracksScrollController.position.pixels >=
        _tracksScrollController.position.maxScrollExtent - 300) {
      _loadMoreTracks();
    }
  }

  Future<void> _loadMoreTracks() async {
    if (_isLoadingTracks || _tracks.length >= _totalTrackCount) return;
    _isLoadingTracks = true;
    try {
      final nextTracks = await widget.repository.listTracks(
        limit: _trackPageSize,
        offset: _tracks.length,
      );
      if (mounted && !_isDisposed) {
        setState(() {
          _tracks.addAll(nextTracks);
          _isLoadingTracks = false;
        });
      }
    } catch (_) {}
  }

  // ── Albums Paging ──────────────────────────────────────────────────

  Future<void> _loadInitialAlbums() async {
    if (!mounted || _isDisposed) return;
    _isLoadingAlbums = true;
    try {
      final total = await widget.repository.albumCount();
      final albums = await widget.repository.listAlbums(
        limit: _albumPageSize,
        offset: 0,
      );
      if (mounted && !_isDisposed) {
        setState(() {
          _totalAlbumCount = total;
          _albums.clear();
          _albums.addAll(albums);
          _isLoadingAlbums = false;
        });
      }
    } catch (_) {}
  }

  void _onAlbumsScroll() {
    if (_isSearching) return;
    if (_albumsScrollController.position.pixels >=
        _albumsScrollController.position.maxScrollExtent - 300) {
      _loadMoreAlbums();
    }
  }

  Future<void> _loadMoreAlbums() async {
    if (_isLoadingAlbums || _albums.length >= _totalAlbumCount) return;
    _isLoadingAlbums = true;
    try {
      final nextAlbums = await widget.repository.listAlbums(
        limit: _albumPageSize,
        offset: _albums.length,
      );
      if (mounted && !_isDisposed) {
        setState(() {
          _albums.addAll(nextAlbums);
          _isLoadingAlbums = false;
        });
      }
    } catch (_) {}
  }

  // ── Artists Paging ─────────────────────────────────────────────────

  Future<void> _loadInitialArtists() async {
    if (!mounted || _isDisposed) return;
    _isLoadingArtists = true;
    try {
      final total = await widget.repository.artistCount();
      final artists = await widget.repository.listArtists(
        limit: _artistPageSize,
        offset: 0,
      );
      if (mounted && !_isDisposed) {
        setState(() {
          _totalArtistCount = total;
          _artists.clear();
          _artists.addAll(artists);
          _isLoadingArtists = false;
        });
      }
    } catch (_) {}
  }

  void _onArtistsScroll() {
    if (_isSearching) return;
    if (_artistsScrollController.position.pixels >=
        _artistsScrollController.position.maxScrollExtent - 300) {
      _loadMoreArtists();
    }
  }

  Future<void> _loadMoreArtists() async {
    if (_isLoadingArtists || _artists.length >= _totalArtistCount) return;
    _isLoadingArtists = true;
    final nextArtists = await widget.repository.listArtists(
      limit: _artistPageSize,
      offset: _artists.length,
    );
    if (mounted) {
      setState(() {
        _artists.addAll(nextArtists);
        _isLoadingArtists = false;
      });
    }
  }

  // ── Search ─────────────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchSequence++;
      setState(() {
        _searchQuery = '';
        _isSearching = false;
        _searchResults.clear();
        _searchAlbums.clear();
        _searchArtists.clear();
      });
      return;
    }

    setState(() {});

    final seq = ++_searchSequence;
    _searchDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      _performSearch(trimmed, seq);
    });
  }

  Future<void> _performSearch(String query, [int? sequence]) async {
    final currentSeq = sequence ?? ++_searchSequence;
    final results = await widget.repository.search(query);
    final albums = await widget.repository.searchAlbums(query, limit: 100);
    final artists = await widget.repository.searchArtists(query, limit: 100);

    if (mounted && currentSeq == _searchSequence) {
      setState(() {
        _searchQuery = query;
        _isSearching = true;
        _searchResults = results;
        _searchAlbums = albums;
        _searchArtists = artists;
      });
    }
  }

  // ── Folder Actions ─────────────────────────────────────────────────

  Future<void> _openArtistRules() async {
    await ArtistRulesSheet.show(context, repository: widget.repository);
    if (mounted) {
      await _refreshAll();
    }
  }

  Future<void> _openFolderManagement() async {
    await FolderManagementSheet.show(
      context,
      repository: widget.repository,
      scanService: widget.scanService,
      directoryPicker: widget.directoryPicker,
    );
    if (mounted) {
      await _refreshAll();
    }
  }

  Future<void> _pickAndAddFolderDirectly() async {
    try {
      final picker = widget.directoryPicker ?? FilePicker.getDirectoryPath;
      final selectedPath = await picker();
      if (selectedPath != null && selectedPath.isNotEmpty) {
        await widget.scanService.addFolder(selectedPath);
        if (mounted) {
          await _refreshAll();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding folder: $e')),
        );
      }
    }
  }

  // ── Playback helpers ───────────────────────────────────────────────

  Future<void> _playTrackFromList(List<Track> list, int index) async {
    if (list.isEmpty) return;
    final sources = list.map((t) => t.toAudioSource()).toList();
    await widget.controller.playQueue(sources, startIndex: index);
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ── UI Builders ────────────────────────────────────────────────────

  Widget _buildAlbumCover(String? coverKey) {
    if (coverKey != null && CoverCache.hasCover(coverKey)) {
      final file = File(CoverCache.pathFor(coverKey));
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildAlbumPlaceholder(),
      );
    }
    return _buildAlbumPlaceholder();
  }

  Widget _buildAlbumPlaceholder() {
    return Container(
      color: const Color(0xFF222226),
      child: const Center(
        child: Icon(Icons.album, size: 48, color: Colors.white24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isScanning = widget.scanService.isScanning;
    final progress = widget.scanService.currentProgress;
    final isEmptyLibrary = _initialLoadDone &&
        _totalTrackCount == 0 &&
        !isScanning &&
        !_isSearching;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Aestheticy — Library',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              'by mido',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('artist_rules_button'),
            tooltip: 'Artist Rules',
            icon: const Icon(Icons.rule),
            onPressed: _openArtistRules,
          ),
          IconButton(
            key: const Key('manage_folders_button'),
            tooltip: 'Manage Folders',
            icon: const Icon(Icons.folder_open),
            onPressed: _openFolderManagement,
          ),
          IconButton(
            key: const Key('appbar_rescan_button'),
            tooltip: 'Rescan Library',
            icon: const Icon(Icons.sync),
            onPressed: isScanning ? null : () => widget.scanService.rescanAll(),
          ),
          IconButton(
            key: const Key('audio_lab_button'),
            tooltip: 'Audio Lab',
            icon: const Icon(Icons.science_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AudioLabScreen(
                    engine: widget.engine,
                    controller: widget.controller,
                  ),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFC3B1E1),
          tabs: const [
            Tab(text: 'Albums'),
            Tab(text: 'Artists'),
            Tab(text: 'Tracks'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Scan progress banner
          if (isScanning)
            Container(
              color: const Color(0xFF1E1E24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          progress.found > 0
                              ? 'Scanning: ${progress.processed} / ${progress.found} files (${progress.added} new)'
                              : 'Scanning audio library...',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      TextButton(
                        key: const Key('banner_cancel_button'),
                        onPressed: () => widget.scanService.cancel(),
                        child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: progress.found > 0
                        ? (progress.processed / progress.found).clamp(0.0, 1.0)
                        : null,
                    minHeight: 3,
                  ),
                ],
              ),
            ),
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              key: const Key('library_search_field'),
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search albums, artists, tracks...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          // Body content: Empty State or Tabs
          Expanded(
            child: isEmptyLibrary
                ? _buildEmptyState()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAlbumsTab(),
                      _buildArtistsTab(),
                      _buildTracksTab(),
                    ],
                  ),
          ),
          // Now Playing / Footer bar
          _buildBottomPlayerBar(),
        ],
      ),
    );
  }

  // ── Empty State ────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.library_music_outlined,
              size: 64,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            const Text(
              'Your music library is empty',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add a folder containing audio files to start listening.',
              style: TextStyle(color: Colors.white60, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              key: const Key('empty_add_folder_button'),
              onPressed: _pickAndAddFolderDirectly,
              icon: const Icon(Icons.create_new_folder, size: 18),
              label: const Text('Add folder'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tabs ───────────────────────────────────────────────────────────

  Widget _buildAlbumsTab() {
    final list = _isSearching ? _searchAlbums : _albums;
    final hasMore = !_isSearching && _albums.length < _totalAlbumCount;

    if (list.isEmpty) {
      return Center(
        child: Text(
          _isSearching ? 'No albums match "$_searchQuery"' : 'No albums found.',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return GridView.builder(
      key: const Key('albums_grid_view'),
      controller: _albumsScrollController,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.72,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: list.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= list.length) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final album = list[index];
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AlbumDetailScreen(
                  album: album,
                  repository: widget.repository,
                  controller: widget.controller,
                ),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildAlbumCover(album.coverKey),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        album.albumArtist ?? 'Unknown Artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${album.trackCount} track${album.trackCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildArtistsTab() {
    final list = _isSearching ? _searchArtists : _artists;
    final hasMore = !_isSearching && _artists.length < _totalArtistCount;

    if (list.isEmpty) {
      return Center(
        child: Text(
          _isSearching ? 'No artists match "$_searchQuery"' : 'No artists found.',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      key: const Key('artists_list_view'),
      controller: _artistsScrollController,
      itemCount: list.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= list.length) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final artist = list[index];
        return ListTile(
          dense: true,
          leading: const CircleAvatar(
            backgroundColor: Color(0xFF222226),
            child: Icon(Icons.person, color: Color(0xFFC3B1E1), size: 20),
          ),
          title: Text(
            artist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '${artist.albumCount} album${artist.albumCount == 1 ? '' : 's'} • '
            '${artist.trackCount} track${artist.trackCount == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                key: Key('artist_menu_${artist.key}'),
                icon: const Icon(
                  Icons.more_vert,
                  size: 18,
                  color: Colors.white54,
                ),
                tooltip: 'Artist options',
                onSelected: (val) {
                  if (val == 'merge') {
                    _openMergeDialog(artist);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'merge',
                    child: Row(
                      children: [
                        Icon(Icons.call_merge, size: 16),
                        SizedBox(width: 8),
                        Text('Merge into…'),
                      ],
                    ),
                  ),
                ],
              ),
              const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
            ],
          ),
          onLongPress: () => _openMergeDialog(artist),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ArtistDetailScreen(
                  artist: artist,
                  repository: widget.repository,
                  controller: widget.controller,
                ),
              ),
            );
          },
        );
      },
    );
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
                                        await _refreshAll();
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTracksTab() {
    final list = _isSearching ? _searchResults : _tracks;
    final hasMore = !_isSearching && _tracks.length < _totalTrackCount;

    if (list.isEmpty) {
      return Center(
        child: Text(
          _isSearching ? 'No songs match "$_searchQuery"' : 'No tracks found.',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      key: const Key('tracks_list_view'),
      controller: _tracksScrollController,
      itemCount: list.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= list.length) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final track = list[index];
        final title = track.title ?? 'Unknown Track';
        final subtitle =
            '${track.artist ?? 'Unknown Artist'} • ${track.album ?? 'Unknown Album'}';

        return ListTile(
          dense: true,
          leading: const Icon(Icons.music_note, color: Colors.grey, size: 20),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          trailing: Text(
            _formatDuration(track.durationMs),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          onTap: () => _playTrackFromList(list, index),
        );
      },
    );
  }

  // ── Bottom Player Bar / Footer ─────────────────────────────────────

  Widget _buildBottomPlayerBar() {
    return StreamBuilder<AudioSource?>(
      stream: widget.controller.currentStream,
      initialData: widget.controller.queue.current,
      builder: (context, snapshot) {
        final currentSource = snapshot.data;
        if (currentSource == null) {
          return const SizedBox.shrink();
        }

        final title = currentSource.extras?['title'] ?? currentSource.uri;
        final artist = currentSource.extras?['artist'] ?? 'Unknown Artist';

        return StreamBuilder<PlaybackState>(
          stream: widget.controller.stateStream,
          initialData: widget.controller.currentState,
          builder: (context, stateSnap) {
            final isPlaying = stateSnap.data == PlaybackState.playing;

            return InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AudioLabScreen(
                      engine: widget.engine,
                      controller: widget.controller,
                    ),
                  ),
                );
              },
              child: Container(
                color: const Color(0xFF1E1E24),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.audiotrack, color: Color(0xFFC3B1E1), size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                      tooltip: isPlaying ? 'Pause' : 'Play',
                      onPressed: () => widget.controller.togglePlayPause(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      tooltip: 'Next',
                      onPressed: () => widget.controller.skipNext(),
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
}
