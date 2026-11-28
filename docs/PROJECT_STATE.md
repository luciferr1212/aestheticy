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
- **Phase 3–4 (UI, Lyrics, Queue, Mini Player, L10n)**: Glass shell, responsive docked side panel (Queue/Lyrics, 22% clamped to 280–320 px, auto-hidden below 1000 px), mini player + favorites via `AudioSource.uri`, synced/word-level lyrics (with duplicate-timestamp word timing offset propagation and palette codec/image disposal in `finally`), keyboard shortcuts (including Space guard on focused glass buttons), unified `PlaybackController` shuffle/queue mutations, playlist missing-file index mapping, entry-identity queue selection/Delete & multi-selection, session save/restore preserving exact order/repeat/duplicate identity without re-shuffling, stale-guarded search in `AlbumsView`/`ArtistsView`/`TracksView` (including track-artist & translated artist-name album search), real `addedAt` recently-added & displayed-artist album sorting, stale-while-revalidate library/collection refresh via `LibraryDataCache` and `ScanService` on scans/folder changes, EN/AR RTL localization (`no_hardcoded_strings_test.dart` + key coverage check), Settings with live diagnostics (`eqEnabled`) and display-only artist-name translation CRUD.
- **Cleanup and File Splitting (Cleanup 1 & Cleanup 2)**: Split oversized UI views (`LyricsView`, `SettingsView`, `NowPlayingView`, `FullScreenView`, `ArtistDetailView`, `QueueContent`, `AlbumsView`, `BottomNowPlayingBar`, `AppShell`, `AudioPanelsView`, `AudioLabScreen`) and decomposed `SqliteLibraryRepository` into domain stores under `lib/library/sqlite/`; added architecture guard tests `test/architecture/file_size_budget_test.dart` and `test/architecture/no_user_file_writes_test.dart` (`main.dart` and `playback_controller.dart` deferred to Foundation).
- **Foundation F1 (`userdata.db` split, SQLite protection & automatic backups):** Separated user data into `userdata.db` (now `kUserDataSchemaVersion = 3`) attached to `library.db` (`kLibrarySchemaVersion = 4`), added crash-recoverable legacy migration (`LegacyUserDataMigrator` with `VACUUM INTO` + row-count-verified `pre-split-*` backups and full-row SHA-256 verification), added WAL + `PRAGMA quick_check` corruption recovery (`DatabaseProtection` staging `.restoring-*` and verifying before quarantining corrupt `userdata.db`), `UserDataAccessMode.safeReadOnly` with localized `SafeReadOnlyBanner`, and daily `VACUUM INTO` backups (`UserDataBackupService`, 5-backup rotation).
- **Foundation F2 (Stable track identity, move/rename relink & play-event log hardening):** Added `userdata.track_identity` (`kUserDataSchemaVersion = 2`), canonical indexed `path_key`/`uri_key` columns in `userdata.db` v3 (batched backfill behind mandatory pre-migration backup), indexed single-transaction prepared-statement relinking (`SqliteIdentityStore`) with post-first-frame startup reconcile (`StartupIdentityReconciler`) and reconcile-owned identity creation (`upsertTracks` no longer creates identities eagerly), `missing_since_ms` offline-drive preservation, 30s heartbeat & startup `'interrupted'` recovery, origin `source`/`session_id`/`track_uid`/`ended_reason` capture in `PlayRecorder`, and date-range analytics read queries (`SqliteHistoryAnalytics`).
- **Foundation F3 (Error model, rotating privacy logger, no-silent-catch enforcement & versioned JSON stores):** Added `Result<T>` / `AppError` (`lib/core/result.dart`), localized `ErrorPresenter` (`lib/ui/common/error_presenter.dart`, `en`+`ar` `error.*` strings) wired in M3U import/export and add-folder pilots (`ScanService.addFolderResult`, `FolderManagementSheet`, `AppShell`); upgraded `AppLogger` (`lib/diagnostics/app_logger.dart`) with `LogLevel` (`debug`, `info`, `warn`, `error`), `minLevel`, `customSink`, `AppLogger.swallow(...)`, 1 MB x 5 rolling rotation, quoted/UNC/`file://` redaction, and safe uninitialized no-op buffering; audited every `catch`/`on` clause across `lib/` (261 total: 38 class `(a)`, 182 class `(b)`, 41 class `(c)`) guarded by `test/architecture/no_silent_catch_test.dart` (`kSilentCatchAllowlist = {}`); and added `VersionedJsonStoreHelper` (`lib/features/persistence/versioned_json_store.dart`) + `AtomicFileWriter` across `SettingsStore`, `EqStore`, `ArtistNameStore`, `LyricsOffsetStore`, and `SessionStore` with `schemaVersion`, ordered migrations, unknown-key preservation, `.bad-<timestamp>` quarantine, and 3-file rolling backups under `backups/settings/`.
- **Foundation F4 (Composition root, PlaybackController split, platform layer, feature flags & architecture tests — Foundation complete):** Extracted composition root into `lib/app/` (`AppBootstrap`, `AppServices`, `WindowLifecycleCoordinator`, `AestheticyApp`, `init_error_apps.dart`, `flutter_error_handler.dart`, shrinking `lib/main.dart` from 1,159 to 55 lines); split `lib/audio/playback_controller.dart` (1,121 -> 661 lines) into internal collaborators under `lib/audio/playback/` with zero behavior change verified by pre-refactor characterization tests; added `PlatformServices` OS selector, `FileAssociationService`, production no-op fallbacks, and typed `FeatureFlags` (`lib/app/feature_flags.dart`, hidden `featureFlags` map in `AppSettings`); and added architecture guards (`ui_layer_boundaries_test.dart`, `no_direct_queue_mutation_in_ui_test.dart`, `windows_platform_isolation_test.dart`) while removing `main.dart` and `playback_controller.dart` from `kFileSizeAllowlist`.

