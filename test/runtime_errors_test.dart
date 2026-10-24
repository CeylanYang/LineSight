import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/runtime_errors.dart';

class UnprintableFailure {
  @override
  String toString() =>
      throw StateError('Raw exception must never be formatted');
}

class UnprintableStack implements StackTrace {
  @override
  String toString() => throw StateError('Raw stack must never be formatted');
}

void main() {
  test(
    'plugin boot hooks get sanitized framework failure and keep reporting',
    () {
      final previous = FlutterError.onError;
      final previousAsync = PlatformDispatcher.instance.onError;
      final output = <String>[];
      final reports = <String>[];
      try {
        installRuntimeErrorPrivacy(enabled: true, sink: output.add);
        final privateHandler = FlutterError.onError!;
        FlutterError.onError = (details) {
          reports.add(details.exception.toString());
          expect(details.stack.toString(), isEmpty);
          expect(details.context, isNull);
          expect(details.informationCollector, isNull);
          privateHandler(details);
        };
        sanitizeInstalledRuntimeErrorHandlers(enabled: true);
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: UnprintableFailure(),
            stack: UnprintableStack(),
            context: ErrorDescription('private-context'),
            informationCollector: () => throw StateError('Must never collect'),
          ),
        );
        expect(reports, ['LINESIGHT_ERROR source=framework category=unknown']);
        expect(output, reports);
      } finally {
        FlutterError.onError = previous;
        PlatformDispatcher.instance.onError = previousAsync;
      }
    },
  );

  test('plugin asynchronous boot hook keeps its signal without raw values', () {
    final previous = FlutterError.onError;
    final previousAsync = PlatformDispatcher.instance.onError;
    final output = <String>[];
    final reports = <String>[];
    try {
      installRuntimeErrorPrivacy(enabled: true, sink: output.add);
      final privateHandler = PlatformDispatcher.instance.onError!;
      PlatformDispatcher.instance.onError = (error, stack) {
        reports.add(error.toString());
        expect(stack.toString(), isEmpty);
        return privateHandler(error, stack);
      };
      sanitizeInstalledRuntimeErrorHandlers(enabled: true);
      expect(
        PlatformDispatcher.instance.onError!(
          PlatformException(
            code: 'private-code',
            message: 'private-token',
            details: {'password': 'private-password'},
          ),
          UnprintableStack(),
        ),
        isTrue,
      );
      expect(reports, [
        'LINESIGHT_ERROR source=asynchronous category=platform',
      ]);
      expect(output, reports);
    } finally {
      FlutterError.onError = previous;
      PlatformDispatcher.instance.onError = previousAsync;
    }
  });

  test('framework handler never evaluates messages, stacks or collectors', () {
    final previous = FlutterError.onError;
    final previousAsync = PlatformDispatcher.instance.onError;
    final output = <String>[];
    try {
      installRuntimeErrorPrivacy(enabled: true, sink: output.add);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: UnprintableFailure(),
          stack: UnprintableStack(),
          library: 'secret-library',
          context: ErrorDescription('secret-account-context'),
          informationCollector: () =>
              throw StateError('Collector must not run'),
        ),
      );
      expect(output, ['LINESIGHT_ERROR source=framework category=unknown']);
    } finally {
      FlutterError.onError = previous;
      PlatformDispatcher.instance.onError = previousAsync;
    }
  });

  test('async handler handles plugin secrets without default raw logging', () {
    final previous = FlutterError.onError;
    final previousAsync = PlatformDispatcher.instance.onError;
    final output = <String>[];
    try {
      installRuntimeErrorPrivacy(enabled: true, sink: output.add);
      final handled = PlatformDispatcher.instance.onError!(
        PlatformException(
          code: 'private-token-code',
          message: 'Bearer private-access-token',
          details: {'password': 'private-password', 'card': 'private-card'},
          stacktrace: 'https://private-endpoint/?refresh_token=private-refresh',
        ),
        UnprintableStack(),
      );
      expect(handled, isTrue);
      expect(output, ['LINESIGHT_ERROR source=asynchronous category=platform']);
    } finally {
      FlutterError.onError = previous;
      PlatformDispatcher.instance.onError = previousAsync;
    }
  });

  test('known error categories preserve no supplied values', () {
    final errors = <Object>[
      TimeoutException('private-timeout'),
      const FormatException('private-format', 'private-record'),
      StateError('private-state'),
      AssertionError('private-assertion'),
    ];
    final messages = errors
        .map((e) => privateRuntimeErrorMessage(e, RuntimeErrorSource.framework))
        .toList();
    expect(messages.map((m) => m.split('category=').last), [
      'timeout',
      'format',
      'state',
      'assertion',
    ]);
    expect(messages.any((m) => m.contains('private-')), isFalse);
  });

  test('development retains existing framework and async diagnostics', () {
    final framework = FlutterError.onError;
    final asynchronous = PlatformDispatcher.instance.onError;
    installRuntimeErrorPrivacy(
      enabled: false,
      sink: (_) => fail('Unexpected logging'),
    );
    expect(FlutterError.onError, same(framework));
    expect(PlatformDispatcher.instance.onError, same(asynchronous));
  });
}
