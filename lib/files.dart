import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'backup.dart';
import 'stream_backup.dart';
import 'models.dart';
import 'store.dart';
import 'ui.dart';
import 'recovery_storage.dart';
import 'record_csv.dart';
import 'l10n.dart';

const _archiveFiles = MethodChannel('linesight/files');
final _activeScratch = <String>{};

Future<Directory> newBackupScratch() async {
  final root = Directory(
    (await _archiveFiles.invokeMethod<String>('scratchRoot'))!,
  );
  final rootPath = await root.resolveSymbolicLinks();
  // Only expired directories created by this feature are eligible for cleanup.
  await for (final entry in root.list(followLinks: false)) {
    if (entry is! Directory ||
        !entry.path.split(Platform.pathSeparator).last.startsWith('job_') ||
        _activeScratch.contains(entry.path)) {
      continue;
    }
    try {
      final resolved = await entry.resolveSymbolicLinks();
      if (resolved.startsWith('$rootPath${Platform.pathSeparator}') &&
          DateTime.now().difference((await entry.stat()).modified) >
              const Duration(days: 1)) {
        await entry.delete(recursive: true);
      }
    } on FileSystemException {
      /* A stale cache must not block a new backup. */
    }
  }
  final directory = await root.createTemp('job_');
  _activeScratch.add(directory.path);
  return directory;
}

Future<void> removeBackupScratch(Directory directory) async {
  // Only directories issued in this process can be removed through this helper.
  if (!_activeScratch.remove(directory.path)) return;
  try {
    await directory.delete(recursive: true);
  } on FileSystemException {
    /* Retried as expired cache. */
  }
}

Future<bool> saveArchiveFile(PreparedArchive archive, String name) async =>
    await _archiveFiles.invokeMethod<bool>('saveArchive', {
      'path': archive.path,
      'name': name,
      'sha256': archive.sha256,
    }) ??
    false;

Future<void> exportStreamBackup(
  BuildContext context, {
  void Function(ArchiveTask<PreparedArchive> task)? onTask,
  void Function()? onSaving,
  String? name,
}) async {
  final s = AppScope.of(context), session = AppScope.of(context).session;
  s.requireSession(session, elevated: true);
  final snapshot = s.data;
  final ticket = await s.beginExport('LSB 备份', snapshot.inspections.length);
  var outcome = ExportOutcome.failed;
  Directory? scratch;
  PreparedArchive? archive;
  String? detail;
  try {
    s.requireSession(session, elevated: true);
    scratch = await newBackupScratch();
    s.requireSession(session, elevated: true);
    final task = ArchiveTask.write(snapshot, '${scratch.path}/workspace.lsb');
    onTask?.call(task);
    archive = await task.result;
    if (!context.mounted) throw const BackupCancelled();
    s.requireSession(session, elevated: true);
    onSaving?.call();
    outcome =
        await saveArchiveFile(
          archive,
          name ?? 'LineSight-${DateTime.now().millisecondsSinceEpoch}.lsb',
        )
        ? ExportOutcome.saved
        : ExportOutcome.cancelled;
  } on BackupCancelled {
    outcome = ExportOutcome.cancelled;
  } catch (error) {
    detail = error is FormatException
        ? error.message
        : error is StateError
        ? error.message.toString()
        : null;
  } finally {
    if (scratch != null) await removeBackupScratch(scratch);
  }
  await _finishWorkspaceExport(
    context.mounted ? context : null,
    s,
    ticket,
    outcome,
    fileBytes: archive?.bytes,
    fileSha256: archive?.sha256,
    detail: detail,
  );
}

Future<void> exportRecoveryOriginal(
  BuildContext context,
  RecoverySnapshot snapshot, {
  required bool Function() cancelled,
  BackupReporter? onProgress,
  void Function()? onSaving,
}) async {
  final s = AppScope.of(context), session = AppScope.of(context).session;
  s.requireSession(session, owner: true);
  final ticket = await s.beginExport(
    '恢复前原件',
    0,
    reference: '恢复编号 ${snapshot.id}',
  );
  Directory? scratch;
  PreparedArchive? archive;
  var outcome = ExportOutcome.failed;
  String? detail;
  void check() {
    if (!context.mounted || cancelled()) throw const BackupCancelled();
    s.requireSession(session, owner: true);
  }

  try {
    check();
    scratch = await newBackupScratch();
    check();
    archive = await writeRecoveryOriginal(
      s.db,
      snapshot.id,
      '${scratch.path}/original.lsr',
      check: check,
      report: onProgress,
    );
    check();
    onSaving?.call();
    outcome =
        await saveArchiveFile(archive, 'LineSight-original-${snapshot.id}.lsr')
        ? ExportOutcome.saved
        : ExportOutcome.cancelled;
  } on BackupCancelled {
    outcome = ExportOutcome.cancelled;
  } catch (e) {
    detail = e is FormatException
        ? e.message
        : e is StateError
        ? e.message.toString()
        : null;
  } finally {
    if (scratch != null) await removeBackupScratch(scratch);
  }
  await _finishWorkspaceExport(
    context.mounted ? context : null,
    s,
    ticket,
    outcome,
    fileBytes: archive?.bytes,
    fileSha256: archive?.sha256,
    detail: detail,
  );
}

Future<bool> saveTextFile(
  String name,
  String text, {
  String? dialogTitle,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle ?? '保存导出文件',
    fileName: name,
    bytes: Uint8List.fromList(utf8.encode(text)),
  );
  return path != null;
}

