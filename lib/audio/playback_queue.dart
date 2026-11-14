/// Pure-Dart playback queue with shuffle, repeat, entry identity, and user-queue semantics.
///
/// Zero package imports — fully unit-testable on any platform.
library;

import 'dart:math';

import 'audio_models.dart';

/// Whether upcoming user-queued tracks survive and play after the newly started track
/// when starting playback from a new context (e.g. clicking an album or track list).
const bool kKeepUserQueueOnNewContext = true;

/// Repeat / loop mode for the queue.
enum RepeatMode {
  /// No repeat — stop after the last item.
  off,

  /// Repeat the entire queue.
  all,

  /// Repeat the currently playing item.
  one,
}

/// An ordered list of [QueueEntry] items with a cursor, shuffle support,
/// and repeat modes.
class PlaybackQueue {
  /// Incrementing ID counter for unique entry identity within this queue.
  int _nextEntryId = 0;

  /// The entries in their original (natural) storage order.
  final List<QueueEntry> _entries = [];

  /// The active playback order (indices into [_entries]). Equals natural order
  /// when not shuffled.
  List<int> _order = [];

  /// Cursor into [_order].
  int _orderIndex = -1;

  /// Current repeat mode.
  RepeatMode repeatMode = RepeatMode.off;

  /// Whether the queue is in shuffle mode.
  bool _shuffled = false;

  /// RNG for shuffle — injectable for deterministic tests.
  final Random _random;

  /// Creates an empty queue with an optional injectable [random] for
  /// deterministic shuffle in tests.
  PlaybackQueue({Random? random}) : _random = random ?? Random();

  // ── Accessors ───────────────────────────────────────────────────────

  /// Unmodifiable view of the audio sources in active playback order (reflects shuffle).
  List<AudioSource> get items {
    if (_order.isEmpty) return const [];
    return List<AudioSource>.unmodifiable(_order.map((i) => _entries[i].source));
  }

  /// Unmodifiable view of the queue entries in active playback order (reflects shuffle).
  List<QueueEntry> get entries {
    if (_order.isEmpty) return const [];
    return List<QueueEntry>.unmodifiable(_order.map((i) => _entries[i]));
  }

  /// Number of items.
  int get length => _entries.length;

  /// Whether the queue is empty.
  bool get isEmpty => _entries.isEmpty;

  /// The index in active playback order of the currently playing item, or –1 if
  /// nothing is selected.
  int get currentIndex => _orderIndex;

  /// The currently selected queue entry, or `null`.
  QueueEntry? get currentEntry {
    if (_orderIndex < 0 || _orderIndex >= _order.length) return null;
    return _entries[_order[_orderIndex]];
  }

  /// The currently selected audio source, or `null`.
  AudioSource? get current => currentEntry?.source;

  /// Whether the queue is shuffled.
  bool get isShuffled => _shuffled;

  /// Allocates a new [QueueEntry] with a unique incrementing id for this queue.
  QueueEntry createEntry(AudioSource source, {bool isUserQueued = false}) {
    return QueueEntry(
      id: _nextEntryId++,
      source: source,
      isUserQueued: isUserQueued,
    );
  }

  // ── Mutation ────────────────────────────────────────────────────────

  /// Appends [source] to the end of the queue.
  void add(AudioSource source, {bool isUserQueued = false}) {
    final curId = currentEntry?.id;
    _entries.add(createEntry(source, isUserQueued: isUserQueued));
    _rebuildOrder(prevEntryId: curId);
  }

  /// Inserts [source] at [index] in natural storage order.
  void insert(int index, AudioSource source, {bool isUserQueued = false}) {
    final curId = currentEntry?.id;
    final clamped = index.clamp(0, _entries.length);
    _entries.insert(clamped, createEntry(source, isUserQueued: isUserQueued));
    _rebuildOrder(prevEntryId: curId);
  }

