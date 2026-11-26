# ADR 0003: Stable Track Identity and Relink Rules

- **Status:** Accepted
- **Context:** Keying `favorites`, `ratings`, `playlist_items`, and `play_events` strictly by file path loses or orphans user data whenever audio files are moved, renamed, or on temporarily disconnected drives.
- **Decision:** Add `userdata.track_identity` (`uid` 128-bit hex PK, path, size, duration, `TextNormalizer` title/artist/album keys, `first_seen_ms`, `last_seen_ms`, `missing_since_ms`) in `userdata.db` v2 with pre-migration backup, scan-end and direct-upsert reconciliation, and backfill for legacy user paths. Missing identities relink in one `userdata` transaction only on unique exact `(size_bytes, duration_ms)` or unique `(title_key, artist_key, album_key)` with `|duration delta| <= 1500` ms, keeping the newest row on `favorites`/`ratings` PK collisions and logging & skipping ambiguous candidates.
- **Consequences:**
  - Favorites, ratings, playlists, and play history follow moved/renamed files without mutating user audio files.
  - Temporarily offline drives set `missing_since_ms` cleanly instead of deleting user data, clearing it when the file returns.
  - `LibraryScanner` defers new-track identity creation until scan completion (`upsertTracksFromScan`) so moves within one scan always relink accurately.
