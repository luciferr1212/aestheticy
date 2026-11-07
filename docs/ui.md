# UI Foundation Architecture & Design System Documentation

## Overview

Phase 3a establishes the design system, theme tokens, glass rendering system, settings store, localization foundation, and developer Design Gallery for Aestheticy.

---

## 1. Directory Structure

```text
lib/ui/
├── artist_names/
│   ├── artist_name_scope.dart        # Inherited notifier exposing ArtistNameStore
│   └── artist_name_store.dart        # User translations store & display resolver
├── audio_panels/
│   ├── audio_panels_view.dart        # Combined side-by-side / stacked EQ & Signal Path
│   ├── eq_controller.dart            # Equalizer controller with 50ms trailing engine throttle
│   ├── eq_scope.dart                 # Inherited notifier exposing EqController
│   ├── eq_store.dart                 # eq_settings.json persistence with built-in presets
│   └── signal_path_model.dart        # Pure 4-stage pipeline builder and text export
├── gallery/
│   ├── design_gallery_screen.dart    # Full-screen developer gallery (Ctrl+Shift+G)
│   └── performance_metrics.dart      # Pure calculations for frame timings & export
├── glass/
│   ├── glass_blur_budget.dart        # Global budget enforcer (max 6 concurrent blurs)
│   ├── glass_button.dart             # GlassIconButton & GlassPillButton
│   ├── glass_quality.dart            # Quality tiers: full (flagship default), light, off
│   ├── glass_scope.dart              # Inherited notifier exposing GlassController
│   └── glass_surface.dart            # Adaptive surface widget (BackdropFilter in full)
├── l10n/
│   ├── app_strings.dart              # Pure Dart EN & AR dictionary & textDirectionFor()
│   ├── locale_controller.dart        # Ambient Locale & TextDirection coordinator
│   └── number_format.dart            # Digit localizer, duration and count formatting
├── now_playing/
│   ├── cover_palette.dart            # 12-hue bin palette extractor with LRU caching
│   ├── full_screen_view.dart         # Immersive window fill with ambient canvas blobs
│   └── now_playing_view.dart         # Desktop two-column player with isolated seekbar
├── quick_search/
│   └── quick_search_overlay.dart     # Global floating Ctrl+K overlay with section caps
├── settings/
│   ├── app_settings.dart             # Immutable settings model with tolerant parser
│   ├── app_shortcuts.dart            # Single source of truth for keyboard shortcuts
│   ├── audio_settings_applier.dart   # Audio settings applier with typed error enum
│   ├── settings_scope.dart           # Inherited notifier exposing SettingsStore
│   ├── settings_store.dart           # Debounced atomic JSON persistence
│   └── settings_view.dart            # Central configuration screen (max 1 blur surface)
├── shell/
│   ├── app_navigator.dart            # Pure Dart hierarchical navigation controller
│   └── app_shell.dart                # Desktop application shell with adaptive glass
└── theme/
    ├── app_colors.dart               # Static WCAG-compliant color palette
    ├── app_spacing.dart              # Standard spacing and border radii
    ├── app_theme.dart                # Material 3 dark theme builder
    ├── app_typography.dart           # Windows desktop font family & text scale
    └── font_manager.dart             # Runtime FontManifest parser with system fallback
```

---

## 2. Design Tokens Table

### Colors & WCAG Contrast Compliance

All colors were verified against WCAG 2.1 relative luminance standards:

| Token | Value | Opacity / Role | Measured Contrast on Base | WCAG Compliance |
|---|---|---|---|---|
| `base` | `#0F1115` | 100% background | — | Base target |
| `surface` | `#1D1C25` | 100% elevated card surface | 1.15:1 | Non-text container |
| `text` | `#E9E7F0` | Primary high-contrast text | 15.4:1 | AAA (>= 7.0:1) |
| `textSecondary` | `#A9A7B3` | Secondary metadata text | 7.8:1 | AA (>= 4.5:1) |
| `textMuted` | `#8E8C99` | Captions & inactive labels | 5.6:1 | AA (>= 3.0:1) |
| `accent` | `#D3C9EA` | Lavender highlight & controls | 12.3:1 | AA (>= 4.5:1) |
| `accentSoft` | `#C9BEE4` | Soft secondary accent | 11.2:1 | AA (>= 4.5:1) |
| `accentFill` | `Color(0x42D3C9EA)` | 26% alpha accent fill | — | Translucent fill |
| `border` | `Color(0x1FFFFFFF)` | 12% alpha white border | — | Surface boundary |
| `borderSubtle` | `Color(0x14FFFFFF)` | 8% alpha white border | — | Inactive boundary |
| `fillGlass` | `Color(0x0CFFFFFF)` | 4.5% alpha white fill | — | Full-tier glass |
| `fillControl` | `Color(0x12FFFFFF)` | 7% alpha white fill | — | Glass control buttons |
| `danger` | `#D9908F` | Soft muted coral | 7.2:1 | AA (>= 4.5:1) |
| `success` | `#A9C4AE` | Soft muted sage | 9.4:1 | AA (>= 4.5:1) |

### Spacing & Corner Radii

- **Spacing:** `s4` (4 dp), `s8` (8 dp), `s12` (12 dp), `s16` (16 dp), `s24` (24 dp), `s32` (32 dp).
- **Radii:** `r10` (10 dp), `r12` (12 dp), `r16` (16 dp), `r22` (22 dp - default glass surface), `r26` (26 dp), `pill` (999 dp).

### Typography Scale

- **Font Family:** `'Segoe UI Variable'`, `'Segoe UI'`.
- **Font Fallback:** `['Segoe UI', 'Tahoma', 'Arial']` (renders Arabic seamlessly without external font downloads).
- **Display:** 32.0 dp / w600 / height 1.25.
- **Title:** 20.0 dp / w600 / height 1.30.
- **Body:** 14.0 dp / w400 / height 1.43.
- **BodyStrong:** 14.0 dp / w600 / height 1.43.
- **Caption:** 12.5 dp / w400 / height 1.36.
- **Micro:** 11.0 dp / w500 / letterSpacing 0.8 / height 1.36 (for uppercase labels).

---

## 3. Glass System & Blur Budget

The glass system prioritizes a flagship-first design with optional fallbacks across three quality tiers:

