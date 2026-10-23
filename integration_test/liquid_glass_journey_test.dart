import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/liquid_glass_bar.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('glass navigation renders and interacts on Android', (
    tester,
  ) async {
    // In-memory fixture: never opens or changes the installed user database.
    final store = AppStore()
      ..ready = true
      ..data = Workspace.seed()
      ..user = const LocalUser(
        'glass-review',
        'review',
        'Review',
        'admin',
        true,
      )
      ..preferences = {'glass': true, 'haptics': false, 'autoLock': false};
    store.users = [store.user!];
    await tester.pumpWidget(LineSightApp(store: store));
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('glass-light-dashboard');

    final first = find.byKey(const ValueKey('liquid-tab-0'));
    final held = await tester.startGesture(tester.getCenter(first));
    await tester.pump(const Duration(milliseconds: 220));
    await binding.takeScreenshot('glass-light-pressed');
    await held.up();
    await tester.pumpAndSettle();
    for (var i = 1; i < 4; i++) {
      await tester.tap(find.byKey(ValueKey('liquid-tab-$i')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LiquidGlassBar>(find.byType(LiquidGlassBar))
            .selectedIndex,
        i,
      );
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('glass-light-tab-$i');
    }
    await tester.drag(find.byType(LiquidGlassBar), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<LiquidGlassBar>(find.byType(LiquidGlassBar)).selectedIndex,
      0,
    );
    // Validate the dark palette independently without changing stored settings.
    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(theme: appTheme(true), home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();
    await binding.takeScreenshot('glass-dark-dashboard');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