  /// Removes the item at [index] in active playback order.
  ///
  /// If the removed item is the current one, the cursor stays at the
  /// same order position (or moves to the last valid one).
  void remove(int index) {
    if (index < 0 || index >= _order.length) return;
    final wasCurrent = _orderIndex == index;
    final originalIdx = _order.removeAt(index);

    _entries.removeAt(originalIdx);

    if (_entries.isEmpty) {
      _order = [];
      _orderIndex = -1;
      return;
    }

    for (var i = 0; i < _order.length; i++) {
      if (_order[i] > originalIdx) {
        _order[i]--;
      }
    }

    if (wasCurrent) {
      _orderIndex = index.clamp(0, _order.length - 1);
    } else if (index < _orderIndex) {
      _orderIndex--;
    } else if (_orderIndex >= _order.length) {
      _orderIndex = _order.length - 1;
    }
  }

  /// Moves the item at [from] to [to] in active playback order.
  ///
  /// The moved entry preserves its [QueueEntry.isUserQueued] flag.
  void move(int from, int to) {
    if (from < 0 || from >= _order.length) return;
    if (to < 0 || to >= _order.length) return;
    if (from == to) return;

    final o = _order.removeAt(from);
    _order.insert(to, o);

    if (_orderIndex == from) {
      _orderIndex = to;
    } else if (from < _orderIndex && to >= _orderIndex) {
      _orderIndex--;
    } else if (from > _orderIndex && to <= _orderIndex) {
      _orderIndex++;
    }
  }

  /// Removes all items and resets the cursor.
  void clear() {
    _entries.clear();
    _order = [];
    _orderIndex = -1;
  }

  /// Replaces all items in the queue with [sources] in natural order,
  /// resets shuffle to off, and sets the cursor to [startIndex].
  void replaceAll(
    List<AudioSource> sources, {
    int startIndex = 0,
    List<bool>? userQueuedFlags,
  }) {
    _entries.clear();
    for (var i = 0; i < sources.length; i++) {
      final isUser = userQueuedFlags != null && i < userQueuedFlags.length
          ? userQueuedFlags[i]
          : false;
      _entries.add(createEntry(sources[i], isUserQueued: isUser));
    }
    _shuffled = false;
    _order = List<int>.generate(_entries.length, (i) => i);
    if (_entries.isEmpty) {
      _orderIndex = -1;
    } else {
      _orderIndex = startIndex.clamp(0, _entries.length - 1);
    }
  }

  /// Replaces all items in the queue with the provided [entries],
  /// resets shuffle to off, and sets the cursor to [startIndex].
  void replaceAllEntries(List<QueueEntry> entries, {int startIndex = 0}) {
    _entries.clear();
    _entries.addAll(entries);
    _shuffled = false;
    _order = List<int>.generate(_entries.length, (i) => i);
    if (_entries.isEmpty) {
      _orderIndex = -1;
    } else {
      _orderIndex = startIndex.clamp(0, _entries.length - 1);
    }
  }

  /// Removes upcoming items from the queue.
  ///
  /// If an item is currently selected, all items after the cursor in active
  /// playback order are removed (both context and user-queued items); the
  /// current item and any preceding items in active order are preserved.
  ///
  /// If nothing is currently selected (or the queue is empty), the entire
  /// queue is cleared.
  void clearUpcoming() {
    if (current == null || _orderIndex < 0 || _orderIndex >= _order.length) {
      clear();
      return;
    }
    if (_orderIndex + 1 >= _order.length) {
      return;
    }

    final keptEntries = [
      for (var i = 0; i <= _orderIndex; i++) _entries[_order[i]],
    ];
    _entries.clear();
    _entries.addAll(keptEntries);
    _shuffled = false;
    _order = List<int>.generate(_entries.length, (i) => i);
    _orderIndex = _entries.length - 1;
  }

