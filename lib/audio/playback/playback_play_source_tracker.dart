/// Internal play-event origin source tracker for [PlaybackController].
class PlaybackPlaySourceTracker {
  /// Allowed play-event origin sources stored in `play_events.source`.
  static const Set<String> allowedPlaySources = {
    'album',
    'artist',
    'playlist',
    'favorites',
    'search',
    'queue',
    'mini',
    'unknown',
  };

  String _currentPlaySource = 'unknown';

  String get currentPlaySource => _currentPlaySource;

  static String normalize(String? source) {
    if (source != null && allowedPlaySources.contains(source)) {
      return source;
    }
    return 'unknown';
  }

  void setSource(String? source) {
    _currentPlaySource = normalize(source);
  }

  void reset() {
    _currentPlaySource = 'unknown';
  }
}
