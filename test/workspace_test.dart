import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';

void main() {
  test(
    'seed and empty workspace are valid and round trip without data loss',
    () {
      for (final examples in [true, false]) {
        final w = Workspace.seed(examples: examples);
        w.validate();
        final restored = Workspace.fromJson(jsonDecode(jsonEncode(w.toJson())));
        restored.validate();
        expect(restored.toJson(), w.toJson());
        expect(restored.inspections.length, examples ? 96 : 0);
        expect(restored.inspections.every((r) => r.sample), isTrue);
      }
    },
  );
  test(
    'backup validator rejects duplicate IDs, broken associations and invalid parameters',
    () {
      final store = AppStore();
      String source(Workspace w) => jsonEncode({
        'app': 'LineSight',
        'schema': 1,
        'workspace': w.toJson(),
      });
      final duplicate = Workspace.seed();
      duplicate.inspections[1].id = duplicate.inspections.first.id;
      expect(() => store.parseBackup(source(duplicate)), throwsFormatException);
      final orphan = Workspace.seed();
      orphan.inspections.first.stationId = 'missing';
      expect(() => store.parseBackup(source(orphan)), throwsFormatException);
      final parameter = Workspace.seed();
      parameter.recipes.first.confidence = 2;
      expect(() => store.parseBackup(source(parameter)), throwsFormatException);
      expect(
        () => store.parseBackup('{"app":"other","schema":1}'),
        throwsFormatException,
      );
      expect(() => store.parseBackup('{broken'), throwsFormatException);
      expect(
        () =>
            store.parseBackup('{"app":"LineSight","schema":1,"workspace":{}}'),
        throwsFormatException,
      );
    },
  );
  test(
    'review does not change original verdict and archived records leave pending queue',
    () {
      final r = Workspace.seed().inspections.first;
      expect(r.passed, isFalse);
      expect(r.pending, isTrue);
      r.review = 'pass';
      expect(r.passed, isFalse);
      expect(r.finalPassed, isTrue);
      expect(r.pending, isFalse);
      r.review = null;
      r.archived = true;
      expect(r.pending, isFalse);
    },
  );
  test(
    'CSV is escaped, formula neutralized, and export requires elevated role',
    () {
      final s = AppStore()..ready = true;
      final record = s.data.inspections;
      expect(() => s.csv(record), throwsStateError);
      s.user = const LocalUser('o', 'operator', '操作员', 'operator', true);
      expect(() => s.csv(record), throwsStateError);
      s.user = const LocalUser('a', 'admin', '管理员', 'admin', true);
      final r = Workspace.seed().inspections.first;
      r.serial = '=HYPERLINK("demo")';
      r.note = '一行,文字\n第二行';
      final csv = s.csv([r]);
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv, contains('"\'=HYPERLINK(""demo"")"'));
      expect(csv, contains('"一行,文字\n第二行"'));
      final backup = jsonDecode(s.backup()) as Map;
      expect(backup.keys.toSet(), {'app', 'schema', 'exportedAt', 'workspace'});
      expect(s.backup(), isNot(contains('recoveryHash')));
    },
  );
}
