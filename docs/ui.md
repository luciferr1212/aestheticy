# UI Foundation Architecture & Design System Documentation

## Overview

Phase 3a establishes the design system, theme tokens, glass rendering system, settings store, localization foundation, and developer Design Gallery for Aestheticy.

---

## 1. Directory Structure

```text
lib/ui/
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
│   └── locale_controller.dart        # Ambient Locale & TextDirection coordinator
├── settings/
│   ├── app_settings.dart             # Immutable settings model with tolerant parser
│   └── settings_store.dart           # Debounced atomic JSON persistence
└── theme/
    ├── app_colors.dart               # Static WCAG-compliant color palette
    ├── app_spacing.dart              # Standard spacing and border radii
    ├── app_theme.dart                # Material 3 dark theme builder
    └── app_typography.dart           # Windows desktop font family & text scale
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

## 8. Decisions

- **D1:** All color tokens met or exceeded WCAG AAA and AA contrast ratios on `#0F1115` without requiring adjustments (`text` at 15.4:1, `textSecondary` at 7.8:1, `textMuted` at 5.6:1, `accent` at 12.3:1).
- **D2:** `GlassController` binds to `SettingsStore` as the single source of truth, guaranteeing consistent quality across app restarts.
- **D3:** `AppSettings.fromJson` validates string tokens against known sets and strictly falls back to field defaults on invalid values while ignoring unexpected keys.
- **D4:** Responsive `Wrap` layouts are used in `DesignGalleryScreen` to guarantee zero `RenderFlex` overflows on compact test or split viewports.
- **D5:** `textDirectionFor()` ignores whitespace, punctuation, brackets, and digits to determine direction strictly from the first strong character.
- **D6:** Flagship-first default: moved default glass quality to `GlassQuality.full` everywhere with saturation 1.5 boost composed with 30px blur, and expanded `GlassBlurBudget` capacity from 2 to 6 (`kMaxBlurredSurfaces = 6`). Beyond 6, surfaces fall back to `light`.

---

## 9. Known Limitations

- **Local Build Workload:** Local compilation of native Windows `.exe` binaries is disabled due to absence of Visual Studio C++ build tools; all native binaries are compiled via GitHub Actions CI.
- **Headless Performance Benchmarks:** In unit and widget tests, frame timing callbacks operate within simulated clock dispatchers. Real GPU raster and build times must be evaluated directly on the Windows release executable using the Design Gallery.
- **System Font Reliance:** Typography relies on Windows desktop system fonts (`Segoe UI Variable` and `Segoe UI`); custom bundled web fonts are not yet bundled.
