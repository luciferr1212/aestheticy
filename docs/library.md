# Library Data Layer Architecture & Documentation

## Overview

Aestheticy's Phase 2 introduces the local music library subsystem. Phase 2.5 establishes multi-artist support, normalized artist grouping, and manual artist merging backed by SQLite (`sqlite3` package) with strict separation of concerns:
- **No audio dependencies:** Domain models and database operations in `lib/library/` have zero dependencies on any audio engine or audio packages.
- **Pure Dart value types:** Domain models (`Track`, `LibraryFolder`) and read summaries (`AlbumSummary`, `ArtistSummary`) are immutable with `const` constructors.
- **Derived hierarchies & multi-artist mapping:** Albums are derived on the fly from track metadata. Artists are derived from `track_artists`, enabling duets and collaborations to appear under all involved artists without redundant duplicate files or combined artist entries.
- **Decoupled audio bridge:** A dedicated mapper extension (`Track.toAudioSource()`) maps library entities to pure Dart audio models without polluting the storage layer.

---

## SQLite Database Schema (Version 3)

```text
┌───────────────────────────────┐
│            folders            │
├───────────────────────────────┤
│ id           INTEGER PK AUTO  │
│ path         TEXT NOT NULL UQ │
│ last_scan_at INTEGER          │
└───────────────┬───────────────┘
                │ 1
                │
                │ * (ON DELETE CASCADE)
                ▼
┌───────────────────────────────┐        ┌───────────────────────────────────┐
│            tracks             │ 1    * │           track_artists           │
├───────────────────────────────┤───────►├───────────────────────────────────┤
│ id           INTEGER PK AUTO  │        │ track_id    INTEGER (FK CASCADE)  │
│ path         TEXT NOT NULL UQ │        │ artist_key  TEXT NOT NULL (INDEX) │
│ folder_id    INTEGER NOT NULL │        │ artist_name TEXT NOT NULL         │
│ title        TEXT             │        │ PRIMARY KEY (track_id, artist_key)│
│ artist       TEXT             │        └───────────────────────────────────┘
│ album_artist TEXT             │
│ album        TEXT             │        ┌───────────────────────────────────┐
│ track_no     INTEGER          │        │          artist_aliases           │
│ disc_no      INTEGER          │        ├───────────────────────────────────┤
│ year         INTEGER          │        │ alias_key      TEXT PRIMARY KEY   │
│ duration_ms  INTEGER NOT NULL │        │ canonical_key  TEXT NOT NULL      │
│ mtime_ms     INTEGER NOT NULL │        │ canonical_name TEXT NOT NULL      │
│ size_bytes   INTEGER NOT NULL │        └───────────────────────────────────┘
│ cover_key    TEXT             │
│ added_at     INTEGER NOT NULL │        ┌───────────────────────────────────┐
│ search_text  TEXT NOT NULL    │        │          artist_no_split          │
└───────────────────────────────┘        ├───────────────────────────────────┤
                                         │ artist_key  TEXT PRIMARY KEY      │
                                         │ artist_name TEXT NOT NULL         │
                                         └───────────────────────────────────┘

┌────────────────────────────────────────┐
│              play_events               │
├────────────────────────────────────────┤
│ id             INTEGER PK AUTOINCREMENT│
│ uri            TEXT NOT NULL (INDEX)   │
│ title          TEXT                    │
│ artist         TEXT                    │
│ album          TEXT                    │
│ album_artist   TEXT                    │
│ duration_ms    INTEGER                 │
│ started_at_ms  INTEGER NOT NULL (INDEX)│
│ listened_ms    INTEGER NOT NULL        │
│ counted        INTEGER NOT NULL (0/1)  │
│ completed      INTEGER NOT NULL (0/1)  │
└────────────────────────────────────────┘
```

### Tables

1. **`folders`**
   - `id`: Auto-incrementing primary key.
   - `path`: Normalized filesystem folder path (`UNIQUE`).
   - `last_scan_at`: Unix epoch millisecond timestamp of the last complete scan.

