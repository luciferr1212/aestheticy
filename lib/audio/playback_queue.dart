/// Pure-Dart playback queue with shuffle and repeat.
///
/// Zero package imports — fully unit-testable on any platform.
library;

import 'dart:math';

import 'audio_models.dart';

/// Repeat / loop mode for the queue.
enum RepeatMode {
  /// No repeat — stop after the last item.
  off,

  /// Repeat the entire queue.
  all,

  /// Repeat the currently playing item.
  one,
}

/// An ordered list of [AudioSource] items with a cursor, shuffle support,
/// and repeat modes.
class PlaybackQueue {
  /// The items in their original (user) order.
  final List<AudioSource> _items = [];

  /// The playback order (indices into [_items]). Equals the natural order
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

  /// Unmodifiable view of the items in active playback order (reflects shuffle).
  List<AudioSource> get items {
    if (_order.isEmpty) return const [];
    return List<AudioSource>.unmodifiable(_order.map((i) => _items[i]));
  }

  /// Number of items.
  int get length => _items.length;

  /// Whether the queue is empty.
  bool get isEmpty => _items.isEmpty;

  /// The index in active playback order of the currently playing item, or –1 if
  /// nothing is selected.
  int get currentIndex => _orderIndex;

  /// The currently selected item, or `null`.
  AudioSource? get current {
    if (_orderIndex < 0 || _orderIndex >= _order.length) return null;
    return _items[_order[_orderIndex]];
  }

  /// Whether the queue is shuffled.
  bool get isShuffled => _shuffled;

  // ── Mutation ────────────────────────────────────────────────────────

  /// Appends [source] to the end of the queue.
  void add(AudioSource source) {
    final currentItem = current;
    _items.add(source);
    _rebuildOrder(prevItem: currentItem);
  }

  /// Inserts [source] at [index] in user order.
  void insert(int index, AudioSource source) {
    final currentItem = current;
    _items.insert(index, source);
    _rebuildOrder(prevItem: currentItem);
  }

  /// Removes the item at [index] in active playback order.
  ///
  /// If the removed item is the current one, the cursor stays at the
  /// same order position (or moves to the last valid one).
  void remove(int index) {
    if (index < 0 || index >= _order.length) return;
    final currentItem = current;
    final wasCurrent = _orderIndex == index;
    final originalIdx = _order[index];

    _items.removeAt(originalIdx);
    if (_items.isEmpty) {
      _order = [];
      _orderIndex = -1;
      return;
    }

    if (wasCurrent) {
      _rebuildOrder(prevItem: null);
      _orderIndex = index.clamp(0, _order.length - 1);
    } else {
      _rebuildOrder(prevItem: currentItem);
    }
  }

  /// Moves the item at [from] to [to] in active playback order.
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
    _items.clear();
    _order = [];
    _orderIndex = -1;
  }

  /// Replaces all items in the queue with [sources] in natural order,
  /// resets shuffle to off, and sets the cursor to [startIndex].
  void replaceAll(List<AudioSource> sources, {int startIndex = 0}) {
    _items.clear();
    _items.addAll(sources);
    _shuffled = false;
    _order = List<int>.generate(_items.length, (i) => i);
    if (_items.isEmpty) {
      _orderIndex = -1;
    } else {
      _orderIndex = startIndex.clamp(0, _items.length - 1);
    }
  }

  /// Removes upcoming items from the queue.
  ///
  /// If an item is currently selected, all items after the cursor in active
  /// playback order are removed; the current item and any preceding items in
  /// the active order are preserved.
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

    final keptItems = [
      for (var i = 0; i <= _orderIndex; i++) _items[_order[i]],
    ];
    _items.clear();
    _items.addAll(keptItems);
    _order = List<int>.generate(_items.length, (i) => i);
    _orderIndex = _items.length - 1;
  }

  // ── Shuffle ─────────────────────────────────────────────────────────

  /// Enables or disables shuffle.
  ///
  /// When turning shuffle **on**, the current item stays first in the
  /// shuffled order; the rest are randomised.
  ///
  /// When turning shuffle **off**, the order reverts to the natural
  /// sequence and the cursor points at the current item's original index.
  void setShuffle(bool enabled) {
    final currentItem = current;
    _shuffled = enabled;
    _rebuildOrder(prevItem: currentItem);
  }

  /// Rebuilds [_order] from [_items]. When [prevItem] is non-null, the
  /// cursor stays on that item.
  void _rebuildOrder({required AudioSource? prevItem}) {
    _order = List<int>.generate(_items.length, (i) => i);

    if (_shuffled && _items.isNotEmpty) {
      // Fisher-Yates, but pin the current item at position 0.
      final pinIdx = prevItem != null ? _items.indexOf(prevItem) : -1;

      if (pinIdx >= 0) {
        _order.remove(pinIdx);
        // Shuffle the rest.
        for (var i = _order.length - 1; i > 0; i--) {
          final j = _random.nextInt(i + 1);
          final tmp = _order[i];
          _order[i] = _order[j];
          _order[j] = tmp;
        }
        _order.insert(0, pinIdx);
        _orderIndex = 0;
      } else {
        // No current item — shuffle everything.
        for (var i = _order.length - 1; i > 0; i--) {
          final j = _random.nextInt(i + 1);
          final tmp = _order[i];
          _order[i] = _order[j];
          _order[j] = tmp;
        }
        _orderIndex = _items.isEmpty ? -1 : 0;
      }
    } else if (prevItem != null) {
      _orderIndex = _items.indexOf(prevItem);
      if (_orderIndex < 0 && _items.isNotEmpty) _orderIndex = 0;
    } else if (_items.isNotEmpty && _orderIndex < 0) {
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
      // Stay on the same item.
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
    if (_order.isEmpty) return null;

    if (repeatMode == RepeatMode.one) {
      return current;
    }

    if (_orderIndex + 1 < _order.length) {
      return _items[_order[_orderIndex + 1]];
    }

    if (repeatMode == RepeatMode.all && _order.isNotEmpty) {
      return _items[_order[0]];
    }

    return null;
  }

  /// Jumps to [index] in active playback order.
  void jumpTo(int index) {
    if (index < 0 || index >= _order.length) return;
    _orderIndex = index;
  }
}