1. **`full` (Flagship Default):**
   - Composes a 1.5x saturation boost with Gaussian blur: `ImageFilter.compose(outer: ColorFilter.matrix(saturation 1.5), inner: ImageFilter.blur(sigmaX: 30, sigmaY: 30))`.
   - 4.5% alpha translucent fill with 1px 12% white border and a subtle top inner highlight.
   - Enforces the **Glass Blur Budget** (`kMaxBlurredSurfaces = 6`): `GlassBlurBudget.instance.tryAcquire(this)`. At most **6** blurred surfaces may be active concurrently across the entire app.
   - If budget acquisition fails (e.g. 7th surface mounted), it gracefully falls back to `light` rendering (never blur a 7th surface).
2. **`light` (Performance Fallback):**
   - Zero `BackdropFilter` and zero GPU blur overhead.
   - Opaque vertical simulated gradient: `rgba(52, 50, 62, 0.84)` to `rgba(32, 31, 40, 0.88)`.
   - 1px 10% white border and soft drop shadow (blur 28, offset y 10, black 28% alpha).
3. **`off` (Maximum Compatibility):**
   - Solid flat `AppColors.surface`, 1px subtle border, zero drop shadow.

Every surface is wrapped in a `RepaintBoundary` to isolate paint invalidation. Translucency is strictly prohibited without real blur; only `full` is translucent.

---

## 4. Glass Control Buttons

Two standard button widgets sit on top of glass surfaces (`GlassIconButton` and `GlassPillButton`):
- **Never invoke blur:** They never use `BackdropFilter` and never request `GlassBlurBudget`.
- **Standard look:** 7% alpha white fill (`AppColors.fillControl`) and 1px 12% alpha border (`AppColors.border`).
- **Interactive states:**
  - Hover: +4% alpha fill (100ms fade).
  - Pressed: -2% alpha fill.
  - Focus: 2px solid accent ring (accessible via Tab and Enter/Space keyboard navigation).
  - Disabled: 40% overall opacity with no hover or press effects.
- **Variants:**
  - `normal`: standard translucent control.
  - `primary`: strictly reserved for Play/Pause transport. 26% alpha accent fill (`AppColors.accentFill`), 45% alpha accent border.
  - `selected`: toggle state (e.g. active shuffle/repeat), accent fill with accent icon.
- **GlassQuality off:** Renders with a solid 6% lightened surface fill (`#282733`) and zero transparency.
- **Accessibility:** `tooltip` and `semanticLabel` are mandatory parameters on every icon button.

---

## 5. Settings Model & Persistence

- **Model:** Immutable `AppSettings` with value equality, `copyWith`, `toJson`, and tolerant `fromJson`.
- **Keys & Defaults:**
  - `language`: `'en'` (`'en'` or `'ar'`).
  - `userName`: `''`.
  - `glassQuality`: `GlassQuality.full` (`'full'`, `'light'`, or `'off'`).
  - `reduceMotion`: `false`.
  - `sidebarCompact`: `false`.
  - `libraryViewMode`: `'square'` (`'square'`, `'wide'`, or `'list'`).
  - `albumSort`: `'recentlyAdded'`.
  - `trackSort`: `'title'`.
- **Storage Location:** `ui_settings.json` located in `getApplicationSupportDirectory()/Aestheticy/` (reusing the same directory path strategy as `SqliteLibraryRepository`).
- **Atomic & Debounced:** Writes are debounced by 400ms, written to `ui_settings.json.tmp`, and atomically renamed.
- **Resilience:** If the file is missing or corrupted, defaults are loaded and the corrupted file is renamed to `ui_settings.json.bad`. Writes never crash or throw to the UI.
- **Single Source of Truth:** `SettingsStore.bindGlassController(...)` synchronizes `GlassController` with persistent settings.

---

## 6. Localization & RTL Rules

- Pure Dart static lookup (`AppStrings.t(key, language: ...)`), no external packages or code generation.
- Complete 1:1 parity between English (`en`) and Modern Standard Arabic (`ar`).
- **Layout Rules:**
  - Always use `EdgeInsetsDirectional`, `AlignmentDirectional`, `BorderRadiusDirectional`, `PositionedDirectional`, and `TextAlign.start`/`end`. Never hardcode left or right.
  - Directional navigation icons (e.g. chevrons, back arrows) flip in RTL; non-directional icons (e.g. play, search, volume) never flip.
  - Media transport controls and seek bars are explicitly wrapped in `Directionality(textDirection: TextDirection.ltr)` to preserve left-to-right temporal progression across all languages.
  - Audio file metadata (track titles, artist names, album titles) is NEVER translated. It is rendered with its own intrinsic direction computed via `textDirectionFor(String)` by inspecting the first strong directional character.
  - Numbers and durations remain in standard Western digits (e.g. `1:24`).

---

## 7. Design Gallery

- **Shortcut:** Press `Ctrl + Shift + G` anywhere in the app to open the Design Gallery.
- **Availability:** Active across **ALL** build modes (Debug, Profile, and Release).
- **Dismissal:** Press `Esc` or the close icon in the app bar.
- **Features:**
  1. Color palette and typography token samples.
  2. Live `GlassSurface` specimens (Full, Light, Off) with an interactive quality switcher.
  3. All button variants (Normal, Primary, Selected, Disabled) across Small (32dp), Medium (40dp), and Large (56dp).
  4. Language switcher (English / Arabic) with bidirectional sample text rendered using `textDirectionFor()`.
  5. Reduce motion toggle.
  6. **Performance Panel:** Captures frame timings via `SchedulerBinding.instance.addTimingsCallback` across a rolling 300-frame window. Displays average and p95 build/raster times, percent of slow frames (> 16.7ms), quality tier, and build mode. Includes "Reset" and "Copy results" buttons.
  7. **Animate Test Toggle:** Runs a worst-case continuous moving blob under glass surfaces for benchmarking. Automatically forced off when `reduceMotion` is active.

---

## 8. App Shell Structure & Navigation

### Shell Layout (`lib/ui/shell/`)
The desktop shell orchestrates five core architectural components:
1. **Ambient Background (`AmbientBackground`):** Static calm background painted with a single `CustomPainter` inside a dedicated `RepaintBoundary`. Combines base `#0F1115` with two soft radial gradients: muted purple `#6B5B7B` (45% alpha) and muted teal `#3F6C7A` (30% alpha) anchored at opposite corners.
2. **Sidebar Navigation (`Sidebar`):** `GlassSurface` (blur slot 1). Expands to 208 dp and compacts to 64 dp with a 150ms animation (instant when `reduceMotion` is true). Compact state is persisted in `AppSettings.sidebarCompact`. Contains:
   - Brand Header: "Aestheticy" with "by mido" credit.
   - Section "Library": Albums, Artists, Tracks.
   - Section "Yours": Playlists, Favorites, Recently played (disabled placeholders with "Soon" label).
   - Section "Tools": Audio Lab (enabled, direct access to `AudioLabScreen`), Last.fm (disabled placeholder with "Soon" label, neutral icon, no external links).
   - Bottom items: Folders (triggers folder management sheet) and Settings (disabled placeholder with "Soon" label).