2. **`tracks`**
   - `id`: Auto-incrementing primary key.
   - `path`: Absolute filesystem path to the audio file (`UNIQUE`).
   - `folder_id`: Foreign key referencing `folders(id)` with `ON DELETE CASCADE`.
   - `title`, `artist`, `album_artist`, `album`: Metadata tags parsed from the file. Tracks preserve their original `artist` string for display.
   - `track_no`, `disc_no`, `year`: Numerical sequencing and release year.
   - `duration_ms`: Audio duration in milliseconds.
   - `mtime_ms`, `size_bytes`: Filesystem metadata used for change detection.
   - `cover_key`: Cached artwork identifier or relative cover file path.
   - `added_at`: Unix epoch timestamp when first inserted (preserved across tag updates).
   - `search_text`: Pre-normalized text containing title, artist, album, and album artist for fast search matching.

3. **`track_artists`**
   - `track_id`: Foreign key referencing `tracks(id)` with `ON DELETE CASCADE`.
   - `artist_key`: Normalized, canonical grouping key.
   - `artist_name`: Display name parsed from track metadata.
   - Primary key: `(track_id, artist_key)`.

4. **`artist_aliases`**
   - `alias_key`: Normalized source artist key being merged (`PRIMARY KEY`).
   - `canonical_key`: Normalized target canonical artist key.
   - `canonical_name`: Display name of the canonical artist.

5. **`artist_no_split`**
   - `artist_key`: Normalized artist string that must never be split (`PRIMARY KEY`).
   - `artist_name`: Original casing/display name.

6. **`play_events`** (Introduced in Schema v3)
   - `id`: Auto-incrementing primary key.
   - `uri`: Audio source identifier / path (`NOT NULL`).
   - `title`, `artist`, `album`, `album_artist`: Snapshot of track metadata at the time of playback. Preserved independently so history remains accurate even if tracks are moved, edited, or rescanned.
   - `duration_ms`: Track duration in milliseconds (nullable for unknown stream lengths).
   - `started_at_ms`: UTC epoch milliseconds timestamp when playback session started.
   - `listened_ms`: Cumulative playback time in milliseconds (excluding pauses, seeks, and skips).
   - `counted`: Integer boolean flag (`1` if scrobble/play threshold reached, `0` otherwise).
   - `completed`: Integer boolean flag (`1` if playback reached natural track completion, `0` otherwise).

### Indexes & Pragmas

- **Pragmas:**
  - `PRAGMA foreign_keys = ON;` enforced on every opened connection to guarantee relational integrity.
  - `PRAGMA user_version = 3` tracks the applied schema migration.
- **Indexes:**
  - `idx_tracks_folder_id` on `tracks(folder_id)`: Accelerates cascaded operations and folder-scoped queries.
  - `idx_tracks_album` on `tracks(album)`: Speeds up album aggregation and filtering.
  - `idx_tracks_artist` on `tracks(artist)`: Speeds up artist aggregation and filtering.
  - `idx_tracks_search_text` on `tracks(search_text)`: Optimizes normalized search queries.
  - `idx_tracks_added_at` on `tracks(added_at)`: Enables efficient sorting by newly added tracks.
  - `idx_track_artists_artist_key` on `track_artists(artist_key)`: Accelerates artist lookups and track aggregations.
  - `idx_play_events_started_at` on `play_events(started_at_ms)`: Fast retrieval of recent play history.
  - `idx_play_events_uri` on `play_events(uri)`: Accelerated history lookup by track URI.

---

## Multi-Artist Splitting & Normalization (`ArtistSplitter`)

Phase 2.5 introduces pure Dart artist splitting rules in `lib/library/artist_splitter.dart`:

1. **Unambiguous Separators (Always Split):**
   - Semicolon: `';'` (with optional surrounding whitespace).
   - Collaboration tokens (case-insensitive): `' feat. '`, `' feat '`, `' ft. '`, `' featuring '`.
   - Always split regardless of whether parts exist standalone in the library.

2. **Ambiguous Separators (Conditional Split):**
   - Separators: `' & '`, `' and '`, `' اند '`, `' و '`, `','`, `'،'`, `' + '`.
   - A string is split on them **only** when at least one resulting part is a standalone artist already present in the library (a distinct artist string in tracks that contains no ambiguous separator), compared via `TextNormalizer` and after alias resolution.
   - Other resulting parts simply become new artists.
   - Example: `'fairouz and kaza kaza'` splits into `'fairouz'` and `'kaza kaza'` if `'fairouz'` exists alone, even if `'kaza kaza'` does not exist alone.
   - Example: `'Simon & Garfunkel'` remains a single artist when neither `'Simon'` nor `'Garfunkel'` exists alone.

