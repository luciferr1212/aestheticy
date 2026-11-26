# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

### Added
- Split `userdata.db` (`kUserDataSchemaVersion = 1`) from rebuildable `library.db` (`kLibrarySchemaVersion = 4`) via SQLite `ATTACH DATABASE ... AS userdata`, keeping all user collections, play history, and artist rules intact across library resets (`resetLibrary`) and folder removals.
- Crash-recoverable legacy migration state machine (`LegacyUserDataMigrator`, `legacy_migration_state` in `userdata.meta`) with pre-split backups (`backups/pre-split-<yyyyMMdd-HHmmss>/`), single-file transactions, SHA-256 primary-key checksum verification, and `legacy_<name>` table preservation.
- SQLite protection (`DatabaseProtection`): WAL + `synchronous=NORMAL` on file databases, startup `PRAGMA quick_check`, automatic quarantine and recovery for corrupt `library.db` (recreate + rescan) and `userdata.db` (restore newest valid backup or reset empty), and `UserDataAccessMode.safeReadOnly` with a persistent localized `SafeReadOnlyBanner` (Open logs / Open backups actions) and localized mutation blocks.
- Automatic daily backup service (`UserDataBackupService` / `SqliteUserDataBackupService`) writing verified `backups/userdata/userdata-<yyyyMMdd>.db` snapshots via `VACUUM INTO` (with `wal_checkpoint` + copy fallback), keeping the newest 5 backups, plus pre-upgrade backups before `userdata.db` schema migrations.
- Architecture decisions `docs/decisions/0001-split-userdata-db.md` and `docs/decisions/0002-never-write-user-audio-files.md`.
- Request tokens (`_searchRequestId`) on `AlbumsView`, `ArtistsView`, and `TracksView` search flows to discard out-of-order and post-clear stale search responses, plus `ArtistNameStore.expandedSearchQueries`.
- `FilePathUtils` (`lib/library/file_path_utils.dart`) and SQLite scalar function `normalize_file_path` to match `file://` URIs, Windows backslash paths, UNC shares, and POSIX paths consistently across `recentlyPlayedTracks` and `playlistEntries`.
- `M3u.importPlaylistWithSummary` (`M3uImportSummary`), `M3u.validateExportTarget`, `M3u.writeM3uAtomically`, and localized export refusal/overwrite confirmation strings (`m3u.exportRefusedAudio`, `m3u.exportRefusedOtherFile`, `m3u.overwriteTitle`, `m3u.overwriteMessage`, `m3u.overwriteConfirm`) in `AppStrings` (en + ar).
- `computeMissingPaths` helper in `LibraryScanner` and tests covering search race/debounce/translated-name scope (`test/ui/library/library_search_test.dart`), M3U Windows paths/refusals/confirmation/atomic overwrite (`test/features/collections/m3u_test.dart`), `rescanAll` continuity and cancellation (`test/library/scan_service_test.dart`), duplicate-timestamp LRC word shifting (`lrc_parser_test.dart`, `lyrics_controller_test.dart`), and `CoverPalette` resource disposal (`cover_palette_test.dart`).
- Unified `AlbumIdentity` helper (`lib/library/album_identity.dart`) and `AlbumSummary.identityKey` / `AlbumSummary.addedAt` (`MAX(added_at)`), plus SQLite `album_identity_key` scalar function and optional `albumKey` scoping on `LibraryRepository.tracksOfAlbum`.
- `ScanService.libraryVersion` counter and `ScanService.removeFolder` plus `UserCollections.refresh` for flicker-free library refresh notifications.
- `PlaybackController.playShuffled`, `PlaybackController.clearQueue`, `PlaybackController.restoreQueueSnapshot`, `PlaybackController.removeEntryFromQueue`, and `PlaybackController.removeEntriesFromQueue` with entry-identity tracking (`PlaybackQueue.removeByIds`, `indexOfEntryId`, `restoreSnapshot`).
- `SavedSessionItem.entryId` and `SavedSession.currentEntryId` persistence for exact duplicate-entry restoration.
- Multi-selection (Ctrl+Click / Shift+Click / Shift+Arrows) and identity-preserving Delete key handling in `QueueContent`.
- Settings UI under **Artist names** to add, edit, and remove display-only artist-name translations with normalized-key duplicate validation and confirmation-free undo SnackBar.
- Localization key coverage test in `test/ui/l10n/l10n_test.dart` scanning `lib/` lookups against both English and Arabic dictionaries.
- Tests covering `AlbumIdentity` (`test/library/album_identity_test.dart`), `recentlyAdded` sorting, flicker-free library auto-refresh (`test/ui/library_auto_refresh_test.dart`), shuffled/duplicate/missing session restore, unified album/artist/playlist/favorites shuffle sync, missing-file playlist play mapping, queue Delete edge cases, and focused `GlassIconButton`/`GlassPillButton` Space-key guards.

