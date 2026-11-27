/// Result container and typed application error hierarchy.
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// Represents the outcome of an operation that can either succeed with a
/// value of type [T] ([Ok]) or fail with a structured [AppError] ([Err]).
sealed class Result<T> {
  const Result();

  /// Whether this result holds a success value.
  bool get isOk => this is Ok<T>;

  /// Whether this result holds a failure.
  bool get isErr => this is Err<T>;

  /// Returns the success value when [Ok], or `null` when [Err].
  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  /// Returns the [AppError] when [Err], or `null` when [Ok].
  AppError? get errorOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final error) => error,
      };

  /// Matches both outcomes and returns the handler value.
  R when<R>({
    required R Function(T value) ok,
    required R Function(AppError error) err,
  }) {
    return switch (this) {
      Ok<T>(:final value) => ok(value),
      Err<T>(:final error) => err(error),
    };
  }

  /// Transforms the success value while propagating any [Err] unchanged.
  Result<U> map<U>(U Function(T value) transform) {
    return switch (this) {
      Ok<T>(:final value) => Ok<U>(transform(value)),
      Err<T>(:final error) => Err<U>(error),
    };
  }
}

/// Successful outcome wrapping [value].
final class Ok<T> extends Result<T> {
  /// The wrapped success value.
  final T value;

  /// Creates an [Ok] result holding [value].
  const Ok(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Ok<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Ok($value)';
}

/// Failed outcome wrapping an [AppError].
final class Err<T> extends Result<T> {
  /// The structured application failure.
  final AppError error;

  /// Creates an [Err] result holding [error].
  const Err(this.error);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Err<T> && other.error == error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Err($error)';
}

/// Typed, localizable error hierarchy shared across storage, parsing, I/O,
/// network, and platform boundaries.
sealed class AppError implements Exception {
  /// Stable machine-readable error code for diagnostics and tests.
  final String code;

  /// Key in `AppStrings` used to display a localized one-line message.
  final String messageKey;

  /// Optional placeholder substitutions passed to `AppStrings.t`.
  final Map<String, String> messageArgs;

  /// Original thrown object, if any (never displayed raw to the user).
  final Object? cause;

  /// Stack trace captured alongside [cause], if any.
  final StackTrace? stackTrace;

  /// Creates an [AppError].
  const AppError({
    required this.code,
    required this.messageKey,
    this.messageArgs = const {},
    this.cause,
    this.stackTrace,
  });

  /// Maps an arbitrary thrown [error] into an appropriate [AppError] subtype.
  factory AppError.fromException(
    Object error, [
    StackTrace? stackTrace,
    String? messageKey,
    Map<String, String> messageArgs = const {},
  ]) {
    if (error is AppError) {
      return error;
    }
    final typeName = error.runtimeType.toString();
    if (error is SocketException || error is HttpException) {
      return NetworkFailure(
        messageKey: messageKey ?? 'error.networkFailure',
        messageArgs: messageArgs,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is FileSystemException || error is IOException) {
      return IoFailure(
        messageKey: messageKey ?? 'error.ioFailure',
        messageArgs: messageArgs,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is FormatException) {
      return ParseFailure(
        messageKey: messageKey ?? 'error.parseFailure',
        messageArgs: messageArgs,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is PlatformException) {
      return PlatformFailure(
        messageKey: messageKey ?? 'error.platformFailure',
        messageArgs: messageArgs,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (typeName.contains('Sqlite') ||
        typeName == 'UserDataReadOnlyException' ||
        (error is StateError &&
            error.toString().toLowerCase().contains('database'))) {
      return DatabaseFailure(
        code: typeName == 'UserDataReadOnlyException'
            ? 'userdata_read_only'
            : 'database_failure',
        messageKey: messageKey ?? 'error.databaseFailure',
        messageArgs: messageArgs,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return PlatformFailure(
      messageKey: messageKey ?? 'error.platformFailure',
      messageArgs: messageArgs,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  @override
  String toString() => '$runtimeType(code: $code, messageKey: $messageKey)';
}

/// Filesystem or stream I/O failure.
final class IoFailure extends AppError {
  /// Creates an [IoFailure].
  const IoFailure({
    super.code = 'io_failure',
    super.messageKey = 'error.ioFailure',
    super.messageArgs,
    super.cause,
    super.stackTrace,
  });
}

/// Local SQLite or user-data persistence failure.
final class DatabaseFailure extends AppError {
  /// Creates a [DatabaseFailure].
  const DatabaseFailure({
    super.code = 'database_failure',
    super.messageKey = 'error.databaseFailure',
    super.messageArgs,
    super.cause,
    super.stackTrace,
  });
}

/// Remote HTTP / DNS / socket connectivity failure.
final class NetworkFailure extends AppError {
  /// Creates a [NetworkFailure].
  const NetworkFailure({
    super.code = 'network_failure',
    super.messageKey = 'error.networkFailure',
    super.messageArgs,
    super.cause,
    super.stackTrace,
  });
}

/// Malformed JSON, LRC, M3U, or metadata format failure.
final class ParseFailure extends AppError {
  /// Creates a [ParseFailure].
  const ParseFailure({
    super.code = 'parse_failure',
    super.messageKey = 'error.parseFailure',
    super.messageArgs,
    super.cause,
    super.stackTrace,
  });
}

/// OS / Win32 / plugin platform bridge failure.
final class PlatformFailure extends AppError {
  /// Creates a [PlatformFailure].
  const PlatformFailure({
    super.code = 'platform_failure',
    super.messageKey = 'error.platformFailure',
    super.messageArgs,
    super.cause,
    super.stackTrace,
  });
}
