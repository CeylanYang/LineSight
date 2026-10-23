import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/store.dart';

class StartupTestStore extends AppStore {
  void step(String stage, {bool complete = false}) {
    startupStage = stage;
    ready = complete;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'startup stages fit narrow, landscape and tablet with live announcements',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final dark in [false, true]) {
        for (final size in [
          const Size(320, 740),
          const Size(844, 390),
          const Size(1100, 800),
        ]) {
          tester.view.physicalSize = size;
          final store = StartupTestStore()
            ..preferences = {'dark': dark, 'reduceMotion': true};
          await tester.pumpWidget(LineSightApp(key: UniqueKey(), store: store));
          await tester.pumpAndSettle();
          expect(find.text('LineSight'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
          for (final stage in [
            '读取本机账户',
            '读取检测记录与本机设置',
            '检查工作区与还原点',
            '保存旧版时间原件',
          ]) {
            store.step(stage);
            await tester.pumpAndSettle();
            expect(find.text(stage), findsOneWidget);
            final semantic = tester.widget<Semantics>(
              find
                  .ancestor(
                    of: find.text(stage),
                    matching: find.byType(Semantics),
                  )
                  .first,
            );
            expect(semantic.properties.liveRegion, isTrue);
            expect(
              tester.takeException(),
              isNull,
              reason: '$dark $size $stage',
            );
          }
          store.step('完成', complete: true);
          await tester.pumpAndSettle();
          expect(find.text('准备好，看见细节。'), findsOneWidget);
          expect(find.byKey(const ValueKey('brand-reveal-canvas')), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
        }
      }
    },
  );
}
