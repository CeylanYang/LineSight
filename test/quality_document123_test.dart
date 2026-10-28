import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/runtime_content.dart';
import 'package:linesight_flutter/screens/quality_document_library.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:linesight_flutter/l10n_catalog.dart';

void main() {
  late ByteData bytes;
  setUpAll(() async {
    bytes = await rootBundle.load(
      'assets/templates/aluminum_housing_inspection.png',
    );
  });
  for (final language in ['zh', 'en']) {
    testWidgets(
      '$language original document failure retries without losing form',
      (t) async {
        var mode = 0;
        const asset = 'assets/templates/retry-test.png';
        t.binding.defaultBinaryMessenger.setMockMessageHandler(
          'flutter/assets',
          (message) async {
            final key = utf8.decode(
              message!.buffer.asUint8List(
                message.offsetInBytes,
                message.lengthInBytes,
              ),
            );
            if (key != asset || mode == 0) return null;
            return mode == 1
                ? ByteData.sublistView(Uint8List.fromList([1, 2, 3]))
                : bytes;
          },
        );
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMessageHandler(
            'flutter/assets',
            null,
          ),
        );
        final s = AppStore();
        addTearDown(s.dispose);
        final definition = Map<String, dynamic>.from(
          RuntimeContent.instance.documents.first,
        )..['asset'] = 'retry-test.png';
        String label(String v) =>
            language == 'en' ? englishMessages[v] ?? v : v;
        await t.pumpWidget(
          AppScope(
            store: s,
            child: MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('zh'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: QualityDocumentPage(definition: definition),
            ),
          ),
        );
        await t.pumpAndSettle();
        final controller = t
            .widget<TextField>(find.byType(TextField).first)
            .controller!;
        controller.text = 'WO-KEEP';
        await t.tap(find.text(label('原版文件')));
        await t.pumpAndSettle();
        expect(find.text(label('图片无法显示，请重新加载')), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        mode = 1;
        await t.tap(find.byKey(const ValueKey('procedure-original-retry')));
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await t.pumpAndSettle();
        expect(find.text(label('图片无法显示，请重新加载')), findsOneWidget);
        expect(controller.text, 'WO-KEEP');
        mode = 2;
        await t.tap(find.byKey(const ValueKey('procedure-original-retry')));
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await t.pumpAndSettle();
        await t.runAsync(() async {
          final picture = t.widget<Image>(find.byType(Image).first);
          await precacheImage(
            picture.image,
            t.element(find.byType(InteractiveViewer)),
          );
        });
        await t.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(
          find.byKey(const ValueKey('procedure-original-retry')),
          findsNothing,
        );
        expect(controller.text, 'WO-KEEP');
        expect(t.takeException(), isNull);
      },
    );
  }
}
