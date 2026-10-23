import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_trace.dart';
import 'package:linesight_flutter/cloud_vision.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_access_ui_test.dart' show AccessAccount;

class VisionAccount extends AccessAccount {
  Object? failure;
  final queries = <String>[];
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    queries.add(path);
    if (failure != null) throw failure!;
    return {
      'jobs': [
        {
          'id': '5327299a-6201-4fdf-abba-f2037fc89712',
          'part_name': 'DEMO · SN inspection history',
          'batch_code': 'DEMO-HISTORY-a86a7fcd5b',
          'quantity': 2,
          'status': 'closed',
          'matched_serial': 'DEMO-HISTORY-a86a7fcd5b-01',
          'piece_verdict': 'pass',
        },
      ],
      'truncated': false,
    };
  }
}

void main() {
  final folder = Directory('docs/product/linesight/acceptance/vision-batch');
  test(
    'batch and piece payloads round trip and reject remote URLs and controls',
    () {
      for (final code in ['BATCH-07', 'SN-001', '批次 A/1']) {
        final trace = BatchTrace(5, code);
        expect(BatchTrace.parse(trace.link)!.code, code);
        expect(BatchTrace.parse(code, workspaceId: 5)!.code, code);
      }
      for (final invalid in [
        'https://evil.example/SN-1',
        'linesight://batch/0/B1',
        'linesight://batch/5/B1?token=x',
        'linesight://task/5/not-uuid',
        'SN\x00X',
      ]) {
        expect(BatchTrace.parse(invalid, workspaceId: 5), isNull);
      }
    },
  );
  test('frame result decodes production PNG bytes', () {
    final bytes = File(
      '${folder.path}/reference-contour-processed.png',
    ).readAsBytesSync();
    final result = VisionFrameResult.fromJson({
      'original_png': base64Encode(bytes),
      'edge_png': base64Encode(bytes),
      'processing_ms': 17,
    });
    expect(result.edge, bytes);
    expect(result.milliseconds, 17);
  });
  for (final language in ['zh', 'en']) {
    testWidgets(
      'vision and piece lookup $language render actual source contours and server fixture',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 1600));
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
        final account = VisionAccount();
        final store = AppStore()
          ..ready = true
          ..preferences = {'reduceMotion': true, 'glass': false};
        addTearDown(account.dispose);
        addTearDown(store.dispose);
        Future<void> show(Widget page) async {
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
          await tester.pumpAndSettle();
        }

        final result = VisionFrameResult(
          File(
            '${folder.path}/cloud-frame-original-source.png',
          ).readAsBytesSync(),
          File(
            '${folder.path}/cloud-frame-contour-processed.png',
          ).readAsBytesSync(),
          jsonDecode(
                File('${folder.path}/live-api.json').readAsStringSync(),
              )['processing_ms']
              as int,
        );
        await show(
          DetailScaffold(
            title: language == 'zh' ? '在线质检' : 'Live inspection',
            children: [CloudVisionResultView(result: result)],
          ),
        );
        await tester.runAsync(() async {
          for (final element in find.byType(Image).evaluate()) {
            await precacheImage((element.widget as Image).image, element);
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            '../${folder.path}/png/68-live-contours-$language-desktop-render.png',
          ),
        );
        await show(
          const CloudBatchTracePage(
            trace: BatchTrace(1, 'DEMO-HISTORY-a86a7fcd5b-01'),
          ),
        );
        expect(
          account.queries.single,
          contains('code=DEMO-HISTORY-a86a7fcd5b-01'),
        );
        expect(find.textContaining('DEMO-HISTORY-a86a7fcd5b-01'), findsWidgets);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            '../${folder.path}/png/69-piece-lookup-$language-desktop-render.png',
          ),
        );
      },
    );
  }
  testWidgets(
    'camera requires explicit start and drops results after scope switch',
    (tester) async {
      final account = VisionAccount();
      final store = AppStore()..ready = true;
      addTearDown(account.dispose);
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppScope(
            store: store,
            child: CloudScope(account: account, child: child!),
          ),
          home: const CloudLiveInspectionPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(account.queries, isEmpty);
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
      account.activeWorkspace = {...account.activeWorkspace!, 'id': 2};
      account.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.videocam_outlined), findsNothing);
    },
  );
  testWidgets('lookup error is recoverable and does not claim empty state', (
    tester,
  ) async {
    final account = VisionAccount()
      ..failure = const CollaborationApiException(503, 'private server data');
    final store = AppStore()..ready = true;
    addTearDown(account.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(account: account, child: child!),
        ),
        home: const CloudBatchTracePage(trace: BatchTrace(1, 'B1')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('private server'), findsNothing);
    expect(find.text('没有匹配的工件或批次'), findsNothing);
    account.failure = null;
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    expect(account.queries.length, 2);
    expect(account.queries.first, account.queries.last);
  });
}
