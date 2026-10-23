import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/collaboration_api.dart';

class MemoryVault implements CloudTokenVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

class TestIdentity implements CloudIdentityGateway {
  int refreshes = 0;
  bool logoutAllowed = true;
  bool expired = false;
  Completer<void>? refreshGate;
  CloudTokens token([String access = 'initial']) => CloudTokens(
    access,
    'refresh',
    'linesight-android',
    DateTime.now().add(const Duration(minutes: 5)),
  );
  @override
  Future<CloudTokens?> signIn({bool changePassword = false}) async => token();
  @override
  Future<CloudTokens> demo() async => token();
  @override
  Future<CloudTokens> refresh(CloudTokens previous) async {
    refreshes++;
    await refreshGate?.future;
    if (expired) throw const CollaborationApiException(401, 'expired');
    return token('refreshed');
  }

  @override
  Future<bool> signOut(CloudTokens previous) async => logoutAllowed;
}

void main() {
  late HttpServer server;
  late MemoryVault vault;
  late TestIdentity identity;
  late CloudAccount account;
  var status = 200;
  setUp(() async {
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = status;
      final path = request.uri.path;
      if (path.endsWith('evidence/')) {
        final received = await request.fold<List<int>>(
          [],
          (all, part) => all..addAll(part),
        );
        expect(request.headers.contentLength, received.length);
        expect(request.headers.chunkedTransferEncoding, false);
        final body = utf8.decode(received);
        expect(body, contains('name="image"; filename="photo.jpg"'));
        expect(body, contains('name="stage"\r\n\r\ninspection'));
        expect(body, contains('attachment-content'));
        request.response.write('{"id":42}');
        await request.response.close();
        return;
      }
      final Object body = status != 200
          ? {'detail': 'server rejection'}
          : path.endsWith('metrics/')
          ? <String, dynamic>{}
          : path.endsWith('auth/me/')
          ? {'display_name': 'Engineer', 'home_workspace_id': 1}
          : path.endsWith('workspaces/')
          ? [
              {'id': 1, 'name': 'Personal', 'role': 'owner'},
              {'id': 2, 'name': 'Team', 'role': 'viewer'},
            ]
          : [
              {'id': path.contains('/2/') ? 'team-job' : 'personal-job'},
            ];
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    vault = MemoryVault();
    identity = TestIdentity();
    account = CloudAccount(
      vault: vault,
      identity: identity,
      apiUrl: 'http://127.0.0.1:${server.port}/api/v1/',
    );
  });
  tearDown(() async {
    account.dispose();
    await server.close(force: true);
  });

  test(
    'photo multipart declares its complete length for the cloud WSGI server',
    () async {
      await account.signIn();
      final receipt = await account.uploadPhoto(
        'workspaces/1/jobs/task/evidence/',
        utf8.encode('attachment-content'),
        'stable-key',
        {'stage': 'inspection'},
      );
      expect(receipt['id'], 42);
    },
  );

  test(
    'sign in and workspace switch load only selected workspace jobs',
    () async {
      await account.signIn();
      expect(account.displayName, 'Engineer');
      expect(account.jobs.single['id'], 'personal-job');
      await account.selectWorkspace(account.workspaces.last);
      expect(account.jobs.single['id'], 'team-job');
      expect(account.canEdit, false);
      expect(vault.value, isNotNull);
    },
  );
  test('malformed persisted session is removed', () async {
    vault.value = '{broken';
    await account.restore();
    expect(account.signedIn, false);
    expect(account.restoring, false);
    expect(vault.value, isNull);
  });
  test('concurrent requests share a rotating refresh', () async {
    vault.value = jsonEncode(
      CloudTokens(
        'old',
        'refresh',
        'linesight-android',
        DateTime.now().subtract(const Duration(minutes: 1)),
      ).toJson(),
    );
    identity.refreshGate = Completer<void>();
    final restoring = account.restore();
    while (identity.refreshes == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final first = account.request('GET', 'workspaces/');
    final second = account.request('GET', 'workspaces/');
    identity.refreshGate!.complete();
    await Future.wait([restoring, first, second]);
    expect(identity.refreshes, 1);
    expect(account.signedIn, true);
    expect(jsonDecode(vault.value!)['access'], 'refreshed');
  });
  test('revoked refresh removes identity and cached data', () async {
    vault.value = jsonEncode(
      CloudTokens(
        'old',
        'refresh',
        'linesight-android',
        DateTime(2000),
      ).toJson(),
    );
    identity.expired = true;
    await account.restore();
    expect(account.signedIn, false);
    expect(account.jobs, isEmpty);
    expect(vault.value, isNull);
  });
  test('403 retains login, 401 removes session and workspace data', () async {
    await account.signIn();
    status = 403;
    await account.reload();
    expect(account.signedIn, true);
    status = 401;
    await account.reload();
    expect(account.signedIn, false);
    expect(account.workspaces, isEmpty);
    expect(account.jobs, isEmpty);
    expect(vault.value, isNull);
  });
  test(
    'cancelled provider logout retains session; completed logout clears it',
    () async {
      await account.signIn();
      identity.logoutAllowed = false;
      await account.signOut();
      expect(account.signedIn, true);
      identity.logoutAllowed = true;
      await account.signOut();
      expect(account.signedIn, false);
      expect(account.profile, isNull);
      expect(vault.value, isNull);
    },
  );
}
