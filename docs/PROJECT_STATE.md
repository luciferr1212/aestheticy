# Aestheticy Project State

## Standing Rules
- Flutter Windows desktop player (`libmpv` behind `AudioEngine`); UI never imports audio packages directly.
- Pure Dart queue/shuffle/repeat and text normalization; SQLite storage in `lib/library/`.
- All user-facing text in `AppStrings` (`en` + `ar` parity); no `LogicalKeyboardKey` outside `app_shortcuts.dart`.
- Calm muted palette (`AppColors`); `BackdropFilter` only inside `GlassSurface` (max 6 blur budget); respect `reduceMotion`, `GlassQuality`, and RTL symmetry.
- Credit text strictly `by mido`.

## DONE
- **Phase 1 (Audio Core)**: `AudioEngine`, `PlaybackController`, `PlaybackQueue`, fade profiles, EQ, ReplayGain, diagnostics.
- **Phase 2 (Library)**: SQLite schema/migrations, folder scanner (`ScanService.rescanAll` continuous `isScanning` state and cancellation-safe `computeMissingPaths`), unified `AlbumIdentity` grouping/caching/classification (`tracksOfAlbum`, `CoverCache`, `ReleaseKindClassifier`, SQLite `album_identity_key`), `FilePathUtils` / SQLite `normalize_file_path` for `file://` URI & Windows/POSIX path matching in `recentlyPlayedTracks` and playlists, `AlbumSummary.addedAt` metadata, artist split/merge/never-split rules, favorites, playlists, M3U import summary (Windows path & `file://` support) & atomic/validated `.m3u`/`.m3u8` export, play history, quick search.
- **Phase 3–4 (UI, Lyrics, Queue, Mini Player, L10n)**: Glass shell, resizable docked side panel (Queue/Lyrics), mini player + favorites via `AudioSource.uri`, synced/word-level lyrics (with duplicate-timestamp word timing offset propagation and palette codec/image disposal in `finally`), keyboard shortcuts (including Space guard on focused glass buttons), unified `PlaybackController` shuffle/queue mutations, playlist missing-file index mapping, entry-identity queue selection/Delete & multi-selection, session save/restore preserving exact order/repeat/duplicate identity without re-shuffling, stale-guarded search in `AlbumsView`/`ArtistsView`/`TracksView` (including track-artist & translated artist-name album search), real `addedAt` recently-added & displayed-artist album sorting, stale-while-revalidate library/collection refresh via `LibraryDataCache` and `ScanService` on scans/folder changes, EN/AR RTL localization (`no_hardcoded_strings_test.dart` + key coverage check), Settings with live diagnostics (`eqEnabled`) and display-only artist-name translation CRUD.
- **Cleanup and File Splitting (Cleanup 1 & Cleanup 2)**: Split oversized UI views (`LyricsView`, `SettingsView`, `NowPlayingView`, `FullScreenView`, `ArtistDetailView`, `QueueContent`, `AlbumsView`, `BottomNowPlayingBar`, `AppShell`, `AudioPanelsView`, `AudioLabScreen`) and decomposed `SqliteLibraryRepository` into domain stores under `lib/library/sqlite/`; added architecture guard tests `test/architecture/file_size_budget_test.dart` and `test/architecture/no_user_file_writes_test.dart` (`main.dart` and `playback_controller.dart` deferred to Foundation).

## NOT DONE (In Order)
1. Foundation (play-event log, stable identity, userdata.db split, SQLite protection, no silent catch, composition root, platform layer, error model, versioned settings, logging, feature flags).
2. Prompt 9 (Home, Stats, Wrapped monthly + weekly listening activity, Recommended, Smart playlists, shareable image).
3. Quick wins.
4. Logic audit.
5. Open-with + drag-drop + single instance.
6. UI redesign.
7. Installer + auto-update + signing.
8. Long soak test.
9. v1.0.

## Key Decisions
- Aestheticy never writes to user audio files.
- Unified album identity uses `AlbumIdentity` (`album + normalized albumArtist` with `artist` fallback, or `track::<path>` for untagged singles) across SQLite queries, `CoverCache`, `ReleaseKindClassifier`, and UI views.
- M3U export validates targets before any disk write (`FilePicker.getDirectoryPath` rather than `FilePicker.saveFile` which eagerly writes bytes on Windows), enforces `.m3u`/`.m3u8`, refuses audio/existing non-playlist targets, requires localized overwrite confirmation, and writes atomically via temp sibling + flush + rename.
- Display-only artist translations live in `ArtistNameStore` (`artist_names.json`) and never mutate library merge aliases.
- Sideloaded Windows test validation relies on unit/widget tests with `FakeAudioEngine` and `FakeWindowService`; live audio and native windowing require testing the CI build.
