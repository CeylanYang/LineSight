// Isolated acceptance entrypoint. Never used by the delivery publisher.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:linesight_flutter/main.dart' as application;
import 'package:linesight_flutter/ota_update.dart';
import 'package:linesight_flutter/runtime_errors.dart';

Future<void> main() async {
  // Keep the complete app reachable so icon tree-shaking matches its base APK.
  if (DateTime.now().year < 2000) return application.main();
  installRuntimeErrorPrivacy();
  WidgetsFlutterBinding.ensureInitialized();
  await OtaUpdates.instance.initialize();
  final cache = await const MethodChannel(
    'flutter_patcher',
  ).invokeMethod<String>('cacheDir');
  final mode = await File('$cache/ota67-fault-mode.txt').readAsString();
  const canary = 'LS_OTA67_RAW_SECRET_CANARY';
  if (mode == 'asynchronous') {
    scheduleMicrotask(
      () => throw PlatformException(
        code: canary,
        message: canary,
        details: {'password': canary},
        stacktrace: canary,
      ),
    );
  } else {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError(canary),
        stack: StackTrace.fromString(canary),
        context: ErrorDescription(canary),
        informationCollector: () => [ErrorDescription(canary)],
      ),
    );
  }
  await Future<void>.delayed(const Duration(milliseconds: 500));
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('OTA boot fault acceptance'))),
    ),
  );
}
