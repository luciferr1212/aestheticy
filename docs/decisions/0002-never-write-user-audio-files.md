# ADR 0002: Never Write User Audio Files

- **Status:** Accepted
- **Context:** Desktop music players that write tags or metadata directly into user audio files risk silent corruption, broken file hashes, and unexpected library rescan churn on user-owned media.
- **Decision:** Aestheticy never opens user audio files for writing, never modifies audio tags, and enforces this in CI via `test/architecture/no_user_file_writes_test.dart`, restricting filesystem write/copy/rename/delete APIs in `lib/` strictly to app-support/cache directories and validated `.m3u`/`.m3u8` exports.
- **Consequences:**
  - All user edits (favorites, ratings, playlists, play history, artist merges/no-split rules, display translations, lyrics offsets) persist solely inside `userdata.db` or app-support JSON files.
  - User audio files remain bit-for-bit untouched across playback, scanning, and database recovery.
  - Any future tag editor must be proposed separately with explicit backup, atomic write, and verification.
