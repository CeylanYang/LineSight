import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/l10n.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/screens/cloud_profiles.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_profile_workflow_test.dart' show printerProfile;
import 'cloud_template_workflow_test.dart' show checklist;
import 'cloud_team_workflow_test.dart' show TeamAccount;

class RoleNavigationAccount extends TeamAccount {
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (method == 'GET' && path.endsWith('printer-profiles/')) {
      return [printerProfile];
    }
    return super.request(
      method,
      path,
      body: body,
      idempotencyKey: idempotencyKey,
    );
  }
}

void main() {
  for (final language in ['en', 'zh']) {
    for (final role in ['owner', 'manager', 'operator', 'viewer']) {
      testWidgets(
        '$language $role configuration and team route permissions at 360px',
        (tester) async {
          await (FontLoader('EvidenceFont')..addFont(
                Future.value(
                  ByteData.sublistView(
                    File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
                  ),
                ),
              ))
              .load();
          final account = RoleNavigationAccount();
          account.activeWorkspace!['role'] = role;
          account.templates = [checklist()];
          final store = AppStore()
            ..ready = true
            ..preferences = {
              'reduceMotion': true,
              'glass': false,
              'haptic': false,
            };
          addTearDown(account.dispose);
          addTearDown(store.dispose);
          await tester.binding.setSurfaceSize(const Size(360, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('zh')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: ThemeData(fontFamily: 'EvidenceFont'),
              builder: (context, child) => AppScope(
                store: store,
                child: CloudScope(account: account, child: child!),
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Column(
                    children: [
                      TextButton(
                        onPressed: () => openPage(
                          context,
                          const Scaffold(body: CloudConfigurationPage()),
                        ),
                        child: const Text('Configuration origin'),
                      ),
                      TextButton(
                        onPressed: () =>
                            openPage(context, const CloudTeamPage()),
                        child: const Text('Team origin'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          String label(String zh) =>
              tr(tester.element(find.byType(Scaffold).last), zh);
          Future<void> tap(Finder target) async {
            if (target.evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                target,
                220,
                scrollable: find.byType(Scrollable).last,
              );
            }
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            await tester.tap(target);
            await tester.pumpAndSettle();
          }

          Future<void> back() async {
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
          }

          Future<Set<String>> visibleTextsAcrossPage() async {
            final values = <String>{};
            final scroll = find.byType(Scrollable).last;
            for (var i = 0; i < 15; i++) {
              values.addAll(
                tester
                    .widgetList<Text>(find.byType(Text))
                    .map((w) => w.data ?? ''),
              );
              final position = tester.state<ScrollableState>(scroll).position;
              if (position.pixels >= position.maxScrollExtent) break;
              await tester.drag(scroll, const Offset(0, -260));
              await tester.pumpAndSettle();
            }
            return values;
          }

          final manage = role == 'owner' || role == 'manager';
          final edit = role != 'viewer';
          await tap(find.text('Configuration origin'));
          await tap(find.text(label('打印配置')));
          expect(
            find.byTooltip(label('创建打印配置')),
            manage ? findsOneWidget : findsNothing,
          );
          await tap(find.text('Bambu Lab A1'));
          final profileTexts = await visibleTextsAcrossPage();
          expect(profileTexts.contains(label('复制打印配置')), manage);
          expect(profileTexts.contains(label('使用此配置创建任务')), edit);
          if (edit) {
            await tap(find.text(label('使用此配置创建任务')));
            expect(find.byType(CloudCreateTaskPage), findsOneWidget);
            await back();
            expect(find.byType(CloudProfileDetailPage), findsOneWidget);
          }
          await back();
          expect(find.byType(CloudProfilesPage), findsOneWidget);
          await back();
          expect(find.byType(CloudConfigurationPage), findsOneWidget);
          await tap(find.text(label('检查模板')));
          expect(
            find.byTooltip(label('发布检查模板')),
            manage ? findsOneWidget : findsNothing,
          );
          await tap(find.text('Bracket checklist'));
          final templateTexts = await visibleTextsAcrossPage();
          expect(templateTexts.contains(label('复制模板')), manage);
          expect(templateTexts.contains(label('使用此模板创建任务')), edit);
          if (edit) {
            await tap(find.text(label('使用此模板创建任务')));
            expect(find.byType(CloudCreateTaskPage), findsOneWidget);
            await back();
            expect(find.byType(CloudTemplateDetailPage), findsOneWidget);
          }
          await back();
          expect(find.byType(CloudTemplatesPage), findsOneWidget);
          await back();
          await back();
          expect(find.text('Configuration origin'), findsOneWidget);
          await tap(find.text('Team origin'));
          final teamTexts = await visibleTextsAcrossPage();
          expect(teamTexts.contains(label('生成邀请码')), role == 'owner');
          expect(
            find.byType(PopupMenuButton<String>),
            role == 'owner' ? findsWidgets : findsNothing,
          );
          await back();
          expect(find.text('Team origin'), findsOneWidget);
          expect(account.mutations, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
