import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/editions/special/special_activity.dart';
import 'package:linesight_flutter/editions/special/special_content.dart';
import 'package:linesight_flutter/l10n_catalog.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

void main() {
  for (final language in ['zh', 'en']) {
    testWidgets(
      '$language discovery fits narrow large text and preserves routes',
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
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      SpecialPromotionStrip(title: '生产任务'),
                      SpecialPromotionShortcuts(),
                      SpecialDiscoveryShelf(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text(label('会员专享 · 每天都有新惊喜')), findsOneWidget);
        expect(find.text(label('质检员的一天')), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.tap(find.text(label('邀请有礼')));
        await t.pumpAndSettle();
        expect(find.byType(SpecialActivityPage), findsOneWidget);
        expect(
          (t.widget(find.byType(SpecialActivityPage)) as SpecialActivityPage)
              .section,
          '邀请有礼',
        );
        await t.tap(find.byTooltip(language == 'zh' ? '返回' : 'Back'));
        await t.pumpAndSettle();
        expect(find.byType(SpecialPromotionShortcuts), findsOneWidget);
        await t.ensureVisible(find.text(label('会员专享 · 每天都有新惊喜')));
        await t.pumpAndSettle();
        await t.tap(find.text(label('会员专享 · 每天都有新惊喜')));
        await t.pumpAndSettle();
        expect(
          (t.widget(find.byType(SpecialActivityPage)) as SpecialActivityPage)
              .section,
          '会员好礼',
        );
        expect(t.takeException(), isNull);
      },
    );
  }
}

