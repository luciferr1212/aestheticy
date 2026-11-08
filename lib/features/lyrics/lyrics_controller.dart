/// State coordination and playback position tracking for lyrics.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../diagnostics/app_logger.dart';
import '../../ui/settings/settings_store.dart';
import 'lyrics_models.dart';
import 'lyrics_repository.dart';

/// Presentation state of the lyrics controller.
sealed class LyricsControllerState {
  const LyricsControllerState();
}

/// Lyrics display is disabled in user settings.
class LyricsStateOff extends LyricsControllerState {
  const LyricsStateOff();

  @override
  String toString() => 'LyricsStateOff()';
}

/// Lyrics are actively resolving from local or online sources.
class LyricsStateLoading extends LyricsControllerState {
  const LyricsStateLoading();

  @override
  String toString() => 'LyricsStateLoading()';
}

/// Lyrics document was successfully found and loaded.
class LyricsStateFound extends LyricsControllerState {
  /// The resolved document.
  final LyricsDocument document;

  /// Creates a [LyricsStateFound].
  const LyricsStateFound(this.document);

  @override
  String toString() => 'LyricsStateFound(${document.kind}, source: ${document.source})';
}

/// No lyrics were found across the active sources.
class LyricsStateNotFound extends LyricsControllerState {
  const LyricsStateNotFound();

  @override
  String toString() => 'LyricsStateNotFound()';
}

/// An error occurred while retrieving lyrics (e.g. network offline or timeout).
class LyricsStateError extends LyricsControllerState {
  /// The classified error reason.
  final LyricsErrorReason reason;

  /// Creates a [LyricsStateError].
  const LyricsStateError(this.reason);

  @override
  String toString() => 'LyricsStateError($reason)';
}

/// Coordinates lyrics loading, state changes, and binary-search time synchronization.
class LyricsController extends ChangeNotifier {
  final PlaybackController playbackController;
  final LyricsRepository repository;
  final SettingsStore settingsStore;

  final List<StreamSubscription<dynamic>> _subs = [];
  int _requestId = 0;
  String? _currentTrackUri;
  String _lastLyricsSource = '';
  Future<void>? _currentResolveFuture;

  /// Future of the currently running lyrics resolution, if any.
  @visibleForTesting
  Future<void>? get currentResolveFuture => _currentResolveFuture;

  LyricsControllerState _state = const LyricsStateLoading();
  int _currentLineIndex = -1;
  int _currentWordIndex = -1;
  double _wordProgress = 0.0;
  bool _disposed = false;

  /// Creates a [LyricsController].
  LyricsController({
    required this.playbackController,
    required this.repository,
    required this.settingsStore,
  }) {
    _lastLyricsSource = settingsStore.settings.lyricsSource;

    // Follow track changes
    _subs.add(playbackController.currentStream.listen(_onTrackChanged));

    // Follow position ticks
    _subs.add(playbackController.engine.positionStream.listen((pos) {
      updatePosition(pos);
    }));

    // Follow seeks
    _subs.add(playbackController.seekStream.listen((pos) {
      updatePosition(pos);
    }));

    // Follow settings changes (lyrics source re-resolve)
    settingsStore.addListener(_onSettingsChanged);

    // Initial load for whatever is currently queued
    final current = playbackController.queue.current;
    if (current != null) {
      _currentTrackUri = current.uri;
      _currentResolveFuture = _resolveForSource(current);
    } else {
      _state = settingsStore.settings.lyricsSource == 'off'
          ? const LyricsStateOff()
          : const LyricsStateNotFound();
    }
  }

  /// Current presentation state.
  LyricsControllerState get state => _state;

  /// The URI of the track currently being tracked.
  String? get currentTrackUri => _currentTrackUri;

  /// 0-based index of the actively playing line, or -1 if before the first line or not found.
  int get currentLineIndex => _currentLineIndex;

  /// 0-based index of the actively playing word within [currentLineIndex], or -1.
  int get currentWordIndex => _currentWordIndex;

  /// 0.0 to 1.0 progress of the current word between start and end times.
  double get wordProgress => _wordProgress;

  /// Currently loaded document, or null if not found/error/loading.
  LyricsDocument? get document => switch (_state) {
        LyricsStateFound(document: final doc) => doc,
        _ => null,
      };

  void _onSettingsChanged() {
    if (_disposed) return;
    final newSource = settingsStore.settings.lyricsSource;
    if (newSource != _lastLyricsSource) {
      _lastLyricsSource = newSource;
      final current = playbackController.queue.current;
      if (current != null) {
        _currentResolveFuture = _resolveForSource(current);
      } else {
        _state = newSource == 'off'
            ? const LyricsStateOff()
            : const LyricsStateNotFound();
        notifyListeners();
      }
    }
  }

