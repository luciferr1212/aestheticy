# Audio Core Architecture & Documentation

## Overview & Architecture

Aestheticy's Phase 1 introduces a decoupled, robust audio architecture. High-level UI and application logic interact strictly with the abstract `AudioEngine` interface and pure Dart playback controllers. Direct native bindings and third-party dependencies are isolated inside `MpvAudioEngine`.

```text
┌─────────────────────────────────────────────────────────────┐
│                    UI & Application Layer                   │
│         (Screens, Controls, Widgets - Later Phases)         │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 PlaybackController (Pure Dart)              │
│       - Auto-advance on completion                          │
│       - Error tolerance & automatic skip                    │
│       - Gapless preloading coordination                     │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
               ▼                              ▼
┌─────────────────────────────┐  ┌────────────────────────────┐
│  PlaybackQueue (Pure Dart)  │  │  AudioEngine (Interface)   │
│  - Ordering & cursor        │  │  - Transport (play/pause)  │
│  - Shuffle (pinned current) │  │  - EQ & ReplayGain         │
│  - Repeat (off / all / one) │  │  - Stream info & devices   │
│  - Peek next                │  └─────────────┬──────────────┘
└─────────────────────────────┘                │
                                               │
               ┌───────────────────────────────┴───────────────────────────────┐
               ▼                                                               ▼
┌─────────────────────────────┐                                 ┌─────────────────────────────┐
│    MpvAudioEngine (Real)    │                                 │    FakeAudioEngine (Test)   │
│  - Backend: mpv_audio_kit   │                                 │  - In-memory mock           │
│  - Windows x64 libmpv       │                                 │  - Controllable tick/events │
│  - WASAPI & native DSP      │                                 │  - Runs in pure unit tests  │
└─────────────────────────────┘                                 └─────────────────────────────┘
```

---

## Package Decision: `mpv_audio_kit`

**Chosen Package:** `mpv_audio_kit` (v0.5.3, BSD-3-Clause)

### Why `mpv_audio_kit` was chosen over `media_kit`:
1. **Audio-focused with typed DSP API:** `mpv_audio_kit` provides typed Dart models and effect classes (e.g. `EqualizerEffect`, `ReplayGainSettings`, `AudioParams`) wrapping FFmpeg audio filters directly without fragile string interpolation.
2. **Recent Active Maintenance:** Released actively in October 2026 with recent libmpv v0.41.0 native binaries for Windows x64, compared to `media_kit_libs_windows_audio` which has not had native updates in over 2 years.
3. **Dedicated Background Event Isolate:** libmpv event loop runs in a background isolate, leaving the Flutter UI thread entirely free of audio-event stutter.

---

## Capability Matrix

| Capability | Supported | Backend Implementation Detail |
|---|---|---|
| **Windows x64 Native** | Yes | Bundled libmpv v0.41.0 + FFmpeg binaries in `mpv_audio_kit` |
| **Transport (play/pause/seek)** | Yes | libmpv `pause`, `seek`, `loadfile`, `stop` |
| **Volume & Speed** | Yes | libmpv `volume` (0-100), `speed` |
| **Device Selection** | Yes | Enumerated from `audio-device-list`, selected via `audio-device` |
| **WASAPI Exclusive Mode** | Yes | Configured via `audio-exclusive=yes` |
| **Gapless Playback** | Yes | Prefetching via `prefetch-playlist=yes` & `gapless-audio=weak` |
| **ReplayGain** | Yes | Atomic setting of `replaygain` (`no`, `track`, `album`) & preamp |
| **10-band Equalizer** | Yes | Chain of 10 `EqualizerEffect` instances mapped to FFmpeg `equalizer` filter |
| **Stream Info Inspection** | Yes | Decoded via `audioParams`, `audioBitrate`, and container metadata |

---

## PlaybackController Resume Hook (`armResume`)

To support non-intrusive session resuming:
- `armResume(Duration position)`: Registers a target playback position for the currently armed track without triggering immediate playback, loading, or seeking.
- **Lazy Execution:** When the user initiates playback for the restored track and the audio engine notifies that the track is loaded (duration is non-null and greater than zero), `PlaybackController` seeks to the armed position once and disarms.
- **Auto-Cancellation:** If the user initiates playback of a different track or clears the queue before playing the restored track, the armed position is discarded, ensuring stale positions never leak across track boundaries.

---

## Known Limitations

