import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/app/flutter_error_handler.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';

void main() {
  group('handleFlutterError (S2)', () {
    test('presents error details and logs FlutterError with stack trace', () {
      final sink = StringBuffer();
      final logger = AppLogger(customSink: sink);
      final stack = StackTrace.fromString(
        '#0      boomFunction (package:aestheticy/example.dart:42:5)\n'
        '#1      callerFunction (package:aestheticy/main.dart:10:3)',
      );
      final details = FlutterErrorDetails(
        exception: StateError('widget layout exploded'),
        stack: stack,
        library: 'widgets library',
      );

      final presented = <FlutterErrorDetails>[];
      handleFlutterError(
        details,
        logger: logger,
        presentError: presented.add,
      );

      expect(presented, [details]);

      final output = sink.toString();
      expect(output, contains('[ERROR] [Flutter]'));
      expect(output, contains('FlutterError: Bad state: widget layout exploded'));
      expect(output, contains('boomFunction'));
      expect(output, contains('callerFunction'));
    });

    test('handles null stack trace cleanly without throwing', () {
      final sink = StringBuffer();
      final logger = AppLogger(customSink: sink);
      final details = FlutterErrorDetails(
        exception: ArgumentError('bad arg'),
      );

      var presentCalled = false;
      handleFlutterError(
        details,
        logger: logger,
        presentError: (_) => presentCalled = true,
      );

      expect(presentCalled, isTrue);
      final output = sink.toString();
      expect(output, contains('[ERROR] [Flutter]'));
      expect(output, contains('FlutterError: Invalid argument(s): bad arg'));
      expect(output, isNot(contains('| null')));
    });
  });
}
