import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/collaboration_api.dart';

void main() {
  late HttpServer server;
  late KeycloakIdentityGateway gateway;
  Map<String, String>? submitted;
  var response = <String, dynamic>{};
  var status = 200;
  setUp(() async {
    submitted = null;
    status = 200;
    response = {
      'access_token': 'fresh-access',
      'refresh_token': 'rotated-refresh',
      'expires_in': 300,
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.uri.path, '/realms/demo/protocol/openid-connect/token');
      submitted = Uri.splitQueryString(await utf8.decoder.bind(request).join());
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    gateway = KeycloakIdentityGateway(
      issuer: 'http://127.0.0.1:${server.port}/realms/demo',
    );
  });
  tearDown(() => server.close(force: true));
  CloudTokens previous() => CloudTokens(
    'expired-access',
    'old-refresh',
    'linesight-demo',
    DateTime.now().subtract(const Duration(minutes: 1)),
    idToken: 'original-id',
  );
  test(
    'expired demo session rotates refresh token through standard token endpoint',
    () async {
      final next = await gateway.refresh(previous());
      expect(submitted, {
        'grant_type': 'refresh_token',
        'client_id': 'linesight-demo',
        'refresh_token': 'old-refresh',
      });
      expect(next.access, 'fresh-access');
      expect(next.refresh, 'rotated-refresh');
      expect(next.clientId, 'linesight-demo');
      expect(next.expiresAt.isAfter(DateTime.now()), isTrue);
    },
  );
  test(
    'demo refresh retains existing refresh and ID tokens when server omits them',
    () async {
      response.remove('refresh_token');
      final next = await gateway.refresh(previous());
      expect(next.refresh, 'old-refresh');
      expect(next.idToken, 'original-id');
    },
  );
  test('revoked demo refresh returns authentication failure', () async {
    status = 400;
    response = {'error': 'invalid_grant'};
    await expectLater(
      gateway.refresh(previous()),
      throwsA(
        isA<CollaborationApiException>().having((e) => e.status, 'status', 401),
      ),
    );
  });
}
