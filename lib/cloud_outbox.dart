import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';
import 'cloud_account.dart';
import 'collaboration_api.dart';

/// Encrypted, identity/workspace-scoped attachments. Success is acknowledged only
/// after the server has returned its durable evidence ID.
class CloudOutbox {
  final CloudAccount account;
  final String scope;
  final Future<String> Function() directory;
  static final Expando<Map<String, Future<void>>> _accountLocks = Expando();
  Map<String, Future<void>> get _locks => _accountLocks[account] ??= {};
  CloudOutbox(this.account, {Future<String> Function()? directory})
    : scope =
          account.draftKey('outbox') ??
          (throw const CollaborationApiException(401, '请先登录')),
      directory = directory ?? getDatabasesPath;
  void authorize() {
    if (scope != account.draftKey('outbox')) {
      throw const CollaborationApiException(401, '请切回原工作区后重试');
    }
  }

  Future<T> locked<T>(Future<T> Function() operation) {
    final result = (_locks[scope] ?? Future<void>.value())
        .catchError((_) {})
        .then((_) {
          authorize();
          return operation();
        });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _locks[scope] = tail;
    tail.then((_) {
      if (identical(_locks[scope], tail)) _locks.remove(scope);
    });
    return result;
  }

  Future<List<Map<String, dynamic>>> _rows() async {
    final saved = await account.readDraft(scope);
    authorize();
    return (saved?['items'] as List? ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<void> _save(List<Map<String, dynamic>> rows) async {
    authorize();
    await account.saveDraft(scope, {'items': rows});
    authorize();
  }

  Future<List<Map<String, dynamic>>> list() => locked(_rows);
  Future<File> _file(String key) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw const CollaborationApiException(400, '图片标识无效');
    }
    final folder = Directory('${await directory()}/cloud-outbox');
    await folder.create(recursive: true);
    return File(
      '${folder.path}/${sha256.convert(utf8.encode(scope))}-$key.bin',
    );
  }

  Future<SecretKey> _key() async {
    final saved = await account.readDraft('$scope.key');
    authorize();
    if (saved != null) {
      return SecretKey(base64Decode(saved['secret'] as String));
    }
    final key = await AesGcm.with256bits().newSecretKey();
    await account.saveDraft('$scope.key', {
      'secret': base64Encode(await key.extractBytes()),
    });
    return key;
  }

  Future<Map<String, dynamic>> enqueue(
    String jobId,
    List<int> bytes, {
    String stage = 'inspection',
    int? issueId,
  }) => locked(() async {
    if (bytes.length > 10 * 1024 * 1024) {
      throw const CollaborationApiException(400, '请选择不超过 10 MB 的图片');
    }
    final key = sha256.convert([
      ...utf8.encode('$scope/$jobId/$stage/$issueId/'),
      ...bytes,
    ]).toString();
    final rows = await _rows();
    final prior = rows.where((r) => r['key'] == key);
    if (prior.isNotEmpty) return prior.first;
    final box = await AesGcm.with256bits().encrypt(
      bytes,
      secretKey: await _key(),
    );
    final file = await _file(key);
    await file.writeAsBytes(box.concatenation(), flush: true);
    final item = <String, dynamic>{
      'key': key,
      'job_id': jobId,
      'workspace_id': account.activeWorkspace!['id'],
      'stage': stage,
      'issue_id': issueId,
      'state': 'pending',
      'bytes': bytes.length,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    rows.add(item);
    await _save(rows);
    return item;
  });
  Future<int> retry(String key) => locked(() async {
    final rows = await _rows();
    final index = rows.indexWhere((r) => r['key'] == key);
    if (index < 0) throw const CollaborationApiException(404, '图片队列已更新，请刷新');
    final item = rows[index];
    if (item['state'] == 'uploaded') {
      if (item.containsKey('error')) {
        item.remove('error');
        await _save(rows);
      }
      await _cleanup(key);
      authorize();
      return item['evidence_id'] as int;
    }
    try {
      final bytes = await AesGcm.with256bits().decrypt(
        SecretBox.fromConcatenation(
          await (await _file(key)).readAsBytes(),
          nonceLength: 12,
          macLength: 16,
        ),
        secretKey: await _key(),
      );
      authorize();
      final result = await account.uploadPhoto(
        'workspaces/${item['workspace_id']}/jobs/${item['job_id']}/evidence/',
        bytes,
        key,
        {
          'stage': '${item['stage']}',
          if (item['issue_id'] != null) 'issue_id': '${item['issue_id']}',
        },
      );
      authorize();
      item['state'] = 'uploaded';
      item['evidence_id'] = result['id'];
      item.remove('error');
      await _save(rows);
      await _cleanup(key);
      authorize();
      return result['id'] as int;
    } catch (failure) {
      authorize();
      item['error'] = failure is CollaborationApiException
          ? failure.message
          : '网络连接失败，请重试';
      await _save(rows);
      rethrow;
    }
  });
  // A durable upload receipt remains successful when temporary-file cleanup
  // fails. Replaying the uploaded row retries cleanup without uploading again.
  Future<void> _cleanup(String key) async {
    try {
      final file = await _file(key);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Keep the encrypted file for a later cleanup attempt.
    }
  }

  Future<void> remove(String key) => locked(() async {
    final rows = await _rows();
    rows.removeWhere((r) => r['key'] == key);
    await _save(rows);
    final file = await _file(key);
    if (await file.exists()) await file.delete();
  });
  Future<void> consume(String jobId, List<int> ids) => locked(() async {
    final rows = await _rows();
    rows.removeWhere(
      (r) => r['job_id'] == jobId && ids.contains(r['evidence_id']),
    );
    await _save(rows);
  });
}
