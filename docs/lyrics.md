# Lyrics Feature Architecture & Specifications

## Overview
Aestheticy provides native desktop time-synchronized and plain lyrics with both local file resolution and online LRCLIB integration, Enhanced LRC per-word highlight, persistent atomic caching, and global keyboard transport controls with Space chords.

---

## 1. Core Architecture
- **Pure Dart Model & Parser** (`lib/features/lyrics/lyrics_models.dart`, `lrc_parser.dart`):
  - Completely decoupled from Flutter widgets and audio engine plugins.
  - Testable anywhere `dart test` runs.
- **Injectable Networking & Storage** (`lyrics_http.dart`, `lyrics_cache.dart`, `lyrics_repository.dart`):
  - All HTTP requests go through the `LyricsHttp` interface (`dart:io` `HttpClient` in production; in-memory mocks in tests).
  - Cache uses an injectable support directory.
- **State Coordination** (`lib/features/lyrics/lyrics_controller.dart`):
  - Extends `ChangeNotifier` to coordinate presentation state without coupling to Flutter views.
  - Follows `PlaybackController.currentStream` and audio engine position streams.
  - Emits typed state instances: `LyricsStateLoading`, `LyricsStateFound`, `LyricsStateNotFound`, `LyricsStateError`, `LyricsStateOff`.
  - Cancels in-flight requests on track changes to avoid stale responses overwriting newer track state.

---

## 2. Resolution Modes
Configurable in `AppSettings.lyricsSource`:
1. `localThenOnline` (default): Checks local sidecar files first. If synced lyrics are found, uses them immediately. Otherwise queries LRCLIB. If LRCLIB provides synced lyrics, they are preferred over local plain text.
2. `onlineThenLocal`: Queries LRCLIB first. If synced lyrics are found, uses them; otherwise inspects local sidecar files.
3. `localOnly`: Inspects local files and embedded metadata tags only. Makes zero network calls.
4. `onlineOnly`: Queries LRCLIB only. Does not read local filesystem sidecar files.
5. `off`: Disables lyrics resolution completely. Touches neither disk nor network.

---

## 3. Local Sources & Embedded Tags
- **Sidecar Files**: Looked up in the same directory as the audio track, with matching basename:
  - First `.lrc` (case-insensitive), then `.txt` (case-insensitive).
  - Read asynchronously with a safety cap of 1 MB.
- **Embedded Lyrics**: Read via `TagReader` (`audio_metadata_reader` 1.8.1 `AudioMetadata.lyrics`), mapped through `RawTags.lyrics` without modifying database schema or migrations.

---

## 4. Online Source: LRCLIB Integration
- **Host & Protocol**: HTTPS only to `https://lrclib.net`. No third-party redirects or alternate hosts.
- **Client Configuration**: 8-second request timeout, User-Agent `Aestheticy/1 (by mido)`.
- **Privacy & Metadata Sent**:
  - Only original primary artist (from `splitArtistNames`, never translated display names), track title, album title, and track duration rounded to whole seconds.
  - Zero search tokens, file paths, user identifiers, or personal data are transmitted.
- **Query Strategy**:
  1. `GET /api/get?track_name=&artist_name=&album_name=&duration=`
  2. On 404, fall back to `GET /api/search?track_name=&artist_name=` and select the best candidate within a strict 3-second duration tolerance (preferring synced lyrics, then closest duration). Candidates differing by >3 seconds are rejected.
  3. `instrumental: true` produces a dedicated instrumental state.

---

## 5. LRC Parser & Character Encoding
- **BOM Handling**: Detects and strips UTF-8 Byte Order Mark (`\uFEFF`) automatically.
- **Timestamp Formats**: Supports `[mm:ss.xx]`, `[mm:ss.xxx]`, `[mm:ss]`, and `[m:ss.x]`.
- **Multi-timestamps**: Lines with multiple timestamp tags (e.g. `[00:12.00][00:34.00]Chorus`) generate duplicate lines sorted chronologically.
- **Offset Tag**: Parses `[offset:+/-ms]` (positive = lyrics appear earlier).
- **Enhanced LRC Per-Word Timing**:
  - Tags `<mm:ss.xx>` inside lines parse into `LyricsWord(startMs, endMs, text)`.
  - Sets `hasWordTiming: true`. Word timing is strictly parsed from real timestamps and is NEVER estimated or interpolated from line duration.
- **Windows-1256 Fallback**:
  - `decodeLyricsBytes(bytes)` uses strict UTF-8 decoding first.
  - On UTF-8 format exceptions, decodes bytes using the complete Windows-1256 mapping table (`0x80` to `0xFF`) for legacy Arabic text. Never throws.

---

