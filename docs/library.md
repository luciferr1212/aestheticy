# Library Data Layer Architecture & Documentation

## Overview

Aestheticy's Phase 2 introduces the local music library subsystem. Step 1 establishes a pure, decoupled data access layer backed by SQLite (`sqlite3` package) with strict separation of concerns:
- **No audio dependencies:** Domain models and database operations in `lib/library/` have zero dependencies on any audio engine or audio packages.
- **Pure Dart value types:** Domain models (`Track`, `LibraryFolder`) and read summaries (`AlbumSummary`, `ArtistSummary`) are immutable with `const` constructors.
- **Derived hierarchies:** Albums and artists are dynamically aggregated from track metadata via SQL queries rather than stored in redundant, denormalized tables.
- **Decoupled audio bridge:** A dedicated mapper extension (`Track.toAudioSource()`) maps library entities to pure Dart audio models without polluting the storage layer.

---

## SQLite Database Schema

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
┌───────────────────────────────┐
│            tracks             │
├───────────────────────────────┤
│ id           INTEGER PK AUTO  │
│ path         TEXT NOT NULL UQ │
│ folder_id    INTEGER NOT NULL │
│ title        TEXT             │
│ artist       TEXT             │
│ album_artist TEXT             │
│ album        TEXT             │
│ track_no     INTEGER          │
│ disc_no      INTEGER          │
│ year         INTEGER          │
│ duration_ms  INTEGER NOT NULL │
│ mtime_ms     INTEGER NOT NULL │
│ size_bytes   INTEGER NOT NULL │
│ cover_key    TEXT             │
│ added_at     INTEGER NOT NULL │
│ search_text  TEXT NOT NULL    │
└───────────────────────────────┘
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
   - `title`, `artist`, `album_artist`, `album`: Metadata tags parsed from the file.
   - `track_no`, `disc_no`, `year`: Numerical sequencing and release year.
   - `duration_ms`: Audio duration in milliseconds.
   - `mtime_ms`, `size_bytes`: Filesystem metadata used for change detection.
   - `cover_key`: Cached artwork identifier or relative cover file path.
   - `added_at`: Unix epoch timestamp when first inserted (preserved across tag updates).
   - `search_text`: Pre-normalized text containing title, artist, album, and album artist for fast search matching.

### Indexes & Pragmas

- **Pragmas:**
  - `PRAGMA foreign_keys = ON;` enforced on every opened connection to guarantee relational integrity.
  - `PRAGMA user_version` used for tracking applied database schema migrations.
- **Indexes:**
  - `idx_tracks_folder_id` on `tracks(folder_id)`: Accelerates cascaded operations and folder-scoped queries.
  - `idx_tracks_album` on `tracks(album)`: Speeds up album aggregation and filtering.
  - `idx_tracks_artist` on `tracks(artist)`: Speeds up artist aggregation and filtering.
  - `idx_tracks_search_text` on `tracks(search_text)`: Optimizes normalized search queries.
  - `idx_tracks_added_at` on `tracks(added_at)`: Enables efficient sorting by newly added tracks.

---

## Key Design Decisions

1. **Derived Albums & Artists:**
   - Instead of maintaining separate relational tables (`albums`, `artists`) with relational synchronization and desynchronization bugs when files are edited or deleted, summaries are aggregated on the fly using SQL `GROUP BY` queries.
   - Missing album or artist tags are cleanly normalized to `'Unknown Album'` and `'Unknown Artist'`.

2. **Batch Upserts in One Transaction:**
   - Scanners produce track batches that are ingested via `upsertTracks(List<Track>)` wrapped inside a single `BEGIN IMMEDIATE TRANSACTION`.
   - SQLite's `INSERT ... ON CONFLICT(path) DO UPDATE SET ...` updates all metadata, duration, modification times, and search indices while deliberately preserving the original `added_at` date.

3. **Multilingual Search Normalization (`TextNormalizer`):**
   - Standard SQLite builds do not bundle ICU extension collations for multilingual diacritic stripping.
   - Normalization is handled in pure Dart before storing in `search_text` and before executing queries:
     - **Arabic:** Strips all Tashkeel/Harakat diacritics (`[\u064B-\u065F\u0670\u0640]`), unifies Alef variants (`[آأإٱ]` -> `ا`), normalizes Alef Maqsura (`ى` -> `ي`), and normalizes Taa Marbuta (`ة` -> `ه`).
     - **Latin:** Replaces common accented characters (e.g. `é, è, ê` -> `e`, `ñ` -> `n`, `ß` -> `ss`).
     - **Case:** Lowercases all characters and normalizes multiple spaces.
   - **Known Limits:** Does not perform linguistic root extraction, stemming, or fuzzy phonetic matching. Queries perform substring matching (`LIKE %term%`).

4. **In-Memory and Custom Path Injection:**
   - `SqliteLibraryRepository.inMemory()` opens a temporary in-memory database (`sqlite3.openInMemory()`), enabling fast, isolated unit tests without disk access.
   - `SqliteLibraryRepository.openDefault()` resolves the OS-specific application support directory via `path_provider` (`%APPDATA%/Aestheticy/library.db` on Windows).

---

## How to Extend

1. **Phase 2, Step 2 (Folder Scanner & Metadata Reader):**
   - Implement background directory crawling (using `existingFiles(folderId)` for differential scanning).
   - Extract ID3/Vorbis/FLAC metadata tags in a background isolate.
   - Batch insert/update scanned tracks into `LibraryRepository.upsertTracks()`.
2. **Phase 2, Step 3 (Library UI):**
   - Consume `LibraryRepository.listAlbums()`, `listArtists()`, `listTracks()`, and `search()`.
   - Bind track selection to `Track.toAudioSource()` and pass to `PlaybackController`.
3. **Future Schema Migrations:**
   - Increment `kLibrarySchemaVersion` in `lib/library/migrations.dart`.
   - Add incremental migration routines (`_migrateToV2(db)`, etc.) inside `SchemaMigrator.apply()`.
