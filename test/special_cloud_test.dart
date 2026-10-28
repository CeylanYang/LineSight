import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_navigation.dart';
import 'package:linesight_flutter/editions/edition_host.dart';
import 'package:linesight_flutter/editions/special/special_content.dart';
import 'package:linesight_flutter/editions/special/special_workbench.dart';
import 'package:linesight_flutter/editions/special/special_theme.dart';
import 'package:linesight_flutter/screens/cloud_shell.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_layout80_test.dart' show Layout80Account;

void main() {
  setUpAll(() async {
    for (final family in ['sans-serif', 'Roboto']) {
      await (FontLoader(family)..addFont(
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
  for (final width in [320.0, 390.0]) {
    testWidgets('special cloud tabs and business routes at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final account = Layout80Account();
      final store = AppStore()
        ..preferences = {
          'specialEdition': true,
          'haptics': false,
          'glass': false,
        };
      final tabs = ValueNotifier<int>(0);
      addTearDown(account.dispose);
      addTearDown(store.dispose);
      addTearDown(tabs.dispose);
      await tester.pumpWidget(
        CloudNavigationScope(
          controller: tabs,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: specialTheme(appTheme(false)),
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => AppScope(
              store: store,
              child: CloudScope(account: account, child: child!),
            ),
            home: const EditionHost(child: CloudShell()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final context = tester.element(find.byType(MaterialApp));
        final files = Directory('assets')
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) =>
                  RegExp(r'\.(png|jpg|jpeg)$').hasMatch(file.path) &&
                  !RegExp(r'[\\/][23]\.0x[\\/]').hasMatch(file.path),
            );
        for (final file in files) {
          await precacheImage(
            AssetImage(file.path.replaceAll(Platform.pathSeparator, '/')),
            context,
          );
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final home = tester.widget<SpecialWorkbenchPage>(
        find.byType(SpecialWorkbenchPage),
      );
      expect(home.counts['jobs'], 8);
      home.actions['异常处理']!();
      await tester.pumpAndSettle();
      expect(find.byType(CloudTaskListPage), findsOneWidget);
      expect(
        tester.widget<CloudTaskListPage>(find.byType(CloudTaskListPage)).status,
        'exception',
      );
      Navigator.of(tester.element(find.byType(CloudTaskListPage))).pop();
      await tester.pumpAndSettle();
      for (final index in [1, 2, 3, 4]) {
        await tester.tap(find.byKey(ValueKey('liquid-tab-$index')));
        await tester.pumpAndSettle();
        expect(find.byType(SpecialPromotionShortcuts), findsWidgets);
        expect(tester.takeException(), isNull);
        if (width == 390) {
          // ResizeImage has a separate cache key from the original asset.
          // Wait for the actual displayed providers, including task thumbnails.
          await tester.runAsync(() async {
            final context = tester.element(find.byType(MaterialApp));
            for (final rendered in tester.widgetList<Image>(
              find.byType(Image),
            )) {
              await precacheImage(rendered.image, context);
            }
          });
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/special_cloud_tab_$index.png'),
          );
        }
      }
    });
  }
}