## 6. Atomic Disk Cache
- **Location**: `<supportDir>/lyrics/<md5(filePath)>.json`.
- **Atomic Persistence**: Writes first to `.tmp` file and flushes before renaming to target path.
- **TTL**:
  - Found lyrics: Valid for 30 days.
  - Negative cache (not found): Valid for 3 days to avoid hammering LRCLIB on repeated track plays.
  - Corrupt or invalid JSON entries are discarded and treated as cache misses.

---

## 7. UI Components, Motion & Presentation
- **`LyricsView`** (`lib/ui/lyrics/lyrics_view.dart`):
  - **Calm Line Scrolling**: Active line sits slightly above vertical center (alignment 0.42) with a smooth 550 ms glide (`Curves.easeOutCubic`).
  - **Manual Scroll Pause**: If the user scrolls manually, auto-follow pauses for 4 seconds, then smoothly glides back to the current line. Clicking any line seeks immediately and scrolls.
  - **Typography & Scale**:
    - Current line: fontSize 32 on the lyrics page, 40 in Full screen (scale 1.0).
    - Inactive lines: fontSize 24 on page, 28 in Full screen (scale 0.92, anchored to text start side).
    - Transitions animate scale and opacity over 350 ms with `Curves.easeOut`.
    - Line height 1.35 with dynamic per-line text direction (`textDirectionFor`).
  - **Opacity Falloff & Hover**:
    - Current active line: 1.0.
    - Upcoming lines: distance 1 = 0.55, distance 2 = 0.38, distance 3 = 0.26, distance 4+ = 0.20 (floor).
    - Past lines: dimmer than upcoming (distance 1 = 0.44, distance 2 = 0.30, distance 3 = 0.21, distance 4+ = 0.20).
    - Line hover raises opacity by 0.18 over 150 ms with pointer cursor.
  - **Edge Softening**:
    - Top and bottom 12% of the lyrics area are dissolved with a `ShaderMask` linear gradient so lines enter and leave view softly without harsh cuts.
  - **Enhanced Word Highlight**:
    - Current word fills smoothly from dim to full color with a soft gradient sweep (right-to-left for RTL, left-to-right for LTR) driven strictly by real word timing.
    - Previous word settles to full color over 120 ms.
    - Zero per-frame list rebuilds: on ticker frames only the active line's word sweep repaints within its `RepaintBoundary`.
  - **State Transitions & Loading**:
    - States switch with an `AnimatedSwitcher` (250 ms fade).
    - Track change cross-fades out old lyrics and resets new lyrics scroll offset to top without a visual jump.
    - Loading displays calm dimmed placeholder lines (no fast spinner).
  - **Performance & Accessibility**:
    - Each line wrapped in a `RepaintBoundary`.
    - Reduce Motion ON: all durations become `Duration.zero`, scale stays 1.0, word sweep is replaced by instant color switch, scroll jumps immediately, and ticker is stopped.
- **Navigation & Full Screen**:
  - Accessible via `AppDestination.lyrics` with glass back button and metadata header.
  - Displayed alongside album artwork in `FullScreenView` when `showLyricsInFullScreen` is enabled (`isFullScreen: true`).
- **Settings Section**:
  - Source selector (5 modes).
  - Highlight mode selector (Line vs. Word).
  - Full screen toggle.
  - Playback seek step selector (1s, 2s, 5s).

---

## 8. Keyboard Transport & Space Chords
- **Global Space Handling**:
  - Triggers play/pause on **key up** if and only if Space was not used as a chord modifier.
  - While held down, repeat events do not trigger play/pause.
- **Space Chords**:
  - `Space + →`: Next track (skips once, marks chord used; releasing Space does not toggle play/pause).
  - `Space + ←`: Previous track (skips once, marks chord used; releasing Space does not toggle play/pause).
- **Seek Arrows (← / →)**:
  - Global scope seeking by `seekStepSeconds` (1s, 2s, or 5s; default 2s).
  - Coalesces rapid key repeat events every 120ms with a clean final seek on key up.
  - Clamps seek position between `0` and track duration.
  - Idle state: Seeking while playback is idle updates the armed resume position and updates the saved session.
- **Input & Control Safety**:
  - Text fields (`EditableText`), dialogs, modal popups, and sliders consume arrow and Space keys first.
  - Focus change and window blur immediately reset chord modifier state.

---

## 9. Decisions & Known Limitations
- **Decision**: Embedded lyrics are exposed through `RawTags.lyrics` via `AudioMetadataTagReader` directly without SQLite migrations or schema changes.
- **Decision**: Word timing is never estimated. When a track has line timestamps only, line highlighting is applied regardless of the user's `lyricsHighlight` preference.
- **Decision**: LRCLIB search results enforce a strict 3-second duration threshold to eliminate false positives on different edits or versions.
- **Known Limitation**: LRCLIB queries require an active internet connection. Offline playback uses cached results or local sidecars.
