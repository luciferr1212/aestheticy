/// Localized SnackBar/banner presentation helper for structured [AppError]s.
library;

import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../l10n/app_strings.dart';

/// Maps [AppError] instances to concise localized UI feedback.
abstract final class ErrorPresenter {
  /// Returns the localized one-line message for [error] using [context].
  static String messageFor(BuildContext context, AppError error) {
    return context.t(error.messageKey, args: error.messageArgs);
  }

  /// Displays a calm single-line SnackBar for [error] when [context] is mounted.
  ///
  /// When [onRetry] is provided, attaches a Retry action; otherwise attaches an
  /// Open Logs action when [onOpenLog] is provided.
  static void show(
    BuildContext context,
    AppError error, {
    VoidCallback? onRetry,
    VoidCallback? onOpenLog,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final SnackBarAction? action;
    if (onRetry != null) {
      action = SnackBarAction(
        label: context.t('error.actionRetry'),
        onPressed: onRetry,
      );
    } else if (onOpenLog != null) {
      action = SnackBarAction(
        label: context.t('error.actionOpenLog'),
        onPressed: onOpenLog,
      );
    } else {
      action = null;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          messageFor(context, error),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        duration: duration,
        action: action,
      ),
    );
  }
}
