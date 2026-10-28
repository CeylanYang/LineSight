import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';
Future<void> main() async {
  await integrationDriver(responseDataCallback: (data) async {
    await File('D:/ENT207/deliverables/LineSight-video-production-20261025/review/runtime-marks.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  });
}
