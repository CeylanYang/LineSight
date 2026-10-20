import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/files.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';
import 'package:sqflite/sqflite.dart';

// Drive the Android DocumentsUI with tool/drive_file_picker.py while this runs.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native save, open and cancel round trip actual backup bytes',
      (tester) async {
    final id = uid();
    final path = '${await getDatabasesPath()}/file-roundtrip-$id.db';
    final store = AppStore();
    await store.init(path: path);
    await store.register('file.admin', '文件验证员', 'File-test-pass-42');
    await store.login('file.admin', 'File-test-pass-42');
    await store.preference('autoLock', false);
    await tester.pumpWidget(LineSightApp(store: store));
    await tester.pumpAndSettle();
    final original = store.backup();
    final fileName = 'linesight-roundtrip-$id.json';
    debugPrint('PICKER_STAGE:SAVE_JSON:$fileName');
    expect(await saveTextFile(fileName, original), isTrue);
    debugPrint('PICKER_STAGE:OPEN_JSON:$fileName');
    final result = await FilePicker.platform
        .pickFiles(type: FileType.any, allowMultiple: false);
    expect(result, isNotNull);
    final imported = await File(result!.files.single.path!).readAsString();
    expect(imported, original);
    final backup = store.parseBackup(imported);
    expect(backup.inspections.length, 96);
    await store.restore(backup);
    debugPrint('PICKER_STAGE:SAVE_CSV:linesight-roundtrip-$id.csv');
    expect(
        await saveTextFile(
            'linesight-roundtrip-$id.csv', store.csv(store.records)),
        isTrue);
    debugPrint('PICKER_STAGE:CANCEL:linesight-cancel-$id.json');
    expect(await saveTextFile('linesight-cancel-$id.json', original), isFalse);
    debugPrint('PICKER_STAGE:DONE');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await store.db.close();
    store.dispose();
    await deleteDatabase(path);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
