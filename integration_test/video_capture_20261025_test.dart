// Video-only runtime tour. Uses isolated fixture data; no customer API writes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/store.dart';
import 'package:sqflite/sqflite.dart';
import '../test/cloud_layout80_test.dart' show Layout80Account;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('record two editions and their real interactions', (t) async {
    final store = AppStore();
    final dbRoot = await getDatabasesPath();
    await t.runAsync(() => store.init(path: '$dbRoot/video-${DateTime.now().millisecondsSinceEpoch}.db'));
    expect(store.startupError, isNull);
    store.preferences = {'language': 'zh', 'glass': false, 'haptics': false};
    final cloud = Layout80Account();
    final marks = <Map<String, dynamic>>[];
    Future<void> hold(String name, [int seconds = 3]) async {
      await t.pumpAndSettle();
      marks.add({'name': name, 'time': DateTime.now().toUtc().toIso8601String()});
      print('VIDEO_MARK $name ${DateTime.now().toUtc().toIso8601String()}');
      await testerWait(t, seconds);
    }
    Future<void> tapText(String name) async {
      final f = find.text(name);
      await t.ensureVisible(f.first);
      await t.tap(f.first);
      await t.pumpAndSettle();
    }
    Future<void> back() async {
      await binding.handlePopRoute();
      await t.pumpAndSettle();
    }
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await t.pumpWidget(LineSightApp(store: store, cloud: cloud, showBrandReveal: false));
    await t.pumpAndSettle();
    print('VIDEO_READY');
    await testerWait(t, 18);
    await hold('home', 5);
    await t.tap(find.byKey(const ValueKey('liquid-tab-1')));
    await hold('production', 5);
    await tapText('传动支架 1');
    await hold('task-detail', 5);
    await back();
    await t.tap(find.byKey(const ValueKey('liquid-tab-3')));
    await hold('configuration', 4);
    await tapText('检查模板');
    await hold('templates', 4);
    await tapText('交互预览');
    await hold('template-preview', 4);
    // The preview is intentionally isolated from real inspection records.
    if (find.byKey(const ValueKey('preview-size-fail')).evaluate().isNotEmpty) {
      final choice = find.byKey(const ValueKey('preview-size-fail'));
      await t.ensureVisible(choice);
      await t.pumpAndSettle();
      await t.tap(choice);
      await hold('template-choice', 4);
    }
    await back();
    await t.tap(find.byKey(const ValueKey('liquid-tab-4')));
    await hold('profile', 3);
    final switcher = find.byKey(const ValueKey('special-edition-switch'));
    await t.scrollUntilVisible(switcher, 220, scrollable: find.byType(Scrollable).last);
    await t.ensureVisible(switcher);
    await hold('edition-switch', 3);
    await t.tap(switcher);
    await hold('special-enabled', 3);
    await t.tap(find.byKey(const ValueKey('liquid-tab-0')));
    await hold('special-home', 5);
    print('VIDEO_NATIVE_AURORA');
    await hold('aurora', 5);
    await t.tap(find.byKey(const ValueKey('liquid-tab-0')));
    await t.pumpAndSettle();
    await tapText('在线金融');
    await hold('finance', 4);
    await back();
    await tapText('在线读书');
    await hold('reader', 3);
    await tapText('第2章');
    await hold('reader-chapter2', 3);
    await back();
    await tapText('在线健康');
    await hold('health', 3);
    await tapText('来一杯 +200ml');
    await hold('health-added', 3);
    await back();
    await tapText('在线运动');
    await hold('sports', 3);
    await back();
    await t.tap(find.byKey(const ValueKey('liquid-tab-4')));
    await t.scrollUntilVisible(switcher, 220, scrollable: find.byType(Scrollable).last);
    await t.ensureVisible(switcher);
    await t.tap(switcher);
    await hold('large-restored', 3);
    await t.tap(find.byKey(const ValueKey('liquid-tab-0')));
    await hold('home-final', 3);
    binding.reportData = {'video_marks': marks, 'fixture_only': true, 'production_writes': 0};
    print('VIDEO_FINISH');
    await t.pumpWidget(const SizedBox.shrink());
    cloud.dispose();
    store.dispose();
  });
}

Future<void> testerWait(WidgetTester tester, int seconds) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(seconds: seconds)));
  await tester.pumpAndSettle();
}
