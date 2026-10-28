import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../ui.dart';
import '../../store.dart';
import '../../l10n.dart';
import 'special_catalog.dart';

class SpecialMediaBody extends StatefulWidget {
  final bool drama;
  const SpecialMediaBody({super.key, required this.drama});
  @override
  State<SpecialMediaBody> createState() => _SpecialMediaBodyState();
}

class _SpecialMediaBodyState extends State<SpecialMediaBody>
    with WidgetsBindingObserver {
  VideoPlayerController? controller;
  int episode = 0;
  String? error;
  bool busy = false, bookmarking = false;
  int generation = 0;
  AppStore? progressStore;
  String? actor;
  int loadedEpisode = 0;
  int lastSavedSecond = -1;
  bool initialized = false;
  String get progressKey => widget.drama ? 'dramaProgress' : 'videoProgress';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    initialized = true;
    progressStore = AppScope.of(context);
    actor = specialActor(context);
    final progress = specialState(context)[progressKey] as Map?;
    episode = (progress?['episode'] as int? ?? 0).clamp(0, 5);
    load();
  }

  Future<void> persistProgress() async {
    final c = controller, store = progressStore, owner = actor;
    if (c == null || !c.value.isInitialized || store == null || owner == null) {
      return;
    }
    final position = c.value.position.inMilliseconds;
    if (position ~/ 1000 == lastSavedSecond) return;
    lastSavedSecond = position ~/ 1000;
    final snapshot = {'episode': loadedEpisode, 'position': position};
    try {
      await store.updateSpecialExperience(
        owner,
        (state) => {...state, progressKey: snapshot},
      );
    } catch (_) {
      lastSavedSecond = -1;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> load() async {
    await persistProgress();
    final gen = ++generation;
    final previous = controller;
    controller = null;
    await previous?.dispose();
    final next = VideoPlayerController.asset(
      'assets/checkcheck/media/${episode.isEven ? 'bee' : 'butterfly'}.mp4',
    );
    if (!mounted || gen != generation) {
      await next.dispose();
      return;
    }
    controller = next;
    loadedEpisode = episode;
    lastSavedSecond = -1;
    next.addListener(() {
      if (next.value.isInitialized &&
          (next.value.position.inSeconds - lastSavedSecond).abs() >= 5) {
        persistProgress();
      }
      if (mounted &&
          next.value.isPlaying &&
          ModalRoute.of(context)?.isCurrent == false) {
        next.pause();
      }
    });
    try {
      await next.initialize();
      if (!mounted || gen != generation) return;
      final progress =
          progressStore?.specialExperienceFor(actor!)[progressKey] as Map?;
      if (progress?['episode'] == loadedEpisode) {
        final saved = progress?['position'] as int? ?? 0;
        final end = next.value.duration.inMilliseconds;
        if (saved > 0 && saved < end - 1000) {
          await next.seekTo(Duration(milliseconds: saved));
        }
      }

      if (mounted && gen == generation) setState(() => error = null);
    } catch (_) {
      if (mounted && gen == generation) setState(() => error = '播放准备失败，点此重试');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      persistProgress();
      controller?.pause();
    }
  }

  @override
  void deactivate() {
    persistProgress();
    controller?.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    persistProgress();
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    super.dispose();
  }

  Future<void> bookmark() async {
    if (bookmarking) return;
    final savedEpisode = episode;
    final key = widget.drama ? 'dramaEpisode' : 'videoEpisode';
    setState(() => bookmarking = true);
    try {
      await persistProgress();
      if (!mounted) return;
      await saveSpecial(context, (s) => {...s, key: savedEpisode});
      if (mounted) toast(context, '已收藏，第 ${savedEpisode + 1} 集等你回来');
    } catch (_) {
      if (mounted) toast(context, '收藏失败，请重试');
    } finally {
      if (mounted) setState(() => bookmarking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final state = specialState(context);
    final saved = state[widget.drama ? 'dramaEpisode' : 'videoEpisode'] as int?;
    final reward = '${widget.drama ? '小剧场' : '视频'}/第${episode + 1}集';
    final rewarded = AppScope.of(context).specialRewardClaimed(reward);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(context, widget.drama ? '小剧场 · 花园里的大冒险' : '随手刷 · 自然小放映'),
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
        ),
        Text(tr(context, '今日精选 · 轻松看一会儿')),
        const SizedBox(height: 12),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(18),
          ),
          child: AspectRatio(
            aspectRatio: c?.value.isInitialized == true
                ? c!.value.aspectRatio
                : 16 / 9,
            child: error != null
                ? TextButton(onPressed: load, child: Text(tr(context, error!)))
                : c?.value.isInitialized == true
                ? VideoPlayer(c!)
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
        if (c?.value.isInitialized == true) ...[
          VideoProgressIndicator(
            c!,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (context, value, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: tr(context, '上一集'),
                  onPressed: episode == 0
                      ? null
                      : () {
                          setState(() => episode--);
                          load();
                        },
                  icon: const Icon(Icons.skip_previous),
                ),
                FilledButton.icon(
                  onPressed: () {
                    value.isPlaying ? c.pause() : c.play();
                  },
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(tr(context, value.isPlaying ? '暂停' : '播放')),
                ),
                IconButton(
                  tooltip: tr(context, '下一集'),
                  onPressed: () {
                    setState(() => episode = (episode + 1) % 6);
                    load();
                  },
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ),
        ],
        Text(
          tr(context, '第 {0} 集 · {1}', [
            episode + 1,
            tr(context, episode.isEven ? '蜜蜂的忙碌早晨' : '蝴蝶的午后散步'),
          ]),
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: bookmarking ? null : bookmark,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(tr(context, '收藏本集')),
            ),
            if (saved != null)
              TextButton(
                onPressed: () {
                  setState(() => episode = saved.clamp(0, 5));
                  load();
                },
                child: Text(tr(context, '打开收藏第 {0} 集', [saved + 1])),
              ),
            FilledButton.tonal(
              onPressed: busy || rewarded
                  ? null
                  : () async {
                      final store = AppScope.of(context);
                      if (c?.value.isInitialized != true ||
                          c!.value.position.inSeconds < 3) {
                        toast(context, '先看一会儿，精彩马上来');
                        return;
                      }
                      setState(() => busy = true);
                      try {
                        await store.claimSpecialReward(reward, points: 20);
                        if (context.mounted) toast(context, '积分已到账');
                      } catch (_) {
                        if (context.mounted) toast(context, '领取失败，请重试');
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: Text(tr(context, rewarded ? '本集今日积分已领' : '领 20 积分')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          tr(context, widget.drama ? '全部剧集' : '推荐放映'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < 6; i++)
              ChoiceChip(
                label: Text(tr(context, '第 {0} 集', [i + 1])),
                selected: episode == i,
                onSelected: (_) {
                  setState(() => episode = i);
                  load();
                },
              ),
          ],
        ),
      ],
    );
  }
}

class SpecialWebPage extends StatefulWidget {
  const SpecialWebPage({super.key});
  @override
  State<SpecialWebPage> createState() => _SpecialWebPageState();
}

class _SpecialWebPageState extends State<SpecialWebPage> {
  static final uri = Uri.parse('https://99ai.pronhubcn.com/linesight/whatif');
  late final WebViewController controller;
  bool failed = false;
  int progress = 0;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => progress = p);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted) {
              setState(() => failed = true);
            }
          },
          onNavigationRequest: (r) {
            final u = Uri.tryParse(r.url);
            return u?.scheme == 'https' && u?.host == uri.host
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(uri);
  }

  Future<void> back() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop) {
        if (await controller.canGoBack()) {
          await controller.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      }
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: tr(context, '返回'),
          onPressed: back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('WhatIfIBought'),
        actions: [
          IconButton(
            tooltip: tr(context, '关闭'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Column(
        children: [
          if (progress < 100) LinearProgressIndicator(value: progress / 100),
          if (failed)
            Expanded(
              child: Center(
                child: FilledButton(
                  onPressed: () {
                    setState(() => failed = false);
                    controller.loadRequest(uri);
                  },
                  child: Text(tr(context, '连接失败，重新加载')),
                ),
              ),
            )
          else
            Expanded(child: WebViewWidget(controller: controller)),
        ],
      ),
    ),
  );
}
