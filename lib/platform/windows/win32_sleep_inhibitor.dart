import 'dart:ffi';
import 'dart:io';

import '../../diagnostics/app_logger.dart';
import '../sleep_inhibitor.dart';

typedef _SetThreadExecutionStateC = Uint32 Function(Uint32 esFlags);
typedef _SetThreadExecutionStateDart = int Function(int esFlags);

/// Real Windows implementation of [SleepInhibitor] using kernel32 `SetThreadExecutionState`.
class Win32SleepInhibitor implements SleepInhibitor {
  static const int _esSystemRequired = 0x00000001;
  static const int _esContinuous = 0x80000000;

  _SetThreadExecutionStateDart? _setThreadExecutionState;
  bool _initialized = false;
  bool _isAcquired = false;

  void _ensureLoaded() {
    if (_initialized || !Platform.isWindows) return;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      _setThreadExecutionState = kernel32
          .lookupFunction<_SetThreadExecutionStateC, _SetThreadExecutionStateDart>(
        'SetThreadExecutionState',
      );
      _initialized = true;
    } catch (e, st) {
      _initialized = true;
      AppLogger.instance.warning('SleepInhibitor', 'Failed to load kernel32: $e', e, st);
    }
  }

  @override
  void acquire() {
    if (!Platform.isWindows) return;
    _ensureLoaded();
    final fn = _setThreadExecutionState;
    if (fn == null) return;

    try {
      final result = fn(_esContinuous | _esSystemRequired);
      if (result == 0) {
        AppLogger.instance.warning(
          'SleepInhibitor',
          'SetThreadExecutionState acquire returned 0',
        );
      } else {
        _isAcquired = true;
      }
    } catch (e, st) {
      AppLogger.instance.warning(
        'SleepInhibitor',
        'SetThreadExecutionState acquire failed: $e',
        e,
        st,
      );
    }
  }

  @override
  void release() {
    if (!Platform.isWindows) return;
    _ensureLoaded();
    final fn = _setThreadExecutionState;
    if (fn == null) return;

    try {
      final result = fn(_esContinuous);
      if (result == 0) {
        AppLogger.instance.warning(
          'SleepInhibitor',
          'SetThreadExecutionState release returned 0',
        );
      } else {
        _isAcquired = false;
      }
    } catch (e, st) {
      AppLogger.instance.warning(
        'SleepInhibitor',
        'SetThreadExecutionState release failed: $e',
        e,
        st,
      );
    }
  }

  /// Whether sleep prevention is currently active on the thread.
  bool get isAcquired => _isAcquired;
}
