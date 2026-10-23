import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/nfc_client.dart';
import 'package:linesight_flutter/nfc_reader.dart';
import 'package:linesight_flutter/screens/cloud_nfc.dart';
import 'package:linesight_flutter/screens/cloud_shell.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_access_ui_test.dart' show AccessAccount;

class MemoryNfcVault implements NfcVault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class WaitingCardReader extends NfcCardReader {
  final completion = Completer<NfcCardRead?>();
  int scans = 0, stops = 0;
  @override
  Future<NfcCardRead?> scan({bool initializeEmptyCard = false}) {
    scans++;
    return completion.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (!completion.isCompleted) completion.complete(null);
  }
}

class CardAccount extends AccessAccount {
  final requests = <String>[];
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    requests.add('$method $path');
    return jsonDecode(
      File(
        'docs/product/linesight/acceptance/nfc-batch/live-card-list.json',
      ).readAsStringSync(),
    );
  }
}

void main() {
  test(
    'NFC refresh and logout use the cloud proof endpoint instead of browser login',
    () async {
      final vault = MemoryNfcVault();
      final actions = <String>[];
      final client = NfcClient(
        vault: vault,
        send: (method, path, {body}) async {
          if (path.endsWith('challenges/')) {
            actions.add((body as Map)['action'] as String);
            return {
              'id': 'session-proof',
              'message': 'one-use cloud challenge',
            };
          }
          return {
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'expires_in': 300,
          };
        },
      );
      final gateway = KeycloakIdentityGateway(nfcClient: client);
      final previous = CloudTokens(
        'access',
        'refresh',
        'linesight-nfc',
        DateTime.now(),
        nfcCredential: 'binding-one',
      );
      final next = await gateway.refresh(previous);
      expect(next.nfcCredential, 'binding-one');
      expect(next.refresh, 'new-refresh');
      expect(await gateway.signOut(next), isTrue);
      expect(actions, ['refresh', 'logout']);
    },
  );
  test(
    'revoked NFC session can still be cleared locally on sign out',
    () async {
      final client = NfcClient(
        vault: MemoryNfcVault(),
        send: (method, path, {body}) async =>
            throw const CollaborationApiException(401, '卡片绑定已失效'),
      );
      final gateway = KeycloakIdentityGateway(nfcClient: client);
      expect(
        await gateway.signOut(
          CloudTokens(
            'access',
            'refresh',
            'linesight-nfc',
            DateTime.now(),
            nfcCredential: 'binding-one',
          ),
        ),
        isTrue,
      );
    },
  );
  test(
    'server challenge is signed with persisted device key, no card code stored',
    () async {
      final vault = MemoryNfcVault();
      final signatures = <String>[];
      String? public;
      final client = NfcClient(
        vault: vault,
        send: (method, path, {body}) async {
          if (path.endsWith('challenges/')) {
            final fields = body as Map;
            public ??= fields['public_key'] as String?;
            return {
              'id': 'test-challenge',
              'message': 'server-owned one-use message ${fields['action']}',
            };
          }
          final fields = body as Map;
          signatures.add(fields['signature'] as String);
          final valid = await Ed25519().verify(
            utf8.encode('server-owned one-use message bind'),
            signature: Signature(
              base64Decode(signatures.last),
              publicKey: SimplePublicKey(
                base64Decode(public!),
                type: KeyPairType.ed25519,
              ),
            ),
          );
          expect(valid, isTrue);
          return {'id': 'binding-one'};
        },
      );
      final result = await client.bind(
        client.send,
        cardCode: 'a' * 64,
        technology: 'NfcA, IsoDep',
      );
      expect(result['id'], 'binding-one');
      expect(vault.values['device-key-v1'], isNotEmpty);
      expect(
        vault.values.values.any((value) => value.contains('raw-card-uid')),
        isFalse,
      );
      final next = NfcClient(vault: vault);
      expect(
        await (await next.key()).extractPrivateKeyBytes(),
        await (await client.key()).extractPrivateKeyBytes(),
      );
    },
  );
  test(
    'unknown card fails before network, known card uses server login and preserves credential',
    () async {
      final vault = MemoryNfcVault();
      int calls = 0;
      final client = NfcClient(
        vault: vault,
        send: (method, path, {body}) async {
          calls++;
          if (path.endsWith('challenges/')) {
            expect((body as Map)['credential_id'], 'binding-one');
            return {'id': 'login-one', 'message': 'server nonce for login'};
          }
          return {
            'access_token': 'access',
            'refresh_token': 'refresh',
            'expires_in': 300,
          };
        },
      );
      await expectLater(client.login('unknown'), throwsException);
      expect(calls, 0);
      await vault.write('bindings-v1', jsonEncode({'known': 'binding-one'}));
      final result = await client.login('known');
      expect(calls, 2);
      expect(result['credential_id'], 'binding-one');
      final tokens = CloudTokens.fromNfc(result, 'binding-one');
      final restored = CloudTokens.fromJson(tokens.toJson());
      expect(restored.clientId, 'linesight-nfc');
      expect(restored.nfcCredential, 'binding-one');
      expect(restored.refresh, 'refresh');
    },
  );
  test(
    'refresh uses device proof and signed server challenge before forwarding token',
    () async {
      final vault = MemoryNfcVault();
      final bodies = <Map>[];
      final client = NfcClient(
        vault: vault,
        send: (method, path, {body}) async {
          bodies.add(body as Map);
          if (path.endsWith('challenges/')) {
            return {
              'id': 'refresh-one',
              'message': 'refresh nonce bound to old-token',
            };
          }
          return {
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'expires_in': 300,
          };
        },
      );
      final result = await client.session(
        'refresh',
        'binding-one',
        'old-token',
      );
      expect(bodies.first['action'], 'refresh');
      expect(bodies.last['refresh_token'], 'old-token');
      expect(bodies.last['signature'], isNotEmpty);
      expect(result['refresh_token'], 'new-refresh');
    },
  );
  test('UID and initialized NDEF identifiers are domain-separated', () {
    final uid = nfcCardCode([1, 2, 3, 4]);
    expect(uid.length, 64);
    expect(uid, nfcCardCode([1, 2, 3, 4]));
    expect(uid, isNot(nfcCardCode([], ndef: [1, 2, 3, 4])));
  });
  Future<void> show(
    WidgetTester tester,
    Widget page,
    CardAccount account,
    AppStore store, {
    String language = 'en',
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          fontFamily: 'EvidenceFont',
          colorScheme: appTheme(false).colorScheme,
        ),
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(account: account, child: child!),
        ),
        home: page,
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets(
    'leaving scanning stops NFC and late discovery cannot complete navigation',
    (tester) async {
      final account = CardAccount();
      final store = AppStore()..ready = true;
      final reader = WaitingCardReader();
      addTearDown(account.dispose);
      addTearDown(store.dispose);
      await show(
        tester,
        CloudNfcScanPage(reader: reader),
        account,
        store,
        settle: false,
      );
      expect(reader.scans, 1);
      await show(tester, const Scaffold(body: Text('Closed')), account, store);
      expect(reader.stops, greaterThanOrEqualTo(1));
      expect(reader.completion.isCompleted, isTrue);
    },
  );
  testWidgets('cards do not survive an account scope switch', (tester) async {
    final account = CardAccount();
    final store = AppStore()..ready = true;
    addTearDown(account.dispose);
    addTearDown(store.dispose);
    await show(tester, const CloudNfcCardsPage(), account, store);
    expect(find.text('LineSight · 01'), findsOneWidget);
    account.profile = {...account.profile!, 'id': 'other-user'};
    account.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('LineSight · 01'), findsNothing);
  });
  for (final language in ['zh', 'en']) {
    testWidgets('card pages $language fit 360px and save desktop PNG', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await (FontLoader('EvidenceFont')..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
              ),
            ),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final account = CardAccount();
      final store = AppStore()
        ..ready = true
        ..preferences = {'reduceMotion': true, 'glass': false};
      addTearDown(account.dispose);
      addTearDown(store.dispose);
      await show(
        tester,
        const CloudNfcCardsPage(),
        account,
        store,
        language: language,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../docs/product/linesight/acceptance/nfc-batch/png/70-my-cards-$language-desktop-render.png',
        ),
      );
      await show(
        tester,
        const CloudNfcScanPage(binding: true),
        account,
        store,
        language: language,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../docs/product/linesight/acceptance/nfc-batch/png/71-bind-card-$language-desktop-render.png',
        ),
      );
      await show(
        tester,
        const CloudLoginPage(),
        account,
        store,
        language: language,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../docs/product/linesight/acceptance/read-state-batch/png/129-unified-login-$language-desktop-render.png',
        ),
      );
    });
  }
}
