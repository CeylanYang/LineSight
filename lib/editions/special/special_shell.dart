import 'package:flutter/material.dart';
import '../../l10n.dart';
import '../../runtime_content.dart';

/// Special-edition canvas. Business pages, identity and navigation stay shared.
class SpecialEditionHeader extends StatelessWidget {
  const SpecialEditionHeader({super.key});
  @override
  Widget build(BuildContext context) {
    final configuration = RuntimeContent.instance.data['special'] as Map? ?? {};
    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        color: const Color(0xFF123348),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${configuration['title'] ?? 'LineSight'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              tr(context, '特供版'),
              style: const TextStyle(color: Color(0xFF9AE2D0), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