  void _onTrackChanged(AudioSource? source) {
    if (_disposed) return;
    final newUri = source?.uri;
    _currentTrackUri = newUri;
    _currentLineIndex = -1;
    _currentWordIndex = -1;
    _wordProgress = 0.0;

    if (source == null) {
      _requestId++;
      _state = const LyricsStateNotFound();
      notifyListeners();
      return;
    }

    _currentResolveFuture = _resolveForSource(source);
  }

  /// Retries resolution for the current track.
  Future<void> retry() async {
    final current = playbackController.queue.current;
    if (current != null) {
      await (_currentResolveFuture = _resolveForSource(current));
    }
  }

  Future<void> _resolveForSource(AudioSource source) async {
    final thisRequestId = ++_requestId;

    final mode = settingsStore.settings.lyricsSource;
    if (mode == 'off') {
      _state = const LyricsStateOff();
      notifyListeners();
      return;
    }

    _state = const LyricsStateLoading();
    notifyListeners();

    try {
      final filePath = source.uri.replaceFirst(RegExp(r'^file:\/\/\/|^file:\/\/'), '');
      final title = source.extras?['title'] ?? p.basenameWithoutExtension(filePath);
      final artist = source.extras?['artist'] ?? '';
      final album = source.extras?['album'];
      final durationMs = int.tryParse(source.extras?['durationMs'] ?? '') ??
          playbackController.currentDuration.inMilliseconds;

      final result = await repository.resolve(
        filePath: filePath,
        title: title,
        artist: artist,
        album: album,
        durationMs: durationMs,
        mode: mode,
      );

      // Stale result check: discard if a newer request began
      if (_disposed || thisRequestId != _requestId) return;

      switch (result) {
        case LyricsResultFound(document: final doc):
          _state = LyricsStateFound(doc);
          _calculatePosition(playbackController.currentPosition);
          notifyListeners();
        case LyricsResultNotFound():
          _state = const LyricsStateNotFound();
          notifyListeners();
        case LyricsResultError(reason: final r):
          AppLogger.instance.warning(
            'Lyrics',
            'Lyrics resolution failed with reason: ${r.name}',
          );
          _state = LyricsStateError(r);
          notifyListeners();
        case LyricsResultOff():
          _state = const LyricsStateOff();
          notifyListeners();
      }
    } catch (_) {
      if (_disposed || thisRequestId != _requestId) return;
      _state = const LyricsStateError(LyricsErrorReason.badResponse);
      notifyListeners();
    }
  }

  /// Updates current line and word positions according to [position].
  ///
  /// Only calls [notifyListeners] when line/word boundaries change, or when
  /// [forceNotify] is true (e.g. for smooth animation tickers).
  void updatePosition(Duration position, {bool forceNotify = false}) {
    if (_disposed) return;
    final changed = _calculatePosition(position);
    if (changed || forceNotify) {
      notifyListeners();
    }
  }

  bool _calculatePosition(Duration position) {
    final doc = document;
    if (doc == null || doc.lines.isEmpty) {
      var didChange = false;
      if (_currentLineIndex != -1) {
        _currentLineIndex = -1;
        didChange = true;
      }
      if (_currentWordIndex != -1) {
        _currentWordIndex = -1;
        didChange = true;
      }
      if (_wordProgress != 0.0) {
        _wordProgress = 0.0;
        didChange = true;
      }
      return didChange;
    }

    final posMs = position.inMilliseconds;
    final newLineIndex = _binarySearchLine(doc.lines, posMs);

    var newWordIndex = -1;
    var newWordProgress = 0.0;

    if (newLineIndex >= 0 && doc.hasWordTiming) {
      final line = doc.lines[newLineIndex];
      final words = line.words;
      if (words != null && words.isNotEmpty) {
        if (posMs >= words.first.startMs) {
          // Find the active word
          var wIdx = 0;
          for (var i = 0; i < words.length; i++) {
            if (words[i].startMs <= posMs) {
              wIdx = i;
            } else {
              break;
            }
          }
          newWordIndex = wIdx;

          final w = words[wIdx];
          final end = w.endMs;
          if (end != null && end > w.startMs) {
            newWordProgress = ((posMs - w.startMs) / (end - w.startMs)).clamp(0.0, 1.0);
          } else {
            newWordProgress = 1.0;
          }
        }
      }
    }

    final changed = newLineIndex != _currentLineIndex ||
        newWordIndex != _currentWordIndex ||
        (newWordProgress - _wordProgress).abs() > 0.02;

    _currentLineIndex = newLineIndex;
    _currentWordIndex = newWordIndex;
    _wordProgress = newWordProgress;

    return changed;
  }

  static int _binarySearchLine(List<LyricsLine> lines, int targetMs) {
    if (lines.isEmpty || targetMs < lines.first.startMs) {
      return -1;
    }

    var low = 0;
    var high = lines.length - 1;
    var result = 0;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].startMs <= targetMs) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    settingsStore.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
