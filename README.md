# Aestheticy

A native Windows desktop music player built with Flutter.  
Calm, minimal, and beautiful — by mido.

## Status

Phase 1: Audio core (in progress).

## Local Development

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel).

```powershell
# Install dependencies
flutter pub get

# Run static analysis (should report 0 issues)
flutter analyze

# Run tests
flutter test
```

> **Note:** Building for Windows requires Visual Studio with the C++ workload.  
> We use GitHub Actions for builds instead of building locally.

## Download the Windows Build

1. Go to the [Actions tab](../../actions) on GitHub.
2. Click the latest successful **Build Windows** run.
3. Download the **aestheticy-windows** artifact from the bottom of the page.
4. Extract the zip and run `aestheticy.exe`.

## Tech Stack

- **Flutter** (Dart) — Windows desktop target
- **libmpv** (planned) — Audio playback behind an `AudioEngine` interface

## License

Private project. All rights reserved.