1. **WASAPI Exclusive Mode Sample Rate Switching:** When transitioning between tracks with different sample rates in WASAPI exclusive mode, an unavoidable hardware handshake gap occurs as the DAC re-clocks.
2. **Local Windows Build Environment:** Because Visual Studio C++ build tools are not installed on the local development machine, native compilation is only performed on GitHub Actions runners.
3. **Headless Tests:** `MpvAudioEngine` requires the native `mpv.dll` binary and an audio output device; native audio cannot be verified inside CI headless unit tests and must be tested using `FakeAudioEngine` for unit testing and manual testing on Windows desktop for the real engine.

---

## Windows Manual Testing Checklist

Run these steps when testing the Windows artifact downloaded from GitHub Actions:

- [ ] **Basic Playback:** Open a local `.flac`, `.mp3`, or `.wav` file; audio plays smoothly without clipping or stutter.
- [ ] **Transport Controls:** Play, pause, resume, and seek to various positions (start, middle, near end). Verify position updates correctly.
- [ ] **Volume & Mute:** Adjust volume slider from 0% to 100%; verify volume matches system expectation. Toggle mute.
- [ ] **Gapless Playback:** Queue two consecutive tracks from a gapless album (e.g. Pink Floyd or live concerts); verify no click, pop, or silence at the track boundary.
- [ ] **10-Band EQ:** Boost bass (31-125 Hz) or treble (8-16 kHz) by +6 dB; verify audible frequency modification. Reset to flat (0 dB).
- [ ] **WASAPI Output & Exclusive Mode:** Select an external DAC/soundcard; verify sound switches to the selected output. Toggle exclusive mode on and verify other Windows sounds are muted/blocked.
- [ ] **Error Recovery:** Queue an invalid file or broken URL; verify the player skips to the next valid track without crashing.

---

## Future Work: Crossfading

Crossfade is deliberately **not** implemented in Phase 1 to maintain a clean, stable single-player core. 

To implement smooth crossfading in a future phase:
1. Maintain two parallel `AudioEngine` instances (Player A and Player B).
2. When Track 1 approaches its end minus crossfade duration (e.g. 5 seconds remaining), initialize Player B with Track 2 in paused state.
3. Ramp Player B's volume linearly or logarithmically from 0.0 to 1.0 while simultaneously ramping Player A's volume from 1.0 to 0.0.
4. Stop Player A once Player B reaches full volume and swap player references for the subsequent track transition.

---

## Queue Architecture & Controller Operations (Phase 4, Prompt 2)

### Active Playback Order
All queue indices across `PlaybackQueue` and `PlaybackController` operate strictly in **active playback order**:
- When shuffle is off: active order matches the underlying user insertion order.
- When shuffle is on: active order reflects the shuffled playlist order (with the current track pinned to index 0 on shuffle enable).
- Deletions and movements retain indices in active playback order without unprovoked reshuffling, ensuring consistent index math between UI, controller, and tests.

### Controller Operations
1. `Future<void> moveInQueue(int from, int to)`:
   - Validates indices against active queue bounds (ignores invalid indices safely).
   - Calls `queue.move(from, to)`, keeping the active cursor synchronized with the current item.
   - Moving the playing item itself is supported without reloading or restarting audio (`engine.open` is not called).
   - Emits `queueChangeStream` once and refreshes gapless preloading.
2. `Future<void> removeFromQueue(int index)`:
   - Non-current item: safely removed via `queue.remove(index)`. The playing track continues uninterrupted without calling `engine.open`. Cursor index is adjusted, `queueChangeStream` emits once, and gapless preload is refreshed.
   - Current item (with other items remaining): removed from queue. The track that shifts into the active cursor position is immediately opened and played via `engine.open` (resetting armed resume and consecutive fatal error counters). This guarantees the engine never continues playing a track that has been deleted from the queue.
   - Current item (only item left): queue is cleared, playback stops via `engine.stop()`, and `_emitCurrent(null)` is dispatched.
   - Out-of-bounds indices are safely ignored.
3. `Future<void> playNextFromQueue(int index)`:
   - Moves the track at `index` to immediately follow the current playing track (`currentIndex + 1`).
   - No-op if `index` is already the current track or already next in sequence.
   - Notifies `queueChangeStream` and refreshes gapless preloading.

### Media Session & Persistence Integration
- **SessionSaver:** Already subscribes directly to `controller.queueChangeStream` to immediately persist reorders and item removals into `session.json` (`debounce: false`), ensuring accurate queue state on app restore.
- **MediaSessionController:** Synchronized via `controller.currentStream` which fires whenever the current track changes or ends, keeping SMTC timeline and metadata aligned.

---

## Queue Known Limitations

