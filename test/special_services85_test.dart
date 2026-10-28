import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/editions/special/special_activity.dart';
import 'package:linesight_flutter/editions/special/special_catalog.dart';
import 'package:linesight_flutter/editions/special/special_vip.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

void main() {
  AppStore make() => AppStore()
    ..preferences = {'specialEdition': true, 'reduceMotion': true}
    ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
  Future<void> mount(WidgetTester t, AppStore s, String section) async {
    await t.pumpWidget(
      AppScope(
        store: s,
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: SpecialActivityPage(section: section),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  test(
    'experience saves serialize and isolate actors without losing preferences',
    () async {
      final s = make();
      addTearDown(s.dispose);
      await Future.wait([
        s.updateSpecialExperience('a', (v) => {...v, 'vip': 2}),
        s.updateSpecialExperience('a', (v) => {...v, 'chapter': 1}),
        s.updateSpecialExperience('b', (v) => {'vip': 0}),
      ]);
      expect(s.specialExperienceFor('a'), {'vip': 2, 'chapter': 1});
      expect(s.specialExperienceFor('b'), {'vip': 0});
      expect(s.specialEdition, true);
    },
  );
  for (final id in [
    'finance',
    'stocks',
    'books',
    'coins',
    'points',
    'fragments',
    'running',
    'health',
    'sports',
    'insurance',
    'rental',
    'vip',
    'ledger',
    'invite',
  ]) {
    testWidgets('$id secondary page fits 320px', (t) async {
      t.view.physicalSize = const Size(320, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final s = make();
      addTearDown(s.dispose);
      await mount(t, s, id);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'VIP free claim upgrades and does not downgrade; avatar only in special',
    (t) async {
      final s = make();
      addTearDown(s.dispose);
      await mount(t, s, 'vip');
      await t.tap(find.text('至尊会员').first);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('claim-special-vip')));
      await t.ensureVisible(find.byKey(const ValueKey('claim-special-vip')));
      await t.tap(find.byKey(const ValueKey('claim-special-vip')));
      await t.pumpAndSettle();
      expect(s.specialExperienceFor('local/u1')['vip'], 2);
      await t.ensureVisible(find.text('铂金会员').first);
      await t.pumpAndSettle();
      await t.tap(find.text('铂金会员').first);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('claim-special-vip')));
      await t.tap(find.byKey(const ValueKey('claim-special-vip')));
      await t.pumpAndSettle();
      expect(s.specialExperienceFor('local/u1')['vip'], 2);
      await t.pumpWidget(
        AppScope(
          store: s,
          child: const MaterialApp(
            home: Scaffold(body: SpecialVipAvatar(child: CircleAvatar())),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('special-vip-avatar-badge')),
        findsOneWidget,
      );
      s.preferences = {...s.preferences, 'specialEdition': false};
      s.notifyListeners();
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('special-vip-avatar-badge')),
        findsNothing,
      );
    },
  );
  testWidgets('reader chapter and type size persist', (t) async {
    final s = make();
    addTearDown(s.dispose);
    await mount(t, s, 'books');
    await t.tap(find.text('第2章'));
    await t.pumpAndSettle();
    expect(s.specialExperienceFor('local/u1')['chapter'], 1);
    await t.pumpWidget(const SizedBox());
    await mount(t, s, 'books');
    expect(find.text('第二章 · 交接班的纸飞机'), findsOneWidget);
  });
  testWidgets('water add and undo', (t) async {
    final s = make();
    addTearDown(s.dispose);
    await mount(t, s, 'health');
    await t.tap(find.text('喝一杯水 +200ml'));
    await t.pumpAndSettle();
    expect(s.specialExperienceFor('local/u1')['water'], 200);
    await t.tap(find.text('撤销一杯'));
    await t.pumpAndSettle();
    expect(s.specialExperienceFor('local/u1')['water'], 0);
  });
  testWidgets('fragments dedupe and collect', (t) async {
    final s = make();
    addTearDown(s.dispose);
    await mount(t, s, 'fragments');
    await t.tap(find.text('点亮\n碎片1'));
    await t.pumpAndSettle();
    expect(s.specialExperienceFor('local/u1')['pieces'], [0]);
    expect(find.text('✓ 碎片1'), findsOneWidget);
  });
  testWidgets('finance saves plan; rental requires dates', (t) async {
    final s = make();
    addTearDown(s.dispose);
    await mount(t, s, 'finance');
    await t.tap(find.text('收藏这个方案'));
    await t.pumpAndSettle();
    expect((s.specialExperienceFor('local/u1')['plans'] as List).length, 1);
    await t.pumpWidget(const SizedBox());
    await mount(t, s, 'rental');
    await t.tap(find.text('保存行程计划'));
    await t.pumpAndSettle();
    expect(find.text('请先选择取车和还车日期'), findsOneWidget);
    expect((s.specialExperienceFor('local/u1')['plans'] as List).length, 1);
  });
  testWidgets('stock calculator validates and renders result', (t) async {
    final s = make();
    addTearDown(s.dispose);
    await mount(t, s, 'stocks');
    await t.enterText(find.byType(TextField), '0');
    await t.tap(find.text('计算样例收益'));
    await t.pumpAndSettle();
    expect(find.text('请输入 1～100000000 的金额'), findsOneWidget);
    await t.enterText(find.byType(TextField), '1000');
    await t.tap(find.text('计算样例收益'));
    await t.pumpAndSettle();
    expect(find.textContaining('期末价值'), findsOneWidget);
  });
  test('legacy links map to distinct category pages', () {
    expect(specialCategory('ledger'), 'ledger');
    expect(specialCategory('invite'), 'invite');
    expect(specialCategory('hub'), 'hub');
    expect(specialCategory('会员好礼'), 'vip');
    expect(specialCategory('视频积分'), 'video');
    expect(specialCategory('返利专场'), 'finance');
    expect(specialServices.length, 14);
  });
}
