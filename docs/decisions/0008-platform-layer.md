# ADR 0008: Cross-OS Platform Layer and Feature Flags

- **Status:** Accepted
- **Context:** Windows-specific services (`SmtcMediaSession`, `Win32SleepInhibitor`, `WindowsTrayService`, `WindowsWindowService`, `openFolderInExplorer`) were previously instantiated directly inside `lib/main.dart`, coupling startup code to Windows implementations and lacking a clean interface for future file-extension association or non-Windows CI analysis.
- **Decision:**
  - Define abstract platform interfaces under `lib/platform/`: `TrayService`, `WindowService`, `MediaSessionService`, `SleepInhibitor`, and `FileAssociationService`.
  - Keep all Windows-specific code strictly under `lib/platform/windows/` (including `WindowsFileAssociationService` placeholder).
  - Provide production no-op fallbacks (`lib/platform/noop_platform_services.dart`) and a single OS selector (`lib/platform/platform_services.dart`: `PlatformServices.create()`) choosing Windows implementations when `Platform.isWindows` is true and no-op fallbacks otherwise.
  - Add typed `FeatureFlags` (`lib/app/feature_flags.dart`: `canvas`, `jam`, `tagEditor`, `scrobbling`, `videoConcerts`, all defaulting to `false`), overridable via a hidden `featureFlags` map in `AppSettings` (`ui_settings.json`) with no UI exposed.
- **Consequences:**
  - The repository can be analyzed and tested cleanly on macOS/Linux CI without loading Windows plugins.
  - Future Phase 5+ features stay gated behind typed `false`-by-default flags until ready.