3. **Dynamic Content Area:** Switches between destinations without blur overhead or unnecessary rebuilds (120ms fade, instant when `reduceMotion` is true).
4. **Scanning Progress Panel (`ScanningPanel`):** Floats at the top of content when `ScanService.isScanning` is true, displaying current phase, file counts, and an active Cancel button.
5. **Bottom Now-Playing Bar (`BottomNowPlayingBar`):** Floating `GlassSurface` (blur slot 2, height 84 dp, radius 24 dp) anchored with 16 dp margins. Features:
   - Start side: Cover thumbnail (52x52, radius 10), track title, artist name, directional expand chevron; whole area taps to stub SnackBar ("Soon").
   - Center side: Directionality forced to LTR; previous, primary play/pause, next buttons, and an isolated seekbar with time labels. Seek position updates rebuild only the seek slider leaf.
   - End side: Volume button (opens Glass popup with volume slider), lyrics (disabled), queue (disabled), equalizer (disabled), full screen (disabled).

### Navigation Model (`AppNavigator`)
Pure Dart `ChangeNotifier` managing `AppDestination`:
`albums`, `artists`, `tracks`, `albumDetail`, `artistDetail`, `audioLab`, `folders`.
Detail screens retain selected entity IDs and support back navigation returning cleanly to previous list states.

---

## 9. Library Screens (`lib/ui/library/`)

All library screens consume the existing `LibraryRepository` and `ScanService` interfaces directly without mocking or fake datasets:
1. **Welcome View (`WelcomeView`):** Displayed when library folders are empty. Greets the user, provides an optional name field (shown only when `userName` is empty; trimmed and clamped to 40 characters), and an "Add folder" button to initiate library scanning.
2. **Library Header (`LibraryHeader`):** Common header for list views featuring dynamic greeting (calculated from `greetingKey(DateTime.now())`), display title, debounced search field (250ms debounce with Ctrl+K chip hint), item count badge, sort dropdown chip (persisted to settings), and view mode toggle on Albums view.
3. **Albums View (`AlbumsView`):** Virtualized grid supporting `square` (cover tile with metadata below), `wide` (horizontal card with cover on start side), and `list` (compact table row). Retrieves decoded artwork from `CoverCache` and falls back to a calm gradient placeholder. Tapping an album navigates to `AlbumDetailView`.
4. **Artists View (`ArtistsView`):** Virtualized grid of circular avatars with deterministic calm gradients derived from artist name hash. Displays merged badges for aliases and provides a context menu with "Merge into…", "Artist rules...", and disabled "Choose picture" stubs. Tapping an artist navigates to `ArtistDetailView`.
5. **Tracks View (`TracksView`):** Virtualized fixed-height table rendering track title, artist, album, and duration. Currently playing track is highlighted with accent tint and animated 3-bar equalizer (static when paused or `reduceMotion` is true). Double-clicking starts playback from that track.
6. **Album Detail (`AlbumDetailView`):** Large 220 dp artwork, album title, artist, release year, track count, primary Play and normal Shuffle buttons, and full album tracklist.
7. **Artist Detail (`ArtistDetailView`):** Large circular avatar, artist name, track count, Play and Shuffle actions, back button, and complete artist tracklist.

---

## 10. Decisions

- **D1:** All color tokens met or exceeded WCAG AAA and AA contrast ratios on `#0F1115` without requiring adjustments (`text` at 15.4:1, `textSecondary` at 7.8:1, `textMuted` at 5.6:1, `accent` at 12.3:1).
- **D2:** `GlassController` binds to `SettingsStore` as the single source of truth, guaranteeing consistent quality across app restarts.
- **D3:** `AppSettings.fromJson` validates string tokens against known sets and strictly falls back to field defaults on invalid values while ignoring unexpected keys.
- **D4:** Responsive `Wrap` layouts are used in `DesignGalleryScreen` to guarantee zero `RenderFlex` overflows on compact test or split viewports.
- **D5:** `textDirectionFor()` ignores whitespace, punctuation, brackets, and digits to determine direction strictly from the first strong character.
- **D6:** Flagship-first default: moved default glass quality to `GlassQuality.full` everywhere with saturation 1.5 boost composed with 30px blur, and expanded `GlassBlurBudget` capacity from 2 to 6 (`kMaxBlurredSurfaces = 6`). Beyond 6, surfaces fall back to `light`.
- **D7:** Pure Dart navigation model with `AppNavigator` avoids heavy router dependencies and supports seamless back navigation from detail views to list screens.
- **D8:** Overlay `Directionality` moved to `MaterialApp.builder` wrapping the root `Navigator`, ensuring tooltips, popup menus, dialogs, and snackbars automatically inherit RTL layout in Arabic.
- **D9:** Leaf-level stream listeners (`ValueListenableBuilder`/`StreamBuilder`) for player seekbar isolate position ticks, ensuring 0 rebuilds for metadata and the parent now-playing bar.
- **D10:** Disabled placeholders for upcoming features (Last.fm, Playlists, Favorites, Recently Played, Equalizer, Queue, Lyrics) retain accessible tooltips and 40% muted opacity without invoking external web browsers, processes, or network requests.
- **D11:** First launch onboarding (`WelcomeView`) shows username entry only when `userName` is empty in settings, clamping to 40 characters and immediately updating the top greeting.
- **D12:** `CoverPalette` extracts primary, secondary, and tertiary tones from album artwork using 12 hue bins (30° each). Target saturation is clamped to `<= 0.54` (ensuring 8-bit quantization never exceeds 0.55) and lightness is bounded between `0.25` and `0.60`. Multi-color extraction is cached in a 32-entry LRU cache, with deterministic hue shift derivation when fewer than 3 valid bins exist.
- **D13:** `GlassDensity.clear` provides a lighter glass surface variant with 22px blur and 0.08 tint in `full` mode (0.45 alpha in `light` mode), ideal for floating decorative elements and HUD overlays while respecting blur budget limits.
- **D14:** Ambient blob animation in `FullScreenView` runs on a single CustomPainter inside a dedicated `RepaintBoundary` capped to ~30 fps (`elapsed - lastTick >= 33ms`). The ticker automatically stops when `reduceMotion` is true or when app lifecycle enters `inactive`/`paused`, resuming on `resumed`.
- **D15:** `AppStrings.t` supports parameterized interpolation `{arg}` with fallback to the placeholder tag if an argument is omitted, verified by a strict source-code scanner test preventing unlocalized strings in `lib/ui/`.
- **D16:** Full-screen mode is implemented as an immersive in-app window fill that replaces the shell layout (releasing bottom bar blur budget slots) rather than an OS-level window resize or maximize. Back navigation and `Esc` return cleanly to the previous destination (`nowPlaying` or previous library view).

