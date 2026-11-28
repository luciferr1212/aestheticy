import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:aestheticy/app/aestheticy_app.dart';
import 'package:aestheticy/app/app_bootstrap.dart';
import 'package:aestheticy/app/flutter_error_handler.dart';
import 'package:aestheticy/app/init_error_apps.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';

export 'package:aestheticy/app/aestheticy_app.dart';
export 'package:aestheticy/app/init_error_apps.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppLogger.instance.init();

    FlutterError.onError = handleFlutterError;

    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.instance.error(
        'Platform',
        'PlatformDispatcher error: $error',
        error,
        stack,
      );
      return true;
    };

    final result = await AppBootstrap.initialize();
    switch (result) {
      case AppBootstrapAudioFailure(:final error, :final stackTrace):
        runApp(AudioInitErrorApp(
          error: error.toString(),
          stackTrace: stackTrace.toString(),
        ));
      case AppBootstrapLibraryFailure(:final error, :final stackTrace):
        runApp(LibraryInitErrorApp(
          error: error.toString(),
          stackTrace: stackTrace.toString(),
        ));
      case AppBootstrapSuccess(:final services):
        runApp(AestheticyApp.fromServices(services));
    }
  }, (error, stack) {
    AppLogger.instance.error(
      'Zone',
      'Unhandled zone error: $error',
      error,
      stack,
    );
  });
}
