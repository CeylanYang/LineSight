import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'cloud_account.dart';
import 'cloud_outbox.dart';
import 'collaboration_api.dart';

class CloudPhotoRecovery {
  static final instance = CloudPhotoRecovery();
  static const contextKey = 'linesight.cloud.photo-context.v1';
  final ImagePicker picker;
  final CloudOutbox Function(CloudAccount) outbox;
  bool picking = false;
  Future<int>? recovering;
  CloudPhotoRecovery({
    ImagePicker? picker,
    CloudOutbox Function(CloudAccount)? outbox,
  }) : picker = picker ?? ImagePicker(),
       outbox = outbox ?? ((account) => CloudOutbox(account));

  void authorize(CloudAccount account, Map<String, dynamic> context) {
    if (context['scope'] == null ||
        context['scope'] != account.draftKey('outbox') ||
        !account.canEdit) {
      throw const CollaborationApiException(403, '请切回拍照时的账户和团队后恢复照片');
    }
  }

  Future<Map<String, dynamic>> enqueue(
    CloudAccount account,
    Map<String, dynamic> context,
    XFile file,
  ) async {
    authorize(account, context);
    var bytes = await file.readAsBytes();
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final longest = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      final scale = longest > 3000 ? 3000 / longest : 1.0;
      final codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round(),
        targetHeight: (descriptor.height * scale).round(),
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final png = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          bytes = Uint8List.view(
            png!.buffer,
            png.offsetInBytes,
            png.lengthInBytes,
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
        descriptor.dispose();
        buffer.dispose();
      }
    }
    authorize(account, context);
    final item = await outbox(account).enqueue(
      '${context['job_id']}',
      bytes,
      stage: '${context['stage']}',
      issueId: context['issue_id'] as int?,
    );
    authorize(account, context);
    return item;
  }

  Future<Map<String, dynamic>?> pick(
    CloudAccount account,
    String jobId,
    ImageSource source, {
    String stage = 'inspection',
    int? issueId,
  }) async {
    if (picking || recovering != null) {
      throw const CollaborationApiException(409, '照片正在处理中，请稍后');
    }
    final previous = await account.readDraft(contextKey);
    if (previous != null) {
      authorize(account, previous);
      throw const CollaborationApiException(409, '请先在同步页面恢复上次照片');
    }
    final context = <String, dynamic>{
      'scope': account.draftKey('outbox'),
      'job_id': jobId,
      'stage': stage,
      'issue_id': issueId,
    };
    authorize(account, context);
    picking = true;
    try {
      await account.saveDraft(contextKey, context);
      final photo = await picker.pickImage(
        source: source,
        maxWidth: 3000,
        maxHeight: 3000,
        imageQuality: 88,
      );
      if (photo == null) {
        await account.deleteDraft(contextKey);
        return null;
      }
      context['files'] = [photo.path];
      await account.saveDraft(contextKey, context);
      final item = await enqueue(account, context, photo);
      await account.deleteDraft(contextKey);
      return item;
    } finally {
      picking = false;
    }
  }

  Future<int> recover(CloudAccount account) {
    if (picking) return Future.value(0);
    return recovering ??= _recover(
      account,
    ).whenComplete(() => recovering = null);
  }

  Future<int> _recover(CloudAccount account) async {
    final context = await account.readDraft(contextKey);
    if (context == null) return 0;
    authorize(account, context);
    List<XFile> files;
    if (context['files'] is List) {
      files = (context['files'] as List).map((path) => XFile('$path')).toList();
    } else {
      final lost = await picker.retrieveLostData();
      if (lost.exception != null) {
        throw const CollaborationApiException(503, '照片未能恢复，请重新拍照');
      }
      files = lost.files ?? [];
      context['files'] = files.map((file) => file.path).toList();
      await account.saveDraft(contextKey, context);
      authorize(account, context);
    }
    for (final file in files) {
      await enqueue(account, context, file);
    }
    authorize(account, context);
    await account.deleteDraft(contextKey);
    return files.length;
  }

  Future<void> discard(CloudAccount account) async {
    if (picking || recovering != null) {
      throw const CollaborationApiException(409, '照片正在处理中，请稍后');
    }
    final context = await account.readDraft(contextKey);
    if (context != null) authorize(account, context);
    await account.deleteDraft(contextKey);
  }

  Future<int> onStartup(CloudAccount account) =>
      Platform.isAndroid ? recover(account) : Future.value(0);
}
