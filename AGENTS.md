# Aestheticy Player — Project Instructions

## What we are building
A native Windows desktop music player called Aestheticy, built with Flutter (no WebView, no Electron). Final goal: an Apple Music-like player with real liquid-glass visuals, synced lyrics, local library, mini player, and shared listening. We build it in phases. Phase 1 = a professional audio core only (no pretty UI).

## Owner context (important)
- The owner (mido) is a beginner: first month of computer science, builds by vibe coding. He does not write code by hand.
- After EVERY task, finish with a short summary in simple Egyptian Arabic: what changed, how to verify it, what he should do next. Define any jargon the first time.
- Explain every terminal command before asking him to run it. Prefer doing it yourself.
- Code, comments, commit messages, and docs are in English.

## Locked tech stack
- Flutter (stable channel) + Dart. Primary target: Windows desktop.
- Audio: libmpv through a Dart package, always behind our own AudioEngine interface (see rules).
- Add a new package only when needed. Say why, and pin its version in pubspec.yaml.

## Architecture rules
- The UI and all other code NEVER call the audio package directly. They use the AudioEngine interface in lib/audio/.
- Queue, shuffle and repeat logic is pure Dart (no plugin imports) so it is unit-testable anywhere.
- Keep files small and named by purpose. Folders: lib/audio, lib/core, lib/features (later phases).
- Errors are typed and surfaced as streams or results. No silent failures, no empty catch blocks.

## Environment facts
- Development happens on the owner's Windows 10 PC (old CPU, little free disk) using Google Antigravity. Use PowerShell commands.
- Visual Studio (C++ workload) is NOT installed, so flutter build windows and flutter run -d windows will NOT work locally. Do not try to install Visual Studio.
- Locally you may only run: flutter pub get, flutter analyze, flutter test, and git commands.
- Windows builds are produced by GitHub Actions on windows-latest. The owner downloads the build artifact and runs it himself.
- Never claim that audio works unless the owner reports that he tested the Actions build. State clearly what is untested.

## Working rules
- One task at a time. Small steps. Do not touch files outside the task.
- Never invent a package API from memory. Read the package's current README and source (pub.dev page or the downloaded package in the pub cache) before using it. If unsure, say so.
- Run flutter analyze and flutter test before saying a task is done, and report the results honestly.
- Ask before any large change, deleting files, or changing the architecture.
- Never commit secrets or personal files.

## Design preferences (for later phases)
- Calm, muted colors. No neon or loud colors.
- The only credit text in the app is: by mido

## Roadmap
1 Audio core -> 2 Library (scan folders, tags, SQLite) -> 3 UI and liquid glass -> 4 Lyrics, queue UI, mini player, stats -> 5 Shared listening and polish.