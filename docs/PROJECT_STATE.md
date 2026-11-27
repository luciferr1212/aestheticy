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
- **Foundation F1 (`userdata.db` split, SQLite protection & automatic backups):** Separated user data into `userdata.db` (now `kUserDataSchemaVersion = 3`) attached to `library.db` (`kLibrarySchemaVersion = 4`), added crash-recoverable legacy migration (`LegacyUserDataMigrator` with `VACUUM INTO` + row-count-verified `pre-split-*` backups and full-row SHA-256 verification), added WAL + `PRAGMA quick_check` corruption recovery (`DatabaseProtection` staging `.restoring-*` and verifying before quarantining corrupt `userdata.db`), `UserDataAccessMode.safeReadOnly` with localized `SafeReadOnlyBanner`, and daily `VACUUM INTO` backups (`UserDataBackupService`, 5-backup rotation).
- **Foundation F2 (Stable track identity, move/rename relink & play-event log hardening):** Added `userdata.track_identity` (`kUserDataSchemaVersion = 2`), canonical indexed `path_key`/`uri_key` columns in `userdata.db` v3 (batched backfill behind mandatory pre-migration backup), indexed single-transaction prepared-statement relinking (`SqliteIdentityStore`) with post-first-frame startup reconcile (`StartupIdentityReconciler`) and reconcile-owned identity creation (`upsertTracks` no longer creates identities eagerly), `missing_since_ms` offline-drive preservation, 30s heartbeat & startup `'interrupted'` recovery, origin `source`/`session_id`/`track_uid`/`ended_reason` capture in `PlayRecorder`, and date-range analytics read queries (`SqliteHistoryAnalytics`).
- **Foundation F3 (Error model, rotating privacy logger, no-silent-catch enforcement & versioned JSON stores):** Added `Result<T>` / `AppError` (`lib/core/result.dart`), localized `ErrorPresenter` (`lib/ui/common/error_presenter.dart`, `en`+`ar` `error.*` strings) wired in M3U import/export and add-folder pilots (`ScanService.addFolderResult`, `FolderManagementSheet`, `AppShell`); upgraded `AppLogger` (`lib/diagnostics/app_logger.dart`) with `LogLevel` (`debug`, `info`, `warn`, `error`), `minLevel`, `customSink`, `AppLogger.swallow(...)`, 1 MB x 5 rolling rotation, quoted/UNC/`file://` redaction, and safe uninitialized no-op buffering; audited every `catch`/`on` clause across `lib/` (261 total: 38 class `(a)`, 182 class `(b)`, 41 class `(c)`) guarded by `test/architecture/no_silent_catch_test.dart` (`kSilentCatchAllowlist = {}`); and added `VersionedJsonStoreHelper` (`lib/features/persistence/versioned_json_store.dart`) + `AtomicFileWriter` across `SettingsStore`, `EqStore`, `ArtistNameStore`, `LyricsOffsetStore`, and `SessionStore` with `schemaVersion`, ordered migrations, unknown-key preservation, `.bad-<timestamp>` quarantine, and 3-file rolling backups under `backups/settings/`.

## NOT DONE (In Order)
1. Foundation (remaining: composition root, platform layer, feature flags).
2. Prompt 9 (Home, Stats, Wrapped monthly + weekly listening activity, Recommended, Smart playlists, shareable image).
3. Quick wins.
4. Logic audit.
5. Open-with + drag-drop + single instance.
6. UI redesign.
7. Installer + auto-update + signing.
8. Long soak test.
9. v1.0.

## Key Decisions
- [ADR 0001](decisions/0001-split-userdata-db.md): Split user data (`userdata.db`) from rebuildable library index (`library.db`) via `ATTACH DATABASE`, single-file transactions, crash-recoverable migration, WAL + `quick_check`, and daily backups.
- [ADR 0002](decisions/0002-never-write-user-audio-files.md): Aestheticy never writes to user audio files (enforced by `no_user_file_writes_test.dart`).
- [ADR 0003](decisions/0003-stable-track-identity.md): Stable 128-bit `track_identity` UIDs, atomic move/rename relinking, and `missing_since_ms` offline preservation in `userdata.db` v2.
- [ADR 0004](decisions/0004-play-event-log.md): Hardened `play_events` schema, 30s heartbeat crash safety, startup `'interrupted'` closing, and date-range analytics queries.
- [ADR 0005](decisions/0005-error-model-and-logging.md): Typed `Result<T>`/`AppError` model, calm localized `ErrorPresenter`, rotating privacy-redacted `AppLogger`, and empty-allowlist no-silent-catch enforcement.
- [ADR 0006](decisions/0006-versioned-settings.md): Shared `VersionedJsonStoreHelper` with `schemaVersion`, ordered migrations, unknown-key preservation, `.bad-<timestamp>` quarantine, and rolling 3-copy backups.
- Unified album identity uses `AlbumIdentity` (`album + normalized albumArtist` with `artist` fallback, or `track::<path>` for untagged singles) across SQLite queries, `CoverCache`, `ReleaseKindClassifier`, and UI views.
- M3U export validates targets before any disk write (`FilePicker.getDirectoryPath` rather than `FilePicker.saveFile` which eagerly writes bytes on Windows), enforces `.m3u`/`.m3u8`, refuses audio/existing non-playlist targets, requires localized overwrite confirmation, and writes atomically via temp sibling + flush + rename.
- Display-only artist translations live in `ArtistNameStore` (`artist_names.json`) and never mutate library merge aliases.
- Sideloaded Windows test validation relies on unit/widget tests with `FakeAudioEngine` and `FakeWindowService`; live audio and native windowing require testing the CI build.

