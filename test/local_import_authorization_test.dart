import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';

void main() {
  tearDown(CollaborationSession.clear);

  test('cloud identity cannot authorize local preview or export', () {
    final store = AppStore()..ready = true;
    CollaborationSession.token = 'cloud-session';
    CollaborationSession.serviceUrl = 'https://example.com/api/v1/';
    expect(store.captureTeamImport, throwsStateError);
    expect(() => store.captureCsv(store.records), throwsStateError);
    store.user = const LocalUser('o', 'operator', 'Operator', 'operator', true);
    expect(store.captureTeamImport, throwsStateError);
    store.user = const LocalUser('a', 'admin', 'Disabled', 'admin', false);
    expect(store.captureTeamImport, throwsStateError);
  });

  test('authorized snapshot excludes archived and does not mutate source', () {
    final store = AppStore()
      ..ready = true
      ..data = Workspace.seed()
      ..user = const LocalUser('e', 'engineer', 'Engineer', 'engineer', true);
    store.data.inspections.first.archived = true;
    final original = store.data.inspections[1];
    final snapshot = store.captureTeamImport();
    expect(snapshot.length, store.data.inspections.length - 1);
    expect(snapshot.any((r) => r.archived), isFalse);
    snapshot.first.note = 'Preview change';
    expect(original.note, isNot('Preview change'));
    expect(() => snapshot.clear(), throwsUnsupportedError);
    final session = store.session;
    store.lock();
    expect(store.captureTeamImport, throwsStateError);
    expect(
      () => store.requireSession(session, elevated: true),
      throwsStateError,
    );
  });
}
