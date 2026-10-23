import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_lifecycle.dart';
import 'package:linesight_flutter/screens/cloud_evidence_compare.dart';
import 'package:linesight_flutter/screens/cloud_sessions.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_access_ui_test.dart' show AccessAccount;

const folder = 'docs/product/linesight/acceptance/closure-batch';
Map<String, dynamic> workflow() =>
    jsonDecode(File('$folder/live-workflow.json').readAsStringSync())
        as Map<String, dynamic>;

class ClosureAccount extends AccessAccount {
  Completer<List<Map<String, dynamic>>>? sessionGate;
  Completer<List<int>>? imageGate;
  final downloads = <String>[];
  final fixture = workflow();
  @override
  Future<List<Map<String, dynamic>>> listIdentitySessions() async {
    if (sessionGate != null) return sessionGate!.future;
    return (jsonDecode(
              File(
                'docs/product/linesight/acceptance/session-batch/live-sessions.json',
              ).readAsStringSync(),
            )['sessions']
            as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Future<List<int>> download(String path) async {
    downloads.add(path);
    if (imageGate != null) return imageGate!.future;
    final photos = fixture['states']['closed']['evidence'] as List;
    final photo = photos.firstWhere((row) => path.contains('/${row['id']}/'));
    return File('$folder/${photo['stage']}-source.png').readAsBytesSync();
  }
}

void main() {
  test(
    'five stages include exception, reinspection, and a skipped clean branch',
    () {
      final states = workflow()['states'] as Map;
      for (final entry in {
        'queued': 0,
        'printing': 1,
        'inspection': 2,
        'exception': 3,
        'reinspection': 3,
        'closed': 4,
      }.entries) {
        final steps = cloudLifecycle(
          Map<String, dynamic>.from(states[entry.key] as Map),
        );
        expect(steps, hasLength(5));
        expect(steps[entry.value].state, LifecycleState.active);
        if (entry.key == 'reinspection') expect(steps[3].label, '待复检');
      }
      expect(
        cloudLifecycle({'status': 'closed'})[3].state,
        LifecycleState.skipped,
      );
      expect(
        cloudLifecycle({
          'status': 'closed',
          'inspections': [
            {'verdict': 'fail'},
          ],
        })[3].state,
        LifecycleState.complete,
      );
      expect(
        cloudLifecycle({
          'status': 'unknown',
        }).every((step) => step.state == LifecycleState.pending),
        true,
      );
    },
  );
  test('unrecognized browser is not labeled as a physical Android device', () {
    expect(identityDeviceLabel('Python-urllib/3.12'), '其他设备');
    expect(identityDeviceLabel('Android Chrome'), 'Android');
  });
  late ClosureAccount account;
  late AppStore store;
  setUp(() {
    account = ClosureAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'haptic': false, 'glass': false};
  });
  tearDown(() {
    account.dispose();
    store.dispose();
  });

  Future<void> show(
    WidgetTester tester,
    Widget page, {
    String language = 'en',
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          fontFamily: 'EvidenceFont',
          colorScheme: appTheme(false).colorScheme,
        ),
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(account: account, child: child!),
        ),
        home: page,
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  CloudEvidenceComparePage compare({List<Map<String, dynamic>>? photos}) =>
      CloudEvidenceComparePage(
        jobId: account.fixture['job_id'] as String,
        issueId: account.fixture['issue_id'] as int,
        photos:
            photos ??
            (account.fixture['states']['closed']['evidence'] as List)
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList(),
      );

  testWidgets('late session response cannot cross account identity', (
    tester,
  ) async {
    account.sessionGate = Completer();
    await show(tester, const CloudSessionsPage(), settle: false);
    account.profile = {...account.profile!, 'id': 'new-user'};
    account.notifyListeners();
    await tester.pump();
    account.sessionGate!.complete([
      {'browser': 'Android', 'current': true},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Android'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'comparison downloads only selected issue images and drops late bytes on team change',
    (tester) async {
      account.imageGate = Completer();
      await show(
        tester,
        compare(
          photos: [
            ...(compare().photos),
            {'id': 99999, 'issue_id': -1, 'stage': 'before'},
          ],
        ),
        settle: false,
      );
      expect(account.downloads, hasLength(2));
      expect(account.downloads.any((path) => path.contains('99999')), false);
      account.activeWorkspace = {'id': 2, 'role': 'owner'};
      account.notifyListeners();
      await tester.pump();
      account.imageGate!.complete(
        File('$folder/before-source.png').readAsBytesSync(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'empty comparison shows both missing stages without inventing evidence',
    (tester) async {
      await show(tester, compare(photos: []));
      expect(find.text('No photos uploaded yet'), findsNWidgets(2));
      expect(account.downloads, isEmpty);
    },
  );
  for (final language in ['zh', 'en']) {
    testWidgets('closure screens $language render narrow bilingual PNG', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await (FontLoader('EvidenceFont')..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
              ),
            ),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await show(tester, const CloudSessionsPage(), language: language);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../$folder/png/74-sessions-$language-desktop-render.png',
        ),
      );
      await show(tester, compare(), language: language);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../$folder/png/75-before-after-$language-desktop-render.png',
        ),
      );
      final states = account.fixture['states'] as Map;
      await show(
        tester,
        DetailScaffold(
          title: language == 'zh' ? '任务进度' : 'Task progress',
          children: [
            for (final entry in states.entries) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('${entry.key} · ${states[entry.key]['id']}'),
              ),
              CloudLifecycleTrack(
                job: Map<String, dynamic>.from(entry.value as Map),
              ),
            ],
            const SizedBox(height: 20),
            const CloudLifecycleTrack(job: {'status': 'closed'}),
          ],
        ),
        language: language,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../$folder/png/76-lifecycle-$language-desktop-render.png',
        ),
      );
    });
  }
}
