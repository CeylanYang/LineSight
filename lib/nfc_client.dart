import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'collaboration_api.dart';

typedef NfcRequest =
    Future<dynamic> Function(String method, String path, {Object? body});

abstract interface class NfcVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureNfcVault implements NfcVault {
  static const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'linesight_nfc_v1',
      resetOnError: false,
    ),
  );
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
}

class NfcClient {
  final NfcVault vault;
  final NfcRequest send;
  final Ed25519 algorithm = Ed25519();
  NfcClient({
    NfcVault? vault,
    NfcRequest? send,
    String apiUrl = defaultCollaborationApi,
  }) : vault = vault ?? SecureNfcVault(),
       send =
           send ??
           ((method, path, {body}) =>
               CollaborationApi(apiUrl).request(method, path, body: body));
  Future<SimpleKeyPair> key() async {
    var seed = await vault.read('device-key-v1');
    if (seed == null) {
      final pair = await algorithm.newKeyPair();
      seed = base64Encode(await pair.extractPrivateKeyBytes());
      await vault.write('device-key-v1', seed);
    }
    return algorithm.newKeyPairFromSeed(base64Decode(seed));
  }

  Future<Map<String, dynamic>> bindings() async => Map<String, dynamic>.from(
    jsonDecode(await vault.read('bindings-v1') ?? '{}') as Map,
  );
  Future<Map<String, dynamic>> prove(
    NfcRequest request,
    Map<String, dynamic> fields,
  ) async {
    final challenge =
        await request('POST', 'auth/nfc/challenges/', body: fields) as Map;
    final signature = await algorithm.sign(
      utf8.encode(challenge['message'] as String),
      keyPair: await key(),
    );
    final result =
        await request(
              'POST',
              'auth/nfc/complete/',
              body: {
                'challenge_id': challenge['id'],
                'signature': base64Encode(signature.bytes),
                if (fields['refresh_token'] != null)
                  'refresh_token': fields['refresh_token'],
              },
            )
            as Map;
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> bind(
    NfcRequest authenticated, {
    required String cardCode,
    required String technology,
    String label = 'NFC',
  }) async {
    final public = await (await key()).extractPublicKey();
    final result = await prove(authenticated, {
      'action': 'bind',
      'public_key': base64Encode(public.bytes),
      'card_code': cardCode,
      'technology': technology,
      'label': label,
    });
    final saved = await bindings();
    saved[cardCode] = result['id'];
    await vault.write('bindings-v1', jsonEncode(saved));
    return result;
  }

  Future<Map<String, dynamic>> login(String cardCode) async {
    final credential = (await bindings())[cardCode];
    if (credential is! String) {
      throw const CollaborationApiException(401, '请先使用账户登录，并在我的卡片中绑定此卡');
    }
    final result = await prove(send, {
      'action': 'login',
      'credential_id': credential,
      'card_code': cardCode,
    });
    result['credential_id'] = credential;
    return result;
  }

  Future<Map<String, dynamic>> session(
    String action,
    String credential,
    String refresh,
  ) => prove(send, {
    'action': action,
    'credential_id': credential,
    'refresh_token': refresh,
  });
}
