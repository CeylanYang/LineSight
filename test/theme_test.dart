import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/audit.dart';
import 'package:linesight_flutter/screens/backup_transfer.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

class _ThemeStore extends AppStore {
  void setDark(bool value) {
    preferences = {...preferences, 'dark': value};
    notifyListeners();
  }
}

void main() {
  test('displayed version matches the package version', () {
    final manifest = File('pubspec.yaml').readAsStringSync();
    expect(manifest, contains('version: $appVersion+'));
  });
  test('dark theme body and icons use readable foreground colors', () {
    final dark = appTheme(true);
    expect(dark.textTheme.bodyMedium!.color, dark.colorScheme.onSurface);
    expect(dark.iconTheme.color!.computeLuminance(), greaterThan(.5));
  });
  testWidgets(
    'backup format labels and guidance follow theme changes on the same route',
    (tester) async {
      tester.view.physicalSize = const Size(500, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = _ThemeStore()
        ..ready = true
        ..data = Workspace.seed()
        ..user = const LocalUser('a', 'admin', '人员', 'admin', true);
      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pumpAndSettle();
      openPage(tester.element(find.byType(AppShell)), const BackupExportPage());
      await tester.pumpAndSettle();
      for (final dark in [true, false]) {
        s.setDark(dark);
        await tester.pumpAndSettle();
        for (final text in [
          find.text('完整备份 LSB'),
          find.text('兼容 JSON'),
          find.textContaining('保存开始备份时的数据'),
        ]) {
          final rich = tester.widget<RichText>(
            find.descendant(of: text, matching: find.byType(RichText)),
          );
          expect(
            rich.text.style!.color,
            Theme.of(tester.element(text)).colorScheme.onSurface,
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );
  testWidgets(
    'appearance remains bright on a pushed audit route',
    (tester) async {
      final s = _ThemeStore()
        ..ready = true
        ..data = Workspace.seed()
        ..user = const LocalUser('a', 'admin', '人员', 'admin', true);
      s.data.audits.add(
        AuditEntry(
          'event',
          '人员',
          '质量复核',
          '核对完成',
          DateTime.now(),
          changes: [const AuditChange('复核结论', '未复核', '放行')],
        ),
      );
      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pumpAndSettle();
      openPage(
        tester.element(find.byType(AppShell)),
        const AuditDetailPage(id: 'event'),
      );
      await tester.pumpAndSettle();
      s.setDark(true);
      await tester.pumpAndSettle();
      final context = tester.element(find.text('复核结论'));
      expect(
        Theme.of(context).textTheme.bodyMedium!.color,
        Theme.of(context).colorScheme.onSurface,
      );
      expect(Theme.of(context).brightness, Brightness.light);
      final backContext = tester.element(
        find
            .descendant(
              of: find.byType(BackButton).last,
              matching: find.byType(Icon),
            )
            .last,
      );
      expect(
        IconTheme.of(backContext).color,
        Theme.of(backContext).colorScheme.onSurface,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );
}
