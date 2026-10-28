import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/runtime_content.dart';
import 'package:linesight_flutter/runtime_defaults.dart';

void main() {
  late Map<String, dynamic> config;
  late SimpleKeyPair key;
  late List<int> public;
  setUp(() async {
    config =
        jsonDecode(jsonEncode(defaultRuntimeContent)) as Map<String, dynamic>;
    config['revision'] = 2;
    key = await Ed25519().newKeyPair();
    public = (await key.extractPublicKey()).bytes;
  });
  Future<List<int>> signed() async {
    final payload = utf8.encode(jsonEncode(config));
    return utf8.encode(
      jsonEncode({
        'payload': base64Encode(payload),
        'signature': base64Encode(
          (await Ed25519().sign(payload, keyPair: key)).bytes,
        ),
      }),
    );
  }

  Future<Map<String, dynamic>> verify(List<int> bytes, {int minimum = 1}) =>
      RuntimeContent.verify(
        bytes,
        publicKey: public,
        now: DateTime.utc(2026, 10, 24),
        minimumRevision: minimum,
      );

  test(
    'signed public configuration supports both full procedure definitions',
    () async {
      final value = await verify(await signed());
      expect(value['documents'], hasLength(2));
      expect(value['documents'][1]['sections'][1]['items'], hasLength(4));
    },
  );
  test(
    'tampering, unknown key, expiry and revision downgrade are rejected',
    () async {
      final original = await signed();
      final altered = jsonDecode(utf8.decode(original)) as Map;
      altered['payload'] = base64Encode(utf8.encode('{}'));
      await expectLater(
        verify(utf8.encode(jsonEncode(altered))),
        throwsFormatException,
      );
      public = (await (await Ed25519().newKeyPair()).extractPublicKey()).bytes;
      await expectLater(verify(original), throwsFormatException);
      public = (await key.extractPublicKey()).bytes;
      await expectLater(verify(original, minimum: 3), throwsFormatException);
      config['expires'] = '2026-01-01T00:00:00Z';
      await expectLater(verify(await signed()), throwsFormatException);
    },
  );
  test(
    'foreign or unpinned assets and malformed document/feature data fail closed',
    () async {
      config['documents'][0]['image_url'] =
          'https://example.com/content/${'a' * 64}.png';
      config['documents'][0]['sha256'] = 'a' * 64;
      await expectLater(verify(await signed()), throwsFormatException);
      config['documents'][0]['image_url'] = '/content/${'a' * 64}.png';
      expect((await verify(await signed()))['revision'], 2);
      config['documents'][0]['preparation'] = ['bad row'];
      await expectLater(verify(await signed()), throwsFormatException);
      config = jsonDecode(jsonEncode(defaultRuntimeContent));
      config['features'] = {'document_export': 'yes'};
      await expectLater(verify(await signed()), throwsFormatException);
    },
  );
  test(
    'signed presentation config accepts legacy omission and bounded bundled effects',
    () async {
      config.remove('presentation');
      expect((await verify(await signed()))['presentation'], isNull);
      config['presentation'] = {
        'aurora': {
          'enabled': false,
          'double_press_ms': 360,
          'palette': 'ocean',
          'style': 'subtle',
          'speed': 0.35,
        },
        'login_ad': {'enabled': true, 'seconds': 5, 'asset': 'ai_assistant'},
      };
      expect(
        (await verify(await signed()))['presentation']['aurora']['enabled'],
        false,
      );
      config['presentation']['login_ad']['seconds'] = 6;
      await expectLater(verify(await signed()), throwsFormatException);
      config['presentation']['login_ad']['seconds'] = 5;
      config['presentation']['login_ad']['url'] = 'https://example.com/code';
      await expectLater(verify(await signed()), throwsFormatException);
      config['presentation']['login_ad'].remove('url');
      config['presentation']['aurora']['double_press_ms'] = 0;
      await expectLater(verify(await signed()), throwsFormatException);
    },
  );
}
