import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/editions/special/special_interaction.dart';
import 'package:linesight_flutter/editions/special/special_activity.dart';
import 'package:linesight_flutter/editions/special/special_content.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

void main() {
  testWidgets(
    'symbolic progress finishes in 620ms without extending on repeated taps',
    (tester) async {
      final controller = SpecialInteractionController()..configure(true);
      addTearDown(controller.dispose);
      controller.start();
      expect(controller.percent, 1);
      await tester.pump(const Duration(milliseconds: 180));
      expect(controller.percent, 3);
      controller.start();
      await tester.pump(const Duration(milliseconds: 250));
      expect(controller.percent, 15);
      await tester.pump(const Duration(milliseconds: 110));
      expect(controller.percent, 99);
      await tester.pump(const Duration(milliseconds: 40));
      expect(controller.percent, 100);
      await tester.pump(const Duration(milliseconds: 40));
      expect(controller.percent, 0);
      controller.start();
      controller.configure(false);
      expect(controller.percent, 0);
      await tester.pump(const Duration(seconds: 1));
      controller.start();
      expect(controller.percent, 0);
    },
  );

  test(
    'rewards serialize, deduplicate and preserve edition preferences',
    () async {
      final store = AppStore()..preferences = {'specialEdition': true};
      addTearDown(store.dispose);
      await Future.wait([
        store.claimSpecialReward('签到'),
        store.claimSpecialReward('签到'),
        store.claimSpecialReward('好礼', points: 50),
      ]);
      expect(store.specialPointsBalance, 2410);
      expect((store.specialActivity['history'] as List).length, 2);
      expect(store.specialEdition, true);
      await expectLater(
        store.claimSpecialReward('大额兑换', points: -9999),
        throwsStateError,
      );
      expect(store.specialPointsBalance, 2410);
    },
  );

  testWidgets(
    'normal pages have no promotion and special pages open an activity',
    (tester) async {
      final store = AppStore();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        AppScope(
          store: store,
          child: const MaterialApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: PageBody(children: [Text('业务内容')])),
          ),
        ),
      );
      expect(find.byType(SpecialPromotionStrip), findsNothing);
      store.preferences = {'specialEdition': true};
      await tester.pumpWidget(
        AppScope(
          store: store,
          child: const MaterialApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: PageBody(children: [Text('业务内容')])),
          ),
        ),
      );
      expect(find.byType(SpecialPromotionShortcuts), findsOneWidget);
      await tester.tap(find.text('金币夺宝'));
      await tester.pumpAndSettle();
      expect(find.byType(SpecialActivityPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
