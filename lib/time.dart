// Persist instants in UTC; use local calendar dates only at the UI boundary.
final _timestamp = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?([Zz]|[+-]\d{2}:?\d{2})?$',
);

bool hasTimeZone(String source) =>
    RegExp(r'([Zz]|[+-]\d{2}:?\d{2})$').hasMatch(source);

DateTime parseInstant(
  String source, {
  int? legacyOffsetMinutes,
  bool localGapCompatibility = false,
}) {
  final match = _timestamp.firstMatch(source);
  if (match == null || match.end != source.length) {
    throw const FormatException('时间格式无效');
  }
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i]!)];
  final fraction = int.parse((match[7] ?? '').padRight(6, '0'));
  final wall = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
    fraction ~/ 1000,
    fraction % 1000,
  );
  if (parts[0] < 1 ||
      wall.year != parts[0] ||
      wall.month != parts[1] ||
      wall.day != parts[2] ||
      wall.hour != parts[3] ||
      wall.minute != parts[4] ||
      wall.second != parts[5]) {
    throw const FormatException('时间包含不存在的日期或时刻');
  }
  final zone = match[8];
  int? offset = legacyOffsetMinutes;
  if (zone != null) {
    if (zone.toUpperCase() == 'Z') {
      offset = 0;
    } else {
      final digits = zone.substring(1).replaceAll(':', '');
      final hours = int.parse(digits.substring(0, 2));
      final minutes = int.parse(digits.substring(2));
      if (hours > 14 || minutes > 59 || (hours == 14 && minutes != 0)) {
        throw const FormatException('时间的 UTC 偏移无效');
      }
      offset = (hours * 60 + minutes) * (zone.startsWith('-') ? -1 : 1);
    }
  }
  if (offset != null) {
    if (offset < -840 || offset > 840) {
      throw const FormatException('UTC 偏移超出范围');
    }
    return _boundedInstant(wall.subtract(Duration(minutes: offset)));
  }
  // Compatibility for old local timestamps: the device's historical zone rules.
  final local = DateTime(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
    fraction ~/ 1000,
    fraction % 1000,
  );
  if (!localGapCompatibility &&
      (local.year != wall.year ||
          local.month != wall.month ||
          local.day != wall.day ||
          local.hour != wall.hour ||
          local.minute != wall.minute)) {
    throw const FormatException('旧时间在本机时区不存在，请选择来源的固定 UTC 偏移');
  }
  return _boundedInstant(local.toUtc());
}

DateTime _boundedInstant(DateTime instant) {
  if (instant.year < 1 || instant.year > 9999) {
    throw const FormatException('UTC 时间超出支持的年份范围');
  }
  return instant;
}

String instantJson(DateTime value) => value.toUtc().toIso8601String();

String utcOffsetLabel(int minutes) {
  final absolute = minutes.abs();
  return 'UTC${minutes < 0 ? '-' : '+'}'
      '${(absolute ~/ 60).toString().padLeft(2, '0')}:'
      '${(absolute % 60).toString().padLeft(2, '0')}';
}

String stamp(DateTime instant) {
  final date = instant.toUtc().toLocal();
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String zonedStamp(DateTime instant, {bool precise = false}) {
  final local = instant.toUtc().toLocal();
  final clock = precise
      ? local.toIso8601String().replaceFirst('T', ' ')
      : stamp(instant);
  return '$clock ${utcOffsetLabel(local.timeZoneOffset.inMinutes)}';
}

DateTime localDay(DateTime instant, [int dayOffset = 0]) {
  final local = instant.toUtc().toLocal();
  return DateTime(local.year, local.month, local.day + dayOffset);
}

bool sameLocalDay(DateTime a, DateTime b) {
  final x = a.toUtc().toLocal(), y = b.toUtc().toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

bool inLocalDateRange(DateTime instant, DateTime first, DateTime last) =>
    !instant.isBefore(localDay(first)) && instant.isBefore(localDay(last, 1));

// Only known time fields are touched. Audit prose and recipe snapshots are data.
int normalizeTimeField(
  Map<String, dynamic> row,
  String field, {
  int? legacyOffsetMinutes,
  bool localGapCompatibility = false,
}) {
  final value = row[field];
  if (value == null) return 0;
  final source = value as String;
  row[field] = instantJson(
    parseInstant(
      source,
      legacyOffsetMinutes: legacyOffsetMinutes,
      localGapCompatibility: localGapCompatibility,
    ),
  );
  return hasTimeZone(source) ? 0 : 1;
}

int normalizeWorkspaceTimes(
  Map<String, dynamic> workspace, {
  int? legacyOffsetMinutes,
  bool localGapCompatibility = false,
}) {
  var count = 0;
  for (final row in workspace['inspections'] as List) {
    count += normalizeTimeField(
      row,
      'at',
      legacyOffsetMinutes: legacyOffsetMinutes,
      localGapCompatibility: localGapCompatibility,
    );
    count += normalizeTimeField(
      row,
      'reviewedAt',
      legacyOffsetMinutes: legacyOffsetMinutes,
      localGapCompatibility: localGapCompatibility,
    );
  }
  for (final row in workspace['audits'] as List) {
    count += normalizeTimeField(
      row,
      'at',
      legacyOffsetMinutes: legacyOffsetMinutes,
      localGapCompatibility: localGapCompatibility,
    );
  }
  return count;
}