---

## 11. Now Playing & Full Screen Architecture (`lib/ui/now_playing/`)

### Now Playing View (`NowPlayingView`)
- **Layout:** Desktop two-column layout:
  - Start column (flex 5): Large 360dp album artwork with soft drop shadow, radial ambient glow matching extracted cover palette, track title and artist with directional text handling, isolated ticking seekbar, strictly LTR transport controls row (shuffle, previous, play/pause, next, repeat mode with '1' badge when `RepeatMode.one`), and volume slider.
  - End column (flex 5): Glass card containing Up Next queue with clickable tracks, "Clear upcoming" button, audio stream info pill (`AudioStreamInfo` container, codec, sample rate, bit depth, channels, bitrate, and lossless badge), and lyrics placeholder tab.
- **Top Controls:** Back navigation button and full-screen button (`AppDestination.fullScreen`).

### Full Screen View (`FullScreenView`)
- **Immersive Window Fill:** Completely fills the application window; hides sidebar and bottom bar, freeing blur budget slots.
- **Ambient Animated Blobs:** 3 large drifting color blobs driven by extracted `CoverPalette` and painted by `_BlobPainter` with `MaskFilter.blur(120-130)`. Throttled to ~30 fps and observed by `WidgetsBindingObserver` to pause when minimized or out of focus.
- **Floating Glass Shapes:** 2 clear decorative `GlassSurface` panels (2 blur slots) drifting across the background, toggled on/off via top bar button and persisted in `AppSettings.fullScreenGlassShapes`.
- **Slender Progress Line:** 2dp high progress line spanning the entire bottom edge with hover time labels.
- **Auto-Fading Top Controls:** Top bar with "by mido" credit, glass shapes toggle, and exit button fades out after 3 seconds of mouse inactivity, reappearing on mouse motion. Keyboard navigation supports `Space` (toggle play/pause), `ArrowLeft`/`ArrowRight` (seek -5s/+5s), and `Esc` (exit to previous view).

---

## 12. Settings Screen & System Controls (`lib/ui/settings/`)

### Settings View (`SettingsView`)
- **Navigation:** Accessible from the sidebar Settings tile; `Esc` or the back icon button navigates back to the previous list view (`AppNavigator.goBack()`).
- **Layout & Blur Budget:** Scrollable page with max width 880dp centered horizontally. Exactly **one** `GlassSurface` blurred container is used for the entire card (`density: regular`), while all interior section cards are plain translucent containers (`AppColors.fillGlass`, zero blur), strictly respecting the concurrent 6-surface blur budget.
- **Sections (in order):**
  1. **Language and Profile:** Live interface language toggle (English / العربية) flipping directionality and strings instantly; Arabic numerals toggle (enabled strictly when Arabic is selected); User display name text field (trimmed, clamped to 40 characters).
  2. **Appearance:** Glass quality segmented selector (Full / Light / Off) with explanatory captions; Reduce motion switch; "Glass shapes in full screen" toggle; Text size segmented selector (Small 0.92x / Normal 1.0x / Large 1.10x).
  3. **Fonts:** Font picker reading registered families dynamically from `FontManifest.json` at runtime via `FontManager`. Shows "System default" (`Segoe UI Variable` stack) and registered families. Includes live preview specimen `Golden Hour · فيروز · 1:24`.
  4. **Artist Names:** Display name mode selector: `asTagged` (raw tag strings), `followLanguage` (Arabic replacement if Arabic interface, raw otherwise), or `alwaysArabic` (uses Arabic replacement if known). Includes list of custom mappings with add/edit dialog, diacritic/case-insensitive exact whole-name matching, and delete actions.
  5. **Audio:** Output device dropdown populated from `engine.devices` with refresh button; Exclusive mode toggle (disabled with helpful explanation when `engine.capabilities.exclusiveMode` is false); ReplayGain mode segmented selector (Off / Track / Album); ReplayGain preamp slider (-15 to +15 dB, clamped, displaying dB value); Crossfade row disabled with "Soon" badge. All audio adjustments go through `AudioSettingsApplier` and surface localized inline errors on failure.
  6. **Library:** Music folders row with "Manage" button navigating to the folder manager; live read-only folder count and track count badges.
  7. **Shortcuts:** Canonical read-only list derived from `kAppShortcuts` representing only implemented key bindings in the app (`Space`, `Esc`, `←`, `→`, `Ctrl + Shift + G`, `Ctrl + K`). Each shortcut displays its localized scope badge (`Global` vs `Now Playing`).
  8. **About:** Minimalist branding card with "Aestheticy" and "by mido" credit text.

---

## 13. Bundled Fonts Discovery (`lib/ui/theme/font_manager.dart`)

- **Discovery Mechanism:** `FontManager.loadAvailableFonts()` asynchronously inspects `FontManifest.json` via the asset bundle.
- **Safety & Fallback:** Only font families whose 3 weights (Regular 400, SemiBold 600, Bold 700) and `OFL.txt` exist and are registered in `pubspec.yaml` appear in `FontManifest.json`. If unparseable or missing, it safely falls back to `[FontOption.system]`.
- **Theme Stack:** When a bundled font is selected (e.g. `Inter`), `buildAppTheme(uiFont: 'Inter')` sets `fontFamily: 'Inter'` with `fontFamilyFallback: ['Segoe UI Variable', ...AppTypography.fontFamilyFallback]`, guaranteeing that glyphs missing in the chosen font (such as Arabic glyphs in a Latin-only font) render cleanly without tofu boxes.

---

## 14. Artist Display Names (`lib/ui/artist_names/`)

- **Scope & Store:** `ArtistNameStore` persists user-defined artist name translations and display preferences to `artist_display_names.json`.
- **Purely Display-Only Resolver:** Display names are resolved purely in the presentation layer via `context.displayArtist(rawArtist)` or `store.resolve(rawArtist, mode)`. Library database tags, file metadata, SQL indexes, and search tokens remain completely untouched.
- **Matching Rules:** Matching uses `TextNormalizer.normalize()` (pure Dart case folding, diacritic removal, and whitespace trim) for exact whole-string equality. Substring matching is strictly prohibited to avoid partial corrupted names.
- **Live Reactivity:** Wrapped in `ArtistNameScope`, updates to artist rules immediately refresh album details, track rows, artist cards, now-playing bars, and full-screen displays.

