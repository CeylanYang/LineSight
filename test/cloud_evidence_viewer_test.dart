import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_feedback.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_access_ui_test.dart' show AccessAccount;

const evidenceFolder = 'docs/product/linesight/acceptance/evidence-batch';
final viewerFixture =
    jsonDecode(File('$evidenceFolder/viewer-fixture.json').readAsStringSync())
        as Map;
final viewerPhotos = (viewerFixture['photos'] as List)
    .map((row) => Map<String, dynamic>.from(row as Map))
    .toList();
Uint8List imageFor(int index, {bool edge = false}) {
  final id = viewerPhotos[index]['id'];
  final row = (viewerFixture['files'] as List).firstWhere(
    (row) =>
        row['photo_id'] == id && row['mode'] == (edge ? 'preview' : 'original'),
  );
  return File('$evidenceFolder/${row['file']}').readAsBytesSync();
}

class ViewerAccount extends AccessAccount {
  final paths = <String>[];
  final gates = <String, Completer<List<int>>>{};
  Object? failure;
  bool corrupt = false;
  @override
  Future<List<int>> download(String path) async {
    paths.add(path);
    if (gates.containsKey(path)) return gates[path]!.future;
    if (failure != null) throw failure!;
    if (corrupt) return [1, 2, 3];
    final index = viewerPhotos.indexWhere(
      (photo) => path.contains('/evidence/${photo['id']}/'),
    );
    return imageFor(index, edge: path.endsWith('preview/'));
  }
}

