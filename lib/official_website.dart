import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ui.dart';

const officialWebsite = 'https://99ai.pronhubcn.com/';
Future<void> openOfficialWebsite(BuildContext context) async {
  try {
    if (!await launchUrl(
      Uri.parse(officialWebsite),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('暂时无法打开官网');
    }
  } catch (_) {
    if (context.mounted) toast(context, '暂时无法打开官网');
  }
}
