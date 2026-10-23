import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_outbox.dart';

class QueueAccount extends CloudAccount {
  final saved = <String, Map<String, dynamic>>{};
  final receipts = <String, int>{};
  bool loseAcknowledgment = true;
  List<int>? uploadedBytes;
  @override
  bool get signedIn => true;
  QueueAccount() {
    profile = {'id': 'person-1'};
    activeWorkspace = {'id': 1, 'role': 'owner'};
  }
  @override
  Future<Map<String, dynamic>?> readDraft(String key) async =>
      saved[key] == null
      ? null
      : Map<String, dynamic>.from(jsonDecode(jsonEncode(saved[key])) as Map);
  @override
  Future<void> saveDraft(String key, Map<String, dynamic> value) async {
    saved[key] = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(value)) as Map,
    );
  }

  @override
  Future<Map<String, dynamic>> uploadPhoto(
    String path,
    List<int> bytes,
    String key,
    Map<String, String> fields,
  ) async {
    uploadedBytes = bytes;
    receipts.putIfAbsent(key, () => receipts.length + 1);
    if (loseAcknowledgment) {
      loseAcknowledgment = false;
      throw TimeoutException('response lost');
    }
    return {'id': receipts[key]};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'encrypted queue survives restart, deduplicates uncertain uploads and isolates identities',
    () async {
      final folder = await Directory.systemTemp.createTemp('linesight-outbox-');
      final account = QueueAccount();
      try {
        final queue = CloudOutbox(account, directory: () async => folder.path);
        final bytes = utf8.encode(
          'private-photo-content-that-must-not-be-stored-plain',
        );
        final first = await queue.enqueue('job-1', bytes);
        final second = await queue.enqueue('job-1', bytes);
        expect(second['key'], first['key']);
        expect(await queue.list(), hasLength(1));
        final files = await Directory(
          '${folder.path}/cloud-outbox',
        ).list().toList();
        expect(files, hasLength(1));
        expect(
          await (files.single as File).readAsBytes(),
          isNot(containsAllInOrder(bytes)),
        );
        await expectLater(
          queue.retry(first['key'] as String),
          throwsA(isA<TimeoutException>()),
        );
        expect((await queue.list()).single['state'], 'pending');
        final restarted = CloudOutbox(
          account,
          directory: () async => folder.path,
        );
        expect(await restarted.retry(first['key'] as String), 1);
        expect(account.receipts, hasLength(1));
        expect(account.uploadedBytes, bytes);
        expect((await restarted.list()).single['state'], 'uploaded');
        account.activeWorkspace = {'id': 2};
        await expectLater(restarted.list(), throwsException);
        expect(
          await CloudOutbox(account, directory: () async => folder.path).list(),
          isEmpty,
        );
        account.activeWorkspace = {'id': 1};
        account.profile = {'id': 'person-2'};
        expect(
          await CloudOutbox(account, directory: () async => folder.path).list(),
          isEmpty,
        );
        account.profile = {'id': 'person-1'};
        await restarted.consume('job-1', [1]);
        expect(await restarted.list(), isEmpty);
      } finally {
        account.dispose();
        await folder.delete(recursive: true);
      }
    },
  );
}
