import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/editions/special/special_activity.dart';
import 'package:linesight_flutter/editions/special/special_workbench.dart';
import 'package:linesight_flutter/l10n_catalog.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

void main() {
  for (final language in ['zh', 'en']) {
    testWidgets(
      '$language home VIP reflects claim, opens owned tier and isolates accounts',
      (t) async {
        t.view.physicalSize = const Size(320, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final store = AppStore()
          ..preferences = {'specialEdition': true, 'reduceMotion': true}
          ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
        addTearDown(store.dispose);
        String label(String source) =>
            language == 'en' ? englishMessages[source] ?? source : source;
        await t.pumpWidget(
          AppScope(
            store: store,
            child: MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('zh'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: Scaffold(
                body: SpecialWorkbenchPage(
                  onRecords: () {},
                  onTemplates: () {},
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final title = find.byKey(const ValueKey('special-home-vip-level'));
        await t.scrollUntilVisible(
          title,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        expect(t.widget<Text>(title).data, label('质检会员'));
        await t.tap(find.text(label('免费领取')));
        await t.pumpAndSettle();
        await t.tap(find.text(label('无上会员')).first);
        await t.pumpAndSettle();
        final claim = find.byKey(const ValueKey('claim-special-vip'));
        await t.ensureVisible(claim);
        await t.pumpAndSettle();
        await t.tap(claim);
        await t.pumpAndSettle();
        expect(store.specialExperienceFor('local/u1')['vip'], 3);
        await t.tap(find.byTooltip(language == 'zh' ? '返回' : 'Back'));
        await t.pumpAndSettle();
        expect(t.widget<Text>(title).data, label('无上会员'));
        expect(find.text(label('已领取')), findsOneWidget);
        await t.tap(find.text(label('查看详情')).first);
        await t.pumpAndSettle();
        expect(
          t
              .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, label('无上会员')),
              )
              .selected,
          true,
        );
        await t.tap(find.byTooltip(language == 'zh' ? '返回' : 'Back'));
        await t.pumpAndSettle();
        store.user = const LocalUser('u2', 'other', '小周', 'operator', true);
        store.notifyListeners();
        await t.pumpAndSettle();
        expect(t.widget<Text>(title).data, label('质检会员'));
        expect(find.text(label('已领取')), findsNothing);
        store.user = const LocalUser('u1', 'tester', '小林', 'operator', true);
        store.notifyListeners();
        await t.pumpAndSettle();
        expect(t.widget<Text>(title).data, label('无上会员'));
      },
    );
    testWidgets('$language home check-in reflects reward receipt after return', (
      t,
    ) async {
      final store = AppStore()
        ..preferences = {'specialEdition': true, 'reduceMotion': true}
        ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
      addTearDown(store.dispose);
      String label(String source) =>
          language == 'en' ? englishMessages[source] ?? source : source;
      await t.pumpWidget(
        AppScope(
          store: store,
          child: MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: SpecialWorkbenchPage(onRecords: () {}, onTemplates: () {}),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final status = find.byKey(const ValueKey('special-home-checkin-status'));
      await t.scrollUntilVisible(
        status,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(t.widget<Text>(status).data, label('立即签到'));
      expect(find.text('≈ ¥23.40'), findsOneWidget);
      await t.tap(find.text(label('立即签到')).last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text(label('立即签到')));
      await t.tap(find.text(label('立即签到')));
      await t.pumpAndSettle();
      expect(store.specialRewardClaimed('每日签到'), true);
      await t.tap(find.byTooltip(language == 'zh' ? '返回' : 'Back'));
      await t.pumpAndSettle();
      expect(t.widget<Text>(status).data, label('今日已签到'));
      expect(find.text('≈ ¥23.60'), findsOneWidget);
      expect(find.text(label('今日已签到')), findsNWidgets(2));
      expect(store.specialPointsBalance, 2360);
      // Opening a completed check-in keeps its entry useful without claiming twice.
      await t.tap(find.text(label('今日已签到')).last);
      await t.pumpAndSettle();
      expect(find.text(label('今日已签到')), findsOneWidget);
      expect(store.specialPointsBalance, 2360);
    });
    testWidgets(
      '$language workbench cards use stable routes and refresh stays in place',
      (t) async {
        final store = AppStore()
          ..preferences = {'specialEdition': true, 'reduceMotion': true}
          ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
        addTearDown(store.dispose);
        String label(String source) =>
            language == 'en' ? englishMessages[source] ?? source : source;
        await t.pumpWidget(
          AppScope(
            store: store,
            child: MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('zh'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: Scaffold(
                body: SpecialWorkbenchPage(
                  onRecords: () {},
                  onTemplates: () {},
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final swap = find.text(label('换一换'));
        await t.scrollUntilVisible(
          swap,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        final before = t.getTopLeft(find.text(label('质检员的一天'))).dx;
        await t.tap(swap);
        await t.pumpAndSettle();
        expect(find.byType(SpecialActivityPage), findsNothing);
        expect(
          t.getTopLeft(find.text(label('质检员的一天'))).dx,
          greaterThan(before),
        );
        for (final entry in [
          ('查看详情', 'finance'),
          ('邀请同事', 'invite'),
          ('每日任务', 'points'),
          ('充100送20', 'finance'),
        ]) {
          final target = find.text(label(entry.$1));
          await t.scrollUntilVisible(
            target,
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await t.pumpAndSettle();
          await t.tap(target);
          await t.pumpAndSettle();
          expect(
            t
                .widget<SpecialActivityPage>(find.byType(SpecialActivityPage))
                .section,
            entry.$2,
          );
          await t.tap(find.byTooltip(language == 'zh' ? '返回' : 'Back'));
          await t.pumpAndSettle();
        }
      },
    );
  }
}