## NOT DONE (In Order)
1. Prompt 9 (Home, Stats, Wrapped monthly + weekly listening activity, Recommended, Smart playlists, shareable image).
2. Quick wins.
3. Logic audit.
4. Open-with + drag-drop + single instance.
5. UI redesign.
6. Installer + auto-update + signing.
7. Long soak test.
8. v1.0.

## Key Decisions
- [ADR 0001](decisions/0001-split-userdata-db.md): Split user data (`userdata.db`) from rebuildable library index (`library.db`) via `ATTACH DATABASE`, single-file transactions, crash-recoverable migration, WAL + `quick_check`, and daily backups.
- [ADR 0002](decisions/0002-never-write-user-audio-files.md): Aestheticy never writes to user audio files (enforced by `no_user_file_writes_test.dart`).
- [ADR 0003](decisions/0003-stable-track-identity.md): Stable 128-bit `track_identity` UIDs, atomic move/rename relinking, and `missing_since_ms` offline preservation in `userdata.db` v2.
- [ADR 0004](decisions/0004-play-event-log.md): Hardened `play_events` schema, 30s heartbeat crash safety, startup `'interrupted'` closing, and date-range analytics queries.
- [ADR 0005](decisions/0005-error-model-and-logging.md): Typed `Result<T>`/`AppError` model, calm localized `ErrorPresenter`, rotating privacy-redacted `AppLogger`, and empty-allowlist no-silent-catch enforcement.
- [ADR 0006](decisions/0006-versioned-settings.md): Shared `VersionedJsonStoreHelper` with `schemaVersion`, ordered migrations, unknown-key preservation, `.bad-<timestamp>` quarantine, and rolling 3-copy backups.
- [ADR 0007](decisions/0007-composition-root.md): Composition root under `lib/app/` (`AppBootstrap`, `AppServices`, `WindowLifecycleCoordinator`) with slim 60-line `main.dart`.
- [ADR 0008](decisions/0008-platform-layer.md): Cross-OS `PlatformServices` selector, `FileAssociationService`, no-op fallbacks, and typed `FeatureFlags` backed by hidden `AppSettings.featureFlags`.
- [ADR 0009](decisions/0009-architecture-tests.md): Automated architecture guards for file-size budget, UI layer boundaries, controller-only queue mutations, and Windows platform isolation.
- Unified album identity uses `AlbumIdentity` (`album + normalized albumArtist` with `artist` fallback, or `track::<path>` for untagged singles) across SQLite queries, `CoverCache`, `ReleaseKindClassifier`, and UI views.
- M3U export validates targets before any disk write (`FilePicker.getDirectoryPath` rather than `FilePicker.saveFile` which eagerly writes bytes on Windows), enforces `.m3u`/`.m3u8`, refuses audio/existing non-playlist targets, requires localized overwrite confirmation, and writes atomically via temp sibling + flush + rename.
- Display-only artist translations live in `ArtistNameStore` (`artist_names.json`) and never mutate library merge aliases.
- Sideloaded Windows test validation relies on unit/widget tests with `FakeAudioEngine` and `FakeWindowService`; live audio and native windowing require testing the CI build.

## Catch Audit (Verified Live Totals)

Guarded by `test/architecture/no_silent_catch_test.dart` (`kSilentCatchAllowlist = {}`). Every `catch` and `on` clause in `lib/` is classified below without fragile line numbers:

### Summary
- **Total `catch` / `on` clauses in `lib/`:** 261 (`kSilentCatchAllowlist = {}`)
- **Class `(a)` safe ignore (`// ignore-silent:`):** 38
- **Class `(b)` log & recover / surface to user:** 182 (logged via `AppLogger`, with safe fallback recovery and/or `ErrorPresenter`/`onError` feedback where user-visible)
- **Class `(c)` log, roll back / clean up & `rethrow` to outer boundary:** 41 (39 runtime boundaries + 2 `SimulatedCrashException` test hooks)