  /// Inserts [sources] as new user-queued entries immediately after the current entry
  /// (the START of the upcoming user block), preserving their relative order.
  /// Later [playNext] calls go in front of earlier ones.
  void playNext(List<AudioSource> sources) {
    if (sources.isEmpty) return;
    if (isEmpty || currentEntry == null) {
      replaceAll(sources, startIndex: 0);
      return;
    }

    final curNatIdx = _order[_orderIndex];
    final newEntries = [
      for (final s in sources) createEntry(s, isUserQueued: true),
    ];

    final natInsertPos = curNatIdx + 1;
    _entries.insertAll(natInsertPos, newEntries);

    for (var i = 0; i < _order.length; i++) {
      if (_order[i] >= natInsertPos) {
        _order[i] += newEntries.length;
      }
    }

    for (var i = 0; i < newEntries.length; i++) {
      _order.insert(_orderIndex + 1 + i, natInsertPos + i);
    }
  }

  /// Inserts [sources] as new user-queued entries after the current entry and after
  /// the LAST upcoming user-queued entry (the END of the user block), in the given order.
  void addToQueue(List<AudioSource> sources) {
    if (sources.isEmpty) return;
    if (isEmpty || currentEntry == null) {
      replaceAll(sources, startIndex: 0);
      return;
    }

    final curNatIdx = _order[_orderIndex];
    final newEntries = [
      for (final s in sources) createEntry(s, isUserQueued: true),
    ];

    // Find the end of upcoming user-queued block in active playback order
    var activeUserBlockLen = 0;
    while (_orderIndex + 1 + activeUserBlockLen < _order.length &&
        _entries[_order[_orderIndex + 1 + activeUserBlockLen]].isUserQueued) {
      activeUserBlockLen++;
    }
    final activeInsertPos = _orderIndex + 1 + activeUserBlockLen;

    // Find the end of upcoming user-queued block in natural storage order
    var natUserBlockLen = 0;
    while (curNatIdx + 1 + natUserBlockLen < _entries.length &&
        _entries[curNatIdx + 1 + natUserBlockLen].isUserQueued) {
      natUserBlockLen++;
    }
    final natInsertPos = curNatIdx + 1 + natUserBlockLen;

    _entries.insertAll(natInsertPos, newEntries);

    for (var i = 0; i < _order.length; i++) {
      if (_order[i] >= natInsertPos) {
        _order[i] += newEntries.length;
      }
    }

    for (var i = 0; i < newEntries.length; i++) {
      _order.insert(activeInsertPos + i, natInsertPos + i);
    }
  }

  // ── Shuffle ─────────────────────────────────────────────────────────

  /// Enables or disables shuffle.
  ///
  /// When turning shuffle **on**, the current item stays first in the
  /// shuffled order, upcoming user-queued entries immediately follow in their
  /// relative order, and the remaining context items are randomized.
  ///
  /// When turning shuffle **off**, the order reverts to the natural
  /// sequence and the cursor points at the current item's natural index.
  void setShuffle(bool enabled) {
    if (_shuffled == enabled) return;
    final curId = currentEntry?.id;
    _shuffled = enabled;
    _rebuildOrder(prevEntryId: curId);
  }

