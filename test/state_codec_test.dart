import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/state_codec.dart';

String manifest(int parts, int units, String hash) =>
    '$stateChunkMarker${jsonEncode({'parts': parts, 'units': units, 'sha256': hash})}';

List<String> chunksOf(PreparedStateValue plan, String source) => [
  for (var part = 0; part < plan.chunkEnds.length; part++)
    plan.chunk(source, part),
];

void main() {
  test(
    'small values remain byte-exact unchunked cells including the boundary',
    () {
      for (final value in ['', '{"dark":true}', '质' * stateChunkUnits]) {
        final result = prepareStateValue(value);
        expect(result.stored, value);
        expect(result.chunkEnds, isEmpty);
      }
    },
  );
  test('chunk plan preserves version-2 manifest and complete UTF-8 digest', () {
    final value = '质😀\n,"data"' * 100000;
    final result = prepareStateValue(value);
    final expectedHash = sha256.convert(utf8.encode(value)).toString();
    expect(
      result.stored,
      manifest(result.chunkEnds.length, value.length, expectedHash),
    );
    final metadata = StateChunkManifest.parse(result.stored);
    expect(metadata.parts, result.chunkEnds.length);
    expect(metadata.units, value.length);
    expect(metadata.sha256, expectedHash);
    expect(
      assembleStateChunks(StateChunks(metadata, chunksOf(result, value))),
      value,
    );
    expect(() => result.chunkEnds.add(1), throwsUnsupportedError);
  });
  test('chunk edges never split supplementary Unicode characters', () {
    final value =
        '${'a' * (stateChunkUnits - 1)}😀${'b' * (stateChunkUnits - 1)}𠀋末尾';
    final result = prepareStateValue(value);
    expect(chunksOf(result, value).first.length, stateChunkUnits - 1);
    for (final chunk in chunksOf(result, value)) {
      expect(chunk.length, lessThanOrEqualTo(stateChunkUnits));
      expect(utf8.decode(utf8.encode(chunk)), chunk);
    }
    expect(chunksOf(result, value).join(), value);
    expect(
      assembleStateChunks(
        StateChunks(
          StateChunkManifest.parse(result.stored),
          chunksOf(result, value),
        ),
      ),
      value,
    );
  });
  test(
    'write preparation and read verification cross the worker boundary exactly',
    () async {
      final value = '多字节 😀' * 200000;
      final prepared = await compute(prepareStateValue, value);
      final read = await compute(
        assembleStateChunks,
        StateChunks(
          StateChunkManifest.parse(prepared.stored),
          chunksOf(prepared, value),
        ),
      );
      expect(read, value);
    },
  );
  test('corrupt count, content, size and checksum reject assembly', () {
    final value = 'a' * (stateChunkUnits * 3 + 7);
    final prepared = prepareStateValue(value);
    final metadata = StateChunkManifest.parse(prepared.stored);
    for (final chunks in [
      chunksOf(prepared, value).take(2).toList(),
      [...chunksOf(prepared, value), 'extra'],
      [
        'b${chunksOf(prepared, value).first.substring(1)}',
        ...chunksOf(prepared, value).skip(1),
      ],
      ['a' * (stateChunkUnits + 1), ...chunksOf(prepared, value).skip(1)],
    ]) {
      expect(
        () => assembleStateChunks(StateChunks(metadata, chunks)),
        throwsFormatException,
      );
    }
    final wrongHash = StateChunkManifest.parse(
      manifest(metadata.parts, metadata.units, '0' * 64),
    );
    expect(
      () => assembleStateChunks(
        StateChunks(wrongHash, chunksOf(prepared, value)),
      ),
      throwsFormatException,
    );
    final wrongUnits = StateChunkManifest.parse(
      manifest(metadata.parts, metadata.units - 1, metadata.sha256),
    );
    expect(
      () => assembleStateChunks(
        StateChunks(wrongUnits, chunksOf(prepared, value)),
      ),
      throwsFormatException,
    );
  });
  test('invalid manifests fail before any chunks are requested', () {
    final hash = '0' * 64;
    for (final stored in [
      'wrong marker',
      '$stateChunkMarker{',
      '$stateChunkMarker[]',
      '$stateChunkMarker{}',
      manifest(0, 0, hash),
      manifest(2, 1, hash),
      manifest(1, stateChunkUnits + 1, hash),
      manifest(1, 1, 'wrong'),
      '$stateChunkMarker${jsonEncode({'parts': 1.0, 'units': 1, 'sha256': hash})}',
    ]) {
      expect(() => StateChunkManifest.parse(stored), throwsFormatException);
    }
  });
}