---

## 15. Arabic Numerals & Localization Formatter (`lib/ui/l10n/number_format.dart`)

- **Digit Mapping:** `localizeDigits(text, arabicNumerals: bool)` converts Western ASCII digits `0-9` to Arabic-Indic digits `٠-٩` (`U+0660`–`U+0669`).
- **Duration & Count Helpers:** `formatDuration()` formats `m:ss` or `h:mm:ss`, and `formatCount()` formats integer amounts, respecting the `arabicNumerals` setting when the interface language is Arabic.
- **Convenience Extensions:** `context.formatDurationLocalized(d)` and `context.formatCountLocalized(n)` read the ambient `SettingsScope` directly.

---

## 16. Decisions

- **D1:** All color tokens met or exceeded WCAG AAA and AA contrast ratios on `#0F1115` without requiring adjustments (`text` at 15.4:1, `textSecondary` at 7.8:1, `textMuted` at 5.6:1, `accent` at 12.3:1).
- **D2:** `GlassController` binds to `SettingsStore` as the single source of truth, guaranteeing consistent quality across app restarts.
- **D3:** `AppSettings.fromJson` validates string tokens against known sets and strictly falls back to field defaults on invalid values while ignoring unexpected keys.
- **D4:** Responsive `Wrap` layouts are used in `DesignGalleryScreen` to guarantee zero `RenderFlex` overflows on compact test or split viewports.
- **D5:** `textDirectionFor()` ignores whitespace, punctuation, brackets, and digits to determine direction strictly from the first strong character.
- **D6:** Flagship-first default: moved default glass quality to `GlassQuality.full` everywhere with saturation 1.5 boost composed with 30px blur, and expanded `GlassBlurBudget` capacity from 2 to 6 (`kMaxBlurredSurfaces = 6`). Beyond 6, surfaces fall back to `light`.
- **D7:** Pure Dart navigation model with `AppNavigator` avoids heavy router dependencies and supports seamless back navigation from detail views to list screens.
- **D8:** Overlay `Directionality` moved to `MaterialApp.builder` wrapping the root `Navigator`, ensuring tooltips, popup menus, dialogs, and snackbars automatically inherit RTL layout in Arabic.
- **D9:** Leaf-level stream listeners (`ValueListenableBuilder`/`StreamBuilder`) for player seekbar isolate position ticks, ensuring 0 rebuilds for metadata and the parent now-playing bar.
- **D10:** Disabled placeholders for upcoming features (Last.fm, Playlists, Favorites, Recently Played, Equalizer, Queue, Lyrics) retain accessible tooltips and 40% muted opacity without invoking external web browsers, processes, or network requests.
- **D11:** First launch onboarding (`WelcomeView`) shows username entry only when `userName` is empty in settings, clamping to 40 characters and immediately updating the top greeting.
- **D12:** `CoverPalette` extracts primary, secondary, and tertiary tones from album artwork using 12 hue bins (30° each). Target saturation is clamped to `<= 0.54` (ensuring 8-bit quantization never exceeds 0.55) and lightness is bounded between `0.25` and `0.60`. Multi-color extraction is cached in a 32-entry LRU cache, with deterministic hue shift derivation when fewer than 3 valid bins exist.
- **D13:** `GlassDensity.clear` provides a lighter glass surface variant with 22px blur and 0.08 tint in `full` mode (0.45 alpha in `light` mode), ideal for floating decorative elements and HUD overlays while respecting blur budget limits.
- **D14:** Ambient blob animation in `FullScreenView` runs on a single CustomPainter inside a dedicated `RepaintBoundary` capped to ~30 fps (`elapsed - lastTick >= 33ms`). The ticker automatically stops when `reduceMotion` is true or when app lifecycle enters `inactive`/`paused`, resuming on `resumed`.
- **D15:** `AppStrings.t` supports parameterized interpolation `{arg}` with fallback to the placeholder tag if an argument is omitted, verified by a strict source-code scanner test preventing unlocalized strings in `lib/ui/`.
- **D16:** Full-screen mode is implemented as an immersive in-app window fill that replaces the shell layout (releasing bottom bar blur budget slots) rather than an OS-level window resize or maximize. Back navigation and `Esc` return cleanly to the previous destination (`nowPlaying` or previous library view).
- **D17:** Settings screen wraps its entire card in a single `GlassSurface` and renders inner sections with plain translucent containers (`AppColors.fillGlass`), consuming only 1 blur budget slot and leaving ample capacity for floating elements and background layers.
- **D18:** Audio engine parameters are strictly applied via `AudioSettingsApplier`. Invalid or unmounted audio device IDs at startup are safely ignored without overwriting user settings, preventing configuration loss when devices are temporarily disconnected.
- **D19:** Font discovery dynamically parses `FontManifest.json` at runtime instead of hardcoding available fonts. If the asset manifest is missing or empty, it strictly defaults to `FontOption.system`.
- **D20:** Artist display name translation is strictly decoupled from the library repository and database; it operates as an in-memory display resolver using `TextNormalizer` to ensure original tag integrity while providing personalized multilingual names.
- **D21:** `BuildContext.t` prioritizes `SettingsScope.maybeOf(context)?.settings.language` to allow instantaneous live switching between English and Arabic throughout all views without requiring full application restarts.
- **D22:** Localized audio errors: `AudioSettingsError { unsupported, failed }` standardizes engine error feedback, allowing the UI to present localized explanations (`settings.audio.errorUnsupported` and `settings.audio.errorFailed`) in both English and Arabic without leaking raw technical strings or persisting unapplied states.
- **D23:** Centralized shortcuts: `app_shortcuts.dart` serves as the sole authoritative source of truth for keyboard shortcuts across the application. Handlers match events using `matchesShortcut()` or helper functions (`isArrowUpKey`, `isArrowDownKey`, `isEnterKey`). A dedicated test verifies no files under `lib/ui/` reference `LogicalKeyboardKey` directly outside `app_shortcuts.dart`.
- **D24:** Equalizer trailing throttle & safe revert: Band adjustment throttles engine communication with a 50ms trailing timer to ensure rapid mouse drags never saturate the audio thread while guaranteeing the final value always reaches the engine. If the engine reports failure, the in-memory slider reverts to the last good gain without saving to disk.
- **D25:** Signal path strict fidelity: Only verified engine getters and nullable `AudioStreamInfo` fields are displayed. Resampling and output device formats are explicitly documented as engine-managed and not reported. The summary verdict never claims "bit-perfect" or "unaltered" to maintain complete technical honesty.
- **D26:** Quick Search token discard: Fast typing uses an incrementing `_activeQueryToken` to discard out-of-order asynchronous responses, guaranteeing that stale search results never overwrite current input.
- **D27:** Display-only translated artist search: Searching for an artist's Arabic display name inspects `ArtistNameStore` first to locate original tagged names, then queries the library repository with original keys, keeping SQLite database contents completely untouched.
- **D28:** Play tracking & scrobbling rules: A playback session is counted (`counted = 1`) when listened duration reaches $\min(0.50 \times \text{duration}, 240\text{s})$ on tracks with duration $\ge 30\text{s}$. Uncounted short sessions are persisted on session close only if listened duration $\ge 5000\text{ms}$. Loops via repeat-one or replaying the same track generate isolated independent sessions.
- **D29:** Non-blocking session persistence & lazy resume: `session.json` is debounced (1s), saves playback position at most every 10s while playing, and applies saved position lazily via `armResume()` on the first load of the identical track without any audible burst or auto-playback.
- **D30:** Diagnostics logging & privacy sanitization: `AppLogger` records to `logs/aestheticy.log` with automatic 1 MB log rotation preserving up to 3 archive files (`.1.log`..`.3.log`). Usernames, filesystem directories, API keys, and sensitive tokens are strictly scrubbed, and messages are truncated to 500 characters.

