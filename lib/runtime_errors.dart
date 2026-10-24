import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum RuntimeErrorSource { framework, asynchronous }

typedef RuntimeErrorSink = void Function(String message);

// Error messages, plugin codes/details, stack strings and Flutter diagnostic
// collectors can contain credentials, URLs or customer records. None are read.
String privateRuntimeErrorMessage(Object error, RuntimeErrorSource source) {
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
