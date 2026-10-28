import '../../screens/settings.dart' show MembersPage;
import '../edition_brand.dart';
import 'special_activity.dart';
import '../../cloud_account.dart';
import '../../screens/cloud_business.dart';
import 'package:flutter/material.dart';
import '../../l10n.dart';
import '../../ui.dart';
import '../../screens/dashboard.dart';
import 'special_workbench.dart';

/// Special-edition canvas. Business pages, identity and navigation stay shared.
class SpecialEditionHeader extends StatelessWidget {
  const SpecialEditionHeader({super.key});

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF4F8FF),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 14, 8),
        child: SizedBox(
          height: 40,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 361,
              child: Row(
                children: [
                  Image.asset(
                    specialLogoAsset,
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            specialBrand,
                            style: TextStyle(
                              fontSize: 19,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.4,
                              color: Color(0xFF122036),
                            ),
                          ),
                          Text(
                            tr(context, specialBrandSubtitle),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF8B96AC),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  InkWell(
                    onTap: () => openPage(
                      context,
                      context.getInheritedWidgetOfExactType<CloudScope>() !=
                              null
                          ? const CloudTeamPage()
                          : const MembersPage(),
                    ),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Color(0xFF8B96AC),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => openSpecialActivity(context, '积分明细'),
                    child: const _PointsPill(),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => openPage(
                      context,
                      context.getInheritedWidgetOfExactType<CloudScope>() !=
                              null
                          ? const CloudNotificationsPage()
                          : const AlertsPage(),
                    ),
                    child: const SizedBox(
                      width: 38,
                      height: 38,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.notifications_none_rounded,
                            size: 24,
                            color: Color(0xFF1B2437),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0xFFF04438),
                                shape: BoxShape.circle,
                              ),
                              child: SizedBox(width: 7, height: 7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PointsPill extends StatelessWidget {
  const _PointsPill();

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xFFE9EFF9)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D1B3C6B),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/checkcheck/illustrations/illus_coin.png',
          width: 18,
          height: 18,
        ),
        const SizedBox(width: 4),
        Text(
          specialBalance(context),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1B2437),
          ),
        ),
        const SizedBox(width: 3),
        Text(
          tr(context, '积分'),
          style: const TextStyle(fontSize: 10, color: Color(0xFF8B96AC)),
        ),
        const SizedBox(width: 5),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFF3D9B4)),
            color: const Color(0xFFFFFAF2),
          ),
          child: const Icon(
            Icons.add_rounded,
            size: 13,
            color: Color(0xFFB57A24),
          ),
        ),
      ],
    ),
  );
}
