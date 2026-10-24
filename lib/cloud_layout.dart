import 'package:flutter/material.dart';
import 'l10n.dart';
import 'ui.dart';

/// Shared layout for the cloud workspace. Business authorization stays in pages.
class CloudSectionTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  const CloudSectionTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: TextButton(
              onPressed: () => onSelected(i),
              style: TextButton.styleFrom(
                foregroundColor: selected == i ? blue : muted,
                backgroundColor: selected == i
                    ? blue.withValues(alpha: .09)
                    : Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                tr(context, labels[i]),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected == i ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class CloudShortcut {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const CloudShortcut(this.label, this.icon, this.onTap, {this.color = blue});
}

class CloudShortcutGrid extends StatelessWidget {
  final List<CloudShortcut> entries;
  final bool primary;
  const CloudShortcutGrid({
    super.key,
    required this.entries,
    this.primary = false,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final english = Localizations.localeOf(context).languageCode == 'en';
      final columns = constraints.maxWidth > 660
          ? 8
          : scale > 1.3 || english && constraints.maxWidth < 360
          ? 3
          : 4;
      final width = constraints.maxWidth / columns;
      return Wrap(
        children: [
          for (final item in entries)
            SizedBox(
              width: width,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: item.onTap,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: primary ? 12 : 10,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: primary ? 46 : 36,
                          height: primary ? 46 : 36,
                          decoration: BoxDecoration(
                            color: primary
                                ? item.color
                                : item.color.withValues(alpha: .09),
                            borderRadius: BorderRadius.circular(
                              primary ? 14 : 11,
                            ),
                          ),
                          child: Icon(
                            item.icon,
                            color: primary ? Colors.white : item.color,
                            size: primary ? 25 : 22,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          tr(context, item.label),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: primary ? 13 : 12,
                            fontWeight: primary
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
