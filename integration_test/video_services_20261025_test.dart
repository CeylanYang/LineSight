import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/editions/special/special_activity.dart';
import 'package:linesight_flutter/editions/special/special_theme.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import '../test/cloud_layout80_test.dart' show Layout80Account;

void main() {
  final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('record existing service pages with real local persistence', (t) async {
    final store=AppStore();
    final directory=await getDatabasesPath();
    await t.runAsync(()=>store.init(path:'$directory/video-services-${DateTime.now().millisecondsSinceEpoch}.db'));
    expect(store.startupError,isNull);
    store.preferences={'specialEdition':true,'glass':false,'haptics':false};
    final cloud=Layout80Account();
    Future<void> wait(int n) async {
      await t.runAsync(()=>Future<void>.delayed(Duration(seconds:n)));
      await t.pumpAndSettle();
    }
    Future<void> mark(String label,int seconds) async {
      await t.pumpAndSettle();
      print('VIDEO_MARK $label ${DateTime.now().toUtc().toIso8601String()}');
      await wait(seconds);
    }
    Future<void> page(String section) async {
      await t.pumpWidget(AppScope(store:store,child:CloudScope(account:cloud,
        child:MaterialApp(key:ValueKey(section),debugShowCheckedModeBanner:false,
          theme:specialTheme(appTheme(false)),locale:const Locale('zh'),
          supportedLocales:const [Locale('zh')],localizationsDelegates:GlobalMaterialLocalizations.delegates,
          home:SpecialActivityPage(section:section)))));
      await t.pumpAndSettle();
    }
    await page('books');
    print('VIDEO_READY');
    await wait(18);
    await mark('reader',4);
    await t.tap(find.text('第2章'));
    await wait(1);
    expect(find.text('第二章 · 交接班的纸飞机'),findsOneWidget);
    await mark('reader-chapter2',4);
    await page('health');
    await mark('health',4);
    await t.tap(find.text('喝一杯水 +200ml'));
    await wait(1);
    expect(store.specialExperienceFor('cloud/user-a')['water'],200);
    await mark('health-added',4);
    await page('vip');
    await mark('vip',3);
    await t.tap(find.text('至尊会员').first);
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('claim-special-vip')));
    await t.tap(find.byKey(const ValueKey('claim-special-vip')));
    await wait(1);
    expect(store.specialExperienceFor('cloud/user-a')['vip'],2);
    await mark('vip-claimed',4);
    binding.reportData={'fixture_only':true,'production_writes':0,'reading_water_vip_persisted':true};
    print('VIDEO_FINISH');
    await t.pumpWidget(const SizedBox.shrink());
    cloud.dispose();store.dispose();
  });
}