### Changed
- `SchemaMigrator` now owns only library index tables (`folders`, `tracks`, `track_artists`) in `library.db`, while `UserDataMigrator` manages user tables (`meta`, `favorites`, `ratings`, `playlists`, `playlist_items`, `play_events`, `artist_aliases`, `artist_no_split`) in `userdata.db`; all SQLite stores explicitly qualify `main.` and `userdata.` (or `main.` fallback in `safeReadOnly`).
- `SqliteLibraryRepository.openDefault` accepts an injected `supportDir`/`supportDirProvider` so tests remain isolated in temporary directories.
- Split `SqliteLibraryRepository` into focused domain store helpers under `lib/library/sqlite/` (`sqlite_db_initializer.dart`, `sqlite_row_mappers.dart`, `sqlite_tracks_store.dart`, `sqlite_albums_store.dart`, `sqlite_artists_store.dart`, `sqlite_collections_store.dart`, `sqlite_history_store.dart`), split `AudioLabScreen` and `AudioPanelsView` into section widget modules, updated `test/architecture/file_size_budget_test.dart`, and added `test/architecture/no_user_file_writes_test.dart` plus the user-audio write-safety rule in `AGENTS.md`.
- Split oversized UI views (`LyricsView`, `SettingsView`, `NowPlayingView`, `FullScreenView`, `ArtistDetailView`, `QueueContent`, `AlbumsView`, `BottomNowPlayingBar`, and `AppShell`) into focused widget/helper modules while preserving all original public exports and behavior, and added `test/architecture/file_size_budget_test.dart`.
- Removed parent-folder album fallback for untagged singles in `LibraryScanner`, and aligned `SqliteLibraryRepository`, `CoverCache`, `ReleaseKindClassifier`, `AlbumsView`, and `AlbumDetailView` on `AlbumIdentity`.
- Defaulted `AppSettings.albumsSortReversed` to `true` (newest first when `albumSort` is `'recentlyAdded'`).
- Wired `LibraryDataCache`, `UserCollections`, `AppShell`, and all library list/detail/collection views for stale-while-revalidate refresh on scan completion and folder additions/removals.
- Routed all album, artist, playlist, and favorites shuffle actions through `PlaybackController.playShuffled`, and moved `QueueView` clear and `AudioLabScreen` shuffle/repeat mutations behind `PlaybackController`.
- Added missing `AppStrings` translations (`artists.albumsAndTracks`, `common.save`, `miniPlayer.enterTooltip`) in both English and Arabic.
- Localized remaining user-visible strings across `ArtistsView`, `TracksView`, `ArtistRulesSheet`, and `FolderManagementSheet`, and expanded `no_hardcoded_strings_test.dart` to cover `lib/features/library` and multiline/ternary `Text` calls.

### Fixed
- `SqliteLibraryRepository.searchAlbums` now groups by `album_key` before filtering so track artists and merged canonical artist names match without corrupting `trackCount` or `distinct_artist_count`, and `AlbumsView` matches display-only artist translations.
- `M3u.parseM3u` preserves valid Windows backslash paths, decodes `file://` URIs, parses `#EXTINF` titles, and reports missing paths cleanly; `M3u.exportPlaylist` refuses audio extensions and existing non-playlist files, forces `.m3u8` when needed, asks confirmation before overwriting `.m3u`/`.m3u8`, and writes atomically (temp sibling + flush + rename).
- `ScanService.rescanAll` keeps `isScanning` continuously `true` across multiple folders and suppresses intermediate `done: true` events; cancelled scans never mark unscanned files as missing.
- `parseLrc` shifts word timings for every timestamp on multi-timestamp Enhanced LRC lines (including `[offset:]` and duplicate-timestamp `endMs` resolution), and `paletteForCover` disposes decoded `Codec` and `ui.Image` instances in a `finally` block.
- Same-title albums with differing artists or null `album_artist` no longer merge across `tracksOfAlbum`, album queries, `CoverCache` keys, or `ReleaseKindClassifier`, and untagged singles receive unique track-path identities.
- `AlbumsView` `'recentlyAdded'` sort now orders by `AlbumSummary.addedAt` instead of alphabetical album title order, and `'artist'` sort uses displayed artist names.
- All library views (including `AlbumDetailView`, `ArtistDetailView`, `PlaylistDetailView`, `FavoritesView`, `PlaylistsView`, `AlbumsView`, `ArtistsView`, `TracksView`, and `WelcomeView`/`AppShell`) refresh automatically after scans or folder changes without loading flicker.
- Session restore no longer re-shuffles restored shuffled queues and accurately restores repeat modes, duplicate tracks by `QueueEntry` identity, and missing-track fallbacks.
- Playlist track clicks map visible row index to the playable audio source list when earlier or middle playlist entries are missing, and ignore clicks on missing rows.
- Queue Delete key removes selected entry IDs cleanly (including duplicates, multi-selection, current entry, and above/below entries) and refreshes gapless preload.
- Global Space-key playback toggle ignores events when `GlassIconButton` or `GlassPillButton` (as well as standard buttons and text fields) holds focus.
- Mini player favorite button now reads `current?.uri` instead of missing `extras['path']` so toggling favorites works and reflects current track state.
- Diagnostic report now reads the real equalizer enabled state from `EqController`/`EqScope` (with `AudioEngine.isEqEnabled` fallback) instead of hardcoded `false`.
