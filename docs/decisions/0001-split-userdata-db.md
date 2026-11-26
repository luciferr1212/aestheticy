# ADR 0001: Split User Data into `userdata.db`

- **Status:** Accepted
- **Context:** Previously `library.db` stored both rebuildable index tables (`folders`, `tracks`, `track_artists`) and irreplaceable user data (`favorites`, `ratings`, `playlists`, `playlist_items`, `play_events`, `artist_aliases`, `artist_no_split`), exposing user data to library resets and corruption.
- **Decision:** Keep rebuildable index data in `library.db` (`main`) and move all user data into a separate `userdata.db` attached as `userdata` on the same SQLite connection, with independent schema versioning (`kUserDataSchemaVersion = 1`), single-file transactions, WAL + `PRAGMA quick_check` protection, daily `VACUUM INTO` backups, and a crash-recoverable legacy migration state machine (`legacy_migration_state`).
- **Consequences:**
  - Library resets and folder removals cannot delete user data; rescanning re-links tracks by path.
  - Existing queries keep working via `ATTACH DATABASE`, while writes remain strictly single-file atomic.
  - Failed backups, verification mismatches, or locked/unreadable `userdata.db` enter `UserDataAccessMode.safeReadOnly` rather than risking data loss.
