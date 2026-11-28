# Aestheticy

A native Windows desktop music player built with Flutter.  
Calm, minimal, and beautiful — by mido.

## Status

Phase 1–4 active: audio core, SQLite library, liquid-glass UI foundation ([docs/ui.md](docs/ui.md)), synced lyrics, queue, mini player, localization (English & Arabic RTL), and settings management.

## Highlights

- **Home & Discovery**: Calm 3-element Home screen (`HomeView`, `HomeController`) as the default landing view when folders exist, featuring a live time-of-day greeting (`en`/`ar`), Now Playing / Resume Last Session hero card, a "Continue listening" recent albums shelf, and one daily rotating row (`Recently added`, `Forgotten favorites`, `On this day`, or `Most played this month`).
- **Listening Stats**: Calm Statistics screen (`StatsView`, `StatsController`, `lib/ui/stats/`) with segmented range selection (`This week`, `This month`, `This year`, `All time`), locale-aware week starts (Monday in `en`, Saturday in `ar`), 4 KPI summary tiles with previous-period delta comparisons, `CustomPainter` daily/monthly listening bars and 7×24 weekly activity heat strip with hover/focus readouts, and Top 10 tracks/artists/albums respecting `arabicNumerals` and `safeReadOnly` mode.
- **Audio & Queue**: `libmpv` behind `AudioEngine`, 10-band EQ, fade profiles, unified `PlaybackController.playShuffled` / repeat sync, entry-identity multi-select queue editing & delete, session restore preserving shuffled order and duplicate entry identity, and responsive docked Queue/Lyrics side panel (22% of window width clamped to 280–320 px, auto-hidden below 1000 px).
- **Library & Protection**: Folder scanning with continuous multi-folder progress, cancellation protection, split `library.db` (rebuildable index) and `userdata.db` (favorites, ratings, playlists, play history, artist rules) via SQLite `ATTACH`, stable `track_identity` UIDs with automatic move/rename relinking and offline-drive preservation, hardened `play_events` with 30s heartbeats / interrupted-session recovery / date-range analytics queries, WAL + `PRAGMA quick_check` corruption recovery, crash-recoverable legacy migration, safe read-only fallback mode, daily verified `userdata.db` backups (5-day rotation), unified `AlbumIdentity` grouping and cover keys, real recently-added album sorting, live stale-while-revalidate refresh on scan/folder changes, stale-guarded search (matching track artists & display translations on Albums), artist merge/never-split rules, `file://` URI-aware history/playlists, and safe atomic `.m3u`/`.m3u8` export & Windows-path M3U import.
- **Localization & Display**: Full English + Arabic RTL interface, display-only artist name translations manager in Settings, localized library sheets/dialogs.
- **Reliability & Persistence**: Rotating privacy-redacted diagnostics logger (`AppLogger`, 5x 1 MB rolling files), typed `Result<T>` / `AppError` model with calm localized `ErrorPresenter` feedback, empty-allowlist no-silent-catch enforcement across `lib/`, and schema-versioned atomic JSON stores (`SettingsStore`, `EqStore`, `ArtistNameStore`, `LyricsOffsetStore`, `SessionStore`) with ordered migrations, forward unknown-key preservation, `.bad-<timestamp>` quarantine, and rolling 3-copy backups under `backups/settings/`.
- **Mini Player & Shortcuts**: Compact & square modes, lyrics toggle, always-on-top pin, favorite toggle, and Space-key guard covering focused glass buttons and text fields.

## Local Development

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel).

```powershell
# Install dependencies
flutter pub get

# Run static analysis (should report 0 issues)
flutter analyze

# Run tests
flutter test
```

> **Note:** Building for Windows requires Visual Studio with the C++ workload.  
> We use GitHub Actions for builds instead of building locally.

## Download the Windows Build

1. Go to the [Actions tab](../../actions) on GitHub.
2. Click the latest successful **Build Windows** run.
3. Download the **aestheticy-windows** artifact from the bottom of the page.
4. Extract the zip and run `aestheticy.exe`.

## Tech Stack

- **Flutter** (Dart) — Windows desktop target
- **libmpv** — Audio playback behind an `AudioEngine` interface

## Folder Map

- `lib/main.dart` — Slim app entrypoint (`runZonedGuarded`, logger init, `AppBootstrap.initialize`, `runApp`).
- `lib/app/` — Composition root (`app_bootstrap.dart`, `app_services.dart`, `window_lifecycle.dart`, `aestheticy_app.dart`, `init_error_apps.dart`, `flutter_error_handler.dart`, `feature_flags.dart`).
- `lib/audio/` — `AudioEngine` contract, `MpvAudioEngine`, `PlaybackQueue`, and `PlaybackController` facade backed by internal collaborators under `lib/audio/playback/` (fade, gapless preload, queue operations, resume state, play-source tracking).
- `lib/core/` — Shared `Result<T>` and sealed `AppError` types.
- `lib/diagnostics/` — Rotating privacy-redacted `AppLogger` and diagnostic report builder.
- `lib/features/` — Feature coordinators (collections/M3U, play history recorder, OS integration & shutdown, lyrics, atomic & versioned JSON persistence, session save/restore).
- `lib/library/` — Pure-Dart models, scanner, cover cache, and split SQLite stores (`library.db` + `userdata.db` under `lib/library/sqlite/`).
- `lib/platform/` — Abstract OS interfaces (`TrayService`, `WindowService`, `MediaSessionService`, `SleepInhibitor`, `FileAssociationService`), `PlatformServices` OS selector, no-op fallbacks, and isolated Windows implementations under `lib/platform/windows/`.
- `lib/ui/` — Glass UI shell, Home screen (`lib/ui/home/`), Listening Stats screen (`lib/ui/stats/`), library views, settings, mini player, localization (`AppStrings` EN + AR), and `ErrorPresenter`.
- `test/architecture/` — Automated architecture guard tests (file-size budget, UI layer boundaries, no direct UI queue mutation, Windows isolation, no silent catches, no user audio file writes).

## License

Private project. All rights reserved.
