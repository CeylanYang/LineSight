import 'package:flutter/material.dart';
import '../cloud_account.dart';
import 'cloud_business.dart';
import 'cloud_shell.dart';
import 'team_workspace.dart';

/// Local settings share the app's authenticated cloud workspace.
Widget teamEntry(BuildContext context) {
  final scope = context.dependOnInheritedWidgetOfExactType<CloudScope>();
  final account = scope?.notifier;
  if (account == null) return const TeamWorkspacePage();
  return account.signedIn ? const CloudTeamPage() : const CloudLoginPage();
}
