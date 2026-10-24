import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:linesight_flutter/editions/edition_host.dart';
import 'package:linesight_flutter/editions/special/special_shell.dart';
import 'package:linesight_flutter/screens/quality_document_library.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

void main() {
  testWidgets(
    'edition defaults off, toggles without local login and retains shared page state',
    (tester) async {
      final store = AppStore();
      addTearDown(store.dispose);
      expect(store.specialEdition, false);
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => AppScope(
            store: store,
            child: const MaterialApp(
              home: Scaffold(
                body: EditionHost(
                  child: Column(
                    children: [
                      EditionSwitch(),
                      TextField(
                        controller: null,
                        key: ValueKey('shared-input'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'keep this draft');
      await tester.tap(find.byKey(const ValueKey('special-edition-switch')));
      await tester.pumpAndSettle();
      expect(store.specialEdition, true);
      expect(find.byType(SpecialEditionHeader), findsOneWidget);
      expect(find.text('keep this draft'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('special-edition-switch')));
      await tester.pumpAndSettle();
      expect(store.specialEdition, false);
      expect(find.byType(SpecialEditionHeader), findsNothing);
      expect(find.text('keep this draft'), findsOneWidget);
    },
  );
  testWidgets(
    'procedure links open checks and preserve entered values while inspecting',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppScope(
            store: AppStore()
              ..preferences = {'reduceMotion': true, 'haptics': false},
            child: child!,
          ),
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(
            body: SingleChildScrollView(child: QualityDocumentLinks()),
          ),
        ),
      );
      expect(find.textContaining('WI-QC-014'), findsOneWidget);
      expect(find.textContaining('CL-PR-006'), findsOneWidget);
      await tester.tap(find.text('铝合金壳体外观检验作业指导书'));
      await tester.pumpAndSettle();
      expect(find.text('导出 PDF'), findsOneWidget);
      expect(find.text('原版文件'), findsOneWidget);
      final orderController = tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!;
      await tester.enterText(find.byType(TextField).first, 'WO-1001');
      final chip = find.byKey(const ValueKey('procedure-VIS-01-pass'));
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(chip).selected, true);
      await tester.scrollUntilVisible(
        find.text('重置检查'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('重置检查'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<ChoiceChip>(chip).selected, false);
      expect(orderController.text, 'WO-1001');
    },
  );
}
