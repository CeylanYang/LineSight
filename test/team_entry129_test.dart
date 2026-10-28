import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/screens/cloud_shell.dart';
import 'package:linesight_flutter/screens/team_entry.dart';
import 'package:linesight_flutter/screens/team_workspace.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_access_ui_test.dart' show AccessAccount;

void main() {
  Future<void> showEntry(WidgetTester t, CloudAccount? account) async {
    final store = AppStore();
    addTearDown(store.dispose);
    const app = MaterialApp(home: Builder(builder: teamEntry));
    await t.pumpWidget(
      AppScope(
        store: store,
        child: account == null ? app : CloudScope(account: account, child: app),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('signed-out team entry uses unified cloud login', (t) async {
    final account = CloudAccount()..restoring = false;
    addTearDown(account.dispose);
    await showEntry(t, account);
    expect(find.byType(CloudLoginPage), findsOneWidget);
    expect(find.byType(TeamWorkspacePage), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Create team account'), findsNothing);
  });

  testWidgets('signed-in team entry uses existing account and workspace', (
    t,
  ) async {
    final account = AccessAccount();
    addTearDown(account.dispose);
    await showEntry(t, account);
    expect(find.byType(CloudTeamPage), findsOneWidget);
    expect(find.byType(TeamWorkspacePage), findsNothing);
    expect(find.byType(CloudLoginPage), findsNothing);
    expect(account.writes, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('standalone legacy entry has no public registration toggle', (
    t,
  ) async {
    await showEntry(t, null);
    expect(find.byType(TeamWorkspacePage), findsOneWidget);
    expect(find.text('Create team account'), findsNothing);
    expect(find.byIcon(Icons.person_add_alt_1), findsNothing);
    expect(t.takeException(), isNull);
  });
}
