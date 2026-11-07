/// Abstract interface for preventing system sleep or idle suspension while audio is playing.
abstract interface class SleepInhibitor {
  /// Prevents the system from entering idle sleep.
  void acquire();

  /// Releases sleep prevention, allowing normal idle sleep behavior.
  void release();
}
