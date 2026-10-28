import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/editions/edition_brand.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rapid edition changes restore the default launcher in order', () async {
    final calls = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(EditionLauncher.channel, (call) async {
          calls.add(call.arguments as bool);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(EditionLauncher.channel, null);
    });
    final launcher = EditionLauncher();
    launcher.configure(false);
    launcher.configure(true);
    launcher.configure(true);
    launcher.configure(false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, [false, true, false]);
  });
}
