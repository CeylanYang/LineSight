import 'package:flutter/material.dart';
import 'l10n_catalog.dart';

/// Translate application-owned text. Never apply this to user-entered data.
String tr(
  BuildContext context,
  String source, [
  List<Object?> args = const [],
]) {
  final english = Localizations.localeOf(context).languageCode == 'en';
  final template = english ? englishMessages[source] ?? source : source;
  return template.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
    final index = int.parse(match[1]!);
    return index < args.length ? '${args[index] ?? ''}' : match[0]!;
  });
}

/// Localize the built-in station labels while preserving names entered by a team.
String trWorkspaceLabel(BuildContext context, String source) {
  if (Localizations.localeOf(context).languageCode == 'en') return source;
  final station = RegExp(
    r'^Station\s+(\d+)$',
    caseSensitive: false,
  ).firstMatch(source);
  if (station != null) return '工位 ${station[1]}';
  final line = RegExp(
    r'^LINE\s+(\d+)$',
    caseSensitive: false,
  ).firstMatch(source);
  if (line != null) return '产线 ${line[1]}';
  return source;
}

class _MessagePattern {
  final String source;
  final RegExp pattern;
  final List<int> positions;
  final String prefix;
  _MessagePattern(this.source, this.pattern, this.positions, this.prefix);
}

final _messagePatterns =
    englishMessages.keys.where((key) => key.contains(RegExp(r'\{\d+\}'))).map((
      key,
    ) {
      final slots = RegExp(r'\{(\d+)\}').allMatches(key).toList();
      var expression = '^';
      var start = 0;
      final positions = <int>[];
      for (final slot in slots) {
        expression += RegExp.escape(key.substring(start, slot.start));
        expression += r'([\s\S]*?)';
        positions.add(int.parse(slot[1]!));
        start = slot.end;
      }
      expression += '${RegExp.escape(key.substring(start))}\$';
      return _MessagePattern(
        key,
        RegExp(expression),
        positions,
        key.substring(0, slots.first.start),
      );
    }).toList()..sort((a, b) => b.source.length.compareTo(a.source.length));

/// Presentation boundary for legacy service errors and progress messages.
/// Stored messages remain canonical; the active locale controls their display.
String trMessage(BuildContext context, String message) {
  if (Localizations.localeOf(context).languageCode != 'en') return message;
  if (englishMessages.containsKey(message)) return englishMessages[message]!;
  for (final item in _messagePatterns) {
    if (!message.startsWith(item.prefix)) continue;
    final match = item.pattern.firstMatch(message);
    if (match == null) continue;
    final args = List<Object?>.filled(
      item.positions.reduce((a, b) => a > b ? a : b) + 1,
      null,
    );
    for (var i = 0; i < item.positions.length; i++) {
      args[item.positions[i]] = match[i + 1];
    }
    if (const {
      '{0} 已保存，共 {1} 条记录。',
      '已取消 {0} 导出，未保存文件。',
      '{0} 未确认保存，请检查文件位置或存储空间。',
    }.contains(item.source)) {
      args[0] = tr(context, '${args[0]}');
    }
    return tr(context, item.source, args);
  }
  return message;
}
