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
import 'lyrics_offset_store.dart';
import 'lyrics_repository.dart';

/// Number of milliseconds before a synced line timestamp that it becomes active
/// so line scale/opacity and scroll transitions land on the beat.
const int kLyricsLineLeadMs = 120;

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
  late final LyricsOffsetStore _offsetStore;
  bool _createdOffsetStoreLocally = false;

  final List<StreamSubscription<Object?>> _subs = [];
  int _requestId = 0;
  int _offsetRequestId = 0;
  int _offsetMs = 0;
  Duration _lastPlaybackPosition = Duration.zero;
  bool _hasRecordedPosition = false;
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
  final ValueNotifier<int> _activeLineNotifier = ValueNotifier<int>(-1);
  final ValueNotifier<int> _activeWordNotifier = ValueNotifier<int>(-1);
  bool _disposed = false;

  /// Creates a [LyricsController].
  LyricsController({
    required this.playbackController,
    required this.repository,
    required this.settingsStore,
    LyricsOffsetStore? offsetStore,
  }) {
    if (offsetStore != null) {
      _offsetStore = offsetStore;
    } else {
      _offsetStore = LyricsOffsetStore();
      _createdOffsetStoreLocally = true;
    }
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
      unawaited(_loadOffsetForTrack(current, ++_offsetRequestId));
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

  /// Listenables for selector-based line and word updates without whole-list rebuilds.
  ValueListenable<int> get activeLineListenable => _activeLineNotifier;

  /// Listenable notifying when the active word index changes.
  ValueListenable<int> get activeWordListenable => _activeWordNotifier;

  /// 0-based index of the actively playing word within [currentLineIndex], or -1.
  int get currentWordIndex => _currentWordIndex;

  /// 0.0 to 1.0 progress of the current word between start and end times.
  double get wordProgress => _wordProgress;

  /// Latest playback position processed by [updatePosition].
  Duration get lastPlaybackPosition => _lastPlaybackPosition;

  /// Whether at least one playback position update has been recorded for the current track.
  bool get hasRecordedPosition => _hasRecordedPosition;

  /// Current per-track lyrics timing offset in milliseconds (`-15000..+15000`).
  int get offsetMs => _offsetMs;

  /// Updates the current track's lyrics timing offset and persists it.
  ///
  /// Positive values delay lyrics (show later); negative values advance them.
  Future<void> setOffset(int ms) async {
    if (_disposed) return;
    final uri = _currentTrackUri;
    if (uri == null) return;
    _offsetRequestId++;
    final clamped = LyricsOffsetStore.clampOffsetMs(ms);
    if (clamped != _offsetMs) {
      _offsetMs = clamped;
      final pos = _hasRecordedPosition
          ? _lastPlaybackPosition
          : playbackController.currentPosition;
      _calculatePosition(pos);
      notifyListeners();
    }
    await _offsetStore.setOffset(_trackPathForUri(uri), clamped);
  }

  /// Resets the current track's lyrics offset to zero.
  Future<void> resetOffset() => setOffset(0);

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
    _offsetRequestId++;
    _offsetMs = 0;
    _hasRecordedPosition = false;
    _lastPlaybackPosition = Duration.zero;
    _currentLineIndex = -1;
    _currentWordIndex = -1;
    _wordProgress = 0.0;
    _activeLineNotifier.value = -1;
    _activeWordNotifier.value = -1;

    if (source == null) {
      _requestId++;
      _state = const LyricsStateNotFound();
      notifyListeners();
      return;
    }

    unawaited(_loadOffsetForTrack(source, _offsetRequestId));
    _currentResolveFuture = _resolveForSource(source);
  }

  static String _trackPathForUri(String uri) {
    return uri.replaceFirst(RegExp(r'^file:\/\/\/|^file:\/\/'), '');
  }

  Future<void> _loadOffsetForTrack(AudioSource source, int reqId) async {
    final trackPath = _trackPathForUri(source.uri);
    final loaded = await _offsetStore.loadOffset(trackPath);
    if (_disposed ||
        reqId != _offsetRequestId ||
        _currentTrackUri != source.uri) {
      return;
    }
    final clamped = LyricsOffsetStore.clampOffsetMs(loaded);
    if (clamped != _offsetMs) {
      _offsetMs = clamped;
      final pos = _hasRecordedPosition
          ? _lastPlaybackPosition
          : playbackController.currentPosition;
      _calculatePosition(pos);
      notifyListeners();
    }
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
      _resetPositionSelection();
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
          _resetPositionSelection();
          _state = const LyricsStateNotFound();
          notifyListeners();
        case LyricsResultError(reason: final r):
          AppLogger.instance.warning(
            'Lyrics',
            'Lyrics resolution failed with reason: ${r.name}',
          );
          _resetPositionSelection();
          _state = LyricsStateError(r);
          notifyListeners();
        case LyricsResultOff():
          _resetPositionSelection();
          _state = const LyricsStateOff();
          notifyListeners();
      }
    } catch (_) {
      if (_disposed || thisRequestId != _requestId) return;
      _resetPositionSelection();
      _state = const LyricsStateError(LyricsErrorReason.badResponse);
      notifyListeners();
    }
  }

  void _resetPositionSelection() {
    _currentLineIndex = -1;
    _currentWordIndex = -1;
    _wordProgress = 0.0;
    _activeLineNotifier.value = -1;
    _activeWordNotifier.value = -1;
  }

  /// Updates current line and word positions according to [position].
  ///
  /// Only calls [notifyListeners] when line/word boundaries change, or when
  /// [forceNotify] is true (e.g. for smooth animation tickers).
  void updatePosition(Duration position, {bool forceNotify = false}) {
    if (_disposed) return;
    _lastPlaybackPosition = position;
    _hasRecordedPosition = true;
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
        _activeLineNotifier.value = -1;
        didChange = true;
      }
      if (_currentWordIndex != -1) {
        _currentWordIndex = -1;
        _activeWordNotifier.value = -1;
        didChange = true;
      }
      if (_wordProgress != 0.0) {
        _wordProgress = 0.0;
        didChange = true;
      }
      return didChange;
    }

    // Effective position = playback position minus user offset.
    // Positive offset delays lyrics (show later); negative shows earlier.
    final effectivePosMs = position.inMilliseconds - _offsetMs;
    // Apply line lead ONLY to line activation, never to word timing.
    final linePosMs = effectivePosMs + kLyricsLineLeadMs;
    final newLineIndex = _binarySearchLine(doc.lines, linePosMs);

    final wordPosMs = effectivePosMs;
    var newWordIndex = -1;
    var newWordProgress = 0.0;

    if (newLineIndex >= 0 && doc.hasWordTiming) {
      final line = doc.lines[newLineIndex];
      final words = line.words;
      if (words != null && words.isNotEmpty) {
        if (wordPosMs >= words.first.startMs) {
          // Find the active word strictly from un-leaded playback position
          var wIdx = 0;
          for (var i = 0; i < words.length; i++) {
            if (words[i].startMs <= wordPosMs) {
              wIdx = i;
            } else {
              break;
            }
          }
          newWordIndex = wIdx;

          final w = words[wIdx];
          final end = w.endMs;
          if (end != null && end > w.startMs) {
            newWordProgress = ((wordPosMs - w.startMs) / (end - w.startMs)).clamp(0.0, 1.0);
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
    if (_activeLineNotifier.value != newLineIndex) {
      _activeLineNotifier.value = newLineIndex;
    }
    if (_activeWordNotifier.value != newWordIndex) {
      _activeWordNotifier.value = newWordIndex;
    }

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
    if (_createdOffsetStoreLocally) {
      _offsetStore.dispose();
    }
    _activeLineNotifier.dispose();
    _activeWordNotifier.dispose();
    super.dispose();
  }
}
