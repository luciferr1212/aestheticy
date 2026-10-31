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

## Known Limitations

These are known and accepted for Phase 1. Revisit them when the queue UI is built.

1. **Queue changes do not notify the controller.** After add, move, remove or a shuffle toggle, the track that mpv already preloaded is not refreshed, and removing the currently playing track does not stop it.
2. **Synthetic `completed` for gapless.** When mpv moves to the preloaded track by itself, `MpvAudioEngine` emits a `completed` event so the controller advances. This works as long as the package reports another state (for example `playing`) between two transitions. A dedicated `trackAdvanced` event would be cleaner.
3. **Duplicate tracks in the queue.** The cursor is kept by track identity (the URI), so after an add or a shuffle toggle it can jump to the first copy of a track that appears twice.
4. **Repeat one grows mpv's playlist.** Every repeat appends one more entry to mpv's internal playlist. The effect is tiny but it is never trimmed.
5. **Repeat one, last track, Next.** Pressing Next on the last track while repeat one is active stops playback.
6. **Shuffle reshuffles on add.** Adding a track while shuffle is on re-randomizes the upcoming order.
7. **Preload mirror.** `MpvAudioEngine` keeps its own record of mpv's playlist position and preloaded entry. If `player.open()` ever stops replacing the whole playlist, this mirror must be revisited.
