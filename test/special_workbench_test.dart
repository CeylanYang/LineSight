import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/editions/special/special_shell.dart';
import 'package:linesight_flutter/editions/special/special_workbench.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';

void main() {
  testWidgets('special edition mounts checkcheck workbench and five tabs', (
    tester,
  ) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = AppStore()
      ..preferences = {
        'reduceMotion': true,
        'haptics': false,
        'glass': false,
        'specialEdition': true,
      }
      ..ready = true
      ..user = const LocalUser('u1', 'qc', '林晓', '质检员', true);
    addTearDown(store.dispose);

    await tester.pumpWidget(LineSightApp(store: store, showBrandReveal: false));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.byType(SpecialEditionHeader), findsOneWidget);
    expect(find.byType(SpecialWorkbenchPage), findsOneWidget);
    expect(find.byKey(const ValueKey('liquid-tab-4')), findsOneWidget);

    await _precacheCheckcheck(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/special_app_home.png'),
    );

    await tester.tap(find.byKey(const ValueKey('liquid-tab-2')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
      2,
    );
    for (final index in [1, 3, 4]) {
      await tester.tap(find.byKey(ValueKey('liquid-tab-$index')));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    // Changing modes from the fifth tab maps to the normal profile tab.
    store.preferences = {...store.preferences, 'specialEdition': false};
    store.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(SpecialEditionHeader), findsNothing);
    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
      3,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _loadFonts() async {
  final font = File('assets/fonts/NotoSansSC.ttf').readAsBytesSync();
  await (FontLoader(
    'sans-serif',
  )..addFont(Future.value(ByteData.sublistView(font)))).load();
  final icons = File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf');
  if (!icons.existsSync()) return;
  final bytes = icons.readAsBytesSync();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

Future<void> _precacheCheckcheck(WidgetTester tester) async {
  await tester.runAsync(() async {
    final images = Directory('assets/checkcheck')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .where((f) => !f.path.contains('2.0x') && !f.path.contains('3.0x'))
        .map((f) => f.path.replaceAll(Platform.pathSeparator, '/'))
        .toList();
    for (final path in images) {
      await precacheImage(
        AssetImage(path),
        tester.element(find.byType(MaterialApp)),
      );
    }
  });
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}
