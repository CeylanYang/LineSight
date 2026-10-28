import 'special_activity.dart';
import 'special_catalog.dart';
import 'package:flutter/material.dart';
import '../../l10n.dart';
import '../../ui.dart';
import '../../screens/dashboard.dart';
import '../../screens/production.dart';
import '../../screens/settings.dart';
import '../../screens/statistics.dart';

const specialBrand = 'checkcheck';
const specialBrandSubtitle = '生产质量工作台';
const specialPoints = 2340;
const specialPointsLabel = '2,340';

const _bgNewbie = 'assets/checkcheck/backgrounds/bg_banner_newbie.png';
const _bgVip = 'assets/checkcheck/backgrounds/bg_banner_vip.png';
const _bgFinance = 'assets/checkcheck/backgrounds/bg_banner_finance.png';
const _bgSignin = 'assets/checkcheck/backgrounds/bg_card_signin.png';
const _btnClaim = 'assets/checkcheck/backgrounds/bg_btn_claim.png';
const _btnVip = 'assets/checkcheck/backgrounds/bg_btn_vip.png';
const _btnSignin = 'assets/checkcheck/backgrounds/bg_btn_signin.png';
const _btnBlue = 'assets/checkcheck/backgrounds/bg_btn_blue.png';

const _pageTop = Color(0xFFF4F8FF);
const _ink = Color(0xFF1B2437);
const _sub = Color(0xFF8B96AC);
const _line = Color(0xFFE9EFF9);

Widget _art(String name, double size, {Color? tint}) {
  final image = Image.asset(
    'assets/checkcheck/illustrations/$name.png',
    width: size,
    height: size,
    filterQuality: FilterQuality.high,
  );
  if (tint == null) return image;
  return ColorFiltered(
    colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    child: image,
  );
}

Widget _glyph(String name, double size, Color color) => ColorFiltered(
  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  child: Image.asset(
    'assets/checkcheck/icons/$name.png',
    width: size,
    height: size,
    filterQuality: FilterQuality.high,
  ),
);

class SpecialWorkbenchPage extends StatefulWidget {
  final Map<String, VoidCallback> actions;
  final Map<String, int> counts;
  final Widget? workspaceUpdates;
  final VoidCallback onRecords;
  final VoidCallback onTemplates;
  const SpecialWorkbenchPage({
    super.key,
    this.actions = const {},
    this.counts = const {},
    this.workspaceUpdates,
    required this.onRecords,
    required this.onTemplates,
  });
  @override
  State<SpecialWorkbenchPage> createState() => _SpecialWorkbenchPageState();
}

