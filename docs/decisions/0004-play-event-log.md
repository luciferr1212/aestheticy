# ADR 0004: Hardened Play-Event Log and Analytics Foundation

- **Status:** Accepted
- **Context:** `play_events` originally lacked identity links, playback origin context, crash-recovery state, and date-range aggregation queries needed for Stats, Wrapped, recommendations, and scrobbling.
- **Decision:** Add `track_uid`, `source` (`album`, `artist`, `playlist`, `favorites`, `search`, `queue`, `mini`, `unknown`), `session_id` (per-run random 128-bit hex), and `ended_reason` (`completed`, `skipped`, `stopped`, `error`, `interrupted`) to `userdata.play_events` indexed by `started_at_ms` and `track_uid`. `PlayRecorder` persists a periodic 30-second heartbeat (`updatePlayEventHeartbeat`) while playing, app startup closes open rows as `interrupted`, and `clearPlayEvents()` remains the sole deletion path.
- **Consequences:**
  - Crashes during playback lose at most 30 seconds of listened duration while preserving open sessions cleanly on next startup.
  - Additive analytics queries (`playEventsBetween`, `topTracksInRange`, `topArtistsInRange`, `topAlbumsInRange`, `listeningMinutesPerDay`, `distinctTracksFirstPlayedInRange`) group tracks by `COALESCE(track_uid, normalize_file_path(uri))` so history survives moves/renames.
  - Legacy `play_events` rows keep working safely in `safeReadOnly` fallback mode via schema-tolerant column selection.
