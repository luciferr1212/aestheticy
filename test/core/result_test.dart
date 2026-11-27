import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/core/result.dart';

void main() {
  group('Result & AppError (S2)', () {
    test('Ok and Err expose helpers, equality, when, and map', () {
      const Result<int> success = Ok<int>(42);
      const Result<int> failure = Err<int>(IoFailure(cause: 'disk full'));

      expect(success.isOk, isTrue);
      expect(success.isErr, isFalse);
      expect(success.valueOrNull, equals(42));
      expect(success.errorOrNull, isNull);
      expect(
        success.when(ok: (v) => v + 1, err: (_) => -1),
        equals(43),
      );
      expect(success.map((v) => v.toString()), equals(const Ok<String>('42')));

      expect(failure.isOk, isFalse);
      expect(failure.isErr, isTrue);
      expect(failure.valueOrNull, isNull);
      expect(failure.errorOrNull, isA<IoFailure>());
      expect(
        failure.when(ok: (_) => 'ok', err: (e) => e.code),
        equals('io_failure'),
      );
      expect(failure.map((v) => v.toString()).isErr, isTrue);
    });

    test('AppError sealed hierarchy defines stable codes and localization keys', () {
      const errors = <AppError>[
        IoFailure(),
        DatabaseFailure(),
        NetworkFailure(),
        ParseFailure(),
        PlatformFailure(),
      ];

      expect(
        errors.map((e) => e.code).toList(),
        equals([
          'io_failure',
          'database_failure',
          'network_failure',
          'parse_failure',
          'platform_failure',
        ]),
      );
      expect(
        errors.map((e) => e.messageKey).toList(),
        equals([
          'error.ioFailure',
          'error.databaseFailure',
          'error.networkFailure',
          'error.parseFailure',
          'error.platformFailure',
        ]),
      );
    });

    test('AppError.fromException maps IO, network, parse, platform, and existing AppError', () {
      final st = StackTrace.current;

      expect(
        AppError.fromException(const FileSystemException('nope'), st),
        isA<IoFailure>(),
      );
      expect(
        AppError.fromException(const SocketException('offline'), st),
        isA<NetworkFailure>(),
      );
      expect(
        AppError.fromException(const FormatException('bad json'), st),
        isA<ParseFailure>(),
      );
      expect(
        AppError.fromException(PlatformException(code: 'WIN32'), st),
        isA<PlatformFailure>(),
      );

      const original = ParseFailure(messageKey: 'm3u.importFailed');
      expect(AppError.fromException(original), same(original));
    });
  });
}