### Class `(a)` — `// ignore-silent:` Uses (38)
| File | Count | Reason |
| --- | --- | --- |
| `lib/diagnostics/app_logger.dart` | 7 | `AppLogger` internal guards that cannot recurse (`init` fallback, `customSink` sink write, `flush` write, rotation length check, expired archive deletion, archive rename/rotation, optional recent log cache read) |
| `lib/features/collections/m3u.dart` | 1 | Deleting temporary `.tmp` file created by `writeM3uAtomically` |
| `lib/features/integration/app_shutdown.dart` | 1 | Flushing `AppLogger` during shutdown cannot log recursively |
| `lib/features/integration/media_session_controller.dart` | 1 | Reading optional cover cache path falls back without SMTC artwork |
| `lib/features/lyrics/lyrics_cache.dart` | 5 | Optional lyrics disk cache (`read` miss, stale file delete before atomic rename, non-blocking cache write, cached JSON parse miss, corrupt temp file delete) |
| `lib/features/persistence/atomic_file_writer.dart` | 4 | Deleting temporary staging file created by `AtomicFileWriter` |
| `lib/features/persistence/versioned_json_store.dart` | 1 | Deleting temporary backup file created by `VersionedJsonStoreHelper` |
| `lib/library/cover_cache.dart` | 5 | Optional cover cache (`stat`/entry lookup miss 3x, deleting stale cache file before atomic rename retry 2x) |
| `lib/library/sqlite/database_protection.dart` | 2 | Closing SQLite handle after `quick_check` completes/fails; deleting temporary `.restoring-*` staging file created by `prepareUserDataDb` |
| `lib/library/sqlite/legacy_userdata_migrator.dart` | 2 | Deleting partial temporary backup file before checkpoint fallback; rolling back already-failing userdata copy transaction |
| `lib/library/sqlite/userdata_backup_service.dart` | 3 | Closing standalone SQLite connection after `VACUUM INTO` / WAL checkpoint (2x); deleting temporary backup file created by `UserDataBackupService` |
| `lib/platform/windows/smtc_media_session.dart` | 1 | Reading optional cached cover file falls back cleanly without SMTC artwork |
| `lib/platform/windows/windows_tray_service.dart` | 1 | Probing optional cached ICO asset candidate before extraction fallback |
| `lib/ui/library/widgets/artist_album_section.dart` | 1 | Reading optional cover cache falls back cleanly when uninitialized |
| `lib/ui/now_playing/cover_palette.dart` | 1 | Reading optional cover color palette cache falls back to `CoverPalette.fallback` |
| `lib/ui/queue/widgets/queue_row.dart` | 1 | Reading optional cover cache falls back cleanly when uninitialized |
| `lib/ui/shell/widgets/bottom_bar_track_info.dart` | 1 | Reading optional cover cache falls back cleanly when uninitialized |

### Class `(c)` — `rethrow` Uses (41)
| File | Count | Operation & Outer Boundary |
| --- | --- | --- |
| `lib/library/migrations.dart` | 5 | Database schema migration transaction rollbacks (log with stack trace, roll back TX, rethrow to `SqliteLibraryRepository.openFile`) |
| `lib/library/sqlite/userdata_migrator.dart` | 6 | `userdata.db` migration transaction rollbacks (log, roll back TX, rethrow to `SqliteLibraryRepository.openFile`) |
| `lib/library/sqlite/legacy_userdata_migrator.dart` | 3 | Legacy pre-split userdata copy transaction rollbacks / `SimulatedCrashException` hook (log with stack trace, roll back TX, rethrow to `LegacyUserDataMigrator.run`) |
| `lib/library/sqlite/sqlite_artists_store.dart` | 1 | Artist rule write transaction rollback (log, roll back TX, rethrow to artist-merge service/UI boundary) |
| `lib/library/sqlite/sqlite_collections_store.dart` | 6 | Collection/playlist SQLite write transaction rollbacks (log, roll back TX, rethrow to `UserCollections`/`M3u` boundary) |
| `lib/library/sqlite/sqlite_identity_store.dart` | 2 | Track identity reconcile/relink transaction rollbacks (log, roll back TX, rethrow to `LibraryScanner`/`StartupIdentityReconciler` boundary) |
| `lib/library/sqlite/sqlite_tracks_store.dart` | 4 | Library track upsert/cleanup transaction rollbacks (log, roll back TX, rethrow to `ScanService`/`LibraryScanner` boundary) |
| `lib/library/sqlite_library_repository.dart` | 3 | `SimulatedCrashException` test hooks / fatal DB open failure (log, close DB handle, rethrow to `AppBootstrap` -> `LibraryInitErrorApp` boundary) |
| `lib/features/collections/user_collections.dart` | 9 | `init` failure (1x -> startup boundary) and collection mutations (8x -> revert optimistic state, log warn, notify `onError`/`onReadOnlyBlocked`, rethrow to UI action boundary) |
| `lib/features/collections/m3u.dart` | 1 | `writeM3uAtomically` failure (log error, clean up `.tmp`, rethrow to `exportPlaylistResult` boundary) |
| `lib/platform/windows/windows_tray_service.dart` | 1 | Tray `show` failure (log error and rethrow to `TrayWindowController` boundary) |
