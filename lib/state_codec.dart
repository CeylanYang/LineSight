import 'dart:convert';
import 'package:crypto/crypto.dart';

const stateChunkUnits = 128 * 1024;
const stateChunkMarker = 'LineSightState/2:';

class _HashResult implements Sink<Digest> {
  Digest? digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}

/// A bounded-cell write plan, prepared without a database or UI dependency.
class PreparedStateValue {
  final String stored;
  final List<int> chunkEnds;
  PreparedStateValue._(this.stored, List<int> chunkEnds)
    : chunkEnds = List.unmodifiable(chunkEnds);

  // Retain only offsets. The writer materializes at most one batch of chunks.
  String chunk(String source, int part) =>
      source.substring(part == 0 ? 0 : chunkEnds[part - 1], chunkEnds[part]);
}

class StateChunkManifest {
  final int parts, units;
  final String sha256;
  const StateChunkManifest._(this.parts, this.units, this.sha256);

  factory StateChunkManifest.parse(String stored) {
    if (!stored.startsWith(stateChunkMarker)) {
      throw const FormatException('本机数据分块标记无效');
    }
    final value = jsonDecode(stored.substring(stateChunkMarker.length));
    if (value is! Map ||
        value['parts'] is! int ||
        value['units'] is! int ||
        value['sha256'] is! String) {
      throw const FormatException('本机数据分块信息无效');
    }
    final parts = value['parts'] as int, units = value['units'] as int;
    final hash = value['sha256'] as String;
    if (parts < 1 ||
        units < 1 ||
        parts > units ||
        units > parts * stateChunkUnits ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('本机数据分块信息无效');
    }
    return StateChunkManifest._(parts, units, hash);
  }
}

PreparedStateValue prepareStateValue(String value) {
  if (value.length <= stateChunkUnits) {
    return PreparedStateValue._(value, const []);
  }
  final result = _HashResult();
  final hash = sha256.startChunkedConversion(result);
  final ends = <int>[];
  var index = 0;
  while (index < value.length) {
    var end = (index + stateChunkUnits).clamp(0, value.length);
    if (end < value.length &&
        value.codeUnitAt(end - 1) >= 0xD800 &&
        value.codeUnitAt(end - 1) <= 0xDBFF) {
      end--;
    }
    final chunk = value.substring(index, end);
    hash.add(utf8.encode(chunk));
    ends.add(end);
    index = end;
  }
  hash.close();
  return PreparedStateValue._(
    '$stateChunkMarker${jsonEncode({'parts': ends.length, 'units': value.length, 'sha256': result.digest.toString()})}',
    ends,
  );
}

class StateChunks {
  final StateChunkManifest manifest;
  final List<String> chunks;
  StateChunks(this.manifest, List<String> chunks)
    : chunks = List.unmodifiable(chunks);
}

/// Validate and join in a worker. UTF-8 bytes are hashed one bounded chunk at a
/// time; no full encoded byte array is allocated.
String assembleStateChunks(StateChunks input) {
  if (input.chunks.length != input.manifest.parts) {
    throw const FormatException('本机数据分块缺失');
  }
  final result = _HashResult(), output = StringBuffer();
  final hash = sha256.startChunkedConversion(result);
  for (final chunk in input.chunks) {
    if (chunk.length > stateChunkUnits) throw const FormatException('本机数据分块过大');
    output.write(chunk);
    hash.add(utf8.encode(chunk));
  }
  hash.close();
  if (output.length != input.manifest.units ||
      result.digest.toString() != input.manifest.sha256) {
    throw const FormatException('本机数据分块校验失败');
  }
  return output.toString();
}
