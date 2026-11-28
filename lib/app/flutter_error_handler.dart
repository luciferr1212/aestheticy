import 'package:flutter/foundation.dart';

import 'package:aestheticy/diagnostics/app_logger.dart';

/// Signature matching [FlutterError.presentError] for injection in tests.
typedef FlutterErrorPresenter = void Function(FlutterErrorDetails details);

/// Presents a framework [FlutterErrorDetails] report and logs the error and
/// optional stack trace via [AppLogger].
void handleFlutterError(
  FlutterErrorDetails details, {
  AppLogger? logger,
  FlutterErrorPresenter? presentError,
}) {
  (presentError ?? FlutterError.presentError)(details);
  (logger ?? AppLogger.instance).error(
    'Flutter',
    'FlutterError: ${details.exceptionAsString()}',
    null,
    details.stack,
  );
}
