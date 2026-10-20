import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/csv_export.dart';
import 'package:linesight_flutter/screens/records.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

class ObservedInspection extends Inspection {
  int noteReads = 0;
  ObservedInspection(
    String id, {
    super.stationId = 's1',
    super.archived = false,
  }) : super(
         id: id,
         serial: 'MATCH',
         recipeName: '测试配方',
         at: DateTime.utc(2026, 10, 14, 12),
         passed: true,
         defect: '',
         confidence: .98,
         operatorName: '操作者',
         note: '跨字段检索',
       );
  @override
  String get note {
    noteReads++;
    return super.note;
  }
}

void main() {
  testWidgets('selection, pagination and theme updates reuse search results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rows = List.generate(
      65,
      (i) => ObservedInspection('row$i')
        ..at = DateTime.utc(2026, 10, 14, 12, i)
        ..note = '${'质' * 1990}唯一关键词',
    );
    final store = AppStore()
      ..ready = true
      ..data = (Workspace.seed(examples: false)..inspections = rows)
      ..user = const LocalUser('actor', 'admin', '管理员', 'admin', true);
    await tester.pumpWidget(
      AppScope(
        store: store,
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) => MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: appTheme(store.preferences['dark'] == true),
            home: const RecordsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(rows.map((r) => r.noteReads), everyElement(0));
    await tester.enterText(find.byType(TextField).first, '唯一关键词');
    await tester.pumpAndSettle();
    final reads = rows.map((r) => r.noteReads).toList();
    expect(reads, everyElement(1));
    int renderedLimit() => tester
        .widget<PageBody>(find.byType(PageBody))
        .children
        .whereType<Padding>()
        .where((padding) => padding.child is RecordTile)
        .length;
    expect(renderedLimit(), 30);

    Future<void> tap(Finder target, {double delta = 300}) async {
      await tester.scrollUntilVisible(
        target,
        delta,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await tap(find.text('选择'));
    await tap(find.text('全选筛选结果'));
    expect(find.text('已选 65 条'), findsOneWidget);
    await tap(find.byType(Checkbox).first);
    await tester.scrollUntilVisible(
      find.text('全选筛选结果'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('已选 64 条'), findsOneWidget);
    await tap(find.text('加载更多（剩余 35 条）'));
    expect(renderedLimit(), 60);
    store.preferences['dark'] = true;
    store.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(RecordsPage))).brightness,
      Brightness.dark,
    );
    expect(rows.map((r) => r.noteReads), orderedEquals(reads));

    await tap(find.byTooltip('导出筛选结果 CSV'), delta: -500);
    final page = tester.widget<CsvExportPage>(find.byType(CsvExportPage));
    expect(
      page.snapshot.records.map((r) => r.id),
      orderedEquals(rows.reversed.map((r) => r.id)),
    );
    expect(page.snapshot.records, hasLength(65));
    expect(page.filterSummary, contains('关键词：唯一关键词'));
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('workspace replacement updates search, selection and CSV scope', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore()
      ..ready = true
      ..data = (Workspace.seed(
        examples: false,
      )..inspections = [ObservedInspection('row0'), ObservedInspection('row1')])
      ..user = const LocalUser('actor', 'admin', '管理员', 'admin', true);
    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: appTheme(false),
          home: const RecordsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '跨字段检索');
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选筛选结果'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 条'), findsOneWidget);

    // Mirror committed replacement while this page remains mounted.
    store.data = Workspace.fromJson(store.data.toJson());
    store.data.inspections.first.archived = true;
    store.revision++;
    store.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('1 条检测记录'), findsOneWidget);
    expect(find.text('已选 1 条'), findsOneWidget);
    store.data = Workspace.fromJson(store.data.toJson());
    store.data.inspections.last.note = '已修改';
    store.revision++;
    store.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('0 条检测记录'), findsOneWidget);
    expect(find.text('已选 0 条'), findsOneWidget);

    // Initialization/restore can replace a workspace without changing revision.
    store.data = Workspace.seed(examples: false)
      ..inspections = [ObservedInspection('restored')];
    store.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('1 条检测记录'), findsOneWidget);
    expect(find.text('已选 0 条'), findsOneWidget);
    await tester.tap(find.byTooltip('导出筛选结果 CSV'));
    await tester.pumpAndSettle();
    final page = tester.widget<CsvExportPage>(find.byType(CsvExportPage));
    expect(page.snapshot.records.single.id, 'restored');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('empty searches and excluded records do not scan long notes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final visible = ObservedInspection('row0');
    final archived = ObservedInspection('row1', archived: true);
    final otherStation = ObservedInspection('row2', stationId: 's2');
    final store = AppStore()
      ..ready = true
      ..data = (Workspace.seed(examples: false)
        ..inspections = [visible, archived, otherStation])
      ..user = const LocalUser('actor', 'admin', '管理员', 'admin', true);
    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: appTheme(false),
          home: const RecordsScreen(stationId: 's1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 条检测记录'), findsOneWidget);
    expect(
      [visible.noteReads, archived.noteReads, otherStation.noteReads],
      [0, 0, 0],
    );
    for (final query in ['MaTcH row0', '跨字段检索']) {
      await tester.enterText(find.byType(TextField).first, query);
      await tester.pumpAndSettle();
      expect(find.text('1 条检测记录'), findsOneWidget);
      expect(visible.noteReads, greaterThan(0));
      expect(archived.noteReads, 0);
      expect(otherStation.noteReads, 0);
    }
    final previous = visible.noteReads;
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    expect(visible.noteReads, previous);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
