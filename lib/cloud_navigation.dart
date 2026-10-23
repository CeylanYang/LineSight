import 'package:flutter/material.dart';

/// Shared by the shell and routes above it, so explicit destinations also
/// select their main tab. Ordinary route pops keep the caller's tab unchanged.
class CloudNavigationScope extends InheritedNotifier<ValueNotifier<int>> {
  const CloudNavigationScope({
    super.key,
    required ValueNotifier<int> controller,
    required super.child,
  }) : super(notifier: controller);

  static ValueNotifier<int>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CloudNavigationScope>()
      ?.notifier;
}

void returnToCloudWorkbench(BuildContext context) {
  CloudNavigationScope.maybeOf(context)?.value = 0;
  ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
  Navigator.of(context).popUntil((route) => route.isFirst);
}
