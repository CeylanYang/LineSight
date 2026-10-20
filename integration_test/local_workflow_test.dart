import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/models.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'local auth, permissions, inspection, restore and restart survive real SQLite',
      (tester) async {
    final path =
        '${await getDatabasesPath()}/linesight-integration-${uid()}.db';
    var s = AppStore();
    await s.init(path: path);
    expect(s.ready, isTrue);
    expect(s.startupError, isNull);
    final recovery =
        await s.register('test.admin', '本机管理员', 'Test-password-42');
    expect(s.user, isNull);
    expect(s.data.inspections.length, 96);
    final dbUser = (await s.db.query('accounts')).single;
    expect(dbUser['hash'], isNot('Test-password-42'));
    expect(dbUser['hash'], isNotEmpty);
    expect(dbUser['salt'], isNotEmpty);
    await expectLater(s.login('test.admin', 'incorrect'), throwsStateError);
    await s.login('TEST.ADMIN', 'Test-password-42');
    expect(s.admin, isTrue);
    await s.preference('dark', true);
    await expectLater(
        s.updateUser(s.user!, 'operator', true), throwsStateError);
    await expectLater(s.updateUser(s.user!, 'admin', false), throwsStateError);
    final extraStation = Station(
        id: uid(),
        name: '测试工位',
        line: 'TEST LINE',
        recipeId: 'r1',
        running: false);
    await s.saveStation(extraStation);
    expect(s.station(extraStation.id).running, isFalse);
    await s.deleteStation(extraStation.id);
    await expectLater(s.deleteStation('s1'), throwsStateError);
    final first = s.pending.first, original = first.passed;
    await expectLater(s.archive({first.id}, true), throwsStateError);
    await s.review(first.id, 'pass', '已检查合成示例画面，允许放行');
    final reviewed = s.data.inspections.firstWhere((r) => r.id == first.id);
    expect(reviewed.passed, original);
    expect(reviewed.finalPassed, isTrue);
    expect(reviewed.reviewer, '本机管理员');
    await s.archive({first.id}, true);
    expect(s.records.any((r) => r.id == first.id), isFalse);
    await s.archive({first.id}, false);
    final id = await s.simulate('s1');
    expect(s.records.first.id, id);
    await s.toggleStation('s1');
    await expectLater(s.simulate('s1'), throwsStateError);
    await s.toggleStation('s1');
    final snapshot = s.records.first.recipeName;
    final parameters = jsonEncode(s.records.first.recipeSnapshot);
    await s.changeover('s1', 'r2', '切换下一批结构件');
    expect(s.station('s1').recipeId, 'r2');
    expect(
        s.data.inspections.firstWhere((r) => r.id == id).recipeName, snapshot);
    expect(
        jsonEncode(
            s.data.inspections.firstWhere((r) => r.id == id).recipeSnapshot),
        parameters);
    await expectLater(s.deleteRecipe('r2'), throwsStateError);
    final custom = Recipe(
        id: uid(),
        name: 'TEST',
        version: 'v1',
        material: '测试材料',
        sensitivity: 75,
        confidence: .8,
        defects: ['表面划痕']);
    await s.saveRecipe(custom);
    await s.deleteRecipe(custom.id);
    final backup = s.backup();
    expect(jsonDecode(backup)['schema'], 1);
    await s.register('test.operator', '操作同事', 'Operator-password-42');
    final member = s.users.firstWhere((u) => u.username == 'test.operator');
    await s.signOut();
    await s.login('test.operator', 'Operator-password-42');
    await expectLater(s.review(first.id, 'reject', '无权限尝试'), throwsStateError);
    await expectLater(s.restore(s.parseBackup(backup)), throwsStateError);
    await expectLater(
        s.register('intruder', '越权', 'Test-password-42'), throwsStateError);
    expect(() => s.backup(), throwsStateError);
    await s.simulate('s2');
    await s.signOut();
    await s.login('test.admin', 'Test-password-42');
    await s.updateUser(member, 'engineer', true);
    await s.signOut();
    await s.login('test.operator', 'Operator-password-42');
    expect(s.engineer, isTrue);
    await s.review(first.id, 'reject', '工程师确认缺陷，重新判退');
    await s.signOut();
    await s.login('test.admin', 'Test-password-42');
    final count = s.data.inspections.length;
    await s.restore(Workspace.seed(examples: false));
    expect(s.records, isEmpty);
    await s.undoRestore();
    expect(s.data.inspections.length, count);
    await expectLater(s.undoRestore(), throwsStateError);
    final audits = s.data.audits.length;
    await s.restore(s.parseBackup(backup));
    expect(s.data.audits.length, greaterThan(audits));
    await s.changePassword('Test-password-42', 'New-password-42');
    await s.signOut();
    await expectLater(
        s.login('test.admin', 'Test-password-42'), throwsStateError);
    await s.recover('test.admin', recovery, 'Recovered-password-42');
    await s.login('test.admin', 'Recovered-password-42');
    expect(s.admin, isTrue);
    await s.db.close();
    s.dispose();
    s = AppStore();
    await s.init(path: path);
    expect(s.user, isNull);
    expect(s.dark, isTrue);
    expect(s.station('s1').recipeId, 'r2');
    await s.login('test.admin', 'Recovered-password-42');
    expect(s.records, isNotEmpty);
    for (var i = 0; i < 5; i++) {
      await expectLater(
          s.login('test.operator', 'bad-password'), throwsStateError);
    }
    await expectLater(
        s.login('test.operator', 'Operator-password-42'), throwsStateError);
    final locked =
        (await s.db.query('accounts', where: 'id = ?', whereArgs: [member.id]))
            .single;
    expect(locked['lockedUntil'] as int,
        greaterThan(DateTime.now().millisecondsSinceEpoch));
    await s.db.close();
    await expectLater(s.signOut(), throwsA(anything));
    expect(s.user, isNull,
        reason:
            'Signing out must clear authentication even if audit storage is unavailable');
    s.dispose();
    await deleteDatabase(path);
  }, timeout: const Timeout(Duration(minutes: 12)));
}
