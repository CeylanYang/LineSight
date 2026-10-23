import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../cloud_account.dart';
import '../cloud_feedback.dart';
import '../l10n.dart';
import '../ui.dart';
import 'cloud_business.dart';
import 'cloud_tasks.dart';

class CloudEvidenceComparePage extends StatefulWidget {
  final String jobId;
  final int issueId;
  final List<Map<String, dynamic>> photos;
  const CloudEvidenceComparePage({
    super.key,
    required this.jobId,
    required this.issueId,
    required this.photos,
  });
  @override
  State<CloudEvidenceComparePage> createState() =>
      _CloudEvidenceComparePageState();
}

class _CloudEvidenceComparePageState extends State<CloudEvidenceComparePage> {
  String? binding;
  bool initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      binding = CloudScope.of(context).accessScope;
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    if (!account.retainsAccess(binding)) return cloudScopeChanged(context);
    final sides = ['before', 'after']
        .map(
          (stage) => _ComparisonSide(
            key: ValueKey('$binding/$stage'),
            binding: binding!,
            jobId: widget.jobId,
            stage: stage,
            photos: widget.photos
                .where(
                  (row) =>
                      row['issue_id'] == widget.issueId &&
                      row['stage'] == stage,
                )
                .toList(),
          ),
        )
        .toList();
    return DetailScaffold(
      title: tr(context, '整改前后对比'),
      children: [
        Text(
          '${tr(context, '异常记录')} #${widget.issueId}',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 660
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: sides[0]),
                    const SizedBox(width: 16),
                    Expanded(child: sides[1]),
                  ],
                )
              : Column(
                  children: [sides[0], const SizedBox(height: 16), sides[1]],
                ),
        ),
      ],
    );
  }
}

class _ComparisonSide extends StatefulWidget {
  final String binding, jobId, stage;
  final List<Map<String, dynamic>> photos;
  const _ComparisonSide({
    super.key,
    required this.binding,
    required this.jobId,
    required this.stage,
    required this.photos,
  });
  @override
  State<_ComparisonSide> createState() => _ComparisonSideState();
}

class _ComparisonSideState extends State<_ComparisonSide> {
  int selected = 0, generation = 0;
  bool started = false, loading = false;
  Uint8List? bytes;
  Object? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!CloudScope.of(context).retainsAccess(widget.binding)) {
      generation++;
      bytes = null;
      return;
    }
    if (!started && widget.photos.isNotEmpty) {
      started = true;
      load();
    }
  }

  Future<void> load() async {
    final account = CloudScope.of(context);
    if (!account.retainsAccess(widget.binding)) return;
    final ticket = ++generation;
    final id = widget.photos[selected]['id'];
    setState(() {
      loading = true;
      bytes = null;
      error = null;
    });
    try {
      final result = await account.download(
        'workspaces/${account.activeWorkspace!['id']}/jobs/${widget.jobId}/evidence/$id/original/',
      );
      if (mounted &&
          ticket == generation &&
          account.retainsAccess(widget.binding)) {
        setState(() => bytes = Uint8List.fromList(result));
      }
    } catch (failure) {
      if (mounted &&
          ticket == generation &&
          account.retainsAccess(widget.binding)) {
        setState(() => error = failure);
      }
    } finally {
      if (mounted &&
          ticket == generation &&
          account.retainsAccess(widget.binding)) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!CloudScope.of(context).retainsAccess(widget.binding)) {
      return const SizedBox.shrink();
    }
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(context, widget.stage == 'before' ? '处置前照片' : '处置后照片'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (widget.photos.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr(context, '尚未上传照片'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted),
              ),
            ),
          if (widget.photos.length > 1)
            DropdownButton<int>(
              isExpanded: true,
              value: selected,
              items: [
                for (var i = 0; i < widget.photos.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      '${tr(context, '证据')} #${widget.photos[i]['id']}',
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => selected = value);
                  load();
                }
              },
            ),
          if (loading) const CloudLoadingPanel(),
          if (error != null) CloudFailurePanel(failure: error!, onRetry: load),
          if (bytes != null)
            Semantics(
              button: true,
              label: tr(context, '查看原图与边缘参考'),
              child: InkWell(
                onTap: () => openPage(
                  context,
                  CloudEvidencePage(
                    jobId: widget.jobId,
                    photo: widget.photos[selected],
                    gallery: widget.photos,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: const Color(0xFF0B1422),
                    height: 245,
                    alignment: Alignment.center,
                    child: Image.memory(
                      bytes!,
                      fit: BoxFit.contain,
                      gaplessPlayback: false,
                    ),
                  ),
                ),
              ),
            ),
          if (widget.photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${tr(context, '证据')} #${widget.photos[selected]['id']} · ${cloudTimestamp(widget.photos[selected]['created_at'])}',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
            ),
        ],
      ),
    );
  }
}
