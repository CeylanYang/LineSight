import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const specialLogoAsset = 'assets/brand/special_logo.png';

/// Serializes launcher updates so rapid edition switches finish in order.
class EditionLauncher {
  static const channel = MethodChannel('linesight/edition');
  bool? _requested;
  Future<void> _pending = Future<void>.value();

  void configure(bool special) {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _requested == special) {
      return;
    }
    _requested = special;
    _pending = _pending.then((_) async {
      try {
        await channel.invokeMethod<void>('setSpecialEdition', special);
      } on MissingPluginException {
        // Desktop tests and older Android bases have no launcher channel.
      } on PlatformException catch (error) {
        _requested = null;
        debugPrint('Edition launcher update failed: ${error.code}');
      }
    });
  }
}
