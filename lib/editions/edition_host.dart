import 'package:flutter/material.dart';
import '../l10n.dart';
import '../ui.dart';
import 'special/special_shell.dart';

class EditionHost extends StatelessWidget {
  final Widget child;
  const EditionHost({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final special = AppScope.of(context).specialEdition;
    return Column(
      children: [
        if (special) const SpecialEditionHeader(),
        Expanded(
          key: const ValueKey('shared-edition-workspace'),
          child: MediaQuery(
            // The header already clears the status bar; nested pages must not
            // inset for it a second time. The wrapper stays in both editions so
            // toggling never rebuilds the workspace subtree.
            data: special
                ? MediaQuery.of(context).removePadding(removeTop: true)
                : MediaQuery.of(context),
            child: child,
          ),
        ),
      ],
    );
  }
}

class EditionSwitch extends StatelessWidget {
  const EditionSwitch({super.key});
  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return SwitchListTile(
      key: const ValueKey('special-edition-switch'),
      secondary: const Icon(Icons.auto_awesome_outlined, color: blue),
      title: Text(tr(context, '特供版')),
      subtitle: Text(tr(context, store.specialEdition ? '特供版' : '大字版')),
      value: store.specialEdition,
      onChanged: (value) =>
          perform(context, () => store.setSpecialEdition(value)),
    );
  }
}