  /// Rebuilds [_order] from [_entries]. When [prevEntryId] is non-null, the
  /// cursor stays on that entry.
  void _rebuildOrder({required int? prevEntryId}) {
    if (_entries.isEmpty) {
      _order = [];
      _orderIndex = -1;
      return;
    }

    if (!_shuffled) {
      _order = List<int>.generate(_entries.length, (i) => i);
      if (prevEntryId != null) {
        _orderIndex = _entries.indexWhere((e) => e.id == prevEntryId);
        if (_orderIndex < 0) _orderIndex = 0;
      } else if (_orderIndex < 0) {
        _orderIndex = 0;
      } else if (_orderIndex >= _entries.length) {
        _orderIndex = _entries.length - 1;
      }
      return;
    }

    final pinIdx = prevEntryId != null
        ? _entries.indexWhere((e) => e.id == prevEntryId)
        : -1;

    if (pinIdx >= 0) {
      final userQueueIndices = <int>[];
      var k = pinIdx + 1;
      while (k < _entries.length && _entries[k].isUserQueued) {
        userQueueIndices.add(k);
        k++;
      }

      final remaining = <int>[];
      for (var i = 0; i < _entries.length; i++) {
        if (i != pinIdx && !userQueueIndices.contains(i)) {
          remaining.add(i);
        }
      }

      for (var i = remaining.length - 1; i > 0; i--) {
        final j = _random.nextInt(i + 1);
        final tmp = remaining[i];
        remaining[i] = remaining[j];
        remaining[j] = tmp;
      }

      _order = [
        pinIdx,
        ...userQueueIndices,
        ...remaining,
      ];
      _orderIndex = 0;
    } else {
      final all = List<int>.generate(_entries.length, (i) => i);
      for (var i = all.length - 1; i > 0; i--) {
        final j = _random.nextInt(i + 1);
        final tmp = all[i];
        all[i] = all[j];
        all[j] = tmp;
      }
      _order = all;
      _orderIndex = 0;
    }
  }

  // ── Navigation ──────────────────────────────────────────────────────

  /// Automatically advances to the next track upon track completion.
  ///
  /// In [RepeatMode.one], repeats the same track.
  /// In [RepeatMode.all], wraps around to the beginning.
  /// In [RepeatMode.off], stops at the end of the queue.
  AudioSource? advance() {
    if (_order.isEmpty) return null;

    if (repeatMode == RepeatMode.one) {
      return current;
    }

    if (_orderIndex + 1 < _order.length) {
      _orderIndex++;
      return current;
    }

    // End of queue.
    if (repeatMode == RepeatMode.all) {
      _orderIndex = 0;
      return current;
    }

    // RepeatMode.off — no more items.
    return null;
  }

  /// Moves to the next item (manual skip).
  ///
  /// Always moves to the neighbouring track even in [RepeatMode.one].
  /// In [RepeatMode.all], wraps around to the beginning.
  /// Returns the new current item, or `null` if the end was reached without repeat.
  AudioSource? next() {
    if (_order.isEmpty) return null;

    if (_orderIndex + 1 < _order.length) {
      _orderIndex++;
      return current;
    }

    // End of queue.
    if (repeatMode == RepeatMode.all) {
      _orderIndex = 0;
      return current;
    }

    // RepeatMode.off or RepeatMode.one — no more items beyond end.
    return null;
  }

  /// Moves to the previous item (manual skip).
  ///
  /// Always moves to the neighbouring track even in [RepeatMode.one].
  /// In [RepeatMode.all], wraps around to the end.
  /// Returns the new current item, or `null` if at the start without repeat.
  AudioSource? previous() {
    if (_order.isEmpty) return null;

    if (_orderIndex - 1 >= 0) {
      _orderIndex--;
      return current;
    }

    // Start of queue.
    if (repeatMode == RepeatMode.all) {
      _orderIndex = _order.length - 1;
      return current;
    }

    return null;
  }

  /// Returns the next item that [next] would navigate to, without
  /// actually moving the cursor. Used by the controller to preload.
  AudioSource? peekNext() {
    return peekNextEntry()?.source;
  }

  /// Returns the next [QueueEntry] that [next] would navigate to, without
  /// actually moving the cursor.
  QueueEntry? peekNextEntry() {
    if (_order.isEmpty) return null;

    if (repeatMode == RepeatMode.one) {
      return currentEntry;
    }

    if (_orderIndex + 1 < _order.length) {
      return _entries[_order[_orderIndex + 1]];
    }

    if (repeatMode == RepeatMode.all && _order.isNotEmpty) {
      return _entries[_order[0]];
    }

    return null;
  }

  /// Jumps to [index] in active playback order.
  void jumpTo(int index) {
    if (index < 0 || index >= _order.length) return;
    _orderIndex = index;
  }
}
