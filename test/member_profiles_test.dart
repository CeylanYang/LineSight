import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_avatar.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_team_workflow_test.dart' show TeamAccount;

void main() {
  test(
    'supervisor edits production configuration without membership administration',
    () {
      final account = TeamAccount();
      addTearDown(account.dispose);
      account.activeWorkspace!['role'] = 'manager';
      final scope = account.accessScope;
      expect(account.canEdit, isTrue);
      expect(account.canManageProduction, isTrue);
      account.requireAccess(scope, write: true, manageProduction: true);
      expect(() => account.requireAccess(scope, owner: true), throwsException);
      account.activeWorkspace!['role'] = 'operator';
      expect(account.canEdit, isTrue);
      expect(account.canManageProduction, isFalse);
      expect(
        () => account.requireAccess(scope, manageProduction: true),
        throwsException,
      );
    },
  );
  testWidgets(
    'supervisor sees staff titles and cannot invite or change roles',
    (tester) async {
      final account = TeamAccount();
      final store = AppStore()
        ..ready = true
        ..preferences = {'reduceMotion': true, 'glass': false};
      addTearDown(account.dispose);
      addTearDown(store.dispose);
      account.activeWorkspace!['role'] = 'manager';
      account.rows[0].addAll({'role': 'manager', 'job_title': '质量主管'});
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: appTheme(false),
          builder: (_, child) => AppScope(
            store: store,
            child: CloudScope(account: account, child: child!),
          ),
          home: const CloudTeamPage(),
        ),
      );
      await tester.pumpAndSettle();
      final label = find.text('质量主管');
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      expect(label, findsOneWidget);
      expect(find.text('团队主管'), findsWidgets);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.text('生成邀请码'), findsNothing);
      expect(account.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('malformed profile image leaves a usable fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CloudAvatar(
            data: 'invalid portrait',
            size: 56,
            fallback: Text('顾'),
          ),
        ),
      ),
    );
    expect(find.text('顾'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
