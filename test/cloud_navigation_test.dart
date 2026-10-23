import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/screens/cloud_shell.dart';
import 'package:linesight_flutter/store.dart';

void main() {
  testWidgets('one secondary login page fits narrow Chinese and English UI', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final language in ['zh', 'en']) {
      final store = AppStore()..ready = true
        ..preferences = {'language': language, 'reduceMotion': true, 'glass': false};
      final cloud = CloudAccount()..restoring = false;
      await tester.pumpWidget(LineSightApp(key: UniqueKey(), store: store, cloud: cloud));
      await tester.pumpAndSettle();
      expect(find.byType(CloudShell), findsOneWidget);
      expect(find.byType(CloudLoginPage), findsNothing);
      await tester.tap(find.byIcon(Icons.login).first);
      await tester.pumpAndSettle();
      expect(find.byType(CloudLoginPage), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(CloudLoginPage), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose(); cloud.dispose();
    }
  });
}