1. **Individual item additions via raw queue do not notify controller.** When mutating `PlaybackQueue` directly instead of through `PlaybackController`, controller notifications and preloading must be manually invoked. Always use `PlaybackController.moveInQueue`, `removeFromQueue`, `playNextFromQueue`, and `clearUpcoming`.
2. **Synthetic `completed` for gapless.** When mpv moves to the preloaded track by itself, `MpvAudioEngine` emits a `completed` event so the controller advances. This works as long as the package reports another state (for example `playing`) between two transitions. A dedicated `trackAdvanced` event would be cleaner.
3. **Duplicate tracks in the queue.** The cursor is kept by track identity (the URI), so after an add or a shuffle toggle it can jump to the first copy of a track that appears twice.
4. **Repeat one grows mpv's playlist.** Every repeat appends one more entry to mpv's internal playlist. The effect is tiny but it is never trimmed.
5. **Repeat one, last track, Next.** Pressing Next on the last track while repeat one is active stops playback.
6. **Shuffle reshuffles on add.** Adding a track while shuffle is on re-randomizes the upcoming order.
7. **Preload mirror.** `MpvAudioEngine` keeps its own record of mpv's playlist position and preloaded entry. If `player.open()` ever stops replacing the whole playlist, this mirror must be revisited.

---

## Smooth Audio Transitions, Paused-Jump Fix & Transport Serialization (Phase 4, Prompt 4)

### Architecture & Fade Gain
- **`AudioEngine` contract (`lib/audio/audio_engine.dart`):** Adds `double get currentFadeGain` (default `1.0`) and `Future<void> setFadeGain(double gain)`. Transient fade gain (`0.0..1.0`) is kept strictly separate from user volume so UI sliders and persisted settings (`currentVolume` / `volumeStream`) never fluctuate during fades.
- **`MpvAudioEngine` (`lib/audio/mpv_audio_engine.dart`):** Applies `effectiveVolume = (_volume * _fadeGain * 100.0)` to libmpv and guards against mpv volume stream feedback loops during fade ramps via `_ignoreMpvVolumeUpdates`.
- **Pause-safe `open()` (`MpvAudioEngine`):** Upstream `mpv_audio_kit`'s `Player.open(media, play: true)` sets `pause = no` *before* `loadfile`, briefly unpausing an already-paused outgoing track. When `autoPlay && !player.state.playing`, `MpvAudioEngine.open` now opens with `play: false` first and calls `player.play()` afterward only if `_currentUri == source.uri`.

### `PlaybackController` Serialization & Envelopes
- **Single-flight serialization & latest-wins cancellation:** Transport actions (`play`, `playTrack`, `playQueue`, `pause`, `stop`, `skipNext`, `skipPrevious`, `removeFromQueue`, `_autoAdvance`) coordinate via monotonic `_transitionGen`, `_activeTransition` single-flight chaining, and `_abortPendingWaiters()`, cancelling outdated ramps/delays cleanly when rapid user commands arrive.
- **Cosine S-curve envelopes (~16 ms `Timer.periodic` + stopwatch hybrid):**
  - Stopped / new track -> play: `250 ms` fade-in (`kStartFadeInDuration`).
  - Paused -> resume (same track): `120 ms` fade-in (`kResumeFadeInDuration`).
  - Manual jump while playing: `120 ms` fade-out + `60 ms` silent gap (`kSwitchGapDuration`) + `250 ms` fade-in.
  - Playing -> pause: `100 ms` fade-out (`kPauseFadeOutDuration`) -> `engine.pause()` -> restore gain to `1.0`.
  - Playing -> stop / shutdown: `100 ms` fade-out hard-capped at `<= 145 ms` (`kStopMaxFadeOutDuration`).
  - Fades are intentionally skipped (gain stays `1.0`) on manual jump while paused, intra-track `seek()`, gapless auto-advance, or when `smoothTransitions == false`. Smooth audio transitions are independent of UI `reduceMotion`.

### Decisions
- **Standalone default vs app binding:** `PlaybackController({ bool smoothTransitions = false })` defaults to `false` so standalone callers and existing zero-delay unit/widget tests remain deterministic without timers, while `AppSettings.smoothTransitions` defaults to `true` and `_AestheticyAppState` (`lib/main.dart`) keeps the controller synchronized with `SettingsStore` even when `reduceMotion` is enabled.
- **Idle-immediate transition start (`_activeTransition`):** Instead of chaining every call onto an eager `Future<void>.value()` initialized at construction time (which in `setUp` belongs to a different Dart Zone than `testWidgets`'s `FakeAsync`), `_enqueueTransition` starts the task synchronously when `_activeTransition == null` and only chains onto `prev` while an active transition is in flight.

### Known Limitations
- Software fade ramps, pause-safe libmpv loading, and clean shutdown pauses require end-to-end audio verification on a Windows GitHub Actions build artifact (native C++/Windows runtime is not built locally).