Future<void> exportRecords(
  BuildContext context,
  CsvSnapshot snapshot, {
  required int expectedSession,
  String scope = '检测记录',
  String? name,
  void Function(ArchiveTask<PreparedArchive> task)? onTask,
  void Function()? onSaving,
}) async {
  final s = AppScope.of(context);
  s.requireSession(expectedSession, elevated: true);
  final ticket = await s.beginExport(
    'CSV',
    snapshot.records.length,
    targets: snapshot.targets,
    reference: '$scope · 快照 ${instantJson(snapshot.capturedAt)}',
  );
  var outcome = ExportOutcome.failed;
  Directory? scratch;
  PreparedArchive? archive;
  String? detail;
  try {
    s.requireSession(expectedSession, elevated: true);
    scratch = await newBackupScratch();
    s.requireSession(expectedSession, elevated: true);
    final task = ArchiveTask.csv(snapshot, '${scratch.path}/records.csv');
    onTask?.call(task);
    archive = await task.result;
    if (!context.mounted) throw const BackupCancelled();
    s.requireSession(expectedSession, elevated: true);
    onSaving?.call();
    outcome =
        await saveArchiveFile(
          archive,
          name ??
              'LineSight-records-${snapshot.capturedAt.millisecondsSinceEpoch}.csv',
        )
        ? ExportOutcome.saved
        : ExportOutcome.cancelled;
  } on BackupCancelled {
    outcome = ExportOutcome.cancelled;
  } catch (error) {
    detail = error is FormatException
        ? error.message
        : error is StateError
        ? error.message.toString()
        : null;
  } finally {
    if (scratch != null) await removeBackupScratch(scratch);
  }
  await _finishWorkspaceExport(
    context.mounted ? context : null,
    s,
    ticket,
    outcome,
    fileBytes: archive?.bytes,
    fileSha256: archive?.sha256,
    detail: detail,
  );
}

Future<void> exportBackup(BuildContext context) async {
  final s = AppScope.of(context);
  final startedSession = s.session;
  s.requireSession(startedSession, elevated: true);
  final snapshot = s.data;
  final content = await compute(BackupDocument.encode, snapshot);
  s.requireSession(startedSession, elevated: true);
  if (!context.mounted) return;
  await exportWorkspaceFile(
    context,
    kind: 'JSON 备份',
    count: snapshot.inspections.length,
    name: 'LineSight-backup-${DateTime.now().millisecondsSinceEpoch}.json',
    content: content,
  );
}

Future<BackupDocument> readBackupFile(String path) async {
  if (await isArchiveFile(path)) return ArchiveTask.read(path).result;
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in File(path).openRead()) {
    if (bytes.length + chunk.length > maxBackupBytes) {
      throw const FormatException('备份不能超过 20 MB');
    }
    bytes.add(chunk);
  }
  return compute(BackupDocument.parse, utf8.decode(bytes.takeBytes()));
}

(String, int) _originalTimeExport((TimeMigrationArchive, String) input) {
  final source = input.$1.backupSource(input.$2);
  final workspace = jsonDecode(source)['workspace'];
  return (source, (workspace['inspections'] as List).length);
}

Future<void> exportTimeOriginal(
  BuildContext context,
  TimeMigrationArchive archive,
  String key,
) async {
  final s = AppScope.of(context), session = AppScope.of(context).session;
  s.requireSession(session, elevated: true);
  final (source, count) = await compute(_originalTimeExport, (archive, key));
  s.requireSession(session, elevated: true);
  if (!context.mounted) return;
  await exportWorkspaceFile(
    context,
    kind: key == 'workspace' ? '旧版时间原件（工作区）' : '旧版时间原件（还原点）',
    count: count,
    name: 'LineSight-original-${archive.id}-$key.json',
    content: source,
  );
}

Future<void> exportWorkspaceFile(
  BuildContext context, {
  required String kind,
  required int count,
  required String name,
  required String content,
  Iterable<AuditTarget> targets = const [],
}) async {
  final s = AppScope.of(context);
  final dialogTitle = tr(context, '保存导出文件');
  final ticket = await s.beginExport(kind, count, targets: targets);
  var outcome = ExportOutcome.cancelled;
  try {
    s.requireSession(ticket.session, elevated: true);
    outcome = await saveTextFile(name, content, dialogTitle: dialogTitle)
        ? ExportOutcome.saved
        : ExportOutcome.cancelled;
  } catch (_) {
    outcome = ExportOutcome.failed;
  }
  await _finishWorkspaceExport(
    context.mounted ? context : null,
    s,
    ticket,
    outcome,
  );
}

Future<void> _finishWorkspaceExport(
  BuildContext? context,
  AppStore s,
  ExportTicket ticket,
  ExportOutcome outcome, {
  int? fileBytes,
  String? fileSha256,
  String? detail,
}) async {
  s.checkAutoLock();
  final kind = ticket.kind, count = ticket.count;
  var message = switch (outcome) {
    ExportOutcome.saved =>
      kind == '恢复前原件'
          ? '恢复前原件已保存并回读校验，可用于排查原始数据。'
          : kind == 'CSV'
          ? 'CSV 已保存并回读校验，共 $count 条记录。'
          : '$kind 已保存，共 $count 条记录。',
    ExportOutcome.cancelled => '已取消 $kind 导出，未保存文件。',
    ExportOutcome.failed => '$kind 未确认保存，请检查文件位置或存储空间。',
  };
  if (detail != null) message += ' $detail';
  try {
    await s.finishExport(
      ticket,
      outcome,
      fileBytes: fileBytes,
      fileSha256: fileSha256,
    );
  } catch (_) {
    message += ' 操作日志未能写入，请检查本机存储空间。';
  }
  // This notice remains private to the initiating account across a lock.
  s.reportFileNotice(ticket, message);
  if (context != null &&
      context.mounted &&
      s.user?.id == ticket.actorId &&
      s.session == ticket.session) {
    toast(context, message);
  }
}
