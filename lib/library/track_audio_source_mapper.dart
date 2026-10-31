/// Maps library domain models to audio engine models.
library;

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/library/models.dart';

/// Extension providing conversion from a library [Track] to an [AudioSource].
extension TrackAudioSourceMapper on Track {
  /// Converts this [Track] into an [AudioSource] suitable for the audio engine.
  AudioSource toAudioSource() {
    return AudioSource(
      path,
      extras: {
        'title': ?title,
        'artist': ?artist,
        'album': ?album,
        'albumArtist': ?albumArtist,
        if (trackNo != null) 'trackNo': trackNo.toString(),
        if (discNo != null) 'discNo': discNo.toString(),
        if (year != null) 'year': year.toString(),
        'coverKey': ?coverKey,
        'durationMs': durationMs.toString(),
      },
    );
  }
}
