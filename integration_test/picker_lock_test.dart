import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:linesight_flutter/files.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';
import 'package:sqflite/sqflite.dart';

// Run tool/drive_file_picker.py --log build/picker-lock.log alongside this test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native picker remains open beyond 30 seconds without losing export attribution',
    (tester) async {
      final id = uid(),
          path = '${await getDatabasesPath()}/picker-lock-${uid()}.db';
      final s = AppStore();
      await s.init(path: path);
      await s.register('picker.admin', '导出操作人', 'Picker-password-42');
      await s.login('picker.admin', 'Picker-password-42');
      final actorId = s.user!.id;
      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AppShell));
      final name = 'linesight-lock-$id.json';
      final content = s.backup();
      debugPrint('PICKER_STAGE:SAVE_LOCKED:$name');
      await exportWorkspaceFile(
        context,
        kind: 'JSON 备份',
        count: 96,
        name: name,
        content: content,
      );
      await tester.pumpAndSettle();
      expect(
        s.user,
        isNull,
        reason: 'Actual native picker paused the app for over 30 seconds',
      );
      expect(s.lockReason, contains('30 秒'));
      expect(find.byType(AppShell), findsNothing);
      expect(s.lastBackup!.actor, '导出操作人');
      final saved = s.data.audits.lastWhere((a) => a.action == '导出数据');
      expect(saved.actorId, actorId);
      expect(saved.operationId, isNotNull);
      expect(
        s.data.audits.where((a) => a.operationId == saved.operationId).length,
        2,
      );
      await s.login('picker.admin', 'Picker-password-42');
      await tester.pumpAndSettle();
      expect(find.text('上次文件操作'), findsOneWidget);
      expect(s.fileNotice, contains('已保存'));
      // Selecting the actual saved file confirms the export survives locking.
      debugPrint('PICKER_STAGE:OPEN_JSON:$name');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      final document = await readBackupFile(result!.files.single.path!);
      expect(document.workspace.inspections.length, 96);
      debugPrint('PICKER_STAGE:DONE');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await s.db.close();
      s.dispose();
      await deleteDatabase(path);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
