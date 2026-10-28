import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/editions/special/special_activity.dart';
import 'package:linesight_flutter/editions/special/special_vip.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

void main() {
  setUpAll(() async {
    for (final name in ['Roboto', 'sans-serif']) {
      await (FontLoader(name)..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
              ),
            ),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final page in [
    'vip',
    'stocks',
    'finance',
    'books',
    'health',
    'fragments',
    'insurance',
    'rental',
    'running',
    'hub',
  ]) {
    testWidgets('$page special page visual', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final s = AppStore()
        ..preferences = {'specialEdition': true, 'reduceMotion': true};
      addTearDown(s.dispose);
      await t.pumpWidget(
        AppScope(
          store: s,
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeData(
              useMaterial3: true,
              colorSchemeSeed: Colors.orange,
            ),
            home: SpecialActivityPage(section: page),
          ),
        ),
      );
      await t.pumpAndSettle();
      if (page == 'hub') {
        await t.pump(const Duration(milliseconds: 1200));
        await t.pumpAndSettle();
        await t.tap(find.text('稍后再说'));
        await t.pumpAndSettle();
      }
      if (page == 'vip') {
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        });
        await t.pumpAndSettle();
        expect(find.byType(SpecialVipBody), findsOneWidget);
      }
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/special85-$page.png'),
      );
      await t.pumpWidget(const SizedBox());
    });
  }
}
