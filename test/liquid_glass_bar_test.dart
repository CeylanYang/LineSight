import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/liquid_glass_bar.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    ValueChanged<int> onSelected, {
    bool reduced = false,
    bool glass = false,
    bool rtl = false,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            disableAnimations: reduced,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              bottomNavigationBar: LiquidGlassBar(
                labels: const ['Home', 'Records', 'Recipes', 'Profile'],
                icons: const [
                  Icons.home,
                  Icons.list,
                  Icons.layers,
                  Icons.person,
                ],
                selectedIndex: 0,
                onSelected: onSelected,
                glass: glass,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tap selects once; cancel and second pointer do not select', (
    tester,
  ) async {
    final selections = <int>[];
    await mount(tester, selections.add);
    await tester.tap(find.byKey(const ValueKey('liquid-tab-2')));
    await tester.pumpAndSettle();
    expect(selections, [2]);
    selections.clear();
    final point = tester.getCenter(find.byKey(const ValueKey('liquid-tab-0')));
    final first = await tester.startGesture(point, pointer: 1);
    final second = await tester.startGesture(
      point + const Offset(200, 0),
      pointer: 2,
    );
    await second.up();
    await first.cancel();
    await tester.pumpAndSettle();
    expect(selections, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final rtl in [false, true]) {
    testWidgets('drag commits bounded target with RTL=$rtl', (tester) async {
      final selections = <int>[];
      await mount(tester, selections.add, rtl: rtl);
      final point = tester.getCenter(
        find.byKey(const ValueKey('liquid-tab-0')),
      );
      final gesture = await tester.startGesture(point);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(Offset(rtl ? -1000 : 1000, 0));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selections, [3]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow large-text glass fallback and reduced motion render', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selections = <int>[];
    await mount(
      tester,
      selections.add,
      reduced: true,
      glass: true,
      textScale: 2,
    );
    await tester.tap(find.byKey(const ValueKey('liquid-tab-3')));
    await tester.pumpAndSettle();
    expect(selections, [3]);
    expect(tester.takeException(), isNull);
  });
}
