import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/ota_update.dart';

void main() {
  late SimpleKeyPair key;
  late List<int> public;
  final now = DateTime.utc(2026, 10, 24);
  late Map<String, dynamic> manifest;
  setUp(() async {
    key = await Ed25519().newKeyPair();
    public = (await key.extractPublicKey()).bytes;
    manifest = {
      'schema': 1,
      'track': 'preview',
      'base': 8078,
      'abi': 'x86_64',
      'sequence': 2,
      'action': 'patch',
      'expires': '2026-12-31T00:00:00Z',
      'sha256': 'a' * 64,
      'size': 100,
    };
  });
  Future<List<int>> envelope() async {
    final bytes = utf8.encode(jsonEncode(manifest));
    final signature = await Ed25519().sign(bytes, keyPair: key);
    return utf8.encode(
      jsonEncode({
        'payload': base64Encode(bytes),
        'signature': base64Encode(signature.bytes),
      }),
    );
  }

  Future<OtaManifest> verify(List<int> bytes, {int minimum = 0}) =>
      OtaManifest.verify(
        bytes,
        publicKey: public,
        track: 'preview',
        base: 8078,
        abi: 'x86_64',
        minimumSequence: minimum,
        now: now,
      );

  test('accepts signed code bound to the installed base and ABI', () async {
    final result = await verify(await envelope());
    expect(result.sequence, 2);
    expect(result.version, 'ota-2');
    expect(result.rollback, false);
  });
  test('rejects altered metadata and unknown signing keys', () async {
    final bytes = await envelope();
    final altered = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    manifest['size'] = 90;
    altered['payload'] = base64Encode(utf8.encode(jsonEncode(manifest)));
    await expectLater(
      verify(utf8.encode(jsonEncode(altered))),
      throwsFormatException,
    );
    public = (await (await Ed25519().newKeyPair()).extractPublicKey()).bytes;
    await expectLater(verify(bytes), throwsFormatException);
  });
  test('rejects other teams of builds, ABIs and expired metadata', () async {
    for (final entry in {
      'track': 'production',
      'base': 8077,
      'abi': 'arm64-v8a',
      'expires': '2026-10-01T00:00:00Z',
      'size': 100000000,
      'sha256': '../bad',
    }.entries) {
      final before = manifest[entry.key];
      manifest[entry.key] = entry.value;
      await expectLater(
        verify(await envelope()),
        throwsFormatException,
        reason: entry.key,
      );
      manifest[entry.key] = before;
    }
  });
  test('replay cannot override a newer installed command', () async {
    await expectLater(
      verify(await envelope(), minimum: 2),
      throwsFormatException,
    );
    await expectLater(
      verify(await envelope(), minimum: 3),
      throwsFormatException,
    );
  });
  test('rollback is also signed and must advance sequence', () async {
    manifest['action'] = 'rollback';
    manifest.remove('sha256');
    manifest.remove('size');
    expect((await verify(await envelope())).rollback, true);
    await expectLater(
      verify(await envelope(), minimum: 2),
      throwsFormatException,
    );
  });
}
