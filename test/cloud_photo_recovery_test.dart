import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:linesight_flutter/cloud_outbox.dart';
import 'package:linesight_flutter/cloud_photo_recovery.dart';
import 'cloud_outbox_test.dart' show QueueAccount;

class LostPicker extends ImagePicker {
  final XFile file;
  var reads = 0;
  void Function()? onRead;
  LostPicker(this.file);
  @override
  Future<LostDataResponse> retrieveLostData() async {
    reads++;
    onRead?.call();
    return LostDataResponse(files: [file]);
  }
}

class RecoveryAccount extends QueueAccount {
  @override
  Future<void> deleteDraft(String key) async {
    saved.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'lost Android picker result recovers encrypted content once to its original task',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'linesight-lost-photo-',
      );
      final file = await File(
        '${directory.path}/capture.jpg',
      ).writeAsBytes([1, 2, 3, 4]);
      final account = RecoveryAccount(), picker = LostPicker(XFile(file.path));
      final recovery = CloudPhotoRecovery(
        picker: picker,
        outbox: (cloud) =>
            CloudOutbox(cloud, directory: () async => directory.path),
      );
      try {
        await account.saveDraft(CloudPhotoRecovery.contextKey, {
          'scope': account.draftKey('outbox'),
          'job_id': 'original-task',
          'stage': 'after',
          'issue_id': 17,
        });
        expect(await recovery.recover(account), 1);
        final rows = await CloudOutbox(
          account,
          directory: () async => directory.path,
        ).list();
        expect(rows, hasLength(1));
        expect(rows.single['job_id'], 'original-task');
        expect(rows.single['stage'], 'after');
        expect(rows.single['issue_id'], 17);
        expect(rows.single['state'], 'pending');
        expect(account.saved[CloudPhotoRecovery.contextKey], isNull);
        expect(await recovery.recover(account), 0);
        expect(picker.reads, 1);
      } finally {
        account.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'an identity switch during native retrieval retains file paths for the original account',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'linesight-photo-switch-',
      );
      final file = await File(
        '${directory.path}/capture.jpg',
      ).writeAsBytes([5, 6, 7]);
      final account = RecoveryAccount(), picker = LostPicker(XFile(file.path));
      final recovery = CloudPhotoRecovery(
        picker: picker,
        outbox: (cloud) =>
            CloudOutbox(cloud, directory: () async => directory.path),
      );
      try {
        await account.saveDraft(CloudPhotoRecovery.contextKey, {
          'scope': account.draftKey('outbox'),
          'job_id': 'original-task',
          'stage': 'inspection',
        });
        picker.onRead = () => account.profile = {'id': 'another-person'};
        await expectLater(recovery.recover(account), throwsA(isA<Exception>()));
        expect(account.saved[CloudPhotoRecovery.contextKey]!['files'], [
          file.path,
        ]);
        account.profile = {'id': 'person-1'};
        picker.onRead = null;
        expect(await recovery.recover(account), 1);
        expect(picker.reads, 1);
      } finally {
        account.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'switching cloud identity never consumes another account lost image',
    () async {
      final account = RecoveryAccount(),
          picker = LostPicker(XFile('must-not-be-read'));
      final recovery = CloudPhotoRecovery(picker: picker);
      await account.saveDraft(CloudPhotoRecovery.contextKey, {
        'scope': account.draftKey('outbox'),
        'job_id': 'private-task',
        'stage': 'inspection',
      });
      account.profile = {'id': 'another-person'};
      await expectLater(recovery.recover(account), throwsA(isA<Exception>()));
      expect(picker.reads, 0);
      expect(account.saved[CloudPhotoRecovery.contextKey], isNotNull);
      account.dispose();
    },
  );
}
