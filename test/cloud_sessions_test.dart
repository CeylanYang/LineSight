import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'cloud_account_test.dart' show MemoryVault, TestIdentity;

void main() {
  late HttpServer server;
  late CloudAccount account;
  late MemoryVault vault;
  late TestIdentity identity;
  var responseStatus = 200;
  final calls = <String>[];
  Completer<void>? gate;
  setUp(() async {
    calls.clear();
    responseStatus = 200;
    gate = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path.contains('/account/')) {
        calls.add('${request.method} ${request.uri}');
        expect(request.headers.value('Authorization'), startsWith('Bearer '));
        if (gate != null) await gate!.future;
        request.response.statusCode =
            request.method == 'DELETE' && responseStatus == 200
            ? 204
            : responseStatus;
        if (request.response.statusCode != 204) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              responseStatus == 200
                  ? [
                      {'id': 'current-session', 'current': true},
                      {'id': 'other-session'},
                    ]
                  : {'detail': 'denied'},
            ),
          );
        }
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            path.endsWith('auth/me/')
                ? {'id': 'ordinary', 'home_workspace_id': 1}
                : path.endsWith('workspaces/')
                ? [
                    {'id': 1, 'role': 'owner'},
                  ]
                : path.endsWith('metrics/')
                ? {}
                : [],
          ),
        );
      }
      await request.response.close();
    });
    final origin = 'http://127.0.0.1:${server.port}';
    vault = MemoryVault();
    identity = TestIdentity();
    account = CloudAccount(
      vault: vault,
      identity: identity,
      apiUrl: '$origin/api/',
      identityApiFactory: (token) =>
          CollaborationApi('$origin/account/', token: token),
    );
    await account.signIn();
  });
  tearDown(() async {
    account.dispose();
    await server.close(force: true);
  });

  test(
    'revoking another session preserves local session, bulk excludes current',
    () async {
      await account.revokeIdentitySession('other-session');
      await account.revokeOtherIdentitySessions();
      expect(calls, [
        'GET /account/sessions',
        'DELETE /account/sessions/other-session',
        'DELETE /account/sessions?current=false',
      ]);
      expect(account.signedIn, true);
      expect(vault.value, isNotNull);
    },
  );
  test(
    'revoking current session clears token vault and workspace views',
    () async {
      await account.revokeIdentitySession('current-session');
      expect(account.signedIn, false);
      expect(vault.value, isNull);
      expect(account.profile, isNull);
      expect(account.activeWorkspace, isNull);
    },
  );
  test('401 clears session but 403 preserves it', () async {
    responseStatus = 403;
    await expectLater(
      account.listIdentitySessions(),
      throwsA(isA<CollaborationApiException>()),
    );
    expect(account.signedIn, true);
    responseStatus = 401;
    await expectLater(
      account.listIdentitySessions(),
      throwsA(isA<CollaborationApiException>()),
    );
    expect(account.signedIn, false);
    expect(vault.value, isNull);
  });
  test(
    'session path injection and shared demo mutations never reach provider',
    () async {
      await expectLater(
        account.revokeIdentitySession('../sessions?current=true'),
        throwsA(isA<CollaborationApiException>()),
      );
      account.profile = {...account.profile!, 'is_demo': true};
      await expectLater(
        account.revokeOtherIdentitySessions(),
        throwsA(isA<CollaborationApiException>()),
      );
      expect(calls, isEmpty);
    },
  );
  test(
    'late identity response is discarded after signing into another identity',
    () async {
      gate = Completer<void>();
      final pending = account.listIdentitySessions();
      final rejected = expectLater(
        pending,
        throwsA(isA<CollaborationApiException>()),
      );
      while (calls.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await account.signOut();
      await account.signIn();
      gate!.complete();
      await rejected;
      expect(account.signedIn, true);
      expect(vault.value, isNotNull);
    },
  );
  test('expired access refreshes once before identity request', () async {
    await account.signOut();
    vault.value = jsonEncode(
      CloudTokens(
        'expired',
        'refresh',
        'linesight-android',
        DateTime.now().subtract(const Duration(minutes: 1)),
      ).toJson(),
    );
    await account.restore();
    final before = identity.refreshes;
    await account.listIdentitySessions();
    expect(identity.refreshes, greaterThanOrEqualTo(1));
    expect(identity.refreshes, before);
  });
}