---

## 18. Equalizer & Audio Panels (`lib/ui/audio_panels/`)

- **State & Persistence (`EqStore`):** Persists configuration to `eq_settings.json` via atomic writes, debounced disk writes (400ms), and corrupt-file fallback to `.bad`. Stores `enabled` (bool), 10 band gains (`-12.0` to `+12.0` dB), `preampDb` (`-12.0` to `+12.0` dB), `presetId`, and up to 20 custom presets (name trimmed 1..24 characters, case-insensitive unique).
- **Built-in Presets:**
  - Flat: `[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]`, Preamp `0 dB`
  - Warm: `[3, 3, 2, 1, 0, 0, -1, -1, -2, -2]`, Preamp `-3 dB`
  - Bass Boost: `[6, 5, 4, 2, 0, 0, 0, 0, 0, 0]`, Preamp `-6 dB`
  - Vocal: `[-2, -2, -1, 1, 3, 3, 2, 1, 0, -1]`, Preamp `-3 dB`
  - Bright: `[-1, -1, 0, 0, 0, 1, 2, 3, 4, 4]`, Preamp `-4 dB`
- **Controller (`EqController`):** Manages engine communication with a 50ms trailing throttle for live drags. Band editing marks the active preset as `'custom'`. Live band dragging reverts on engine failure and returns `AudioSettingsError`. Startup applies EQ gains and preamp via `applyAll()` only if `engine.capabilities.equalizer` is true.
- **Audio Panels Screen (`AudioPanelsView`):**
  - Responsive two-column desktop layout (EQ flex 640, Signal path flex 552) stacking vertically below 1100dp. Consumes exactly 2 blurred surfaces (`GlassDensity.regular`), staying well within the 6-surface budget.
  - 10 vertical band sliders laid out low-to-high strictly left-to-right (`Directionality(textDirection: TextDirection.ltr)`) across both English and Arabic.
  - Interactive preset chips row with inline "Save preset" creation field, validation feedback, and deletion support for user presets.
  - Preamp slider, 0 dB center reference line, keyboard navigation (0.5 dB step; 2.0 dB with Shift), double-tap reset, and accessible frequency semantic labels (`31Hz`, `62Hz`, etc.).

---

## 19. Signal Path Pipeline (`lib/ui/audio_panels/signal_path_model.dart`)

- **4-Stage Pipeline:**
  1. **Source:** Stream format and container, sample rate, bit depth, channel configuration, bitrate, and lossless badge derived purely from `AudioStreamInfo`.
  2. **Equalizer:** Equalizer state (enabled / disabled), active preset name, preamp gain, and per-band dB adjustments.
  3. **ReplayGain:** Mode (`off`, `track`, `album`) and preamp gain in dB.
  4. **Output:** Output device name, exclusive mode status, and explicit note regarding engine-managed device rate and buffer format.
- **Verdict & Technical Truth:**
  - When all processing is disabled, the panel displays "Direct output (processing off)".
  - When EQ or ReplayGain is active, it displays "Processed".
  - Strictly avoids "bit-perfect" or "unaltered" claims since OS mixers and engine decoders may apply internal resampling or dithering.
- **Interactive Actions:**
  - "Copy details": Copies complete plain-text technical summary to the clipboard.
  - "Turn off processing": Instantly disables EQ and sets ReplayGain to off with inline feedback.

---

## 20. Quick Search Overlay (`lib/ui/quick_search/`)

- **Trigger & Activation:** Activated globally via `Ctrl + K` or by calling `toggleQuickSearch()`. Dismissed by `Esc`, second `Ctrl + K`, or clicking the background scrim.
- **Debounced Parallel Queries:** 120ms debounce before dispatching concurrent repository queries (`searchArtists`, `searchAlbums`, `search`).
- **Section Caps:** Results are strictly capped to 4 artists, 4 albums, and 8 tracks to guarantee responsive rendering and compact display.
- **Keyboard Navigation:** Arrow keys (`ArrowUp`, `ArrowDown`) navigate linearly through flat search results across sections; `Enter` activates the focused item (opens artist detail, album detail, or immediately plays the track).
- **Display-Only Translated Matching:** Matches queries against Arabic display names via `ArtistNameStore` without modifying library repository queries or database contents.

---

## 21. Playback, History & Diagnostics Settings

- **Playback Resume:**
  - Configured via `resumeSession` boolean setting in `AppSettings`.
  - When enabled, player queue, current track index, position, repeat mode, and shuffle state are automatically saved to `session.json` and restored on next app launch.
  - When disabled, session saving is completely bypassed and previous saved sessions are ignored.
- **Listening History Card:**
  - Displays total scrobbled tracks count using `LibraryRepository.playEventCount(countedOnly: true)`.
  - "Clear history" triggers inline two-stage confirmation (`Cancel` / `Clear now`), preventing accidental data loss.
  - Upon confirmation, calls `clearPlayEvents()` and displays a localized SnackBar confirmation.
- **Diagnostics Card:**
  - "Copy diagnostic report": Generates and copies a comprehensive, PII-sanitized markdown diagnostic report (`buildDiagnosticReport`) including application version, OS platform, audio engine capabilities, active output device, library counts, settings state, and recent log tail.
  - "Copy log folder path": Resolves and copies the absolute filesystem directory path containing rotating logs (`aestheticy.log`).

