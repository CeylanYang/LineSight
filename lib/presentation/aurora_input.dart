import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'presentation_controller.dart';

/// Activity-scoped input only: no accessibility service or background listener.
class AuroraInputBridge {
  static const channel = MethodChannel('linesight/aurora');
  final PresentationController controller;
  final VoidCallback onDismissInteraction;
  String? _lastConfiguration;
  bool _disposed = false;
  AuroraInputBridge(this.controller, {required this.onDismissInteraction}) {
    channel.setMethodCallHandler(_handle);
    controller.addListener(sync);
    sync();
  }
  Future<void> _handle(MethodCall call) async {
    if (_disposed) return;
    switch (call.method) {
      case 'show':
        controller.showAurora(trigger: AuroraTrigger.volumeDoublePress);
      case 'dismiss':
        if (controller.auroraVisible) onDismissInteraction();
        controller.dismissAurora();
    }
    // Correct a stale native state even if the requested visual was disabled.
    _lastConfiguration = null;
    sync();
  }

  void sync() {
    if (_disposed ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final value =
        '${controller.canTriggerAurora}/${controller.auroraVisible}/${controller.config.doublePressMs}';
    if (value == _lastConfiguration) return;
    _lastConfiguration = value;
    unawaited(
      _send({
        'enabled': controller.canTriggerAurora,
        'active': controller.auroraVisible,
        'doublePressMs': controller.config.doublePressMs,
      }),
    );
  }

  Future<void> _send(Map<String, Object> arguments) async {
    try {
      await channel.invokeMethod<void>('configure', arguments);
    } on MissingPluginException {
      /* Desktop/test builds have no native key hook. */
    } on PlatformException {
      /* Existing page interaction remains available. */
    }
  }

  void dispose() {
    _disposed = true;
    controller.removeListener(sync);
    channel.setMethodCallHandler(null);
    unawaited(_send({'enabled': false, 'active': false, 'doublePressMs': 360}));
  }
}
