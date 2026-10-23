import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../cloud_account.dart';
import '../cloud_feedback.dart';
import '../l10n.dart';
import '../ui.dart';
import 'cloud_tasks.dart'
    show cloudTimestamp, cloudAccessRequired, cloudScopeChanged;

class CloudEvidencePage extends StatefulWidget {
  final String jobId;
  final Map<String, dynamic> photo;
  final List<Map<String, dynamic>> gallery;
  const CloudEvidencePage({
    super.key,
    required this.jobId,
    required this.photo,
    this.gallery = const [],
  });
  @override
  State<CloudEvidencePage> createState() => _CloudEvidencePageState();
}

class _CloudEvidencePageState extends State<CloudEvidencePage> {
  Uint8List? bytes;
  bool edge = false, loading = false, bound = false;
  Object? error;
  String? binding;
  int generation = 0, selected = 0;
  late final List<Map<String, dynamic>> photos;
  final zoom = TransformationController();
  Offset doubleTapPosition = Offset.zero;
  Map<String, dynamic> get photo => photos[selected];
  @override
  void initState() {
    super.initState();
    final rows = widget.gallery.isEmpty ? [widget.photo] : widget.gallery;
    final index = rows.indexWhere((row) => row['id'] == widget.photo['id']);
    selected = index < 0 ? 0 : index;
    photos = List.unmodifiable(
      (index < 0 ? [widget.photo, ...rows] : rows).map(
        (row) => Map<String, dynamic>.unmodifiable(row),
      ),
    );
  }

  @override
  void dispose() {
    generation++;
    bytes = null;
    zoom.dispose();
    super.dispose();
  }

  void resetZoom() => zoom.value = Matrix4.identity();
  void toggleZoom() {
    if (zoom.value.getMaxScaleOnAxis() > 1.01) {
      resetZoom();
    } else {
      zoom.value = Matrix4.identity()
        ..setEntry(0, 0, 2.5)
        ..setEntry(1, 1, 2.5)
        ..setEntry(0, 3, -doubleTapPosition.dx * 1.5)
        ..setEntry(1, 3, -doubleTapPosition.dy * 1.5);
    }
  }

  void selectPhoto(int index) {
    if (index < 0 || index >= photos.length || index == selected) return;
    setState(() => selected = index);
    load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = CloudScope.of(context);
    if (!bound) {
      binding = account.accessScope;
      bound = true;
    }
    if (!account.retainsAccess(binding)) {
      bytes = null;
      error = null;
      loading = false;
      generation++;
      resetZoom();
      return;
    }
    if (bytes == null && !loading && error == null) load();
  }

  Future<void> load() async {
    final account = CloudScope.of(context);
    if (!account.retainsAccess(binding)) return;
    final ticket = ++generation, id = photo['id'];
    final mode = edge;
    resetZoom();
    setState(() {
      loading = true;
      bytes = null;
      error = null;
    });
    try {
      final result = await account.download(
        'workspaces/${account.activeWorkspace!['id']}/jobs/${widget.jobId}/evidence/$id/${mode ? 'preview' : 'original'}/',
      );
      if (mounted && ticket == generation && account.retainsAccess(binding)) {
        setState(() => bytes = Uint8List.fromList(result));
      }
    } catch (failure) {
      if (mounted && ticket == generation && account.retainsAccess(binding)) {
        setState(() => error = failure);
      }
    } finally {
      if (mounted && ticket == generation && account.retainsAccess(binding)) {
        setState(() => loading = false);
      }
    }
  }

  String stage(BuildContext context) => tr(context, switch (photo['stage']) {
    'before' => '处置前照片',
    'after' => '处置后照片',
    'printing' => '打印阶段',
    'inspection' => '检验阶段',
    'resolution' => '处理阶段',
    _ => '现场',
  });
  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    if (!account.retainsAccess(binding)) return cloudScopeChanged(context);
    const hint = TextStyle(fontSize: 11.5, height: 1.5, color: muted);
    return DetailScaffold(
      title: tr(context, '图片证据'),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.photo_outlined, size: 17),
                    label: Text(tr(context, '原图')),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.gradient_outlined, size: 17),
                    label: Text(tr(context, '边缘参考')),
                  ),
                ],
                selected: {edge},
                onSelectionChanged: (value) {
                  if (value.first == edge) return;
                  setState(() => edge = value.first);
                  load();
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.pinch_outlined, size: 15, color: muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(tr(context, '双指缩放，双击放大或复位'), style: hint),
                  ),
                  IconButton(
                    tooltip: tr(context, '重置缩放'),
                    onPressed: bytes == null ? null : resetZoom,
                    icon: const Icon(Icons.fit_screen_outlined),
                  ),
                ],
              ),
              Row(
                children: [
                  if (photos.length > 1)
                    IconButton(
                      tooltip: tr(context, '上一张'),
                      onPressed: selected == 0
                          ? null
                          : () => selectPhoto(selected - 1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                  Expanded(
                    child: Text(
                      '${tr(context, '证据')} #${photo['id']}${photos.length > 1 ? ' · ${selected + 1} / ${photos.length}' : ''}',
                      textAlign: TextAlign.center,
                      style: hint,
                    ),
                  ),
                  if (photos.length > 1)
                    IconButton(
                      tooltip: tr(context, '下一张'),
                      onPressed: selected == photos.length - 1
                          ? null
                          : () => selectPhoto(selected + 1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (loading) const CloudLoadingPanel(),
        if (error != null) CloudFailurePanel(failure: error!, onRetry: load),
        if (bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              height: MediaQuery.sizeOf(context).height * .62,
              color: const Color(0xFF0B1422),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTapDown: (details) =>
                    doubleTapPosition = details.localPosition,
                onDoubleTap: toggleZoom,
                child: InteractiveViewer(
                  transformationController: zoom,
                  minScale: 1,
                  maxScale: 8,
                  child: Center(
                    child: Image.memory(
                      bytes!,
                      fit: BoxFit.contain,
                      gaplessPlayback: false,
                      errorBuilder: (context, _, __) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tr(context, '图片无法显示，请重新加载'),
                            style: const TextStyle(color: Colors.white),
                          ),
                          TextButton(
                            onPressed: load,
                            child: Text(tr(context, '重新加载')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (bytes != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${stage(context)} · ${cloudTimestamp(photo['created_at'])}',
              textAlign: TextAlign.center,
              style: hint,
            ),
          ),
      ],
    );
  }
}
