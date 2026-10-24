import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum RuntimeErrorSource { framework, asynchronous }

typedef RuntimeErrorSink = void Function(String message);

// Error messages, plugin codes/details, stack strings and Flutter diagnostic
// collectors can contain credentials, URLs or customer records. None are read.
String privateRuntimeErrorMessage(Object error, RuntimeErrorSource source) {
  if (error is _PrivateRuntimeFailure) return error.message;
  final category = switch (error) {
    PlatformException() => 'platform',
    TimeoutException() => 'timeout',
    FormatException() => 'format',
    StateError() => 'state',
    AssertionError() => 'assertion',
    _ => 'unknown',
  };
  return 'LINESIGHT_ERROR source=${source.name} category=$category';
}

class _PrivateRuntimeFailure implements Exception {
  const _PrivateRuntimeFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Plugins can wrap our handlers to report boot failure to native crash guards.
/// Keep that chain intact, but let it see only a fixed category and empty stack.
/// Install after plugin initialization, before starting application work.
void sanitizeInstalledRuntimeErrorHandlers({bool enabled = kReleaseMode}) {
  if (!enabled) return;
  final framework = FlutterError.onError;
  final asynchronous = PlatformDispatcher.instance.onError;
  FlutterError.onError = (details) {
    framework?.call(
      FlutterErrorDetails(
        exception: _PrivateRuntimeFailure(
          privateRuntimeErrorMessage(
            details.exception,
            RuntimeErrorSource.framework,
          ),
        ),
        stack: StackTrace.empty,
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    return asynchronous?.call(
          _PrivateRuntimeFailure(
            privateRuntimeErrorMessage(error, RuntimeErrorSource.asynchronous),
          ),
          StackTrace.empty,
        ) ??
        true;
  };
}

void _writeRuntimeError(String message) {
  // ignore: avoid_print
  print(message);
}

/// Install before binding/plugin initialization. Development keeps Flutter's
/// full diagnostics; these customer-build handlers record only fixed categories.
void installRuntimeErrorPrivacy({
  bool enabled = kReleaseMode,
  RuntimeErrorSink sink = _writeRuntimeError,
}) {
  if (!enabled) return;
  FlutterError.onError = (details) {
    sink(
      privateRuntimeErrorMessage(
        details.exception,
        RuntimeErrorSource.framework,
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    sink(privateRuntimeErrorMessage(error, RuntimeErrorSource.asynchronous));
    return true;
  };
}
