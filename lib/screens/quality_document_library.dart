import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../l10n.dart';
import '../runtime_content.dart';
import '../quality_documents.dart';
import '../ui.dart';

Future<bool> deliverQualityPdf(
  Uint8List bytes,
  String filename, {
  bool print = false,
}) async {
  if (print) {
    return Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
  } else {
    final path = await FilePicker.platform.saveFile(
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      bytes: bytes,
    );
    return path != null;
  }
}

String qualityDeliveryMessage(bool completed, {bool print = false}) =>
    completed ? (print ? '已提交打印' : '文件已保存') : (print ? '已取消打印' : '已取消保存');

class QualityDocumentLinks extends StatelessWidget {
  final bool compact;
  const QualityDocumentLinks({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: RuntimeContent.instance,
    builder: (context, _) =>
        !RuntimeContent.instance.feature('document_library')
        ? const SizedBox.shrink()
        : compact
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final definition in RuntimeContent.instance.documents)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.description_outlined, size: 17),
                    label: Text(
                      tr(
                        context,
                        definition['id'] == 'appearance' ? '外观检验指导' : '换型检查表',
                      ),
                    ),
                    onPressed: () => openPage(
                      context,
                      QualityDocumentPage(definition: definition),
                    ),
                  ),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                tr(context, '作业文件'),
                icon: Icons.description_outlined,
              ),
              for (final definition in RuntimeContent.instance.documents)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.assignment_outlined, color: blue),
                    title: Text(tr(context, definition['title'] as String)),
                    subtitle: Text(
                      '${definition['code']} · Rev.${definition['version']}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openPage(
                      context,
                      QualityDocumentPage(definition: definition),
                    ),
                  ),
                ),
            ],
          ),
  );
}

class QualityDocumentPage extends StatefulWidget {
  final Map<String, dynamic> definition;
  const QualityDocumentPage({super.key, required this.definition});
  @override
  State<QualityDocumentPage> createState() => _QualityDocumentPageState();
}

class _QualityDocumentPageState extends State<QualityDocumentPage> {
  late Future<Uint8List> original;
  final results = <String, String>{};
  final order = TextEditingController(),
      batch = TextEditingController(),
      inspector = TextEditingController();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    original = RuntimeContent.instance.image(
      widget.definition,
      fallback: 'assets/templates/${widget.definition['asset']}',
    );
  }

  @override
  void dispose() {
    order.dispose();
    batch.dispose();
    inspector.dispose();
    super.dispose();
  }

  Future<void> export({bool print = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final bytes = await buildProcedureDocument(
        widget.definition,
        results: Map.of(results),
        record: {
          'order': order.text.trim(),
          'batch': batch.text.trim(),
          'inspector': inspector.text.trim(),
        },
      );
      if (!mounted) return;
      final completed = await deliverQualityPdf(
        bytes,
        'LineSight-${widget.definition['code']}.pdf',
        print: print,
      );
      if (mounted) {
        toast(context, qualityDeliveryMessage(completed, print: print));
      }
    } catch (_) {
      if (mounted) toast(context, print ? '打印失败，请重试' : '导出失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget imageFailure() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Text(tr(context, '图片无法显示，请重新加载')),
        TextButton.icon(
          key: const ValueKey('procedure-original-retry'),
          onPressed: () => setState(() {
            original = RuntimeContent.instance.image(
              widget.definition,
              fallback: 'assets/templates/${widget.definition['asset']}',
            );
          }),
          icon: const Icon(Icons.refresh),
          label: Text(tr(context, '重新加载')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final definition = widget.definition;
    return DetailScaffold(
      title: tr(context, definition['title'] as String),
      children: [
        Text(
          '${definition['code']} · Rev.${definition['version']} · ${tr(context, definition['department'] as String)}',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            if (RuntimeContent.instance.feature('document_export')) ...[
              FilledButton.icon(
                onPressed: busy ? null : () => export(),
                icon: const Icon(Icons.download_outlined),
                label: Text(tr(context, '导出 PDF')),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => export(print: true),
                icon: const Icon(Icons.print_outlined),
                label: Text(tr(context, '打印')),
              ),
            ],
            TextButton(
              onPressed: () => setState(results.clear),
              child: Text(tr(context, '重置检查')),
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        const SizedBox(height: 12),
        ExpansionTile(
          maintainState: true,
          title: Text(tr(context, '原版文件')),
          children: [
            FutureBuilder<Uint8List>(
              future: original,
              builder: (context, state) => state.hasError
                  ? imageFailure()
                  : state.hasData
                  ? SizedBox(
                      height: 440,
                      child: InteractiveViewer(
                        minScale: .5,
                        maxScale: 5,
                        child: Image.memory(
                          state.data!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, error, stack) => imageFailure(),
                        ),
                      ),
                    )
                  : const SizedBox(
                      height: 80,
                      child: Center(child: CircularProgressIndicator()),
                    ),
            ),
          ],
        ),
        SectionHeader(tr(context, '检验记录'), icon: Icons.edit_note),
        TextField(
          controller: order,
          decoration: InputDecoration(labelText: tr(context, '工单号')),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: batch,
          decoration: InputDecoration(labelText: tr(context, '产品 / 批次')),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: inspector,
          decoration: InputDecoration(labelText: tr(context, '检验人')),
        ),
        if ((definition['preparation'] as List? ?? []).isNotEmpty) ...[
          SectionHeader(tr(context, '检验准备'), icon: Icons.fact_check_outlined),
          for (final row in definition['preparation'])
            ListTile(
              title: Text(tr(context, row[0])),
              subtitle: Text(tr(context, row[1])),
            ),
        ],
        for (final section in definition['sections']) ...[
          SectionHeader(tr(context, section['title']), icon: Icons.checklist),
          for (final row in section['items'])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${row[0]} · ${tr(context, row[1])}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr(context, row[2]),
                      style: const TextStyle(height: 1.6),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final entry in {
                          'pass': '合格',
                          'fail': '异常',
                          'na': '不适用',
                        }.entries)
                          ChoiceChip(
                            key: ValueKey('procedure-${row[0]}-${entry.key}'),
                            label: Text(tr(context, entry.value)),
                            selected: results[row[0]] == entry.key,
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                results[row[0]] = entry.key;
                              } else {
                                results.remove(row[0]);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
        SectionHeader(
          tr(context, '异常处置'),
          icon: Icons.assignment_late_outlined,
        ),
        Text(
          tr(context, definition['disposition']),
          style: const TextStyle(height: 1.7),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}
