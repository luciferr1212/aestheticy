# ADR 0007: Composition Root and App Lifecycle Separation

- **Status:** Accepted
- **Context:** `lib/main.dart` grew to 1,159 lines by combining process entrypoint handling, ordered service startup, fallback error UIs, widget tree wiring, and main/mini window close orchestration in a single file, making startup order hard to test in isolation.
- **Decision:** Move application wiring into `lib/app/`:
  - `lib/app/app_services.dart`: plain immutable `AppServices` container holding long-lived services, stores, controllers, and callbacks.
  - `lib/app/app_bootstrap.dart`: `AppBootstrap.initialize(...)` executing the exact startup order (audio engine -> library -> settings -> audio settings apply -> EQ -> artist names -> session restore/saver -> interrupted play-event close & play recorder -> user collections -> platform services -> shutdown/media/sleep/tray-window controllers) with injectable factories for unit tests.
  - `lib/app/window_lifecycle.dart`: `WindowLifecycleCoordinator` owning `AppLifecycleListener` and mini-player close fallback while keeping `TrayWindowController` as the single close owner and ensuring `AppShutdownCoordinator.shutdown()` runs once.
  - `lib/app/init_error_apps.dart` and `lib/app/aestheticy_app.dart`: fallback init error apps and root `AestheticyApp` (re-exported by `lib/main.dart` for backwards compatibility).
  - `lib/main.dart`: slim 60-line entrypoint that sets up `runZonedGuarded`, logging, `AppBootstrap.initialize()`, and `runApp(...)`.
- **Consequences:**
  - Startup and shutdown order are directly testable via `test/app/app_bootstrap_test.dart` without touching native `libmpv` or user directories.
  - `lib/main.dart` drops below 100 lines and is removed from `kFileSizeAllowlist`.
