import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/screens/startup.dart';
import 'package:linesight_flutter/store.dart';

void main() {
  testWidgets('store notifications and session changes reuse fixed themes', (
    tester,
  ) async {
    final store = AppStore()..preferences = {'reduceMotion': true};
    addTearDown(store.dispose);
    await tester.pumpWidget(LineSightApp(store: store));
    await tester.pumpAndSettle();
    MaterialApp app() => tester.widget(find.byType(MaterialApp));
    final light = app().theme, dark = app().darkTheme;
    for (final stage in ['读取本机账户', '读取检测记录与本机设置', '检查工作区与还原点']) {
      store.startupStage = stage;
      store.notifyListeners();
      await tester.pumpAndSettle();
      expect(app().theme, same(light));
      expect(app().darkTheme, same(dark));
      expect(find.text(stage), findsOneWidget);
    }
    store.preferences['dark'] = true;
    store.session++;
    store.notifyListeners();
    await tester.pumpAndSettle();
    expect(app().theme, same(light));
    expect(app().darkTheme, same(dark));
    expect(app().themeMode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(StartupPage))).brightness,
      Brightness.dark,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
