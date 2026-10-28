import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../ui.dart';
import '../../l10n.dart';
import 'special_catalog.dart';
import 'special_activity.dart';

class SpecialVipAvatar extends StatelessWidget {
  final Widget child;
  const SpecialVipAvatar({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    if (!AppScope.of(context).specialEdition) return child;
    final level = specialState(context)['vip'] as int?;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        if (level != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: InkWell(
              onTap: () => openSpecialActivity(context, 'vip'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/checkcheck/vip/${specialLevelAssets[level.clamp(0, 3)]}.svg',
                    width: 20,
                    height: 18,
                  ),
                  Text(
                    tr(context, specialLevels[level.clamp(0, 3)]),
                    key: const ValueKey('special-vip-avatar-badge'),
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF9A6B20),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class SpecialVipBody extends StatefulWidget {
  const SpecialVipBody({super.key});
  @override
  State<SpecialVipBody> createState() => _SpecialVipBodyState();
}

class _SpecialVipBodyState extends State<SpecialVipBody> {
  int selected = 0;
  bool busy = false;
  final benefitsKey = GlobalKey();
  bool initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      selected = (specialState(context)['vip'] as int? ?? 0).clamp(0, 3);
      initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = specialState(context)['vip'] as int?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(context, '这次不用犹豫，会员点击就送'),
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (var i = 0; i < 4; i++)
              ChoiceChip(
                label: Text(tr(context, specialLevels[i])),
                selected: selected == i,
                onSelected: (_) => setState(() => selected = i),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SpecialMotion(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF252746),
                  [
                    const Color(0xFF71899A),
                    const Color(0xFF456CCB),
                    const Color(0xFFB27625),
                    const Color(0xFF713DA8),
                  ][selected],
                ],
              ),
            ),
            child: Column(
              children: [
                SvgPicture.asset(
                  'assets/checkcheck/vip/${specialLevelAssets[selected]}.svg',
                  height: 120,
                ),
                Text(
                  tr(context, specialLevels[selected]),
                  style: const TextStyle(
                    fontSize: 27,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'CHECKCHECK · VIP CLUB',
                  style: TextStyle(
                    color: Colors.white70,
                    letterSpacing: 2,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  active == null
                      ? tr(context, '专属身份，等你点亮')
                      : tr(context, '当前身份：{0}', [
                          tr(context, specialLevels[active.clamp(0, 3)]),
                        ]),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('claim-special-vip'),
                  onPressed: busy
                      ? null
                      : () async {
                          if (active != null && active >= selected) {
                            await Scrollable.ensureVisible(
                              benefitsKey.currentContext!,
                              duration: const Duration(milliseconds: 250),
                            );
                            return;
                          }
                          final requested = selected;
                          setState(() => busy = true);
                          try {
                            await saveSpecial(
                              context,
                              (state) => {
                                ...state,
                                'vip': (state['vip'] as int? ?? -1) > requested
                                    ? state['vip']
                                    : requested,
                              },
                            );
                            if (context.mounted) {
                              toast(context, '会员已到账，专属标识已点亮');
                            }
                          } catch (_) {
                            if (context.mounted) toast(context, '领取失败，请重试');
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  icon: const Icon(Icons.card_giftcard),
                  label: Text(
                    active != null && active >= selected
                        ? tr(context, '已领取 · 再逛逛权益')
                        : tr(context, '免费领取{0}', [
                            tr(context, specialLevels[selected]),
                          ]),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          tr(context, '你的专属权益'),
          key: benefitsKey,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        for (final item in [
          ('专属身份标识', '头像下方展示会员等级', Icons.workspace_premium),
          ('每日会员礼包', '签到、金币和碎片好礼', Icons.redeem),
          ('小剧场与书房', '剧集收藏，阅读进度随时续上', Icons.movie),
          ('出行好礼', '保险方案、租车行程一站收藏', Icons.local_offer),
        ])
          Card(
            child: ListTile(
              leading: Icon(item.$3, color: const Color(0xFFD49A39)),
              title: Text(tr(context, item.$1)),
              subtitle: Text(tr(context, item.$2)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                if (item.$1 == '专属身份标识') {
                  toast(
                    context,
                    active == null
                        ? tr(context, '先领取会员，头像下就会亮起专属标识')
                        : tr(context, '当前身份：{0}', [
                            tr(context, specialLevels[active.clamp(0, 3)]),
                          ]),
                  );
                  return;
                }
                openSpecialActivity(
                  context,
                  item.$1 == '每日会员礼包'
                      ? 'coins'
                      : item.$1 == '出行好礼'
                      ? 'rental'
                      : item.$1 == '小剧场与书房'
                      ? 'drama'
                      : 'vip',
                );
              },
            ),
          ),
      ],
    );
  }
}
