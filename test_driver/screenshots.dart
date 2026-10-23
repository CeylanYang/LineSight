import 'dart:io';
import 'dart:convert';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (data) async {
      if (data?['source_record_id'] != null) {
        final directory = Directory(
          Platform.environment['LINESIGHT_SCREENSHOT_DIR'] ??
              'screenshots/v1.1',
        );
        await directory.parent.create(recursive: true);
        final evidence = <String, dynamic>{
          for (final key in [
            'workspace_id',
            'job_id',
            'source_record_id',
            'samples_excluded',
            'repeat_import_skipped',
            'recovered_photo_acknowledged',
            'actual_transport_progress_samples',
            'diagnostics_connected',
            'diagnostics_redacted_fields_verified',
          ])
            key: data![key],
        };
        await File(
          '${directory.parent.path}/android-journey.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
      }
      await writeResponseData(data);
    },
    onScreenshot: (name, bytes, [args]) async {
      final directory = Directory(
        Platform.environment['LINESIGHT_SCREENSHOT_DIR'] ?? 'screenshots/v1.1',
      );
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