---

## 22. Shared Track Table (`lib/ui/library/track_table.dart`)

Phase 3c extracts a reusable desktop table component `TrackTable` from `TracksView`:
- **Columns:**
  - Row position `#` (swaps to animated equalizer bars when actively playing; shows a warning circle if the file is missing).
  - Artwork thumbnail (falls back to calm dark music note icon).
  - Title (emphasized primary text).
  - Artist (rendered via `context.displayArtist`, routed to artist detail on click).
  - Album (secondary text, routed to album detail on click).
  - Duration (formatted mm:ss localized).
  - Trailing action button (opens `TrackActionsMenu`).
- **Dimmed Missing Files:** Tracks whose files are missing from the library (e.g. from an imported M3U) render dimmed at 40% opacity with a localized "Not in library" label and disabled play actions, preventing crash loops.
- **Used Across Views:** `TracksView`, `AlbumDetailView`, `PlaylistDetailView`, `FavoritesView`, and `RecentlyPlayedView` all share this identical table component without visual regressions.

---

## 23. Track Actions Menu (`lib/ui/library/track_actions_menu.dart`)

Every row in `TrackTable` and album detail views exposes a unified `TrackActionsMenu` via both **right click** (secondary tap anywhere on the row) and the **"more" (three dots) icon button**:
- **Menu Actions:**
  - **Play:** Immediately clears the queue and starts playback of the selected track.
  - **Play next:** Inserts the track immediately after the currently playing song without interrupting playback.
  - **Add to queue:** Appends the track to the end of the active playback queue.
  - **Add to playlist (Submenu):** Dynamically lists all user playlists; tapping one appends the track. Includes a "New playlist..." item triggering the creation dialog.
  - **Star rating (Submenu):** Displays 1 to 5 star items with an active checkmark on the current rating, plus a "Clear rating" item.
  - **Remove from playlist / Move actions:** Displayed contextually when invoked from `PlaylistDetailView`.
- **Dialogs:** Localized modal glass dialogs for "New playlist", "Rename playlist", and "Delete playlist" with validation (1..60 chars, duplicate prevention) and keyboard support (`Enter` submits, `Esc` dismisses).

---

## 24. User Collections Screens (`lib/ui/library/`)

### Playlists View (`PlaylistsView`)
- Responsive grid of glass cards representing user playlists.
- Each card displays derived album artwork (from the first resolvable song), playlist title, track count, and formatted total duration.
- Card context menu allows renaming, deleting, and exporting as M3U.
- Top bar features a "New playlist" glass button and "Import M3U" button.
- Localized empty state when no playlists exist.

### Playlist Detail View (`PlaylistDetailView`)
- Back button navigation restoring previous destination history.
- Large cover art thumbnail and header displaying title, track count, and total duration.
- "Play" and "Shuffle" buttons (automatically skipping any missing/unindexed files).
- "Export M3U" button exporting playlist to `.m3u8` with UTF-8 BOM.
- Interactive `TrackTable` with row reordering (Move up, Move down) and removal.

### Favorites View (`FavoritesView`)
- Displays all favorited tracks in reverse chronological order (`newest favorite first`).
- "Play" and "Shuffle" header controls.
- Reactive live removal: when an item is unfavorited from the menu or bottom bar, the row immediately unmounts from the view.
- Localized empty state when no favorites exist.

### Recently Played View (`RecentlyPlayedView`)
- Displays up to 200 distinct tracks recently played (`counted = 1`), newest play session first.
- "Play" button playing the full recent history in order.
- Localized empty state when listening history is empty.

---

## 25. Player Controls: Heart & Star Ratings

### Heart Favorite Toggle
- **Bottom Bar (`BottomNowPlayingBar`):** Compact heart icon button adjacent to the track title. Toggles favorite state with instant visual feedback and localized tooltips (`track.favorite` / `track.unfavorite`).
- **Now Playing Views (`NowPlayingView` / `FullScreenView`):** Heart toggle button placed adjacent to track metadata.
- **States:** Outlined heart in muted text color when un-favorited; filled heart in coral/accent when favorited.

### 5-Star Rating Control
- Available in desktop two-column `NowPlayingView` and `TrackActionsMenu`.
- Displays 5 interactive star icons:
  - Hover highlights target stars.
  - Clicking star `N` assigns an `N`-star rating.
  - Clicking the current star rating clears the rating to 0.

---

## 26. Visual Compromises & Architectural Decisions

- **Star Rating Column Omission in TrackTable:** In a minimum window width of 1000px (with 200px sidebar, 48px padding, leaving ~752px content width), adding a dedicated 5-star column cramped the Title, Artist, and Album columns. Per prompt guidelines, star ratings were omitted from the shared table columns to preserve layout readability and are accessed via `TrackActionsMenu`, the bottom bar, and `NowPlayingView`.
- **Bottom Bar Heart Button Layout:** Using standard `IconButton` with default 8px padding caused a 5.0px RenderFlex overflow inside the 62px constrained bottom bar info column. Replaced with `Tooltip` + `InkResponse` (18x18 bounded box, 16px icon) providing full touch target responsiveness without vertical overflow.

---

## 27. Known Limitations

- **Local Build Workload & Audio Engine:** Local compilation of native Windows `.exe` binaries is disabled due to absence of Visual Studio C++ build tools; all native binaries are compiled via GitHub Actions CI. libmpv audio engine playback is not exercised by local test suites and requires testing on the GitHub Actions Windows desktop build artifact.
- **Headless Performance Benchmarks:** In unit and widget tests, frame timing callbacks operate within simulated clock dispatchers. Real GPU raster and build times must be evaluated directly on the Windows release executable using the Design Gallery.
- **Glass Fallback Re-acquisition:** A GlassSurface that fell back to `light` because the blur budget was full does not re-acquire a slot until quality changes.
- **Tools > Last.fm Placeholder:** Last.fm integration in the sidebar is currently a disabled placeholder with a neutral icon; no scrobbling, authentication, or external web browsing is active.
- **Missing Bundled Font Assets:** Font asset files for Inter, IBM Plex Sans Arabic, Noto Sans Arabic, and Cairo are not yet committed under `assets/fonts/`. Per architecture rules, no external font downloads are permitted; until font files are placed on disk, the UI font picker offers "System default".

---

## 28. Windows Desktop Integration & Platform Services (Phase 3c, Prompt 3)

