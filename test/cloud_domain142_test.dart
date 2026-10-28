import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:linesight_flutter/cloud_account.dart';

class RelayAppAuth extends FlutterAppAuth {
  AuthorizationTokenRequest? authorization;
  TokenRequest? refreshRequest;
  EndSessionRequest? logout;
  @override
  Future<AuthorizationTokenResponse> authorizeAndExchangeCode(
    AuthorizationTokenRequest request,
  ) async {
    authorization = request;
    return AuthorizationTokenResponse(
      'access',
      'refresh',
      DateTime.utc(2030),
      'id',
      'Bearer',
      null,
      null,
      null,
    );
  }

  @override
  Future<TokenResponse> token(TokenRequest request) async {
    refreshRequest = request;
    return TokenResponse(
      'access',
      'refresh',
      DateTime.utc(2030),
      'id',
      'Bearer',
      null,
      null,
    );
  }

  @override
  Future<EndSessionResponse> endSession(EndSessionRequest request) async {
    logout = request;
    return EndSessionResponse(null);
  }
}

void main() {
  const domain = 'https://99ai.pronhubcn.com/sso/realms/linesight';
  const legacy = 'https://47.111.81.94/sso/realms/linesight';
  CloudTokens token(String value) =>
      CloudTokens(value, 'refresh', 'linesight-android', DateTime.utc(2030));
  CloudTokens issued(String issuer) => token(
    'header.${base64Url.encode(utf8.encode(jsonEncode({'iss': issuer}))).replaceAll('=', '')}.signature',
  );
  test(
    'native domain login, refresh and logout use validated relay discovery',
    () async {
      final appAuth = RelayAppAuth();
      final identity = KeycloakIdentityGateway(
        appAuth: appAuth,
        issuer: domain,
      );
      await identity.signIn();
      expect(appAuth.authorization!.issuer, isNull);
      expect(
        appAuth.authorization!.discoveryUrl,
        'https://47.111.81.94/_linesight/identity/discovery',
      );
      expect(appAuth.authorization!.allowInsecureConnections, false);
      expect(
        appAuth.authorization!.redirectUrl,
        'com.linesight.app:/oauthredirect',
      );
      await identity.refresh(issued(domain));
      expect(
        appAuth.refreshRequest!.discoveryUrl,
        appAuth.authorization!.discoveryUrl,
      );
      await identity.signOut(issued(domain));
      expect(appAuth.logout!.discoveryUrl, appAuth.authorization!.discoveryUrl);
      await identity.refresh(issued(legacy));
      expect(appAuth.refreshRequest!.issuer, legacy);
      expect(appAuth.refreshRequest!.discoveryUrl, isNull);
    },
  );
  test(
    'saved legacy session keeps its issuing host for refresh and logout',
    () {
      final saved = CloudTokens.fromJson(issued(legacy).toJson());
      expect(cloudSessionIssuer(domain, saved), legacy);
      expect(cloudSessionIssuer(domain, issued(domain)), domain);
    },
  );
  test('token claims cannot select an untrusted credential endpoint', () {
    for (final issuer in [
      'https://attacker.invalid',
      '$legacy.attacker.invalid',
      'http://47.111.81.94/sso/realms/linesight',
      '$legacy/other',
    ]) {
      expect(cloudSessionIssuer(domain, issued(issuer)), domain);
    }
  });
  test(
    'malformed saved tokens and custom configured realms keep configured host',
    () {
      for (final value in ['', 'opaque', 'a.invalid.c', 'a.W10.c']) {
        expect(cloudSessionIssuer(domain, token(value)), domain);
      }
      expect(
        cloudSessionIssuer('https://test.invalid/realm', issued(legacy)),
        'https://test.invalid/realm',
      );
    },
  );
}
