import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/record_review.dart';
import 'package:linesight_flutter/store.dart';

void main() {
  test(
    'removed records return a clear error before accessing storage',
    () async {
      final s = AppStore()
        ..ready = true
        ..user = const LocalUser('admin', 'admin', '管理员', 'admin', true);
      addTearDown(s.dispose);
      final beforeAudits = List.of(s.data.audits);
      await expectLater(
        s.review('removed', 'pass', '已经核对'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            '记录已移除，请返回检测列表查看当前记录',
          ),
        ),
      );
      expect(s.writing, isFalse);
      expect(s.revision, 0);
      expect(s.data.audits, beforeAudits);
    },
  );
  test('review version detects changes to every persisted evidence field', () {
    final w = Workspace.seed();
    final record = w.inspections.first;
    record.recipeSnapshot = w.recipes.first.toJson();
    final version = ReviewRecordVersion.capture(record);
    for (final edit in <void Function(Inspection)>[
      (r) => r.id = 'different',
      (r) => r.serial = 'different',
      (r) => r.stationId = 's2',
      (r) => r.recipeName = 'different',
      (r) => r.at = r.at.add(const Duration(microseconds: 1)),
      (r) => r.passed = !r.passed,
      (r) => r.defect = 'different',
      (r) => r.confidence = .123,
      (r) => r.operatorName = 'different',
      (r) => r.note = 'different',
      (r) => r.review = 'pass',
      (r) => r.reviewer = 'different',
      (r) => r.reviewedAt = DateTime.utc(2026, 10, 14),
      (r) => r.archived = !r.archived,
      (r) => r.sample = !r.sample,
      (r) => r.recipeSnapshot['sensitivity'] = 12.3,
    ]) {
      final next = Inspection.fromJson(record.toJson());
      edit(next);
      expect(version.matches(next), isFalse);
    }
    record.note = '原对象后来修改';
    expect(version.matches(record), isFalse);
  });

  test('equivalent serialized records keep their review version', () {
    final w = Workspace.seed();
    final record = w.inspections.first;
    record.recipeSnapshot = w.recipes.first.toJson();
    final version = ReviewRecordVersion.capture(record);
    final copy = Inspection.fromJson(record.toJson());
    copy.at = copy.at.toLocal();
    copy.recipeSnapshot = Map.fromEntries(
      copy.recipeSnapshot.entries.toList().reversed,
    );
    expect(version.matches(copy), isTrue);
    w.stations.first.name = '工位已重命名';
    w.recipes.first.name = '当前配方已更新';
    expect(version.matches(record), isTrue);
  });

  test('review note validation follows existing trimmed and UTF-16 limits', () {
    for (final text in ['', '  ', '字', '两个', ' x ']) {
      expect(reviewNoteError(text), isNotNull);
    }
    expect(reviewNoteError('  已核对  '), isNull);
    expect(reviewNoteError('质' * 2000), isNull);
    expect(reviewNoteError('质' * 2001), isNotNull);
    expect(reviewNoteError('😀' * 1001), isNotNull);
  });
}