class _SpecialWorkbenchPageState extends State<SpecialWorkbenchPage> {
  int _videoOffset = 0;
  static const _videoItems = [
    ('质检员的一天', '真实工作日常', '3.2万', '02:18', 'thumb_01_inspector_day'),
    ('那些离谱的缺陷', '生产线上的意外', '1.8万', '01:46', 'thumb_02_defect'),
    ('AI 如何识别缺陷', '3 分钟看懂原理', '2.6万', '02:34', 'thumb_03_ai'),
    ('工厂里的治愈瞬间', '质检人的快乐', '4.1万', '01:52', 'thumb_04_healing'),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 393) return _buildCanvas(context);
      final scale = constraints.maxWidth / 393;
      return FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 393,
          height: constraints.maxHeight / scale,
          child: _buildCanvas(context),
        ),
      );
    },
  );

  Widget _buildCanvas(BuildContext context) {
    final s = AppScope.of(context);
    final stations = s.data.stations;
    final pendingJobs = widget.counts['jobs'] ?? s.data.jobs.length;
    final alerts = widget.counts['alerts'] ?? s.pending.length;
    final records = widget.counts['records'] ?? s.records.length;
    final templates = widget.counts['templates'] ?? s.data.recipes.length;
    void inspect() => openPage(context, StationPage(id: stations.first.id));
    return ColoredBox(
      color: _pageTop,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                6,
                20,
                108 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                _newbieBanner(context),
                const SizedBox(height: 10),
                _search(context),
                const SizedBox(height: 10),
                _quadrants(context, inspect),
                const SizedBox(height: 10),
                _statusCard(
                  context,
                  alerts: alerts,
                  records: records,
                  jobs: pendingJobs,
                  templates: templates,
                  onRecords: widget.onRecords,
                  onTemplates: widget.onTemplates,
                ),
                const SizedBox(height: 10),
                if (widget.workspaceUpdates != null) widget.workspaceUpdates!,
                _vipBanner(context),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SpecialServicesGrid(),
                ),
                const SizedBox(height: 10),
                _signinAndAssets(context),
                const SizedBox(height: 12),
                _videos(context),
                const SizedBox(height: 10),
                _financeBanner(context),
                const SizedBox(height: 10),
                _miniCards(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _newbieBanner(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth, h = w * 84 / 352;
      return SizedBox(
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(_bgNewbie, fit: BoxFit.fill),
              ),
            ),
            Positioned(
              right: -4,
              bottom: -h * .10,
              child: Image.asset(
                'assets/checkcheck/illustrations/illus_mascot.png',
                height: h * 1.22,
                filterQuality: FilterQuality.high,
              ),
            ),
            Positioned(
              left: 14,
              top: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _chip(
                    context,
                    '新人专享礼',
                    const [Color(0xFFFF7A6B), Color(0xFFF03D2E)],
                    fontSize: 8.5,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    trailing: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: Image(
                          image: AssetImage(
                            'assets/checkcheck/illustrations/illus_gift.png',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr(context, '完成 3 个质检任务'),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: tr(context, '送 '),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        const TextSpan(
                          text: '500',
                          style: TextStyle(
                            fontSize: 21,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFE8342A),
                          ),
                        ),
                        TextSpan(
                          text: tr(context, ' 积分'),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    tr(context, '让生产更顺畅，奖励领不停'),
                    style: const TextStyle(
                      fontSize: 9.5,
                      height: 1.1,
                      color: _sub,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 150,
              bottom: 7,
              child: _imageButton(
                context,
                _btnClaim,
                76,
                22,
                tr(context, '立即领取'),
                fontSize: 10,
                onTap: () => openSpecialActivity(context, 'points'),
              ),
            ),
            Positioned(
              right: w * .29,
              top: 8,
              child: Transform.rotate(
                angle: -.045,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    tr(context, '质检也能拿奖励？\n安排！'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 8.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE8342A),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _search(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: widget.actions['搜索'] ?? widget.onRecords,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _line),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 20, color: _sub),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(context, '任务号、批次、产品名称或异常关键词'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _sub),
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, size: 18, color: _ink),
          ],
        ),
      ),
    ),
  );

  Widget _quadrants(BuildContext context, VoidCallback inspect) {
    final items = [
      (
        'glyph_online_qa',
        '在线质检',
        '拍照识别缺陷',
        const [Color(0xFF6BA3F8), Color(0xFF3F7BF6)],
        inspect,
      ),
      (
        'glyph_scan_trace',
        widget.actions.containsKey('扫码追溯') ? '扫码追溯' : '记录查询',
        widget.actions.containsKey('扫码追溯') ? '批次查询' : '查看检测记录',
        const [Color(0xFF8A7BFF), Color(0xFF4A5BFB)],
        widget.onRecords,
      ),
      (
        'glyph_new_task',
        '新建任务',
        '快速创建',
        const [Color(0xFF2BC49B), Color(0xFF0FA88E)],
        () => ProductionPage.createJob(context),
      ),
      (
        'glyph_report',
        '质量报告',
        '自动生成分析',
        const [Color(0xFFA88BEE), Color(0xFF8A63E3)],
        () => openPage(context, const StatisticsPage()),
      ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: widget.actions[item.$2] ?? item.$5,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: item.$4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: item.$4.last.withValues(alpha: .28),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(child: _glyph(item.$1, 23, Colors.white)),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        tr(context, item.$2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr(context, item.$3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 8.5, color: _sub),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusCard(
    BuildContext context, {
    required int alerts,
    required int records,
    required int jobs,
    required int templates,
    required VoidCallback onRecords,
    required VoidCallback onTemplates,
  }) {
    final items = [
      (
        'glyph_todo',
        '待检任务',
        '今日待完成',
        const Color(0xFFE8983B),
        const Color(0xFFFFF4E4),
        jobs,
        onRecords,
      ),
      (
        'glyph_defect',
        '异常处理',
        '待跟进异常',
        const Color(0xFFE15672),
        const Color(0xFFFDEBEF),
        alerts,
        () => openPage(context, const AlertsPage()),
      ),
      (
        'glyph_records',
        '检测记录',
        '历史查询',
        const Color(0xFF3478F6),
        const Color(0xFFEAF2FF),
        records,
        onRecords,
      ),
      (
        'glyph_printer',
        '打印配置',
        '标签 / 报表',
        const Color(0xFF5C8DF6),
        const Color(0xFFEEF3FF),
        0,
        () => openPage(context, const SettingsPage()),
      ),
      (
        'glyph_template',
        '检查模板',
        '快速复用',
        const Color(0xFF18A98C),
        const Color(0xFFE9F8F2),
        templates,
        onTemplates,
      ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: widget.actions[item.$2] ?? item.$7,
                child: Column(
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: item.$5,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(child: _glyph(item.$1, 19, item.$4)),
                          ),
                          if (item.$6 > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 16),
                                height: 16,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF04438),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.2,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${item.$6}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(context, item.$2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      tr(context, item.$3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 8, color: _sub),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _vipBanner(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth, h = w * 38 / 352;
      final level = specialState(context)['vip'] as int?;
      return SizedBox(
        height: h,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(_bgVip, fit: BoxFit.fill),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 4,
              top: 4,
              child: Image.asset(
                'assets/checkcheck/illustrations/illus_crown.png',
                filterQuality: FilterQuality.high,
              ),
            ),
            Positioned(
              left: 56,
              right: 84,
              top: 0,
              bottom: 0,
              child:
                  level != null ||
                      Localizations.localeOf(context).languageCode == 'en'
                  ? Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              tr(
                                context,
                                level == null
                                    ? '质检会员'
                                    : specialLevels[level.clamp(0, 3)],
                              ),
                              key: const ValueKey('special-home-vip-level'),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _chip(
                          context,
                          level == null ? '点击就送' : '已领取',
                          const [Color(0xFFFF8A4C), Color(0xFFF5402F)],
                          fontSize: 8,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Text(
                          tr(
                            context,
                            level == null
                                ? '质检会员'
                                : specialLevels[level.clamp(0, 3)],
                          ),
                          key: const ValueKey('special-home-vip-level'),
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _chip(
                          context,
                          level == null ? '点击就送' : '已领取',
                          const [Color(0xFFFF8A4C), Color(0xFFF5402F)],
                          fontSize: 8,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            tr(context, '四重身份 · 专属标识'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 8,
                              color: Color(0xFFE4E0FF),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            Positioned(
              right: 8,
              top: (h - 27) / 2,
              child: _imageButton(
                context,
                _btnVip,
                72,
                22,
                tr(context, level == null ? '免费领取' : '查看详情'),
                fontSize: 10.5,
                color: const Color(0xFF7A4A12),
                onTap: () => openSpecialActivity(context, '会员好礼'),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _signinAndAssets(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cardWidth = (c.maxWidth - 10) * .58;
      final h = cardWidth * 100 / 198;
      return SizedBox(
        height: h,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 58, child: _signinCard(context)),
            const SizedBox(width: 10),
            Expanded(flex: 42, child: _assetsCard(context)),
          ],
        ),
      );
    },
  );

  Widget _signinCard(BuildContext context) {
    final claimed = AppScope.of(context).specialRewardClaimed('每日签到');
    const rewards = [20, 20, 20, 20, 20, 20];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        image: const DecorationImage(
          image: AssetImage(_bgSignin),
          fit: BoxFit.fill,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(context, '每日签到领积分'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                ),
              ),
              Text(
                tr(context, claimed ? '今日已签到' : '立即签到'),
                key: const ValueKey('special-home-checkin-status'),
                style: const TextStyle(fontSize: 8.5, color: _sub),
              ),
              const Icon(Icons.chevron_right_rounded, size: 14, color: _sub),
            ],
          ),
          const Spacer(),
          Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 12,
                right: 12,
                child: Container(height: 1.2, color: const Color(0xFFF3DCC6)),
              ),
              Row(
                children: [
                  Expanded(child: _dayNode(check: claimed)),
                  for (var i = 0; i < 5; i++) Expanded(child: _dayNode()),
                  Expanded(child: _dayNode(gift: true)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(child: _dayCaption(context, '今天', '', first: true)),
              for (var i = 0; i < rewards.length; i++)
                Expanded(
                  child: _dayCaption(
                    context,
                    tr(context, '第{0}天', [i + 2]),
                    '+20',
                  ),
                ),
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 22,
            width: double.infinity,
            child: _imageButton(
              context,
              _btnSignin,
              double.infinity,
              22,
              tr(context, claimed ? '今日已签到' : '立即签到'),
              fontSize: 10,
              onTap: () => openSpecialActivity(context, '每日签到'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayNode({bool check = false, bool gift = false}) {
    if (check) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFF6DCC2), width: 1.2),
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 14,
          color: Color(0xFFE8802A),
        ),
      );
    }
    if (gift) return _art('illus_gift', 21);
    return _art('illus_coin', 20);
  }

  Widget _dayCaption(
    BuildContext context,
    String day,
    String reward, {
    bool first = false,
  }) => Column(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(
          color: reward.isEmpty ? Colors.transparent : const Color(0xFFFFF0E2),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          reward.isEmpty ? '' : reward,
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(
            fontSize: 8,
            height: 1.1,
            fontWeight: FontWeight.w800,
            color: Color(0xFFE8802A),
          ),
        ),
      ),
      const SizedBox(height: 1),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          tr(context, day),
          style: TextStyle(
            fontSize: 7.5,
            height: 1.15,
            color: first ? _ink : _sub,
            fontWeight: first ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    ],
  );

  Widget _assetsCard(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 9, 9, 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  tr(context, '我的资产'),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  tr(context, '积分明细'),
                  style: const TextStyle(fontSize: 8, color: _sub),
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 12, color: _sub),
          ],
        ),
        const SizedBox(height: 1),
        Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      specialBalance(context),
                      style: const TextStyle(
                        fontSize: 19,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 2),
                      child: Text(
                        tr(context, '积分'),
                        style: const TextStyle(fontSize: 8.5, color: _sub),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  '≈ ¥${(AppScope.of(context).specialPointsBalance / 100).toStringAsFixed(2)}',
                  key: const ValueKey('special-home-points-equivalent'),
                  style: const TextStyle(fontSize: 8, color: _sub),
                ),
              ],
            ),
            Positioned(
              right: -6,
              top: -6,
              child: Opacity(opacity: .95, child: _art('illus_coin_pile', 62)),
            ),
          ],
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(child: _assetAction(context, 'illus_coin', '充值')),
            Expanded(child: _assetAction(context, 'illus_gift_basket', '积分商城')),
            Expanded(child: _assetAction(context, 'illus_coupon', '优惠券')),
            Expanded(child: _assetAction(context, 'illus_star', '任务奖励')),
          ],
        ),
      ],
    ),
  );

  Widget _assetAction(BuildContext context, String art, String label) =>
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openSpecialActivity(context, label),
        child: Column(
          children: [
            _art(art, 18),
            const SizedBox(height: 1),
            Text(
              tr(context, label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 7, color: _sub),
            ),
          ],
        ),
      );

  Widget _videos(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          _art('illus_gift', 16),
          const SizedBox(width: 4),
          Text(
            tr(context, '质检小剧场'),
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() {
              _videoOffset = (_videoOffset + 1) % _videoItems.length;
            }),
            child: Row(
              children: [
                const Icon(
                  Icons.refresh_rounded,
                  size: 13,
                  color: Color(0xFF5C8DF6),
                ),
                Text(
                  tr(context, '换一换'),
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Color(0xFF5C8DF6),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            tr(context, '更多'),
            style: const TextStyle(fontSize: 9.5, color: _sub),
          ),
          const Icon(Icons.chevron_right_rounded, size: 13, color: _sub),
        ],
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 72,
        child: Row(
          children: [
            for (var i = 0; i < _videoItems.length; i++) ...[
              if (i > 0) const SizedBox(width: 7),
              Expanded(
                child: GestureDetector(
                  onTap: () => openSpecialActivity(context, '视频积分'),
                  child: _videoCard(
                    context,
                    _videoItems[(i + _videoOffset) % _videoItems.length],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _videoCard(
    BuildContext context,
    (String, String, String, String, String) item,
  ) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/checkcheck/thumbs/${item.$5}.png',
          fit: BoxFit.cover,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x05000000), Color(0xB3000000)],
              stops: [0, .45, 1],
            ),
          ),
        ),
        Positioned(
          top: 5,
          right: 5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0x66000000),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item.$4,
              style: const TextStyle(fontSize: 8, color: Colors.white),
            ),
          ),
        ),
        Center(
          child: Image.asset(
            'assets/checkcheck/icons/icon_play.png',
            width: 22,
            height: 22,
          ),
        ),
        Positioned(
          left: 4,
          right: 4,
          bottom: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, item.$1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 8.5,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                tr(context, item.$2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 8, color: Color(0xCCFFFFFF)),
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    size: 8,
                    color: Color(0xFFC9D2E3),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    item.$3,
                    style: const TextStyle(
                      fontSize: 7.5,
                      color: Color(0xFFC9D2E3),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _financeBanner(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth, h = w * 46 / 352;
      return SizedBox(
        height: h,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(_bgFinance, fit: BoxFit.fill),
              ),
            ),
            Positioned(
              right: w * .285,
              top: 3,
              bottom: 3,
              child: Image.asset(
                'assets/checkcheck/illustrations/illus_chart_up.png',
                width: 74,
                filterQuality: FilterQuality.high,
              ),
            ),
            Positioned(
              left: 12,
              top: 4,
              right: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 13,
                        height: 13,
                        decoration: const BoxDecoration(
                          color: Color(0xFF3B64F3),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '¥',
                          style: TextStyle(
                            fontSize: 8,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tr(context, '生产金融'),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      Text(
                        tr(context, ' · 助力工厂更轻松'),
                        style: const TextStyle(fontSize: 8, color: _sub),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFCBD5E6)),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          tr(context, '广告'),
                          style: const TextStyle(
                            fontSize: 6.5,
                            color: Color(0xFF9AA5B8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: tr(context, '设备升级分期 · 最低 '),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        const TextSpan(
                          text: '0.99%',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFE8342A),
                          ),
                        ),
                        TextSpan(
                          text: tr(context, ' 月费率'),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    tr(context, '让质检设备不再是负担，灵活分期，轻松上产'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 7.5,
                      height: 1.1,
                      color: _sub,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 8,
              bottom: 7,
              child: _imageButton(
                context,
                _btnBlue,
                78,
                22,
                tr(context, '查看详情'),
                fontSize: 10,
                onTap: () => openSpecialActivity(context, 'finance'),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _miniCards(BuildContext context) {
    final items = [
      ('illus_gift_basket', '邀请同事', '得 2000 积分', 'invite'),
      ('illus_task_pad', '每日任务', '做任务领积分', 'points'),
      ('illus_red_packet', '充100送20', '最高送 10000', 'finance'),
      ('illus_book', '新人必看', '快速上手指南', 'hub'),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => openSpecialActivity(context, items[i].$4),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _line),
                  ),
                  child: Row(
                    children: [
                      _art(items[i].$1, 20),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(context, items[i].$2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 8.5,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                            Text(
                              tr(context, items[i].$3),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 7, color: _sub),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

Widget _chip(
  BuildContext context,
  String label,
  List<Color> colors, {
  Widget? trailing,
  double fontSize = 9.5,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
}) => Container(
  padding: padding,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(20),
    gradient: LinearGradient(colors: colors),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        tr(context, label),
        style: TextStyle(
          fontSize: fontSize,
          height: 1,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      if (trailing != null) trailing,
    ],
  ),
);

Widget _imageButton(
  BuildContext context,
  String background,
  double width,
  double height,
  String label, {
  double fontSize = 12,
  Color color = Colors.white,
  VoidCallback? onTap,
}) => GestureDetector(
  onTap: onTap,
  child: Container(
    width: width == double.infinity ? null : width,
    height: height,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(height / 2),
      image: DecorationImage(image: AssetImage(background), fit: BoxFit.fill),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    ),
  ),
);
