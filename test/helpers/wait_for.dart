import 'package:flutter_test/flutter_test.dart';

/// Polls [condition] with real time every [step] until it returns true or
/// [timeout] expires. Throws a [TestFailure] with a clear message on timeout.
Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration step = const Duration(milliseconds: 10),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed >= timeout) {
      throw TestFailure(
        'Timed out waiting for condition after ${stopwatch.elapsed.inMilliseconds} ms '
        '(timeout was ${timeout.inMilliseconds} ms).',
      );
    }
    await Future<void>.delayed(step);
  }
}