## Catch Audit Table (F3 S3)
| File | Line | Class | Reason |
| --- | --- | --- | --- |
| `lib/audio/mpv_audio_engine.dart` | 166 | b | Log warn setting `sub-auto=no` while `.lrc` filter fallback protects playback |
| `lib/audio/mpv_audio_engine.dart` | 177 | b | Log warn setting `audio-file-auto=no` while safety filter protects playback |
| `lib/audio/mpv_audio_engine.dart` | 548 | b | Log warn and emit non-fatal `AudioError` on preload failure |
| `lib/audio/mpv_audio_engine.dart` | 623 | b | Log warn on `audio-device-list` node failure and fall back to player state |
| `lib/audio/playback_controller.dart` | 984 | b | Log error, restore fadeGain, and advance via `_onError` without rethrowing in playback path |
| `lib/audio/playback_controller.dart` | 1098 | b | Log warn and emit non-fatal `AudioError` when next-track preload fails |
| `lib/diagnostics/app_logger.dart` | 87 | a | `ignore-silent`: disable file logging if support dir is unwritable (`AppLogger.init`) |
| `lib/diagnostics/app_logger.dart` | 150 | a | `ignore-silent`: injected `customSink` failure inside `AppLogger` cannot recurse |
| `lib/diagnostics/app_logger.dart` | 244 | a | `ignore-silent`: `AppLogger.flush` disk write fallback avoids recursion |
| `lib/diagnostics/app_logger.dart` | 260 | a | `ignore-silent`: rotation size check inside `AppLogger` avoids recursion |
| `lib/diagnostics/app_logger.dart` | 277 | a | `ignore-silent`: deleting expired rotated log archive created by `AppLogger` |
| `lib/diagnostics/app_logger.dart` | 303 | a | `ignore-silent`: rotating/renaming `AppLogger` archive files avoids recursion |
| `lib/diagnostics/app_logger.dart` | 334 | a | `ignore-silent`: reading optional log cache returning empty list on miss |
| `lib/main.dart` | 97 | b | Log error and show `AudioInitErrorApp` to user when audio engine init fails |
| `lib/main.dart` | 125 | b | Log error and show `LibraryInitErrorApp` to user when library init fails |
| `lib/main.dart` | 165 | b | Log warning when startup audio settings application fails |
| `lib/main.dart` | 802 | b | Log warning when mini-player frame restore fails on window exit |
| `lib/main.dart` | 829 | b | Log warning when session snapshot fails before hide |
| `lib/main.dart` | 839 | b | Log warning when hiding window fails on close-to-tray |
| `lib/main.dart` | 853 | b | Log warning when pausing playback fails on exit |
| `lib/main.dart` | 863 | b | Log warning when hiding window fails on quit |
| `lib/main.dart` | 983 | b | Log warning when session snapshot fails on mini-player hide |
| `lib/main.dart` | 998 | b | Log warning when pausing playback fails on mini-player quit |
| `lib/main.dart` | 1008 | b | Log warning when hiding mini-player window fails on quit |
| `lib/platform/windows/folder_opener.dart` | 24 | b | Log warn and notify optional `onError` when Explorer launch fails |
| `lib/platform/windows/smtc_media_session.dart` | 54 | b | Log warning and mark SMTC unavailable on initialize failure |
| `lib/platform/windows/smtc_media_session.dart` | 95 | a | `ignore-silent`: reading optional cached cover artwork URI falls back cleanly without artwork |
| `lib/platform/windows/smtc_media_session.dart` | 116 | b | Log warning and disable SMTC updates when metadata update fails |
| `lib/platform/windows/smtc_media_session.dart` | 134 | b | Log warning and disable SMTC updates when playback status update fails |
| `lib/platform/windows/smtc_media_session.dart` | 158 | b | Log warning and disable SMTC updates when timeline update fails |
| `lib/platform/windows/smtc_media_session.dart` | 173 | b | Log warning when disabling SMTC fails |
| `lib/platform/windows/smtc_media_session.dart` | 187 | b | Log warning when disposing SMTC fails |
| `lib/platform/windows/win32_sleep_inhibitor.dart` | 28 | b | Log warning when loading kernel32 `SetThreadExecutionState` fails |
| `lib/platform/windows/win32_sleep_inhibitor.dart` | 51 | b | Log warning when acquiring sleep prevention fails |
| `lib/platform/windows/win32_sleep_inhibitor.dart` | 78 | b | Log warning when releasing sleep prevention fails |
| `lib/platform/windows/windows_tray_service.dart` | 59 | a | `ignore-silent`: probing optional cached ICO asset candidate before extraction fallback |
| `lib/platform/windows/windows_tray_service.dart` | 121 | b | Log warning when fallback tray icon extraction fails |
| `lib/platform/windows/windows_tray_service.dart` | 159 | c | Log error and rethrow tray `show` failure to `TrayWindowController` boundary |
| `lib/platform/windows/windows_tray_service.dart` | 177 | b | Log warning when hiding tray fails |
| `lib/platform/windows/windows_tray_service.dart` | 222 | b | Log warning when updating tray menu fails |
| `lib/platform/windows/windows_window_service.dart` | 51-309 (16x) | b | Log warning across all 16 Win32 window manager calls without crashing |
| `lib/library/cover_cache.dart` | 108, 138, 190 (3x) | a | `ignore-silent`: reading optional cover cache file stat returns false on miss |
| `lib/library/cover_cache.dart` | 152, 204 (2x) | b | Log debug and retry atomic cover file rename after target conflict |
| `lib/library/cover_cache.dart` | 164, 218 (2x) | a | `ignore-silent`: deleting stale cover cache file before atomic rename retry |
| `lib/library/file_path_utils.dart` | 32, 46, 56 (3x) | b | Log debug URI decode fallback for malformed percent-encoded paths |
| `lib/library/library_scanner.dart` | 235, 508, 535, 680 (4x) | b | Log warn on link rebuild / unreadable dirs / stat / corrupt tags; surface counts via `ScanProgress` |
| `lib/library/migrations.dart` | 94, 121, 133, 145, 335 (5x) | c | Log error with stack trace, rollback TX, and rethrow to `SqliteLibraryRepository.openFile` |
| `lib/library/scan_service.dart` | 57 | b | Log error and return `Err(AppError)` in `addFolderResult` |
| `lib/library/sqlite_library_repository.dart` | 195, 291, 306 (3x) | b | Log error and enter `UserDataAccessMode.safeReadOnly` fallback |
| `lib/library/sqlite_library_repository.dart` | 290, 329, 378 (3x) | c | Log error / close DB handle and rethrow (`SimulatedCrashException` test hook or fatal init error to `LibraryInitErrorApp`) |
| `lib/library/startup_identity_reconciler.dart` | 71 | b | Log warning when post-first-frame identity reconciliation fails |
| `lib/library/sqlite/database_protection.dart` | 106-126 (3x) | b | Log debug/warn and map SQLite/IO exception to `QuickCheckResult` |
| `lib/library/sqlite/database_protection.dart` | 134 | a | `ignore-silent`: closing SQLite handle after `quick_check` completes or fails |
| `lib/library/sqlite/database_protection.dart` | 286-546 (9x) | b | Log error/warning during restore/backup/quarantine/WAL cleanup and enter `safeReadOnly` |
| `lib/library/sqlite/database_protection.dart` | 487 | a | `ignore-silent`: deleting temporary `.restoring-*` staging file |
| `lib/library/sqlite/database_protection.dart` | 507, 542 (2x) | b | Log warning when moving `-wal`/`-shm` sidecar files during quarantine/rollback |
| `lib/library/sqlite/legacy_userdata_migrator.dart` | 264-489 (7x) | b | Log error/warning/debug during backup, checkpoint fallback, and verification -> `safeReadOnly` |
| `lib/library/sqlite/legacy_userdata_migrator.dart` | 379 | a | `ignore-silent`: deleting partial temporary backup file before checkpoint fallback |
| `lib/library/sqlite/legacy_userdata_migrator.dart` | 570 | a | `ignore-silent`: rolling back already-failing userdata copy transaction |
| `lib/library/sqlite/legacy_userdata_migrator.dart` | 271, 627, 659 (3x) | c | Log error with stack trace, rollback TX, and rethrow (`SimulatedCrashException` hook or copy failure to `LegacyUserDataMigrator.run` boundary) |
| `lib/library/sqlite/sqlite_artists_store.dart` | 276 | c | Log error, rollback TX, and rethrow to artist-merge UI/service boundary |
| `lib/library/sqlite/sqlite_collections_store.dart` | 148-418 (6x) | c | Log error, rollback TX, and rethrow to `UserCollections`/`M3u` boundary |
| `lib/library/sqlite/sqlite_identity_store.dart` | 254, 550 (2x) | c | Log error, rollback TX, and rethrow to `LibraryScanner`/`StartupIdentityReconciler` boundary |
| `lib/library/sqlite/sqlite_tracks_store.dart` | 48-183 (4x) | c | Log error, rollback TX, and rethrow to `ScanService`/`LibraryScanner` boundary |
| `lib/library/sqlite/userdata_backup_service.dart` | 130-314 (8x) | b | Log error/warning/debug on daily/pre-migration backups and checkpoint fallback |
| `lib/library/sqlite/userdata_backup_service.dart` | 270, 289 (2x) | a | `ignore-silent`: closing standalone SQLite backup connection in `finally` |
| `lib/library/sqlite/userdata_backup_service.dart` | 325 | a | `ignore-silent`: deleting temporary backup file |
| `lib/library/sqlite/userdata_migrator.dart` | 80-420 (6x) | c | Log error, rollback TX, and rethrow to `SqliteLibraryRepository.openFile` boundary |
| `lib/features/audio_lab/audio_lab_screen.dart` | 207 | b | Log error and surface picker failure via `ErrorPresenter.show` |
| `lib/features/collections/m3u.dart` | 371 | c | Log error, clean up temp file, and rethrow to `exportPlaylistResult` boundary |
| `lib/features/collections/m3u.dart` | 377 | a | `ignore-silent`: deleting temporary `.tmp` file created by `writeM3uAtomically` |
| `lib/features/collections/m3u.dart` | 516, 671, 683 (3x) | b | Log warn/error and surface M3U import/export failure via `ErrorPresenter.show` |
| `lib/features/collections/user_collections.dart` | 83 | c | Log error and rethrow `UserCollections.init` failure to startup/caller boundary |
| `lib/features/collections/user_collections.dart` | 139-335 (8x) | c | Revert optimistic state, log warn, notify `onError`/`onReadOnlyBlocked`, and rethrow to UI action boundary |
| `lib/features/collections/user_collections.dart` | 386 | b | Log warn and notify `onError` on background collection refresh failure |
| `lib/features/history/play_recorder.dart` | 350, 415, 468 (3x) | b | Log error with stack trace; never throw into playback path |
| `lib/features/integration/app_shutdown.dart` | 54, 121, 125 (3x) | b | Log error/timeout and continue ordered shutdown sequence |
| `lib/features/integration/app_shutdown.dart` | 105 | a | `ignore-silent`: flushing `AppLogger` during shutdown cannot log recursively |
| `lib/features/integration/media_session_controller.dart` | 75-267 (6x) | b | Log warning and mark SMTC unavailable without interrupting playback |
| `lib/features/integration/media_session_controller.dart` | 171 | a | `ignore-silent`: reading optional cover cache path falls back without SMTC artwork |
| `lib/features/integration/tray_window_controller.dart` | 138, 233, 262 (3x) | b | Log error/warning during tray creation, snapshot, or quit pause |
| `lib/features/library/artist_rules_sheet.dart` | 66, 86 (2x) | b | Log warn and surface `safeReadOnly` block via `ErrorPresenter.show` |
| `lib/features/library/folder_management_sheet.dart` | 111 | b | Log error and surface add-folder failure via `ErrorPresenter.show` |
| `lib/features/lyrics/lrc_parser.dart` | 49 | b | Log debug and fall back to Windows-1256 when strict UTF-8 decode fails |
| `lib/features/lyrics/lyrics_cache.dart` | 126, 174, 181, 244, 255 (5x) | a | `ignore-silent`: optional lyrics cache read/write/corrupt-temp delete falls back to re-fetch |
| `lib/features/lyrics/lyrics_controller.dart` | 336 | b | Log warn on unexpected lyrics resolution failure and show error state |
| `lib/features/lyrics/lyrics_offset_store.dart` | 79, 146 (2x) | b | Log warn/error and invoke optional `onError` on offset store init/save failure |
| `lib/features/lyrics/lyrics_repository.dart` | 236, 327, 335, 338, 370, 429 (6x) | b | Log warn on local/remote lyrics read, timeout, socket error, or LRCLIB JSON parse failure |
| `lib/features/persistence/atomic_file_writer.dart` | 148, 194, 248, 293 (4x) | a | `ignore-silent`: deleting temporary file created by `AtomicFileWriter` |
| `lib/features/persistence/atomic_file_writer.dart` | 67-205 (11x) | b | Log debug/warn/error across rename/copy fallbacks and invoke `onError` if all fail |
| `lib/features/persistence/versioned_json_store.dart` | 140, 169, 219, 265 (4x) | b | Log warn on corrupt JSON load/quarantine and rolling backup write/prune failure |
| `lib/features/persistence/versioned_json_store.dart` | 231 | a | `ignore-silent`: deleting temporary backup file created by `VersionedJsonStoreHelper` |
| `lib/features/session/session_restorer.dart` | 68 | b | Log debug when saved session path existence probe fails |
| `lib/features/session/session_store.dart` | 81, 134, 211 (3x) | b | Log warn/error and invoke optional `onError` on session init/write failure |
| `lib/ui/artist_names/artist_name_store.dart` | 279, 368 (2x) | b | Log warn/error and invoke optional `onError` on store init/write failure |
| `lib/ui/audio_panels/eq_controller.dart` | 71, 88, 187, 306 (4x) | b | Log warn and revert EQ state on engine failure without blocking playback |
| `lib/ui/audio_panels/eq_store.dart` | 346, 405 (2x) | b | Log warn/error and invoke optional `onError` on `eq_settings.json` init/write failure |
| `lib/ui/library/artists_view.dart` | 319, 336 (2x) | b | Log warn/error on artist merge failure and show localized SnackBar |
| `lib/ui/library/library_data_cache.dart` | 178 | b | Log warn when background library cache refresh fails |
| `lib/ui/library/sort_direction_button.dart` | 150 | b | Log warn and return empty map if play-count query fails |
| `lib/ui/library/track_actions_menu.dart` | 57-294 (5x) | b | Log warn on playlist create/rename/delete errors and display inline/SnackBar message |
| `lib/ui/library/widgets/artist_album_section.dart` | 360 | a | `ignore-silent`: reading optional cover cache falls back cleanly when uninitialized |
| `lib/ui/library/widgets/artist_tracks_header.dart` | 242 | b | Log warn on `addNoSplit` read-only block and show localized SnackBar |
| `lib/ui/now_playing/cover_palette.dart` | 253 | a | `ignore-silent`: reading optional cover color palette cache falls back to `CoverPalette.fallback` |
| `lib/ui/queue/queue_view.dart` | 243 | b | Log warn on save-queue-as-playlist failure and show dialog error |
| `lib/ui/queue/widgets/queue_row.dart` | 289 | a | `ignore-silent`: reading optional cover cache falls back cleanly when uninitialized |
| `lib/ui/quick_search/quick_search_overlay.dart` | 263 | b | Log warn on quick-search query failure and clear loading spinner |
| `lib/ui/settings/audio_settings_applier.dart` | 33-136 (10x) | b | Log warn across startup apply & settings setter failures while preserving saved settings |
| `lib/ui/settings/settings_store.dart` | 76, 161 (2x) | b | Log warn/error and invoke optional `onError` on `ui_settings.json` init/write failure |
| `lib/ui/settings/settings_view.dart` | 143 | b | Log warn when loading settings library stats fails |
| `lib/ui/settings/widgets/settings_system_sections.dart` | 359-592 (5x) | b | Log warn/error and surface history/clipboard/diagnostics failures via `ErrorPresenter.show` |
| `lib/ui/shell/app_navigator.dart` | 180 | b | Log warn when capturing view state callback fails during navigation |
| `lib/ui/shell/app_shell.dart` | 437 | b | Log error and surface add-folder picker failure via `ErrorPresenter.show` |
| `lib/ui/shell/widgets/bottom_bar_track_info.dart` | 177 | a | `ignore-silent`: reading optional cover cache falls back cleanly when uninitialized |
| `lib/ui/theme/font_manager.dart` | 70 | b | Log warn when `FontManifest.json` load/parse fails and fall back to system font |

### Catch Audit Summary
- **Total `catch` / `on` clauses in `lib/`:** 261 (`kSilentCatchAllowlist = {}`)
- **Class `(a)` safe ignore (`// ignore-silent:`):** 38
- **Class `(b)` log & recover / surface to user:** 182
- **Class `(c)` log, roll back & rethrow to outer boundary:** 41 (39 runtime boundaries + 2 `SimulatedCrashException` test hooks)
