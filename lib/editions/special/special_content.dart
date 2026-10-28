import 'package:flutter/material.dart';
import 'special_activity.dart';
import '../../l10n.dart';

class SpecialSectionScope extends InheritedWidget {
  final String title;
  const SpecialSectionScope({
    super.key,
    required this.title,
    required super.child,
  });
  static String titleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SpecialSectionScope>()
          ?.title ??
      '工作专区';
  @override
  bool updateShouldNotify(SpecialSectionScope oldWidget) =>
      title != oldWidget.title;
}

Widget specialTabIcon(int index, bool active) => Image.asset(
  'assets/checkcheck/icons/tab_${['workbench', 'production', 'inspect', 'config', 'me'][index]}${active ? '_active' : ''}.png',
  width: 26,
  height: 26,
);

class SpecialPromotionStrip extends StatelessWidget {
  final String title;
  final bool membership;
  const SpecialPromotionStrip({
    super.key,
    required this.title,
    this.membership = false,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openSpecialActivity(context, membership ? '会员好礼' : '新人好礼'),
        child: Ink(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(
                'assets/checkcheck/backgrounds/bg_banner_${membership ? 'vip' : 'newbie'}.png',
              ),
              fit: BoxFit.cover,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      membership
                          ? tr(context, '会员专享 · 每天都有新惊喜')
                          : tr(context, '{0} · 好礼抢先看', [
                              trMessage(context, title),
                            ]),
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: membership
                            ? Colors.white
                            : const Color(0xFF473019),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      membership
                          ? tr(context, '专属礼券 / 热门推荐 / 每日福利')
                          : tr(context, '签到领金币 · 邀请有礼 · 点一下开宝箱'),
                      style: TextStyle(
                        fontSize: 11,
                        color: membership
                            ? Colors.white
                            : const Color(0xFF975729),
                      ),
                    ),
                  ],
                ),
              ),
              Image.asset(
                'assets/checkcheck/illustrations/${membership ? 'illus_crown' : 'illus_gift'}.png',
                width: 62,
                height: 58,
              ),
              const Icon(Icons.chevron_right, color: Colors.orange),
            ],
          ),
        ),
      ),
    ),
  );
}

class SpecialPromotionShortcuts extends StatelessWidget {
  const SpecialPromotionShortcuts({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        for (final item in [
          ('金币夺宝', 'illus_coin'),
          ('视频积分', 'illus_play'),
          ('邀请有礼', 'illus_invite'),
          ('返利专场', 'illus_money_bag'),
        ])
          Expanded(
            child: InkWell(
              onTap: () => openSpecialActivity(context, item.$1),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE6ECFB)),
                ),
                child: Column(
                  children: [
                    Image.asset(
                      'assets/checkcheck/illustrations/${item.$2}.png',
                      height: 30,
                      width: 36,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(context, item.$1),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
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

class SpecialDiscoveryShelf extends StatelessWidget {
  const SpecialDiscoveryShelf({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 12),
      Row(
        children: [
          const Icon(Icons.movie_creation_outlined, color: Color(0xFFF4668B)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tr(context, '金币小短剧 · 看看再开工'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
          TextButton(
            onPressed: () => openSpecialActivity(context, '视频积分'),
            child: Text(tr(context, '更多 ›')),
          ),
        ],
      ),
      SizedBox(
        height: 136,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final item in [
              ('质检员的一天', 'thumb_01_inspector_day'),
              ('那些离谱的缺陷', 'thumb_02_defect'),
              ('AI 如何识别缺陷', 'thumb_03_ai'),
              ('工厂里的治愈瞬间', 'thumb_04_healing'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => openSpecialActivity(context, '视频积分'),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 120,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            'assets/checkcheck/thumbs/${item.$2}.png',
                            fit: BoxFit.cover,
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0xD9000000)],
                              ),
                            ),
                          ),
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                          Positioned(
                            left: 8,
                            right: 6,
                            bottom: 10,
                            child: Text(
                              tr(context, item.$1),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
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
      ),
      const SizedBox(height: 12),
      const SpecialPromotionStrip(title: '今日好物榜', membership: true),
      Material(
        color: const Color(0xFFFFF2DA),
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          leading: Image.asset(
            'assets/checkcheck/illustrations/illus_chart_up.png',
            width: 42,
          ),
          title: Text(tr(context, '广告精选 · 生产好物一站看')),
          subtitle: Text(tr(context, '设备养护 · 工位收纳 · 热门礼包')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => openSpecialActivity(context, '广告精选'),
        ),
      ),
    ],
  );
}