3. **Never-Split Rules:**
   - Slash `'/'` is **never** a separator (e.g. `'AC/DC'` remains intact).
   - Any entry in `artist_no_split` always wins and preserves the entire string as a single artist.

---

## Manual Artist Merging & Aliasing API

Artists tagged with different spellings or multilingual variations (e.g. Arabic `'فيروز'` vs English `'fairouz'`) can be merged manually:

- **Chain Flattening:** Merging chains (A -> B, B -> C) automatically resolve to the root canonical C (both A -> C and B -> C).
- **Cycle Rejection:** Circular aliases (e.g. merging C into A when A already points to C) and self-merges are rejected with `ArgumentError`.
- **Non-Destructive & Rescan-Resilient:** Aliases are stored in `artist_aliases` and never touch local audio files. Rebuilding or rescanning preserves merges.
- **Unmerging:** Calling `unmergeArtist(aliasKey)` removes the alias and restores the original separate artist entries.

---

## Listening History API (`play_events`)

Phase 3c introduces playback tracking and scrobbled history persisted via `LibraryRepository`:

- `insertPlayEvent(PlayEvent e)`: Inserts a newly active or scrobbled play event, returning the generated row id.
- `updatePlayEvent(int id, {required int listenedMs, required bool counted, required bool completed})`: Atomically updates duration listened and completion status when a playback session closes.
- `recentPlayEvents({int limit = 50})`: Retrieves recent listening sessions in reverse chronological order (`ORDER BY started_at_ms DESC`).
- `playEventCount({bool countedOnly = false})`: Returns total event count or scrobbled play count (`counted = 1`).
- `clearPlayEvents()`: Clears all historical playback records atomically within a transaction.

---

## Performance & Benchmark Note

- `LibraryRepository.rebuildArtistLinks()` operates on **DISTINCT** artist strings (`SELECT DISTINCT COALESCE(NULLIF(artist, ''), 'Unknown Artist') FROM tracks`), rather than evaluating splitting rules and regexes per track.
- In a library with 50,000 tracks, there are typically only ~1,000 to 3,000 distinct artist strings.
- Measured rebuild time for 20,000 tracks with ~3,000 distinct artist strings: ~480ms on desktop hardware within a single immediate SQLite transaction using indexed temporary split joins and pre-filtered pure Dart parsing.
- Links are rebuilt automatically once at the end of every scan session (including cancelled or failed scans, rather than per batch or per folder scan), after folder removal, and after any alias or no-split rule changes.

---

## Known Limitations

- **Flattened alias chain un-merging:** Un-merging B after A->B->C was flattened to A->C leaves A merged into C.
- **Bands containing ambiguous separators with solo artists:** If a band's name contains an ambiguous separator (such as `&` in `Simon & Garfunkel`) and one of its members also exists as a standalone solo artist in the library (e.g. solo tracks tagged `'Simon'`), the splitter will treat the band as a collaboration until the user selects `'Treat "Simon & Garfunkel" as one artist'` (which adds it to `artist_no_split`).
- **Album merging across artists:** Albums without an `Album Artist` tag merge across different artists when album names match (grouped by `COALESCE(NULLIF(album, ''), 'Unknown Album'), album_artist`).
- **Paged GROUP BY performance:** Derived aggregation via paged `GROUP BY` is O(n) per page; performance should be benchmarked and measured at 50k+ tracks.
- **ASCII-only collation:** SQLite `COLLATE NOCASE` only folds ASCII characters (A-Z to a-z), leaving non-ASCII uppercase/lowercase variations unfolded unless pre-normalized via `TextNormalizer`.
- **Nested parent and child folders:** Adding both a parent directory and a child directory together can cause tracks to reassign their parent `folder_id` between folders on consecutive rescans.

---

## UI Integration

The library presentation layer is built on top of `LibraryRepository` and `ScanService`, fully documented in [`docs/ui.md`](file:///e:/dev/aestheticy/docs/ui.md). All library screens (`AlbumsView`, `ArtistsView`, `TracksView`, `AlbumDetailView`, `ArtistDetailView`, `WelcomeView`) interact purely with the existing repository and scan service contracts without invoking direct SQLite queries or audio engine primitives.
