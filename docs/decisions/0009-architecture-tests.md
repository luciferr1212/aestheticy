# ADR 0009: Architecture Guard Tests

- **Status:** Accepted
- **Context:** Architectural boundaries (file size limits, UI-to-platform/SQLite separation, controller-only queue mutations, Windows plugin isolation, no silent catches, and no writes to user audio files) erode over time unless enforced automatically in CI.
- **Decision:** Maintain static source-scanning tests under `test/architecture/`:
  - `file_size_budget_test.dart`: enforces <= 1,000 lines per file in `lib/`; `main.dart` and `playback_controller.dart` are removed from `kFileSizeAllowlist`, leaving only `lib/ui/l10n/app_strings.dart`.
  - `ui_layer_boundaries_test.dart`: forbids `lib/ui/` from importing `lib/platform`, `lib/library/sqlite*`, `package:sqlite3`, `package:mpv_audio_kit`, `package:smtc_windows`, `package:tray_manager`, or `package:window_manager`, with an explicit, stale-checked allowlist (`mini_player_controller.dart` and `app_shell.dart` for abstract `WindowService` only).
  - `no_direct_queue_mutation_in_ui_test.dart`: forbids `lib/ui/` from mutating `PlaybackQueue` directly (all queue mutations route through `PlaybackController`).
  - `windows_platform_isolation_test.dart`: ensures files under `lib/platform/windows/` are imported only from `lib/platform/platform_services.dart` or `lib/app/`, and Windows-only plugin packages are imported only inside `lib/platform/windows/`.
  - Existing guards retained: `no_silent_catch_test.dart` (empty allowlist), `no_user_file_writes_test.dart`, and `no_real_support_dir_in_tests_test.dart`.
- **Consequences:**
  - Layering regressions fail fast during `flutter test` with exact file/line diagnostics.
  - Stale allowlist entries fail automatically so exceptions shrink over time rather than accumulating.