### 28.1 Platform Interfaces Architecture (`lib/platform/`)
All native Windows integrations are encapsulated behind lightweight, testable interfaces in `lib/platform/`. Application features and UI components interact exclusively with these abstract contracts:
- **`MediaSessionService`:** Controls OS media session (System Media Transport Controls / SMTC), metadata presentation, timeline progress, playback status, and media button event streams (`play`, `pause`, `next`, `previous`, `stop`).
- **`SleepInhibitor`:** Manages OS sleep/idle execution states (`acquire()`, `release()`).
- **`TrayService`:** Manages system tray icon, tooltips, localized context menu items, and interaction event streams (`iconClicked`, `menuItem`).
- **`WindowService`:** Manages desktop window life cycle, close event interception (`setPreventClose`), visibility toggle (`show`, `hide`), focus, and process termination (`destroy`).
- **Fakes (`FakeMediaSessionService`, `FakeSleepInhibitor`, `FakeTrayService`, `FakeWindowService`):** Deterministic in-memory fakes recording every call for full unit and widget test verification without calling real OS APIs or plugins.

### 28.2 Resolved Package Versions & Dependency Architecture
- **`smtc_windows: 1.1.0`:** Interacts with Windows System Media Transport Controls via WinRT. Requires Rust toolchain in CI (`rustup default stable`).
- **`tray_manager: 0.5.3`:** Interacts with Windows notification area tray icon and context menus via standard Flutter platform channels.
- **`window_manager: 0.4.3`:** Interacts with Win32 desktop window APIs via standard Flutter platform channels.
- **Dependency Version Pinning Decision:** `tray_manager 0.8.x` and `window_manager 0.6.x` incorporate Dart Native Assets C-builder hooks (`cnativeapi`), which require a local MSVC C++ compiler during `flutter test`. To preserve local development workflows without requiring Visual Studio C++ (per project constraints), `tray_manager` was pinned to `0.5.3` and `window_manager` to `0.4.3`. These versions rely purely on standard Flutter platform channels and execute cleanly across local unit and widget test suites.

### 28.3 System Media Transport Controls (SMTC) & Media Keys
- **Implementation:** `lib/platform/windows/smtc_media_session.dart` and pure-Dart controller `lib/features/integration/media_session_controller.dart`.
- **Metadata Presentation:** Synchronizes track title, artist name, and album title with OS SMTC. The artist string passes through `ArtistNameStore.displayArtist` matching current app language and bilingual display mode. Artwork is mapped from `AudioSource.extras['coverKey']` via `CoverCache` to local file URIs.
- **Timeline Throttling:** Timeline progress updates are throttled to at most once per second during continuous playback, but emitted immediately on seek, pause, and track transition.
- **Hardware Media Keys & In-App Keyboard Shortcuts:** Hardware media keys are received directly through SMTC. In-app media shortcuts (`LogicalKeyboardKey.mediaPlayPause`, `mediaTrackNext`, `mediaTrackPrevious`) are registered in `kAppShortcuts` and handled via `CallbackShortcuts` in `lib/main.dart` when the application window is focused.
- **Settings Reactivity:** Toggling `mediaControls` in Settings immediately disables or re-initializes SMTC live without application restart. Plugin exceptions are caught, logged, and surfaced in diagnostics without interrupting audio playback.

### 28.4 Tray Icon & Desktop Close Behavior
- **Asset Registration:** Reused `windows/runner/resources/app_icon.ico` copied to `assets/tray/app_icon.ico` and registered in `pubspec.yaml`.
- **Close Interception:** `WindowService.setPreventClose(true)` intercepts window close requests.
- **Quit vs Tray Modes:**
  - `closeBehavior: 'quit'` (default): Initiates orderly app shutdown via `AppShutdownCoordinator`, then destroys window and exits.
  - `closeBehavior: 'tray'`: Saves a synchronous session snapshot, hides the desktop window, and leaves audio playback active in the background.
- **Tray Interactions:** Clicking the tray icon toggles window visibility (`show` / `hide`). The localized context menu contains Show, Play/Pause (dynamically reflecting current playback state), Next, Previous, and Quit (which triggers full shutdown).

### 28.5 Application Shutdown Coordinator (`AppShutdownCoordinator`)
- **Location:** `lib/features/integration/app_shutdown.dart`.
- **Execution Order (Idempotent & Failure-Tolerant):**
  1. Synchronous session snapshot (`SessionSaver.saveSnapshotSync`).
  2. Finalize active play recorder listening session (`PlayRecorder.dispose`).
  3. Flush settings store (`SettingsStore.flush`).
  4. Flush diagnostics logger (`AppLogger.flush`).
  5. Disable media session and release sleep inhibitor.
  6. Hide system tray icon.
- Handled uniformly for window close requests, tray Quit activations, and `AppLifecycleListener` shutdown events.

### 28.6 Sleep Prevention (`SleepInhibitor` & `SleepController`)
- **Implementation:** `lib/platform/windows/win32_sleep_inhibitor.dart` and `lib/features/integration/sleep_controller.dart`.
- **Mechanism:** Direct Win32 `kernel32.dll` call to `SetThreadExecutionState` via `dart:ffi`.
- **Execution Flags:**
  - `0x80000001` (`ES_CONTINUOUS | ES_SYSTEM_REQUIRED`): Prevents system sleep while allowing monitors to enter low-power sleep.
  - `0x80000000` (`ES_CONTINUOUS`): Releases sleep prevention lock.
- **Reactivity:** Automatically acquired when playback enters `playing` and `preventSleepWhilePlaying` is true; immediately released when paused, stopped, track completes, or the setting is disabled live.

### 28.7 Settings UI & Diagnostics Integration
- **Settings View:** Windows Integration card presented conditionally when running on Windows (or during testing via `isWindowsOverride`). Exposes:
  - Media Controls toggle switch.
  - Prevent Sleep toggle switch.
  - Close Behavior segmented selector ("Quit", "Minimize to tray").
- **Diagnostics Report:** `buildDiagnosticReport` includes Windows integration status lines (`SMTC: active/disabled/unavailable`, `Sleep inhibitor: active/idle/unavailable`, `Tray: active/disabled/unavailable`, `Close behavior: quit/tray`) without exposing system paths or personal data.

### 28.8 Known Limitations & Integration Notes
- **Local Native Execution:** As Visual Studio C++ is not installed on the development PC, real SMTC and tray plugins run exclusively in GitHub Actions release builds. All local behavior is fully verified using platform abstraction fakes and contract tests.
- **Win32 Raw Key Simulator:** Flutter's test raw event simulator on Windows omits `mediaTrackNext` and `mediaTrackPrevious` virtual keycodes. Tests dispatch synthetic key events directly to focus nodes and verify activator acceptance deterministically.
