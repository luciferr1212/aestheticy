# Aestheticy

A native Windows desktop music player built with Flutter.  
Calm, minimal, and beautiful — by mido.

## Status

Phase 1–4 active: audio core, SQLite library, liquid-glass UI foundation ([docs/ui.md](docs/ui.md)), synced lyrics, queue, mini player, localization (English & Arabic RTL), and settings management.

## Highlights

- **Audio & Queue**: `libmpv` behind `AudioEngine`, 10-band EQ, fade profiles, unified `PlaybackController.playShuffled` / repeat sync, entry-identity multi-select queue editing & delete, session restore preserving shuffled order and duplicate entry identity, and resizable docked Queue/Lyrics side panel.
- **Library**: Folder scanning with continuous multi-folder progress, cancellation protection, unified `AlbumIdentity` grouping and cover keys, real recently-added album sorting, live stale-while-revalidate refresh on scan/folder changes, stale-guarded search (matching track artists & display translations on Albums), artist merge/never-split rules, `file://` URI-aware history/playlists, and safe atomic `.m3u`/`.m3u8` export & Windows-path M3U import.
- **Localization & Display**: Full English + Arabic RTL interface, display-only artist name translations manager in Settings, localized library sheets/dialogs.
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
- **libmpv** (planned) — Audio playback behind an `AudioEngine` interface

## License

Private project. All rights reserved.
