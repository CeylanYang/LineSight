import 'package:linesight_flutter/liquid_glass_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:linesight_flutter/screens/dashboard.dart';
import 'package:linesight_flutter/screens/records.dart';
import 'package:linesight_flutter/screens/modules.dart';
import 'package:linesight_flutter/screens/settings.dart';
import 'package:linesight_flutter/screens/statistics.dart';
import 'package:linesight_flutter/screens/team_workspace.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'main navigation and secondary screens render at phone width, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final s = AppStore()
          ..ready = true
          ..data = Workspace.seed()
          ..user = const LocalUser('a', 'admin', '质量负责人', 'admin', true)
          ..preferences = {'dark': dark, 'glass': true, 'reduceMotion': true};
        s.users = [s.user!];
        await tester.pumpWidget(LineSightApp(store: s));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in ['检测记录', '配方中心', '我的', '工作台']) {
          await tester.tap(
            find.descendant(
              of: find.byType(LiquidGlassBar),
              matching: find.text(label),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
        }
        for (final page in <Widget>[
          const StationPage(id: 's1'),
          const RecordDetailPage(id: 'sample-0'),
          const RecipeDetailPage(id: 'r1'),
          const ChangeoverPage(stationId: 's1'),
          const RecipeEditorPage(),
          const StationEditorPage(),
          const StatisticsPage(),
          const AccountPage(),
          const MembersPage(),
          const AuditPage(),
          const DataPage(),
          const HelpPage(),
          const AlertsPage(),
          const TeamWorkspacePage(),
        ]) {
          await tester.pumpWidget(
            AppScope(
              store: s,
              child: MaterialApp(
                theme: appTheme(dark),
                locale: const Locale('zh', 'CN'),
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                supportedLocales: const [Locale('zh', 'CN')],
                home: page,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: page.runtimeType.toString(),
          );
          final scrollable = find.byType(Scrollable).first;
          for (var i = 0; i < 3; i++) {
            await tester.drag(scrollable, const Offset(0, -650));
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${page.runtimeType} scroll $i',
            );
          }
        }
      },
    );
  }
  testWidgets('onboarding at narrow width and tablet', (tester) async {
    for (final size in [
      const Size(320, 740),
      const Size(1200, 900),
      const Size(844, 390),
      const Size(1200, 500),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final s = AppStore()..ready = true;
      await tester.pumpWidget(LineSightApp(key: ValueKey(size), store: s));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
