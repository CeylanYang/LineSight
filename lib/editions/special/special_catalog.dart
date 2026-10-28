import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../cloud_account.dart';
import '../../ui.dart';

String specialActor(BuildContext context) {
  final cloud = context
      .dependOnInheritedWidgetOfExactType<CloudScope>()
      ?.notifier;
  if (cloud != null) {
    return 'cloud/${cloud.profile?['id'] ?? cloud.profile?['username'] ?? 'guest'}';
  }
  return 'local/${AppScope.of(context).user?.id ?? 'guest'}';
}

Map<String, dynamic> specialState(BuildContext context) =>
    AppScope.of(context).specialExperienceFor(specialActor(context));
Future<void> saveSpecial(
  BuildContext context,
  Map<String, dynamic> Function(Map<String, dynamic>) update,
) =>
    AppScope.of(context).updateSpecialExperience(specialActor(context), update);

const specialLevels = ['铂金会员', '钻石会员', '至尊会员', '无上会员'];
const specialLevelAssets = ['platinum', 'diamond', 'supreme', 'celestial'];

class SpecialService {
  final String id, title, subtitle, art;
  final IconData icon;
  final Color color;
  const SpecialService(
    this.id,
    this.title,
    this.subtitle,
    this.art,
    this.icon,
    this.color,
  );
}

const specialServices = [
  SpecialService(
    'finance',
    '在线金融',
    '额度试算 · 福利方案',
    'illus_money_bag',
    Icons.account_balance_wallet_rounded,
    Color(0xFFFF8134),
  ),
  SpecialService(
    'video',
    '在线刷视频',
    '刷一刷 · 乐一乐',
    'illus_play',
    Icons.play_circle_fill,
    Color(0xFFF34C86),
  ),
  SpecialService(
    'stocks',
    '在线股票',
    '时光回测 · 自选组合',
    'illus_chart_up',
    Icons.candlestick_chart,
    Color(0xFFEB5353),
  ),
  SpecialService(
    'drama',
    '在线小短剧',
    '下一集 · 更精彩',
    'illus_megaphone',
    Icons.movie_creation,
    Color(0xFF9166F8),
  ),
  SpecialService(
    'coins',
    '在线领金币',
    '签到开宝箱',
    'illus_coin',
    Icons.toll,
    Color(0xFFFFAF25),
  ),
  SpecialService(
    'books',
    '在线读书',
    '故事不停 · 书签随行',
    'illus_book',
    Icons.menu_book,
    Color(0xFF5779ED),
  ),
  SpecialService(
    'points',
    '在线领积分',
    '任务奖励 · 积分兑换',
    'illus_star',
    Icons.stars,
    Color(0xFFEB8F2F),
  ),
  SpecialService(
    'fragments',
    '在线集碎片',
    '拼齐礼盒 · 解锁好礼',
    'illus_gift_basket',
    Icons.extension,
    Color(0xFFB266E8),
  ),
  SpecialService(
    'running',
    '在线跑步',
    '轻松开跑 · 计时记录',
    'illus_mascot',
    Icons.directions_run,
    Color(0xFF35B79F),
  ),
  SpecialService(
    'health',
    '在线健康',
    '喝水打卡 · 健康小站',
    'illus_gift',
    Icons.favorite,
    Color(0xFFF36D89),
  ),
  SpecialService(
    'sports',
    '在线运动',
    '拉伸训练 · 运动计时',
    'illus_task_pad',
    Icons.fitness_center,
    Color(0xFF558DFF),
  ),
  SpecialService(
    'insurance',
    '在线保险',
    '出行守护 · 方案收藏',
    'illus_coupon',
    Icons.shield,
    Color(0xFF28ACB7),
  ),
  SpecialService(
    'rental',
    '在线租车',
    '城市出行 · 行程计划',
    'illus_red_packet',
    Icons.directions_car_filled,
    Color(0xFF7F7BEF),
  ),
  SpecialService(
    'vip',
    '会员中心',
    '点击就送 · 四重尊享',
    'illus_crown',
    Icons.workspace_premium,
    Color(0xFFD99D33),
  ),
];
String specialCategory(String label) {
  if (label == 'ledger' || label == 'invite' || label == 'hub') return label;
  for (final service in specialServices) {
    if (label == service.id || label == service.title) return service.id;
  }
  if (label.contains('会员') || label.contains('VIP')) return 'vip';
  if (label.contains('短剧') || label.contains('小剧场')) return 'drama';
  if (label.contains('视频')) return 'video';
  if (label.contains('股票') || label.contains('炒股')) return 'stocks';
  if (label.contains('金融') ||
      label.contains('分期') ||
      label.contains('返利') ||
      label == '充值') {
    return 'finance';
  }
  if (label.contains('明细')) return 'ledger';
  if (label.contains('邀请')) return 'invite';
  if (label.contains('金币') || label.contains('签到') || label.contains('夺宝')) {
    return 'coins';
  }
  if (label.contains('积分') || label.contains('商城') || label.contains('礼券')) {
    return 'points';
  }
  return 'hub';
}

/// Finite entry/press animation; no permanent ticker on inactive tabs.
class SpecialMotion extends StatefulWidget {
  final Widget child;
  final int phase;
  const SpecialMotion({super.key, required this.child, this.phase = 0});
  @override
  State<SpecialMotion> createState() => _SpecialMotionState();
}

class _SpecialMotionState extends State<SpecialMotion>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool? _enabled;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled =
        AppScope.maybeOf(context)?.specialEdition == true &&
        AppScope.maybeOf(context)?.reduceMotion != true &&
        !MediaQuery.disableAnimationsOf(context);
    if (enabled != _enabled) {
      _enabled = enabled;
      if (enabled) {
        animation.forward(from: 0);
      } else {
        animation.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerUp: (_) {
      if (_enabled == true) animation.forward(from: 0);
    },
    child: AnimatedBuilder(
      animation: animation,
      child: widget.child,
      builder: (context, child) {
        final wave = _enabled == true && animation.isAnimating
            ? math.sin(animation.value * math.pi * 6) * (1 - animation.value)
            : 0.0;
        return Transform.translate(
          offset: Offset(0, -wave.abs() * 3),
          child: Transform.rotate(
            angle: wave * (widget.phase.isEven ? .025 : -.025),
            child: Transform.scale(scale: 1 + wave.abs() * .025, child: child),
          ),
        );
      },
    ),
  );
  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }
}

bool sameSpecialPlan(dynamic a, dynamic b) =>
    a is Map &&
    b is Map &&
    a['kind'] == b['kind'] &&
    a['name'] == b['name'] &&
    a['detail'] == b['detail'];