void main() {
  late ViewerAccount account;
  late AppStore store;
  setUp(() {
    account = ViewerAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'glass': false};
  });
  tearDown(() {
    account.dispose();
    store.dispose();
  });
  CloudEvidencePage page({int index = 0}) => CloudEvidencePage(
    jobId: viewerFixture['job_id'] as String,
    photo: viewerPhotos[index],
    gallery: viewerPhotos,
  );
  String path(int index, {bool edge = false}) =>
      'workspaces/1/jobs/${viewerFixture['job_id']}/evidence/${viewerPhotos[index]['id']}/${edge ? 'preview' : 'original'}/';
  Future<void> show(
    WidgetTester tester, {
    String language = 'zh',
    int index = 0,
    Widget? home,
    double textScale = 1,
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
          child: CloudScope(
            account: account,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
        ),
        home: home ?? page(index: index),
      ),
    );
    await tester.pumpAndSettle();
    final pictures = find.byType(Image);
    if (pictures.evaluate().isNotEmpty) {
      final picture = tester.widget<Image>(pictures.first);
      await tester.runAsync(
        () => precacheImage(
          picture.image,
          tester.element(pictures.first),
          onError: (_, __) {},
        ),
      );
    }
    await tester.pumpAndSettle();
  }

  Finder control(String label) => find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == label,
  );
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final pictures = find.byType(Image);
    if (pictures.evaluate().isNotEmpty) {
      final picture = tester.widget<Image>(pictures.first);
      await tester.runAsync(
        () => precacheImage(
          picture.image,
          tester.element(pictures.first),
          onError: (_, __) {},
        ),
      );
    }
    await tester.pumpAndSettle();
  }

  TransformationController zoom(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!;
  Uint8List shown(WidgetTester tester) =>
      (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes;

  testWidgets(
    'opens selected photo with translated stage and bounded gallery navigation',
    (tester) async {
      await show(tester, index: 1, language: 'en');
      expect(account.paths, [path(1)]);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.textContaining('After photos'), findsOneWidget);
      expect(find.textContaining('after ·'), findsNothing);
      expect(
        tester.widget<IconButton>(control('Next photo')).onPressed,
        isNull,
      );
      await tap(tester, control('Previous photo'));
      expect(account.paths.last, path(0));
      expect(
        tester.widget<IconButton>(control('Previous photo')).onPressed,
        isNull,
      );
    },
  );
  testWidgets('changing mode or photo resets zoom and keeps chosen mode', (
    tester,
  ) async {
    await show(tester);
    zoom(tester).value = Matrix4.diagonal3Values(3, 3, 1);
    await tap(tester, find.text('边缘参考'));
    expect(zoom(tester).value.getMaxScaleOnAxis(), 1);
    expect(shown(tester), orderedEquals(imageFor(0, edge: true)));
    zoom(tester).value = Matrix4.diagonal3Values(4, 4, 1);
    await tap(tester, control('下一张'));
    expect(account.paths.last, path(1, edge: true));
    expect(zoom(tester).value.getMaxScaleOnAxis(), 1);
  });
  testWidgets('double tap zooms and reset button restores full frame', (
    tester,
  ) async {
    await show(tester);
    final frame = find.byType(InteractiveViewer);
    await tester.ensureVisible(frame);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(frame));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(tester.getCenter(frame));
    await tester.pumpAndSettle();
    expect(zoom(tester).value.getMaxScaleOnAxis(), 2.5);
    await tap(tester, control('重置缩放'));
    expect(zoom(tester).value, Matrix4.identity());
  });
  testWidgets('slow contour response cannot replace newer original selection', (
    tester,
  ) async {
    await show(tester);
    final gate = account.gates[path(0, edge: true)] = Completer<List<int>>();
    await tap(tester, find.text('边缘参考'));
    expect(find.byType(Image), findsNothing);
    await tap(tester, find.text('原图'));
    expect(shown(tester), orderedEquals(imageFor(0)));
    gate.complete(imageFor(0, edge: true));
    await tester.pumpAndSettle();
    expect(shown(tester), orderedEquals(imageFor(0)));
  });
  testWidgets('slow first photo cannot replace selected second photo', (
    tester,
  ) async {
    final gate = account.gates[path(0)] = Completer<List<int>>();
    await show(tester);
    await tap(tester, control('下一张'));
    expect(shown(tester), orderedEquals(imageFor(1)));
    gate.complete(imageFor(0));
    await tester.pumpAndSettle();
    expect(shown(tester), orderedEquals(imageFor(1)));
  });
  testWidgets('failed contour load retries the current image without writes', (
    tester,
  ) async {
    await show(tester);
    account.failure = const CollaborationApiException(
      503,
      'secret-server-error',
    );
    await tap(tester, find.text('边缘参考'));
    expect(find.byType(CloudFailurePanel), findsOneWidget);
    expect(find.textContaining('secret-server-error'), findsNothing);
    expect(find.byType(Image), findsNothing);
    account.failure = null;
    await tap(tester, find.text('重试'));
    expect(account.paths.last, path(0, edge: true));
    expect(shown(tester), orderedEquals(imageFor(0, edge: true)));
    expect(account.writes, 0);
  });
  testWidgets(
    'invalid image bytes show reload action instead of a broken image',
    (tester) async {
      account.corrupt = true;
      await show(tester);
      expect(find.text('图片无法显示，请重新加载'), findsOneWidget);
      expect(tester.takeException(), isNull);
      account.corrupt = false;
      await tap(tester, find.text('重新加载'));
      expect(shown(tester), orderedEquals(imageFor(0)));
      expect(find.text('图片无法显示，请重新加载'), findsNothing);
    },
  );
  testWidgets(
    'switching teams clears current image and rejects a late download',
    (tester) async {
      await show(tester);
      final gate = account.gates[path(1)] = Completer<List<int>>();
      await tap(tester, control('下一张'));
      account.activeWorkspace = {'id': 2, 'role': 'owner'};
      account.notifyListeners();
      await tester.pumpAndSettle();
      gate.complete(imageFor(1));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.byType(InteractiveViewer), findsNothing);
    },
  );
  testWidgets('back from viewer preserves the parent comparison selection', (
    tester,
  ) async {
    await show(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openPage(context, page(index: 1)),
            child: const Text('Selected after photo'),
          ),
        ),
      ),
    );
    await tap(tester, find.text('Selected after photo'));
    await tap(tester, control('上一张'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Selected after photo'), findsOneWidget);
    expect(find.byType(CloudEvidencePage), findsNothing);
  });
  for (final language in ['zh', 'en']) {
    for (final state in ['original', 'contour', 'zoomed', 'failure']) {
      testWidgets('$language evidence $state PNG', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 1100));
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
        if (state == 'failure') {
          account.failure = const CollaborationApiException(503, 'private');
        }
        await show(tester, language: language);
        if (state == 'contour') {
          await tap(
            tester,
            find.text(language == 'zh' ? '边缘参考' : 'Edge reference'),
          );
        }
        if (state == 'zoomed') {
          final center = tester.getCenter(find.byType(InteractiveViewer));
          await tester.tapAt(center);
          await tester.pump(const Duration(milliseconds: 60));
          await tester.tapAt(center);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            '../$evidenceFolder/png/160-evidence-$state-$language-desktop-render.png',
          ),
        );
      });
    }
    testWidgets(
      '$language viewer handles small large-text and tablet layouts',
      (tester) async {
        for (final size in [const Size(320, 640), const Size(900, 1100)]) {
          await tester.binding.setSurfaceSize(size);
          await show(tester, language: language, textScale: 1.6);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
        addTearDown(() => tester.binding.setSurfaceSize(null));
      },
    );
  }
}
