import 'package:flutter/material.dart';
import 'ui.dart';

Future<void> chooseLanguage(BuildContext context) async {
  final store = AppScope.of(context);
  final language = await showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('语言 / Language'),
      children: [
        for (final entry in {'zh': '中文', 'en': 'English'}.entries)
          SimpleDialogOption(
            key: ValueKey('language-option-${entry.key}'),
            onPressed: () => Navigator.pop(dialogContext, entry.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(entry.value)),
                  if (store.languageCode == entry.key)
                    const Icon(Icons.check_rounded),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  if (language != null && context.mounted) {
    await perform(context, () => store.setLanguage(language));
  }
}

/// Self-named language options remain readable in either interface language.
class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return PopupMenuButton<String>(
      key: const ValueKey('language-selector'),
      tooltip: '语言 / Language',
      initialValue: store.languageCode,
      onSelected: (language) =>
          perform(context, () => store.setLanguage(language)),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'zh',
          checked: store.languageCode == 'zh',
          child: const Text('中文'),
        ),
        CheckedPopupMenuItem(
          value: 'en',
          checked: store.languageCode == 'en',
          child: const Text('English'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 20),
            const SizedBox(width: 8),
            Text(store.languageCode == 'en' ? 'English' : '中文'),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
