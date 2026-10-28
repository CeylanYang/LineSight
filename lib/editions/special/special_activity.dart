import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../ui.dart';
import '../../store.dart';
import '../../l10n.dart';
import 'special_catalog.dart';
import 'special_vip.dart';
import 'special_media.dart';

String specialBalance(BuildContext context) =>
    '${AppScope.of(context).specialPointsBalance}'.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
void openSpecialActivity(BuildContext context, [String section = '福利中心']) =>
    openPage(
      context,
      specialCategory(section) == 'stocks'
          ? const SpecialWebPage()
          : SpecialActivityPage(section: section),
    );

class SpecialServicesGrid extends StatelessWidget {
  const SpecialServicesGrid({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          tr(context, '逛逛生活圈 · 福利挤满屏'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
      Wrap(
        children: [
          for (final (i, s) in specialServices.indexed)
            FractionallySizedBox(
              widthFactor: .25,
              child: SpecialMotion(
                phase: i,
                child: InkWell(
                  key: ValueKey('special-service-${s.id}'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => openSpecialActivity(context, s.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 2,
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: s.color.withValues(alpha: .13),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(s.icon, color: s.color, size: 27),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr(context, s.title),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

class SpecialActivityPage extends StatefulWidget {
  final String section;
  const SpecialActivityPage({super.key, required this.section});
  @override
  State<SpecialActivityPage> createState() => _SpecialActivityPageState();
}

class _SpecialActivityPageState extends State<SpecialActivityPage> {
  Timer? promo;
  @override
  void initState() {
    super.initState();
    if (specialCategory(widget.section) == 'hub') {
      promo = Timer(const Duration(milliseconds: 1100), () {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          showDialog<void>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: Row(
                children: [
                  Expanded(child: Text(tr(context, '广告 · 今天也要有排面'))),
                  IconButton(
                    tooltip: tr(context, '关闭'),
                    onPressed: () => Navigator.pop(dialog),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              content: Text(tr(context, '会员免费送，额度先算算。看看你的专属生活方案？')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: Text(tr(context, '稍后再说')),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialog);
                    openSpecialActivity(context, 'finance');
                  },
                  child: Text(tr(context, '去试算')),
                ),
              ],
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    promo?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = specialCategory(widget.section);
    final matches = specialServices.where((s) => s.id == id);
    final title = matches.isNotEmpty
        ? matches.first.title
        : switch (id) {
            'hub' => '福利中心',
            'ledger' => '积分明细',
            'invite' => '邀请同事',
            _ => widget.section,
          };
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, title)),
        actions: [
          if (id != 'hub')
            IconButton(
              tooltip: tr(context, '全部服务'),
              onPressed: () => openSpecialActivity(context),
              icon: const Icon(Icons.apps),
            ),
        ],
      ),
      body: ListView(
        // Stateful services restore progress for the current account only.
        key: ValueKey('special-activity/$id/${specialActor(context)}'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (id == 'hub') ...[
            const SpecialServicesGrid(),
            _promo(context),
            const SpecialVipBody(),
          ] else if (id == 'vip')
            const SpecialVipBody()
          else if (id == 'video' || id == 'drama')
            SpecialMediaBody(drama: id == 'drama')
          else if (id == 'stocks')
            const SpecialStocksBody()
          else if (id == 'books')
            const SpecialReaderBody()
          else if (id == 'running' || id == 'sports')
            SpecialExerciseBody(running: id == 'running')
          else if (id == 'health')
            const SpecialHealthBody()
          else if (id == 'finance' || id == 'insurance' || id == 'rental')
            SpecialPlanBody(kind: id)
          else
            SpecialRewardsBody(kind: id),
        ],
      ),
    );
  }

  Widget _promo(BuildContext context) => Card(
    color: const Color(0xFFFFE9D6),
    child: ListTile(
      leading: const Icon(Icons.auto_awesome, color: Colors.deepOrange),
      title: Text(tr(context, '广告 · 生活方案今日上新')),
      subtitle: Text(tr(context, '先算一算，收藏你的专属方案')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => openSpecialActivity(context, 'finance'),
    ),
  );
}

class SpecialRewardsBody extends StatefulWidget {
  final String kind;
  const SpecialRewardsBody({super.key, required this.kind});
  @override
  State<SpecialRewardsBody> createState() => _SpecialRewardsBodyState();
}

class _SpecialRewardsBodyState extends State<SpecialRewardsBody> {
  bool busy = false;
  Future<void> claim(String name, int points) async {
    if (busy) return;
    if (AppScope.of(context).specialRewardClaimed(name)) {
      toast(context, '今天已经领过啦，明天再来');
      return;
    }
    setState(() => busy = true);
    try {
      await AppScope.of(context).claimSpecialReward(name, points: points);
      if (mounted) toast(context, '领取记录已更新');
    } catch (_) {
      if (mounted) {
        toast(context, points < 0 ? '兑换失败，请重试' : '领取失败，请重试');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final history = store.specialActivity['history'] as List? ?? [];
    final pieces = (specialState(context)['pieces'] as List? ?? []).cast<int>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(context, '{0} 积分', [specialBalance(context)]),
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: Colors.deepOrange,
          ),
        ),
        if (widget.kind != 'ledger')
          TextButton(
            onPressed: () => openSpecialActivity(context, '积分明细'),
            child: Text(tr(context, '查看领取与兑换记录')),
          ),
        if (widget.kind == 'ledger') ...[
          for (final row in history)
            Card(
              child: ListTile(
                title: Text(trMessage(context, '${row['label']}')),
                subtitle: Text('${row['date']}'),
                trailing: Text(tr(context, '{0} 积分', [row['points']])),
              ),
            ),
          if (history.isEmpty) Text(tr(context, '还没有领取记录，去签到吧')),
          if (history.isEmpty)
            FilledButton(
              onPressed: () => openSpecialActivity(context, 'points'),
              child: Text(tr(context, '去签到')),
            ),
        ] else if (widget.kind == 'invite') ...[
          Text(tr(context, '邀请同事，一起逛逛')),
          FilledButton.icon(
            onPressed: () async {
              try {
                await Clipboard.setData(
                  const ClipboardData(text: 'https://99ai.pronhubcn.com/'),
                );
                if (context.mounted) toast(context, '邀请链接已复制');
              } catch (_) {
                if (context.mounted) toast(context, '链接复制失败，请重试');
              }
            },
            icon: const Icon(Icons.copy),
            label: Text(tr(context, '复制官网链接')),
          ),
        ] else if (widget.kind == 'fragments') ...[
          Text(
            tr(context, '好礼拼图 · 已集齐 {0}/6', [pieces.length]),
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < 6; i++)
                SizedBox(
                  width: 88,
                  height: 88,
                  child: FilledButton.tonal(
                    onPressed: busy || pieces.contains(i)
                        ? null
                        : () async {
                            setState(() => busy = true);
                            try {
                              await saveSpecial(context, (s) {
                                final p =
                                    (s['pieces'] as List? ?? [])
                                        .cast<int>()
                                        .toSet()
                                      ..add(i);
                                return {...s, 'pieces': p.toList()};
                              });
                            } catch (_) {
                              if (context.mounted) toast(context, '碎片未保存，请重试');
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    child: Text(
                      tr(
                        context,
                        pieces.contains(i) ? '✓ 碎片{0}' : '点亮\n碎片{0}',
                        [i + 1],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed:
                pieces.length == 6 &&
                    !busy &&
                    !store.specialRewardClaimed('碎片集齐礼')
                ? () => claim('碎片集齐礼', 80)
                : null,
            child: Text(
              tr(
                context,
                store.specialRewardClaimed('碎片集齐礼')
                    ? '今日拼图奖励已领取'
                    : '集齐领取 80 积分',
              ),
            ),
          ),
        ] else ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month),
              title: Text(tr(context, '每日签到领积分')),
              subtitle: Text(tr(context, '签到 +20 · 每日好礼 +50')),
              trailing: FilledButton(
                onPressed: busy || store.specialRewardClaimed('每日签到')
                    ? null
                    : () => claim('每日签到', 20),
                child: Text(
                  tr(
                    context,
                    store.specialRewardClaimed('每日签到') ? '今日已签到' : '立即签到',
                  ),
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: busy || store.specialRewardClaimed('每日好礼')
                    ? null
                    : () => claim('每日好礼', 50),
                child: Text(
                  tr(
                    context,
                    store.specialRewardClaimed('每日好礼') ? '今日好礼已领取' : '领取好礼',
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: busy || store.specialRewardClaimed('金币夺宝')
                    ? null
                    : () => claim('金币夺宝', 30),
                child: Text(
                  tr(
                    context,
                    store.specialRewardClaimed('金币夺宝') ? '今日宝箱已开启' : '免费开一次',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            tr(context, '做任务 · 继续攒'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          for (final entry in [
            ('刷视频', 'video'),
            ('读一章书', 'books'),
            ('集齐碎片', 'fragments'),
            ('运动一下', 'sports'),
          ])
            Card(
              child: ListTile(
                title: Text(tr(context, entry.$1)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openSpecialActivity(context, entry.$2),
              ),
            ),
          Text(
            tr(context, '积分商城'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          for (final gift in [('新人礼券', 100), ('会员体验礼', 200)])
            OutlinedButton(
              onPressed: busy || store.specialRewardClaimed('兑换${gift.$1}')
                  ? null
                  : () {
                      if (store.specialPointsBalance < gift.$2) {
                        toast(context, '积分不足，先去完成每日任务');
                        return;
                      }
                      claim('兑换${gift.$1}', -gift.$2);
                    },
              child: Text(
                store.specialRewardClaimed('兑换${gift.$1}')
                    ? tr(context, '{0} · 今日已兑换', [tr(context, gift.$1)])
                    : tr(context, '{0} · {1} 积分', [
                        tr(context, gift.$1),
                        gift.$2,
                      ]),
              ),
            ),
        ],
      ],
    );
  }
}

class SpecialReaderBody extends StatefulWidget {
  const SpecialReaderBody({super.key});
  @override
  State<SpecialReaderBody> createState() => _SpecialReaderBodyState();
}

class _SpecialReaderBodyState extends State<SpecialReaderBody> {
  int chapter = 0;
  bool claiming = false;
  double font = 19;
  bool loaded = false;
  static const titles = ['第一章 · 今天的第一束光', '第二章 · 交接班的纸飞机', '第三章 · 下班以后'];
  static const texts = [
    '清晨，车间的灯一盏接一盏亮起。小林把工具放在固定的位置，在本子上写下今天的第一项任务。\n\n窗边落了一片叶子。她抬起头，看见同事端着热茶走来。“先把这一件做好。”他们都笑了。\n\n午前，最后一道检查完成。整齐的工件排成一行，像一封刚刚写好的信，等待送到下一位同事手里。',
    '交接班的桌上，放着一架小小的纸飞机。机翼上写着今天需要留意的三个地方，字迹有些歪，内容却很清楚。\n\n小林把它展开，逐项核对。临走前，她折好纸飞机，在背面补了一行：“已确认，明天见。”\n\n窗外的风轻轻吹过，纸飞机没有飞走，留在桌上，替大家守住一个温柔的约定。',
    '下班的铃声响起，城市开始换一种颜色。小林沿着河岸慢慢走，路灯把影子拉得很长。\n\n她在便利店买了一瓶水，坐在长椅上翻开白天的本子。今天没有惊天动地的大事，却有很多值得记住的小事。\n\n她合上本子，给朋友发了一条消息：“周末一起去看日出吧。”',
  ];
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      final s = specialState(context);
      chapter = (s['chapter'] as int? ?? 0).clamp(0, 2);
      font = (s['readerFont'] as num? ?? 19).toDouble().clamp(16, 28);
      loaded = true;
    }
  }

  Future<bool> save() async {
    final savedChapter = chapter;
    final savedFont = font;
    try {
      await saveSpecial(
        context,
        (s) => {...s, 'chapter': savedChapter, 'readerFont': savedFont},
      );
      return true;
    } catch (_) {
      if (mounted) toast(context, '阅读进度未保存，请点书签重试');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        tr(context, '小城工作日'),
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
      ),
      Text(tr(context, '生活短篇 · 三章完结')),
      Wrap(
        spacing: 6,
        children: [
          for (var i = 0; i < 3; i++)
            ChoiceChip(
              label: Text(tr(context, '第{0}章', [i + 1])),
              selected: chapter == i,
              onSelected: (_) {
                setState(() => chapter = i);
                save();
              },
            ),
        ],
      ),
      Row(
        children: [
          Text(tr(context, '字号')),
          Expanded(
            child: Slider(
              min: 16,
              max: 28,
              divisions: 6,
              value: font,
              onChanged: (v) => setState(() => font = v),
              onChangeEnd: (_) => save(),
            ),
          ),
          IconButton(
            tooltip: tr(context, '添加书签'),
            onPressed: () async {
              final saved = await save();
              if (saved && context.mounted) toast(context, '书签已保存，下次继续读');
            },
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
        ],
      ),
      const Divider(),
      Text(
        tr(context, titles[chapter]),
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      Text(
        tr(context, texts[chapter]),
        style: TextStyle(fontSize: font, height: 2),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed:
            claiming ||
                AppScope.of(context).specialRewardClaimed('阅读/第${chapter + 1}章')
            ? null
            : () async {
                final action = '阅读/第${chapter + 1}章';
                setState(() => claiming = true);
                try {
                  await AppScope.of(
                    context,
                  ).claimSpecialReward(action, points: 20);
                  if (context.mounted) toast(context, '阅读积分已到账');
                } catch (_) {
                  if (context.mounted) toast(context, '领取失败，请重试');
                } finally {
                  if (mounted) setState(() => claiming = false);
                }
              },
        icon: const Icon(Icons.stars_outlined),
        label: Text(
          tr(
            context,
            AppScope.of(context).specialRewardClaimed('阅读/第${chapter + 1}章')
                ? '本章今日积分已领取'
                : '读完本章，领取 20 积分',
          ),
        ),
      ),
      FilledButton(
        onPressed: chapter < 2
            ? () {
                setState(() => chapter++);
                save();
              }
            : null,
        child: Text(tr(context, chapter < 2 ? '下一章' : '全书读完啦')),
      ),
    ],
  );
}

class SpecialExerciseBody extends StatefulWidget {
  final bool running;
  const SpecialExerciseBody({super.key, required this.running});
  @override
  State<SpecialExerciseBody> createState() => _SpecialExerciseBodyState();
}

class _SpecialExerciseBodyState extends State<SpecialExerciseBody>
    with WidgetsBindingObserver {
  final watch = Stopwatch();
  Timer? tick;
  String exercise = '自由跑';
  bool saving = false, initialized = false;
  int carried = 0, lastSaved = -1;
  AppStore? sessionStore;
  String? actor;
  String get draftKey => widget.running ? 'runningDraft' : 'sportsDraft';
  int get elapsed => carried + watch.elapsed.inSeconds;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    initialized = true;
    sessionStore = AppScope.of(context);
    actor = specialActor(context);
    final draft = specialState(context)[draftKey] as Map?;
    carried = (draft?['seconds'] as int? ?? 0).clamp(0, 86400);
    final names = widget.running ? ['自由跑', '慢跑', '快走'] : ['拉伸', '深蹲', '平板支撑'];
    exercise = names.contains(draft?['name'])
        ? '${draft!['name']}'
        : names.first;
  }

  Future<void> persist() async {
    final store = sessionStore, owner = actor, seconds = elapsed;
    if (store == null ||
        owner == null ||
        saving ||
        seconds <= 0 ||
        seconds == lastSaved) {
      return;
    }
    lastSaved = seconds;
    final draft = {'seconds': seconds, 'name': exercise};
    try {
      await store.updateSpecialExperience(
        owner,
        (s) => {...s, draftKey: draft},
      );
    } catch (_) {
      lastSaved = -1;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      watch.stop();
      tick?.cancel();
      persist();
      if (mounted) setState(() {});
    }
  }

  void toggle() {
    setState(() {
      if (watch.isRunning) {
        watch.stop();
        tick?.cancel();
        persist();
      } else {
        watch.start();
        tick = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
          if (elapsed % 5 == 0) persist();
        });
      }
    });
  }

  @override
  void dispose() {
    persist();
    WidgetsBinding.instance.removeObserver(this);
    tick?.cancel();
    watch.stop();
    super.dispose();
  }

  Future<void> finish() async {
    final seconds = elapsed;
    watch.stop();
    tick?.cancel();
    setState(() => saving = true);
    try {
      await saveSpecial(
        context,
        (s) => {
          ...s,
          draftKey: null,
          'workouts': [
            {
              'name': exercise,
              'seconds': seconds,
              'date': DateTime.now().toIso8601String(),
            },
            ...(s['workouts'] as List? ?? []),
          ].take(30).toList(),
        },
      );
      watch.reset();
      carried = 0;
      lastSaved = 0;
      if (mounted) toast(context, '本次运动已保存');
    } catch (_) {
      if (mounted) toast(context, '保存失败，计时已保留，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> discard() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(context, '清空本次计时？')),
        content: Text(tr(context, '已保存的运动记录会保留。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr(context, '继续保留')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr(context, '清空计时')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    watch.stop();
    tick?.cancel();
    setState(() => saving = true);
    try {
      await saveSpecial(context, (s) => {...s, draftKey: null});
      watch.reset();
      carried = 0;
      lastSaved = 0;
    } catch (_) {
      if (mounted) toast(context, '清空失败，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seconds = elapsed;
    final history = specialState(context)['workouts'] as List? ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final name
                in widget.running ? ['自由跑', '慢跑', '快走'] : ['拉伸', '深蹲', '平板支撑'])
              ChoiceChip(
                label: Text(tr(context, name)),
                selected: exercise == name,
                onSelected: watch.isRunning || seconds > 0 || saving
                    ? null
                    : (_) => setState(() => exercise = name),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900),
        ),
        Text(
          tr(
            context,
            carried > 0 && !watch.isRunning ? '上次的运动已暂停，可以继续' : '运动计时',
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: saving ? null : toggle,
          icon: Icon(watch.isRunning ? Icons.pause : Icons.play_arrow),
          label: Text(
            tr(
              context,
              watch.isRunning
                  ? '暂停'
                  : seconds > 0
                  ? '继续本次运动'
                  : '开始运动',
            ),
          ),
        ),
        OutlinedButton(
          onPressed: seconds == 0 || saving ? null : finish,
          child: Text(tr(context, '结束并保存')),
        ),
        if (seconds > 0)
          TextButton(
            onPressed: saving ? null : discard,
            child: Text(tr(context, '清空本次计时')),
          ),
        if (history.any(
          (row) =>
              '${row['date']}'.split('T').first ==
              DateTime.now().toIso8601String().split('T').first,
        ))
          TextButton.icon(
            onPressed:
                saving || AppScope.of(context).specialRewardClaimed('今日运动')
                ? null
                : () async {
                    setState(() => saving = true);
                    try {
                      await AppScope.of(
                        context,
                      ).claimSpecialReward('今日运动', points: 20);
                      if (context.mounted) toast(context, '今日运动积分已到账');
                    } catch (_) {
                      if (context.mounted) toast(context, '领取失败，请重试');
                    } finally {
                      if (mounted) setState(() => saving = false);
                    }
                  },
            icon: const Icon(Icons.stars_outlined),
            label: Text(
              tr(
                context,
                AppScope.of(context).specialRewardClaimed('今日运动')
                    ? '今日运动积分已领取'
                    : '领取今日运动 20 积分',
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          tr(context, '最近运动'),
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
        ),
        for (final row in history)
          ListTile(
            leading: const Icon(Icons.timer),
            title: Text(
              tr(context, '{0} · {1} 秒', [
                tr(context, '${row['name']}'),
                row['seconds'],
              ]),
            ),
            subtitle: Text('${row['date']}'.split('T').first),
          ),
        if (history.isEmpty) Text(tr(context, '开始一次运动，留下今天的记录')),
      ],
    );
  }
}

class SpecialHealthBody extends StatefulWidget {
  const SpecialHealthBody({super.key});
  @override
  State<SpecialHealthBody> createState() => _SpecialHealthBodyState();
}

class _SpecialHealthBodyState extends State<SpecialHealthBody> {
  bool saving = false;

  Future<void> recordWater(int change) async {
    if (saving) return;
    setState(() => saving = true);
    final day = DateTime.now().toIso8601String().split('T').first;
    try {
      await saveSpecial(context, (s) {
        final current = s['waterDay'] == day ? (s['water'] as int? ?? 0) : 0;
        return {
          ...s,
          'waterDay': day,
          'water': (current + change).clamp(0, 4000),
        };
      });
    } catch (_) {
      if (mounted) toast(context, '饮水记录未保存，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = DateTime.now().toIso8601String().split('T').first;
    final state = specialState(context);
    final water = state['waterDay'] == day ? (state['water'] as int? ?? 0) : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(context, '今天也要照顾好自己'),
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        const Icon(Icons.water_drop, color: Colors.lightBlue, size: 90),
        Text(
          '$water / 2000 ml',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
        ),
        LinearProgressIndicator(value: (water / 2000).clamp(0, 1)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: saving || water >= 4000 ? null : () => recordWater(200),
          child: Text(tr(context, '喝一杯水 +200ml')),
        ),
        TextButton(
          onPressed: saving || water == 0 ? null : () => recordWater(-200),
          child: Text(tr(context, '撤销一杯')),
        ),
        for (final entry in [
          ('散步放松', 'running'),
          ('伸展身体', 'sports'),
          ('静心读书', 'books'),
        ])
          Card(
            child: ListTile(
              title: Text(tr(context, entry.$1)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openSpecialActivity(context, entry.$2),
            ),
          ),
      ],
    );
  }
}

class SpecialPlanBody extends StatefulWidget {
  final String kind;
  const SpecialPlanBody({super.key, required this.kind});
  @override
  State<SpecialPlanBody> createState() => _SpecialPlanBodyState();
}

// Plans are stored in canonical text so language changes preserve deduplication.
String specialPlanDetail(BuildContext context, String detail) {
  final rental = RegExp(
    r'^(.+) · (\d{4}-\d{2}-\d{2}) · (\d+) 天 · ¥(\d+)$',
  ).firstMatch(detail);
  if (rental != null) {
    return tr(context, '{0} · {1} · {2} 天 · ¥{3}', [
      tr(context, rental[1]!),
      rental[2],
      rental[3],
      rental[4],
    ]);
  }
  return trMessage(context, detail);
}

class _SpecialPlanBodyState extends State<SpecialPlanBody> {
  double amount = 10000;
  int months = 12;
  int choice = 0;
  String city = '杭州';
  DateTime? start, end;
  bool saving = false;
  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final finance = kind == 'finance', rental = kind == 'rental';
    final plans = finance
        ? ['轻松周转', '设备焕新', '安心生活']
        : rental
        ? ['经济型', '舒适型', '商务型']
        : ['城市通勤', '周末出游', '家庭守护'];
    final daily = [129, 229, 399][choice];
    final days = start != null && end != null
        ? math.max(1, end!.difference(start!).inDays)
        : 1;
    final payment =
        amount *
        (.0035 * math.pow(1.0035, months)) /
        (math.pow(1.0035, months) - 1);
    final saved = (specialState(context)['plans'] as List? ?? [])
        .where((p) => p['kind'] == kind)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(
            context,
            finance
                ? '广告 · 生活额度试算'
                : rental
                ? '选好车，安排下一程'
                : '挑一份出行守护',
          ),
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < plans.length; i++)
              ChoiceChip(
                label: Text(tr(context, plans[i])),
                selected: choice == i,
                onSelected: (_) => setState(() => choice = i),
              ),
          ],
        ),
        if (finance) ...[
          Text(
            tr(context, '试算金额 ¥{0}', [amount.toInt()]),
            style: const TextStyle(fontSize: 24),
          ),
          Slider(
            min: 1000,
            max: 50000,
            divisions: 49,
            value: amount,
            onChanged: (v) => setState(() => amount = v),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final m in [3, 6, 12, 24])
                ChoiceChip(
                  label: Text(tr(context, '{0} 期', [m])),
                  selected: months == m,
                  onSelected: (_) => setState(() => months = m),
                ),
            ],
          ),
          Text(tr(context, '月利率 0.35% · 等额本息')),
          Text(
            tr(context, '每期约 ¥{0}', [payment.toStringAsFixed(2)]),
            style: const TextStyle(
              fontSize: 28,
              color: Colors.deepOrange,
              fontWeight: FontWeight.bold,
            ),
          ),
        ] else if (rental) ...[
          DropdownButtonFormField<String>(
            initialValue: city,
            decoration: InputDecoration(labelText: tr(context, '出发城市')),
            items: [
              for (final c in ['杭州', '上海', '北京', '深圳'])
                DropdownMenuItem(value: c, child: Text(tr(context, c))),
            ],
            onChanged: (v) => setState(() => city = v!),
          ),
          ListTile(
            title: Text(
              start == null
                  ? tr(context, '选择取车日期')
                  : tr(context, '取车 {0}', [
                      start!.toIso8601String().split('T').first,
                    ]),
            ),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: start ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null && mounted) {
                setState(() {
                  start = d;
                  if (end != null && end!.isBefore(d)) end = null;
                });
              }
            },
          ),
          ListTile(
            title: Text(
              end == null
                  ? tr(context, '选择还车日期')
                  : tr(context, '还车 {0}', [
                      end!.toIso8601String().split('T').first,
                    ]),
            ),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: end ?? start ?? DateTime.now(),
                firstDate:
                    start ?? DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (d != null && mounted) setState(() => end = d);
            },
          ),
          Text(
            tr(context, '¥{0} / 天 · {1} 天约 ¥{2}', [daily, days, daily * days]),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ] else ...[
          for (final item in [
            ('意外保障', ['10万', '30万', '50万'][choice]),
            ('出行服务', ['道路援助', '行李保障', '家庭出行'][choice]),
            ('计划预算', '¥${[19, 39, 69][choice]} / 月'),
          ])
            ListTile(
              title: Text(tr(context, item.$1)),
              trailing: Text(trMessage(context, item.$2)),
            ),
          const Text(
            '方案比较',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          Text(tr(context, '城市通勤适合日常出行；周末出游增加行李保障；家庭守护可整理全家出行计划。')),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: saving
              ? null
              : () async {
                  if (rental && (start == null || end == null)) {
                    toast(context, '请先选择取车和还车日期');
                    return;
                  }
                  setState(() => saving = true);
                  try {
                    final plan = <String, dynamic>{
                      'kind': kind,
                      'name': plans[choice],
                      'detail': finance
                          ? '¥${amount.toInt()} · $months 期 · 每期 ¥${payment.toStringAsFixed(2)}'
                          : rental
                          ? '$city · ${start!.toIso8601String().split('T').first} · $days 天 · ¥${daily * days}'
                          : '预算 ¥${[19, 39, 69][choice]} / 月',
                      'date': DateTime.now().toIso8601String(),
                    };
                    await saveSpecial(
                      context,
                      (state) => {
                        ...state,
                        'plans': [
                          plan,
                          ...(state['plans'] as List? ?? []).where(
                            (p) => !sameSpecialPlan(p, plan),
                          ),
                        ].take(30).toList(),
                      },
                    );
                    if (context.mounted) toast(context, '已保存到我的方案');
                  } catch (_) {
                    if (context.mounted) toast(context, '保存失败，请重试');
                  } finally {
                    if (mounted) setState(() => saving = false);
                  }
                },
          icon: const Icon(Icons.bookmark_add),
          label: Text(tr(context, rental ? '保存行程计划' : '收藏这个方案')),
        ),
        const SizedBox(height: 16),
        Text(
          tr(context, '我的方案'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        if (saved.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(tr(context, '还没有收藏，选好上面的方案再保存吧')),
          ),
        for (final p in saved)
          Card(
            child: ListTile(
              title: Text(tr(context, '${p['name']}')),
              subtitle: Text(specialPlanDetail(context, '${p['detail']}')),
              trailing: IconButton(
                tooltip: tr(context, '移除方案'),
                icon: const Icon(Icons.bookmark_remove_outlined),
                onPressed: saving
                    ? null
                    : () async {
                        final store = AppScope.of(context);
                        final actor = specialActor(context);
                        if (saving) return;
                        setState(() => saving = true);
                        try {
                          await store.updateSpecialExperience(
                            actor,
                            (state) => {
                              ...state,
                              'plans': (state['plans'] as List? ?? [])
                                  .where((row) => !sameSpecialPlan(row, p))
                                  .toList(),
                            },
                          );
                          if (!context.mounted ||
                              specialActor(context) != actor) {
                            return;
                          }
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(tr(context, '已移除收藏')),
                                action: SnackBarAction(
                                  label: tr(context, '撤销'),
                                  onPressed: () async {
                                    if (!context.mounted ||
                                        specialActor(context) != actor) {
                                      return;
                                    }
                                    try {
                                      await store.updateSpecialExperience(
                                        actor,
                                        (state) => {
                                          ...state,
                                          'plans': [
                                            p,
                                            ...(state['plans'] as List? ?? [])
                                                .where(
                                                  (row) =>
                                                      !sameSpecialPlan(row, p),
                                                ),
                                          ].take(30).toList(),
                                        },
                                      );
                                    } catch (_) {
                                      if (context.mounted &&
                                          specialActor(context) == actor) {
                                        toast(context, '恢复失败，请重试');
                                      }
                                    }
                                  },
                                ),
                              ),
                            );
                        } catch (_) {
                          if (context.mounted &&
                              specialActor(context) == actor) {
                            toast(context, '移除失败，请重试');
                          }
                        } finally {
                          if (mounted) setState(() => saving = false);
                        }
                      },
              ),
            ),
          ),
      ],
    );
  }
}

class SpecialStocksBody extends StatefulWidget {
  const SpecialStocksBody({super.key});
  @override
  State<SpecialStocksBody> createState() => _SpecialStocksBodyState();
}

class _SpecialStocksBodyState extends State<SpecialStocksBody> {
  final amount = TextEditingController(text: '10000');
  String ticker = 'AAPL';

  String? error;
  double? invested;
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prices = [
      for (var i = 0; i <= 12; i++)
        100 +
            math.sin(i * .9) * 8 +
            i *
                (ticker == 'AAPL'
                    ? 6
                    : ticker == 'MSFT'
                    ? 7
                    : 4),
    ];
    final principal = invested ?? 10000;
    final finalValue = principal * prices.last / prices.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(context, '如果当年买了它'),
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
        ),
        Text(tr(context, '样例回测 · 固定示例行情')),
        Wrap(
          spacing: 8,
          children: [
            for (final t in ['AAPL', 'MSFT', 'GOOGL'])
              ChoiceChip(
                label: Text(t),
                selected: ticker == t,
                onSelected: (_) => setState(() => ticker = t),
              ),
          ],
        ),
        TextField(
          controller: amount,
          onChanged: (_) => setState(() {
            invested = null;
            error = null;
          }),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: tr(context, '投入金额'),
            prefixText: '¥ ',
            errorText: error == null ? null : tr(context, error!),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < prices.length; i++)
                      FlSpot(i.toDouble(), prices[i]),
                  ],
                  isCurved: true,
                  color: Colors.deepOrange,
                  barWidth: 3,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.orange.withValues(alpha: .12),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(amount.text);
            setState(() {
              error = v == null || !v.isFinite || v < 1 || v > 100000000
                  ? '请输入 1～100000000 的金额'
                  : null;
              invested = error == null ? v : null;
            });
          },
          child: Text(tr(context, '计算样例收益')),
        ),
        if (invested != null) ...[
          Text(
            tr(context, '期末价值 ¥{0}', [finalValue.toStringAsFixed(2)]),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            tr(context, '区间收益 {0}%', [
              ((finalValue / principal - 1) * 100).toStringAsFixed(1),
            ]),
          ),
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(tr(context, '阶段'))),
                    DataColumn(label: Text(tr(context, '样例价格'))),
                  ],
                  rows: [
                    for (final i in [0, 3, 6, 9, 12])
                      DataRow(
                        cells: [
                          DataCell(Text(tr(context, '第 {0} 月', [i]))),
                          DataCell(Text(prices[i].toStringAsFixed(2))),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        OutlinedButton.icon(
          onPressed: () => openPage(context, const SpecialWebPage()),
          icon: const Icon(Icons.open_in_browser),
          label: Text(tr(context, '打开 WhatIfIBought 完整回测')),
        ),
      ],
    );
  }
}
