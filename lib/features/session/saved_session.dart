import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/playback_queue.dart';

/// An immutable representation of a serialized queue track item.
class SavedSessionItem {
  final String uri;
  final Map<String, String>? extras;

  const SavedSessionItem({
    required this.uri,
    this.extras,
  });

  AudioSource toAudioSource() => AudioSource(uri, extras: extras);

  Map<String, Object?> toJson() => {
        'uri': uri,
        if (extras != null) 'extras': extras,
      };

  factory SavedSessionItem.fromJson(Map<String, Object?>? json) {
    if (json == null) return const SavedSessionItem(uri: '');
    final uri = json['uri'] as String? ?? '';
    final rawExtras = json['extras'];
    Map<String, String>? extras;
    if (rawExtras is Map) {
      extras = rawExtras.map(
        (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
      );
    }
    return SavedSessionItem(uri: uri, extras: extras);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedSessionItem &&
          runtimeType == other.runtimeType &&
          uri == other.uri;

  @override
  int get hashCode => uri.hashCode;
}

/// Immutable model representing a snapshot of the playback queue and state.
class SavedSession {
  static const int maxQueueCapacity = 5000;

  final List<SavedSessionItem> queue;
  final int currentIndex;
  final int positionMs;
  final bool shuffle;
  final String repeatMode;
  final DateTime? savedAt;

  const SavedSession({
    this.queue = const [],
    this.currentIndex = 0,
    this.positionMs = 0,
    this.shuffle = false,
    this.repeatMode = 'off',
    this.savedAt,
  });

  /// An empty default session.
  static const SavedSession empty = SavedSession();

  bool get isEmpty => queue.isEmpty;
  bool get isNotEmpty => queue.isNotEmpty;

  RepeatMode get repeatModeEnum => switch (repeatMode) {
        'all' => RepeatMode.all,
        'one' => RepeatMode.one,
        _ => RepeatMode.off,
      };

  Map<String, Object?> toJson() {
    return {
      'queue': queue.take(maxQueueCapacity).map((item) => item.toJson()).toList(),
      'currentIndex': currentIndex,
      'positionMs': positionMs,
      'shuffle': shuffle,
      'repeatMode': repeatMode,
      'savedAt': savedAt?.toUtc().toIso8601String(),
    };
  }

  factory SavedSession.fromJson(Map<String, Object?>? json) {
    if (json == null) return SavedSession.empty;

    final rawQueue = json['queue'];
    final List<SavedSessionItem> items = [];
    if (rawQueue is List) {
      for (final raw in rawQueue.take(maxQueueCapacity)) {
        if (raw is Map<String, Object?>) {
          items.add(SavedSessionItem.fromJson(raw));
        } else if (raw is Map) {
          items.add(SavedSessionItem.fromJson(Map<String, Object?>.from(raw)));
        }
      }
    }

    final rawIndex = json['currentIndex'];
    final currentIndex = rawIndex is int ? rawIndex : 0;

    final rawPos = json['positionMs'];
    final positionMs = rawPos is int ? rawPos : 0;

    final rawShuffle = json['shuffle'];
    final shuffle = rawShuffle is bool ? rawShuffle : false;

    final rawRepeat = json['repeatMode'];
    final repeatMode = (rawRepeat is String &&
            (rawRepeat == 'off' || rawRepeat == 'all' || rawRepeat == 'one'))
        ? rawRepeat
        : 'off';

    DateTime? savedAt;
    final rawSavedAt = json['savedAt'];
    if (rawSavedAt is String) {
      savedAt = DateTime.tryParse(rawSavedAt);
    }

    return SavedSession(
      queue: items,
      currentIndex: currentIndex,
      positionMs: positionMs,
      shuffle: shuffle,
      repeatMode: repeatMode,
      savedAt: savedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedSession &&
          runtimeType == other.runtimeType &&
          currentIndex == other.currentIndex &&
          positionMs == other.positionMs &&
          shuffle == other.shuffle &&
          repeatMode == other.repeatMode;

  @override
  int get hashCode => Object.hash(
        currentIndex,
        positionMs,
        shuffle,
        repeatMode,
      );
}
