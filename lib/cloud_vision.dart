import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'cloud_account.dart';
import 'cloud_feedback.dart';
import 'l10n.dart';
import 'ui.dart';
import 'screens/cloud_tasks.dart';

class VisionFrameResult {
  final Uint8List original, edge;
  final int milliseconds;
  const VisionFrameResult(this.original, this.edge, this.milliseconds);
  factory VisionFrameResult.fromJson(Map value) => VisionFrameResult(
    base64Decode(value['original_png'] as String),
    base64Decode(value['edge_png'] as String),
    value['processing_ms'] as int,
  );
}

Map<String, dynamic> cameraFramePayload(
  CameraImage image,
  CameraDescription description,
  DeviceOrientation orientation,
) {
  final degrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  }[orientation]!;
  final front = description.lensDirection == CameraLensDirection.front;
  return {
    'width': image.width,
    'height': image.height,
    'format': image.format.group.name,
    'rotation':
        (description.sensorOrientation + (front ? degrees : -degrees) + 360) %
        360,
    'mirror': front,
    'planes': [
      for (final plane in image.planes)
        {
          'bytes': base64Encode(plane.bytes),
          'row_stride': plane.bytesPerRow,
          'pixel_stride': plane.bytesPerPixel ?? 1,
        },
    ],
  };
}

class CloudVisionResultView extends StatelessWidget {
  final VisionFrameResult result;
  const CloudVisionResultView({super.key, required this.result});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(tr(context, '当前画面'), icon: Icons.camera_alt_outlined),
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.memory(
          result.original,
          height: 260,
          width: double.infinity,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
      SectionHeader(
        tr(context, '实时轮廓'),
        icon: Icons.polyline_outlined,
        caption: '${result.milliseconds} ms',
      ),
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.memory(
          result.edge,
          height: 260,
          width: double.infinity,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
    ],
  );
}

class CloudLiveInspectionPage extends StatefulWidget {
  final bool returnCapture;
  const CloudLiveInspectionPage({super.key, this.returnCapture = false});
  @override
  State<CloudLiveInspectionPage> createState() =>
      _CloudLiveInspectionPageState();
}

class _CloudLiveInspectionPageState extends State<CloudLiveInspectionPage>
    with WidgetsBindingObserver {
  CameraController? camera;
  VisionFrameResult? result;
  String? binding, cameraError;
  Object? error;
  bool bound = false, starting = false, sending = false, paused = false;
  int generation = 0;
  DateTime lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      result = null;
      generation++;
      release();
    }
  }

  void release() {
    final old = camera;
    camera = null;
    old?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The Android permission dialog temporarily makes the app inactive while
    // initialize() is still waiting. Keep that request alive until it returns.
    if (state == AppLifecycleState.inactive && starting && camera == null) {
      return;
    }
    if (state != AppLifecycleState.resumed) {
      generation++;
      release();
      if (mounted) {
        setState(() {
          starting = false;
          paused = true;
          result = null;
        });
      }
    }
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    release();
    super.dispose();
  }

  Future<void> start() async {
    final account = CloudScope.of(context);
    if (starting || !account.retainsAccess(binding)) return;
    final ticket = ++generation;
    release();
    setState(() {
      starting = true;
      cameraError = null;
      error = null;
      paused = false;
      result = null;
    });
    CameraController? next;
    try {
      final devices = await availableCameras();
      if (devices.isEmpty) throw CameraException('no_camera', '');
      final description = devices.firstWhere(
        (d) => d.lensDirection == CameraLensDirection.back,
        orElse: () => devices.first,
      );
      next = CameraController(
        description,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await next.initialize();
      if (!mounted || ticket != generation || !account.retainsAccess(binding)) {
        await next.dispose();
        return;
      }
      camera = next;
      await next.startImageStream((image) => process(image, ticket));
      if (mounted) setState(() {});
    } catch (_) {
      if (camera == next) camera = null;
      await next?.dispose();
      if (mounted && ticket == generation) {
        setState(() => cameraError = '相机不可用，请检查相机权限后重试');
      }
    } finally {
      if (mounted && ticket == generation) setState(() => starting = false);
    }
  }

  Future<void> process(CameraImage image, int ticket) async {
    final active = camera;
    if (!mounted ||
        active == null ||
        ticket != generation ||
        sending ||
        paused ||
        DateTime.now().difference(lastSent).inMilliseconds < 900) {
      return;
    }
    final account = CloudScope.of(context);
    if (!account.retainsAccess(binding)) return;
    sending = true;
    lastSent = DateTime.now();
    try {
      final response =
          await account.request(
                'POST',
                'workspaces/${account.activeWorkspace!['id']}/vision/frame/',
                body: cameraFramePayload(
                  image,
                  active.description,
                  active.value.deviceOrientation,
                ),
              )
              as Map;
      final frame = VisionFrameResult.fromJson(response);
      if (mounted && ticket == generation && account.retainsAccess(binding)) {
        setState(() {
          result = frame;
          error = null;
        });
      }
    } catch (failure) {
      if (mounted && ticket == generation && account.retainsAccess(binding)) {
        setState(() {
          error = failure;
          paused = true;
        });
      }
    } finally {
      sending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    if (!account.retainsAccess(binding)) return cloudScopeChanged(context);
    final current = camera;
    return DetailScaffold(
      title: tr(context, '在线质检'),
      children: [
        if (current != null && current.value.isInitialized) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: current.value.aspectRatio,
              child: CameraPreview(current),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => setState(() => paused = !paused),
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            label: Text(tr(context, paused ? '继续提取轮廓' : '暂停提取轮廓')),
          ),
        ] else
          EmptyState(
            icon: Icons.camera_alt_outlined,
            title: tr(context, '开启手机摄像头'),
            subtitle: tr(context, cameraError ?? '将工件放入画面，查看实时轮廓。'),
            action: FilledButton.icon(
              onPressed: starting ? null : start,
              icon: const Icon(Icons.videocam_outlined),
              label: Text(tr(context, '开启相机')),
            ),
          ),
        if (starting) const CloudLoadingPanel(),
        if (error != null)
          CloudFailurePanel(
            failure: error!,
            onRetry: () async {
              if (camera == null) {
                await start();
              } else {
                setState(() {
                  error = null;
                  paused = false;
                });
              }
            },
          ),
        if (result != null) CloudVisionResultView(result: result!),
        if (widget.returnCapture && result != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(result!.original),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(tr(context, '使用当前画面')),
          ),
        ],
      ],
    );
  }
}
