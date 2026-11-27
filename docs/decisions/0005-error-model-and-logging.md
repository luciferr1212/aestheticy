# ADR 0005: Error Model, Rotating Privacy Logger, and No-Silent-Catch Rule

- **Status:** Accepted
- **Context:** Failures across SQLite stores, file persistence, playback, and platform integrations previously used ad-hoc try/catch blocks—some silently swallowing exceptions or risking privacy-sensitive paths in logs, and without a shared typed failure contract for user-visible operations.
- **Decision:**
  - **Typed error model (`lib/core/result.dart`):** Introduce `Result<T>` (`Ok<T>` / `Err<T>`) and sealed `AppError` subclasses (`IoFailure`, `DatabaseFailure`, `NetworkFailure`, `ParseFailure`, `PlatformFailure`) carrying a localization key (`messageKey`), optional placeholder parameters, technical diagnostic detail, and stack trace. Wire initial pilots in M3U import/export (`M3u`) and adding a library folder (`ScanService.addFolderResult` / `FolderManagementSheet`).
  - **Centralized UI feedback (`lib/ui/common/error_presenter.dart`):** Render calm localized feedback (`SnackBar` with optional Retry or Open Logs actions and `ErrorPresenter.banner`) via `AppStrings` (`en` + `ar`).
  - **Rotating privacy logger (`lib/diagnostics/app_logger.dart`):** Support `LogLevel` (`debug`, `info`, `warn`, `error`), `minLevel` filtering, injectable `customSink`, `AppLogger.swallow(...)` for intentional non-fatal swallowing, 1 MB rolling rotation keeping at most 5 files (`aestheticy.log` and `.1`..`.4`) using exact filename regex matching, automatic path/token/user-name redaction, and safe in-memory no-op when disk logging is uninitialized.
  - **No-silent-catch enforcement (`test/architecture/no_silent_catch_test.dart`):** Enforce an empty allowlist (`kSilentCatchAllowlist = {}`) across all of `lib/`. Every `catch` / `on` clause must classify explicitly as:
    - `(a)` safe ignore using a specific one-line `// ignore-silent: <reason>` strictly for deleting self-created temp files, closing/disposing an already-failing resource, reading an optional cache rebuilt on miss, or non-recursive `AppLogger` fallbacks;
    - `(b)` logged and recovered/surfaced via `AppLogger` + `ErrorPresenter` or `onError` where user-visible (never rethrowing inside playback, audio engine, or fade callbacks);
    - `(c)` logged/rolled back and rethrown only where continuing would corrupt state and an explicit outer boundary catches it.
- **Consequences:**
  - Silent error swallowing and stale/corrupt catch regressions fail CI architecture tests automatically.
  - Log archives stay bounded to ~5 MB on disk without leaking user directories or secrets.
