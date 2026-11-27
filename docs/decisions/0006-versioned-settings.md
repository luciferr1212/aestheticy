# ADR 0006: Versioned JSON Settings and Persistent Stores

- **Status:** Accepted
- **Context:** JSON configuration stores (`SettingsStore`, `EqStore`, `ArtistNameStore`, `LyricsOffsetStore`, `SessionStore`) wrote unversioned JSON with inconsistent atomic/temp handling, overwrote single `.bad` files on corruption, could drop unknown keys from newer schemas, and kept no rolling backup copies.
- **Decision:** Introduce `VersionedJsonStoreHelper` (`lib/features/persistence/versioned_json_store.dart`) alongside `AtomicFileWriter` across all five persistent JSON stores (`ui_settings.json`, `eq_settings.json`, `artist_display_names.json`, `lyrics_offsets.json`, `session.json`):
  - **Schema versioning & ordered migrations:** Every persisted file includes top-level `schemaVersion` (v1). Unversioned v0 files (including legacy list format in `artist_display_names.json` and legacy `smoothTransitions` boolean in `ui_settings.json`) migrate step-by-step (`v -> v + 1`) on load.
  - **Forward compatibility:** Unknown top-level keys from newer application versions are captured on load and merged back into the saved JSON payload on write.
  - **Corrupt quarantine:** Unreadable or unparseable JSON logs a `warn` message and atomically renames the corrupt file to `<filename>.bad-<yyyyMMdd-HHmmss>` before falling back cleanly to defaults.
  - **Rolling backups:** Every successful save writes a timestamped snapshot under `<supportDir>/backups/settings/<stem>-<yyyyMMdd-HHmmss>.json` using temp+rename and prunes only older files matching that exact regex down to the newest 3 copies.
- **Consequences:**
  - Configuration downgrades and upgrades preserve forward fields without data loss or accidental field erasure.
  - Repeated corruption events keep distinct timestamped `.bad-*` forensic copies while rolling backups give users recoverable recent states without touching user music folders.
